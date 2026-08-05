# Room content — improvement plan

## Current state

The tagging pass is real: weighted content types, deterministic retries, lock-and-key placement with a solvability validator. What it produces is largely inert. The lock-and-key loop auto-unlocks on pickup so the key is never carried or spent; reward chests spawn empty because nothing hands them a loot list; puzzle and NPC nodes look up their interact areas under the wrong parent and are invisible; `merchant` is unreachable because the weight table overflows before reaching it; and `definition.puzzles` is a hardcoded empty array with no writer. See [`../existing_codebase/room-content.md`](../existing_codebase/room-content.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| RMC-01 | P0 | Locked doors auto-open on key pickup, so the key is never carried back or consumed and the whole loop is decorative | `room_locked_vault_content.gd:75` sets the flag; `room_locked_door_content.gd:23,122-129` unlocks on `flag_changed`; `consume_dungeon_key` at `:116` unreachable |
| RMC-02 | P0 | `reward` chests are never given items, so `LootChest._items` stays `[]` and opening one grants nothing | `room_reward_content.gd:6-10`, `loot_chest.gd:13,27,68` |
| RMC-03 | P0 | `puzzle` content is inert: interact area looked up under the wrong parent, `definition.puzzles` always empty, no mesh | `room_puzzle_content.gd:8,29,45` |
| RMC-04 | P0 | `npc_quest` content is inert: same wrong-parent lookup, `questKeyId`/`dialogueId` never written, no mesh | `room_npc_quest_content.gd:8-9,26,42` |
| RMC-05 | P1 | Keys are always placed on the critical path, so a lock never creates a detour | `room_content_assigner.gd:240` iterates `critical_layout` only |
| RMC-06 | P1 | `merchant` is unreachable: the weight table's cumulative total passes 1.0 at `empty` | `room_content_assigner.gd:150-164`, weights `room_content_config.gd:5-16` |
| RMC-07 | P1 | `weight_locked_vault`, `weight_rest`, `weight_lore` are declared and never used | `room_content_config.gd:12-14` vs the `weights` dictionary |
| RMC-08 | P1 | A key room can be the stairs room, overwriting the `stairs` content type | `room_content_assigner.gd:181` excludes stairs as a lock endpoint but not as a key room; `:257` overwrites |
| RMC-09 | P1 | `RoomContentValidator.simulate_collectibles` has no call sites and validates fields nobody writes | `room_content_validator.gd:75-100` |
| RMC-10 | P2 | Content visuals are placeholder primitives: `rest` is an untextured `BoxMesh`, `puzzle` and `npc_quest` have no mesh at all | `room_rest_content.gd:14-20`, `room_puzzle_content.gd:29-43`, `room_npc_quest_content.gd:26-40` |
| RMC-11 | P2 | Content offsets are hardcoded local positions with no room-size awareness, so props can land inside walls in the 8 x 12 kinds | `room_trap_content.gd:8`, `room_hazard_content.gd:8`, `room_reward_content.gd:9`, `room_lore_content.gd:26`, `room_merchant_content.gd:26` |
| RMC-12 | P2 | `_semantic_to_layout` is misnamed (it maps layout to semantic) and duplicates `_layout_to_semantic` | `room_content_validator.gd:103` |
| RMC-13 | P2 | `TEMPLATE_BY_TYPE` has empty entries for `combat`, `empty`, `boss`, `stairs`, relying on the spawner silently skipping them | `room_content_types.gd:16-28`, `room_content_spawner.gd:26` |

## Target design

The lock-and-key loop is the only mechanic here that shapes how the floor is played, so it goes first and it goes in properly. Content props then become authored scenes placed at authored anchors rather than primitives at magic offsets.

### 1. A real key loop (RMC-01, RMC-05, RMC-08)

Split possession from consumption. `WorldState` flags are permanent and floor-global — the wrong store for a carried item.

- `RoomLockedVaultContent` stops writing the `WorldState` flag on pickup and only calls `InventoryService.add_dungeon_key(key_id, lock_id, key_label)`.
- `RoomLockedDoorContent` stops connecting `WorldState.flag_changed`. `_refresh_state()` reads `InventoryService.has_dungeon_key(_key_id)` to decide whether to show the "Open" prompt versus the "Locked - needs <label>" prompt, but the barrier only clears inside `_unhandled_input` after `InventoryService.consume_dungeon_key(_key_id)` returns true. The `WorldState` flag becomes the *unlocked* record (`"unlocked_" + lock_id`), written after consumption, so the door stays open across a save/load of the same floor.
- `InventoryService` gains `dungeon_keys_for_floor()` and clears dungeon keys on floor transition, so keys never leak between floors.

Key placement becomes a detour. Replace `_find_key_room_layout` with:

1. Build the set of rooms reachable from the start **without** crossing the locked edge (`RoomGraphPaths.bfs_distances` on the door graph minus that edge).
2. Score each candidate by `off_path_depth = distance_from_critical_path(room)`, computed as the BFS distance from the nearest critical-path room.
3. Prefer the highest `off_path_depth`, tie-broken by the largest BFS distance from start, tie-broken by `rng.randi()` for determinism. Require `off_path_depth >= 1` — the key must be off the critical path.
4. If no candidate satisfies `off_path_depth >= 1`, drop that lock rather than degrade to an on-path key. If that leaves zero locks, `_try_assign_once` fails and the retry loop runs.

Exclude the stairs room from key rooms as well as lock endpoints, and make `_apply_key_to_content` assert the target's current content type is not in `_reserved_semantics`.

### 2. Reward chests carry loot (RMC-02)

`reward` entries gain an `items` array, populated by the assigner from the same roller the placement pass uses (`ProcgenLootTables` / `LootRoller`, see [`procgen-placements.md`](procgen-placements.md)), and `RoomRewardContent.configure()` calls `chest.configure({"items": entry.get("items", [])})`. `RoomLockedVaultContent` does the same for the chest it spawns, so a vault chest yields loot alongside the key. Item ids must be resolved during generation, not at open time, so the same seed yields the same loot and the snapshot round-trip in `dungeon_suite.gd` stays stable.

`content/schemas/dungeon-definition.v1.json` gains, inside the `roomContent` item schema, an optional `items` array of `{itemId: string, quantity: integer >= 1, instanceId: string}` matching the existing `placements.loot[].items` shape.

### 3. Puzzles become real (RMC-03)

Fix the parenting bug by caching the node instead of re-resolving it: `_lever = ...; _content_root().add_child(_lever)` and then `_lever.get_node("InteractArea")`. Apply the identical fix in `room_npc_quest_content.gd` (RMC-04).

Then give puzzles data. The assigner writes `content.puzzles` as one entry per `puzzle`-tagged room:

```json
{
  "puzzleId": "puzzle_r03",
  "roomId": "room_03",
  "kind": "lever_gate",
  "flagId": "puzzle_r03_solved",
  "gateRoomId": "room_07",
  "leverCount": 2,
  "solutionOrder": [1, 0]
}
```

`kind` starts as `lever_gate` (N levers, must be pulled in `solutionOrder`) and leaves room for `pressure_plate` and `torch_lighting` later. `gateRoomId` is chosen the same way a lock target is: an off-critical-path room behind the puzzle room, so solving it opens a reward branch rather than the main path. `leverCount` is `rng.randi_range(1, 3)` and `solutionOrder` is a Fisher-Yates shuffle of `range(leverCount)` using the assigner rng, so it is seed-stable.

`RoomPuzzleContent` reads the entry from `definition.puzzles` by `roomId`, spawns `leverCount` authored lever scenes at `Props/PropAnchor_<n>` (see [`room-templates.md`](room-templates.md) RTP-07), tracks pull order, and on success sets `WorldState.set_flag(flagId, true)` plus emits a signal the gate barrier in `gateRoomId` listens for. Wrong order resets the levers with an audio cue.

`content/schemas/dungeon-definition.v1.json` gains a `puzzles` array with `puzzleId`, `roomId`, `kind` (enum), `flagId`, `gateRoomId`, `leverCount`, `solutionOrder` — required alongside the existing `roomContent` and `locks` blocks that the schema does not yet declare at all (owned by [`room-graph-procgen.md`](room-graph-procgen.md) RGP-05).

### 4. NPC quests become real (RMC-04)

The assigner writes `questKeyId` and `dialogueId` onto `npc_quest` entries, choosing from a new `content/quests/dungeon_quests.json` catalog filtered by biome. `content/dialogue/dungeon_npc_stranded.json` already exists and is the first entry. `RoomNpcQuestContent` spawns an authored NPC scene rather than a bare `Node3D`, and `RoomContentValidator.simulate_collectibles` is wired into `validate()` so a quest that needs an item the floor never spawns fails generation (RMC-09).

### 5. Weight table correctness (RMC-06, RMC-07)

Replace the running-total roll with a normalized cumulative distribution built once from the config:

```gdscript
var total := 0.0
for w in weights.values():
    total += w
var roll := rng.randf() * total
var acc := 0.0
for type_id in weights:
    acc += weights[type_id]
    if roll < acc:
        return type_id
return RoomContentTypes.EMPTY
```

`weights` includes `locked_vault: 0.0` (it is only set by the key pass, so keep it out or set it to zero explicitly and delete the config field), and `rest`/`lore` either join the off-path table using `weight_rest`/`weight_lore` or the unused fields are deleted. Preference: join the table — an off-path bonfire and an off-path lore prop are both good finds. Target off-path distribution after normalization: `combat` 0.45, `empty` 0.14, `trap` 0.09, `hazard` 0.07, `reward` 0.06, `lore` 0.06, `rest` 0.05, `puzzle` 0.05, `npc_quest` 0.02, `merchant` 0.01.

### 6. Anchored, authored props (RMC-10, RMC-11)

Every content script stops using hardcoded offsets and instead places its prop at a `Props/PropAnchor_<n>` marker from the room scene, falling back to room center with a `push_warning` when the anchor is missing. `RoomContentBase` gains `_anchor(index: int) -> Node3D` to centralize it. Authored scenes replace the primitives: a bonfire model for `rest`, a lectern for `lore`, a lever for `puzzle`, an NPC for `npc_quest`, a stall for `merchant`. Art direction follows [`pixel-style.md`](../existing_codebase/pixel-style.md).

### 7. Cleanup (RMC-12, RMC-13)

Rename `_semantic_to_layout` to `_layout_to_semantic` and delete the duplicate. Drop the four empty `TEMPLATE_BY_TYPE` entries and have `RoomContentAssigner` omit `templateId` for those types, with `RoomContentSpawner` asserting that a present `templateId` resolves to a known script instead of silently skipping.

## Work plan

1. **Key loop rewrite** — `room_locked_vault_content.gd`, `room_locked_door_content.gd`, `InventoryService` floor-scoped keys. Land with the validation suite additions below (RMC-01).
2. **Key placement off-path** — `_find_key_room_layout` replacement plus the stairs exclusion and the reserved-semantics assertion (RMC-05, RMC-08).
3. **Reward loot** — assigner writes `items`, both chest scripts call `configure`, schema update (RMC-02).
4. **Parenting fix** — cache the spawned node in the puzzle and NPC scripts (RMC-03, RMC-04, part 1). Small and independently landable.
5. **Weight table normalization** — `_pick_content_type` cumulative fix and the config reconciliation (RMC-06, RMC-07).
6. **Puzzle data** — `content.puzzles` writer, schema block, `RoomPuzzleContent` rewrite, gate barrier (RMC-03, part 2).
7. **Quest data** — `content/quests/dungeon_quests.json`, assigner fields, `simulate_collectibles` wired into `validate()` (RMC-04, part 2, RMC-09).
8. **Prop anchors** — `RoomContentBase._anchor()`, all nine scripts, depends on [`room-templates.md`](room-templates.md) step 9 (RMC-11).
9. **Authored prop scenes** — replace primitives theme by theme (RMC-10).
10. **Cleanup** — validator rename, `TEMPLATE_BY_TYPE` pruning (RMC-12, RMC-13).

## Data and schema changes

- `content/schemas/dungeon-definition.v1.json`
  - Declare `roomContent`, `locks`, and `puzzles` at the root (they are produced today and rejected by `additionalProperties: false`).
  - `roomContent` item: `{roomId, layoutId, contentType (enum of the 13 types), templateId?, items?, keyId?, lockId?, keyLabel?, questKeyId?, dialogueId?}`.
  - `locks` item: `{lockId, from, to, keyId, keyRoomId, keyLayoutId, keyLabel}`.
  - `puzzles` item: the shape in section 3.
- New `content/quests/dungeon_quests.json` plus `content/schemas/dungeon-quest.v1.json`: `{questId, dialogueId, questKeyId, biomes: [string], rewardItemId}`.
- Save format: dungeon keys move from `WorldState` flags into a floor-scoped `InventoryService` bucket. `save_migrator.gd` must drop stale `key_*` flags on load; coordinate with [`local-save.md`](local-save.md) and [`save-migrator.md`](save-migrator.md).

## Acceptance criteria

- [ ] Picking up a key does not open any door; a locked door only clears after `consume_dungeon_key` returns true (RMC-01).
- [ ] After opening a locked door, `InventoryService.has_dungeon_key(keyId)` is false (RMC-01).
- [ ] For every lock on every generated floor of every biome, the key room's off-critical-path depth is at least 1 (RMC-05).
- [ ] No key room's prior content type is `boss`, `stairs`, or `entrance` (RMC-08).
- [ ] Every `reward` and `locked_vault` entry has a non-empty `items` array, and opening the chest adds those items to the inventory (RMC-02).
- [ ] Every `puzzle`-tagged room has a matching entry in `definition.puzzles`, and the spawned lever's `InteractArea` resolves non-null (RMC-03).
- [ ] Every `npc_quest` entry has non-empty `questKeyId` and `dialogueId`, and the NPC's `InteractArea` resolves non-null (RMC-04).
- [ ] Over 1000 seeds, every one of the 13 content types except `boss`/`stairs`/`entrance` reservations appears at least once, including `merchant` (RMC-06).
- [ ] `RoomContentConfig` has no unread fields (RMC-07).
- [ ] Same seed produces byte-identical `roomContent`, `locks`, and `puzzles` arrays across two runs in the same process and across a process restart (determinism).
- [ ] A generated definition validates against `content/schemas/dungeon-definition.v1.json` under `scripts/validate-content/validate.mjs` (RMC-03, schema).
- [ ] No content script uses a hardcoded `Vector3` offset (RMC-11).

## Validation

Extend `apps/game/client/scripts/validation/suites/room_content_suite.gd`:

- `test_key_requires_carry` — build a floor with at least one lock; assert `door._is_locked` is true immediately after the vault's key pickup, and false only after `consume_dungeon_key`; assert the key is gone from the inventory afterward.
- `test_key_rooms_are_off_path` — for 200 seeds x 10 biomes, for each lock assert the key room is not in `RoomGraphPaths.critical_path_ids(graph)`.
- `test_key_room_not_reserved` — assert no key room's layout id equals the start, stairs, or boss layout id.
- `test_reward_entries_have_items` — assert every `reward` and `locked_vault` entry has `items.size() > 0` and every `itemId` resolves in `ContentCatalog`.
- `test_puzzle_entries_exist` — assert `definition.puzzles.size()` equals the count of `puzzle`-tagged rooms, and each entry's `gateRoomId` is a real room id off the critical path.
- `test_content_type_coverage` — over 1000 seeds, collect the set of assigned content types; assert it contains all of `combat, empty, trap, hazard, puzzle, npc_quest, locked_vault, reward, rest, lore, merchant`.
- `test_weight_distribution` — over 5000 off-path picks with a fixed seed, assert each type's observed frequency is within 3 percentage points of its normalized weight.
- `test_assignment_determinism` — assert `JSON.stringify(assign(graph, assignment, seed))` is identical across two calls, and that changing the seed by 1 changes the output.
- `test_no_fallback_assignment` — over 500 seeds x 10 biomes, assert `_fallback_assignment` is never reached (add a static counter or a `fallback: true` marker on the returned dictionary).
- `test_collectible_simulation_runs` — assert `validate()` calls `simulate_collectibles` and that a hand-built definition with a quest key that no room grants fails validation.

Extend `apps/game/client/scripts/validation/suites/dungeon_suite.gd`:

- `test_content_nodes_interactable` — build a floor; for every spawned `RoomContent_*` node assert the interactable child resolves and its `Area3D` has a non-zero collision mask.
- `test_content_props_inside_room` — assert every spawned prop's global position is inside the owning room's blockout AABB, inset by 1.0.

## Related

- [`../existing_codebase/room-content.md`](../existing_codebase/room-content.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — RGP-05 schema reconciliation, critical path API
- [`room-templates.md`](room-templates.md) — RTP-07 prop anchors and markers
- [`procgen-placements.md`](procgen-placements.md) — the loot roller the reward chests reuse
- [`dungeon-builder.md`](dungeon-builder.md) — spawner call site
- [`inventory-service.md`](inventory-service.md) — floor-scoped dungeon keys
- [`world-state.md`](world-state.md) — flag semantics
- [`dialogue-quests.md`](dialogue-quests.md) — quest catalog and dialogue ids
- [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md) — key storage migration
