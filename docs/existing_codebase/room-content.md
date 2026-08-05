# Room content

Post-layout content tagging: after the graph and templates are fixed, `RoomContentAssigner` labels every room with a `contentType`, places lock-and-key pairs on the critical path, and `RoomContentValidator` proves the boss is still reachable. `RoomContentSpawner` then instantiates one node per tagged room at build time. The tagging runs on every generated floor; three of the nine content scripts do not work once spawned.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/room_content_assigner.gd` | Content type per room, lock/key placement, branch previews |
| `apps/game/client/scripts/dungeon/procgen/room_content_config.gd` | Weights and limits |
| `apps/game/client/scripts/dungeon/procgen/room_content_types.gd` | Content type constants and `TEMPLATE_BY_TYPE` |
| `apps/game/client/scripts/dungeon/procgen/room_content_validator.gd` | Critical-path key simulation |
| `apps/game/client/scripts/dungeon/room_content/room_content_spawner.gd` | `templateId` -> script, instantiation |
| `apps/game/client/scripts/dungeon/room_content/room_content_base.gd` | Base class, `_content_root()` |
| `apps/game/client/scripts/dungeon/room_content/room_{trap,hazard,puzzle,npc_quest,locked_vault,reward,rest,lore,merchant}_content.gd` | The nine content behaviors |
| `apps/game/client/scripts/dungeon/room_content/room_locked_door_content.gd` | The barrier half of the lock |

## How it works

### Content types

`RoomContentTypes` (`room_content_types.gd`) defines 13 constants. Only 9 have a `TEMPLATE_BY_TYPE` entry, and only those 9 spawn anything:

| Content type | `templateId` | Script |
|--------------|--------------|--------|
| `trap` | `trap_spike_pack` | `room_trap_content.gd` |
| `hazard` | `hazard_poison_zone` | `room_hazard_content.gd` |
| `puzzle` | `puzzle_lever_gate` | `room_puzzle_content.gd` |
| `npc_quest` | `npc_quest_giver` | `room_npc_quest_content.gd` |
| `locked_vault` | `locked_vault_chest` | `room_locked_vault_content.gd` |
| `reward` | `reward_cache` | `room_reward_content.gd` |
| `rest` | `rest_bonfire` | `room_rest_content.gd` |
| `lore` | `lore_readable` | `room_lore_content.gd` |
| `merchant` | `dungeon_merchant` | `room_merchant_content.gd` |

`combat`, `empty`, `boss`, and `stairs` have no template and no spawned node — enemies and the boss come from `placements`, and the stair lever from `DungeonBuilder`.

### Assignment

`RoomContentAssigner.assign()` (`room_content_assigner.gd:7`) computes `RoomGraphPaths.critical_path_ids(graph)` and `bfs_distances()` (both door-mask based), then retries `_try_assign_once()` up to `config.max_assignment_attempts` (48) reseeding `rng.seed + 1_000_003 + attempt` (`:29`). On total failure it returns `_fallback_assignment()` (`:356`), which tags every non-filler room `combat`.

`_try_assign_once()` (`:33`) walks `assignment.rooms` and picks in this precedence:

1. `type == "filler"` -> `empty`, no template (`:71-78`).
2. In `_reserved_semantics` (entrance, stairs, boss, and treasure when `graph.treasure_id != ""`, `:285-296`) -> `_entry_for_special()` (`:265`) maps BOSS->`boss`, TREASURE->`reward`, STAIRS->`stairs`, START->`empty`, anything else->`combat`; all with an empty template.
3. The critical-path room immediately before the boss -> `combat` (`:82-89`).
4. Otherwise `_pick_content_type()`.

`_pick_content_type()` (`:121`):

| Branch | Rule |
|--------|------|
| dead end | roll < 0.30 `lore`, < 0.55 `reward`, < 0.65 `empty`, < 0.85 `combat`, else `empty` (`:129-139`) |
| on critical path, `distance % 4 == 0 and distance < 6` | 65% `rest`, else `empty` (`:141-142`) |
| on critical path, `distance <= 2` | 75% `combat`, else `empty` (`:143-144`) |
| on critical path, otherwise | 88% `combat`, else `empty` (`:145`) |
| off path, `distance < config.min_off_path_distance` (2) | `combat` (`:146-147`) |
| off path, otherwise | weighted roll over the `weights` dictionary (`:150-164`) |

The off-path weights are iterated in dictionary insertion order, accumulating until `roll <= cumulative`:

| Order | Type | Weight | Cumulative |
|-------|------|--------|------------|
| 1 | `trap` | 0.10 (0.0 when `no_trap`) | 0.10 |
| 2 | `hazard` | 0.08 (0.0 when `no_trap`) | 0.18 |
| 3 | `puzzle` | 0.05 | 0.23 |
| 4 | `npc_quest` | 0.03 | 0.26 |
| 5 | `combat` | 0.55 | 0.81 |
| 6 | `empty` | 0.20 | 1.01 |
| 7 | `merchant` | 0.04 | 1.05 |

`rng.randf()` returns `[0, 1)`, so `empty` absorbs `0.81..1.0` and `merchant` is unreachable. `config.weight_locked_vault` (0.07), `weight_rest` (0.08), and `weight_lore` (0.06) are not in the dictionary at all — `locked_vault` is only set by `_apply_key_to_content()`, and `rest`/`lore` only by the critical-path and dead-end branches.

`no_trap` covers the reserved semantics plus every orthogonal neighbor of the start cell (`:51-58`).

### Locks and keys

When `config.enable_locked_door` and the critical path has at least 4 rooms, `_place_locked_doors()` (`:168`) runs:

1. Candidate doors are consecutive critical-path pairs `(i, i+1)` for `i in 1..size-2`, excluding any pair touching the stairs room (`:178-190`).
2. Candidates are sorted by the target room's BFS distance (`:193`).
3. `lock_count = rng.randi_range(config.min_locks_per_floor, config.max_locks_per_floor)` (1..3), clamped to the candidate count.
4. Picks are spread by `step = candidates.size() / lock_count` (`:200-205`), topped up randomly if fewer distinct indices resulted (`:206-209`).
5. For each pick, `_find_key_room_layout()` (`:232`) chooses the **critical-path** room with the largest BFS distance that is still less than the locked room's, is not the start, and satisfies `RoomGraphPaths.is_on_branch_to(graph, layout_id, toLayout)`.

Each lock emits `{lockId, from, to, keyId, keyRoomId, keyLayoutId, keyLabel}` with `lockId = "lock_<from>_<to>"` and `keyId = "key_<from>_<to>"`. `_apply_key_to_content()` (`:254`) rewrites the key room's entry to `locked_vault` and attaches `keyId`, `lockId`, and `keyLabel`.

Because `_find_key_room_layout` only searches `critical_layout`, the key is always in a room the player must walk through anyway — the lock adds no detour.

If `_place_locked_doors` returns empty, `_try_assign_once` fails (`:106-107`) and the whole assignment is retried.

`content.puzzles` is hardcoded `[]` in both the success path (`:113`) and the fallback (`:384`), and `ProcgenPlacements` also returns `puzzles: []` (`procgen_placements.gd:38`). Nothing anywhere writes a puzzle definition.

### Validation

`RoomContentValidator.validate()` (`room_content_validator.gd:7`) checks each lock has a key room and target, that the key room is on a branch to the locked room, then `_simulate_path()` (`:44`) walks the critical path collecting `keyId`s and fails if it reaches a locked room without its key. `_semantic_to_layout()` (`:103`) is misnamed — it maps layout id to semantic id.

`simulate_collectibles()` (`:75`) has no call sites; it is the only code that reads `questKeyId` and `flagId`, neither of which the assigner ever writes.

### Branch previews

`build_branch_previews()` (`room_content_assigner.gd:299`) emits `{fromRoomId, toRoomId, hint}` for every adjacency where the target is off the critical path. `_preview_hint_for_content()` (`:339`) returns `"reward"` for `reward`, `lore`, `rest`, `merchant`, `locked_vault`, `npc_quest`, `empty`, and `puzzle`, and `"danger"` for everything else (so `combat`, `trap`, `hazard`, `boss`, `stairs`). Consumed by `minimap.gd:23` and `castle_run.gd:146`.

### Spawning

`RoomContentSpawner.spawn_all()` (`room_content_spawner.gd:19`) iterates `definition.roomContent`, resolves `templateId` through `CONTENT_SCRIPTS` (`:6-16`), creates a bare `Node3D` named `RoomContent_<templateId>` with the script attached and `biome_id` meta, adds it as a child of the room, then calls `configure(entry, definition)`.

`spawn_locks()` (`:42`) creates one `LockedDoor_<lockId>` node per lock, parented to the `from` room, and calls `configure(lock, from_room, to_room)`.

`RoomContentBase._content_root()` (`room_content_base.gd:11`) returns the room's `Props` child if present, else the room itself. Every content script adds its visuals to `_content_root()`, which is a **sibling** of the content node, not a child.

### The nine behaviors

| Script | What it builds | Works? |
|--------|----------------|--------|
| `room_trap_content.gd:6` | `spike_trap.tscn` at local `(0, 0, 2)` | Yes |
| `room_hazard_content.gd:6` | `poison_pool.tscn` at local `(-2, 0, -2)` | Yes |
| `room_rest_content.gd:9` | 0.5 x 0.7 x 0.5 `BoxMesh` bonfire plus a 1.6-radius `Area3D`; `_physics_process` polls for the player holding `interact` and calls `RunFlow.rest_at_bonfire` (`run_flow.gd:445`) | Yes, but the visual is an untextured box |
| `room_lore_content.gd:9` | `DioramaSkin.build_chest` prop plus interact area; opens dialogue `dungeon_lore_default` (`content/dialogue/dungeon_lore_default.json` exists) | Yes; `entry.dialogueId` is never written by the assigner so the id is always the default |
| `room_locked_vault_content.gd:15` | `loot_chest.tscn` at room center, 3 x 3 x 3 pickup area, `Label3D`; on interact calls `InventoryService.add_dungeon_key` and `WorldState.set_flag(keyId, true)` | Spawns and grants the key, but see the lock loop below |
| `room_locked_door_content.gd:17` | Barrier at the socket toward `to_room`, interact area, `Label3D`; on interact consumes the key | The barrier auto-opens on key pickup (below) |
| `room_reward_content.gd:6` | `loot_chest.tscn` at local `(1, 0, -1)` | BROKEN — `configure(placement)` is never called on the chest, so `LootChest._items` stays `[]` (`loot_chest.gd:13,27,68`) and the chest grants nothing |
| `room_puzzle_content.gd:7` | `PuzzleLever` node with an interact `Area3D`, no mesh | BROKEN — three ways, below |
| `room_npc_quest_content.gd:7` | `QuestNpc` node with an interact `Area3D`, no mesh | BROKEN — node path, below |
| `room_merchant_content.gd:10` | `DioramaSkin.build_portal` stall; opens `merchant_ui.tscn` with merchant id `dungeon_merchant` | Code is sound, but `merchant` is unreachable from `_pick_content_type` |

### The lock-and-key loop does not require the key

`RoomLockedVaultContent._unhandled_input` sets `WorldState.set_flag(_key_id, true)` on pickup (`room_locked_vault_content.gd:75`). `RoomLockedDoorContent` connects `WorldState.flag_changed` in `configure()` (`room_locked_door_content.gd:23`) and `_refresh_state()` unlocks whenever `WorldState.has_flag(_key_id)` (`:128-129`). So the barrier opens the instant the key is picked up, anywhere on the floor. The player never walks back to the door, `InventoryService.consume_dungeon_key` (`:116`) is never called, and the key is never spent. The `_unhandled_input` branch at `:110-119` is unreachable in normal play.

### The puzzle and NPC nodes cannot be interacted with

Both scripts add their interactable to `_content_root()` — the room's `Props` node — but then look it up relative to `self`:

- `room_puzzle_content.gd:29` adds `PuzzleLever` to `_content_root()`; `:45` reads `get_node_or_null("PuzzleLever/InteractArea")`, which resolves under the `RoomContent_puzzle_lever_gate` node and is always `null`.
- `room_npc_quest_content.gd:26` adds `QuestNpc` to `_content_root()`; `:42` reads `get_node_or_null("QuestNpc/InteractArea")`, always `null`.

Additionally `room_puzzle_content.gd:8` scans `definition.puzzles`, which is always `[]`, so `_flag_id` and `_gate_room_id` are always empty even if the lookup worked; and `room_npc_quest_content.gd:8-9` reads `entry.questKeyId` and `entry.dialogueId`, neither of which the assigner writes. Neither node has any visible mesh, so both are invisible.

## Contracts

- `definition.roomContent[]`: `{roomId, layoutId, contentType, templateId}` plus `{keyId, lockId, keyLabel}` on `locked_vault` entries. Read by `room_content_spawner.gd:20`, `room_content_assigner.gd:308`, `room_content_validator.gd:32`.
- `definition.locks[]`: `{lockId, from, to, keyId, keyRoomId, keyLayoutId, keyLabel}`. Read by `room_content_spawner.gd:44`.
- `definition.branchPreviews[]`: `{fromRoomId, toRoomId, hint}`. Read by `minimap.gd:23`, `castle_run.gd:146`.
- `WorldState` flags: `<keyId>` written by the vault (`room_locked_vault_content.gd:75`) and the door (`room_locked_door_content.gd:117`); `quest_<questKeyId>_active` written by the NPC (`room_npc_quest_content.gd:51`); arbitrary `flagId` by the puzzle (`room_puzzle_content.gd:49`).
- `InventoryService.add_dungeon_key(keyId, lockId, keyLabel)` / `has_dungeon_key` / `consume_dungeon_key`.
- Group `dialogue_ui` with `start_dialogue(id) -> bool`, used by the lore and NPC scripts.
- Collision: every interact `Area3D` uses `collision_layer = 0`, `collision_mask = 2`.
- Node-name contract: the room must have a `Props` child or content lands directly on the room (`room_content_base.gd:12`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Content tagging per room | IMPLEMENTED | `room_content_assigner.gd:33-118` |
| Solvability validation | IMPLEMENTED | `room_content_validator.gd:7-41` |
| Branch previews | IMPLEMENTED | `room_content_assigner.gd:299-336` |
| Lock-and-key loop | BROKEN | barrier auto-unlocks on pickup via `WorldState.flag_changed` (`room_locked_door_content.gd:23,122-129`); key is never consumed |
| Key placement adds no exploration | PARTIAL | `_find_key_room_layout` searches only the critical path (`room_content_assigner.gd:240`) |
| `reward` chests | BROKEN | `LootChest.configure` never called, `_items` stays empty (`room_reward_content.gd:6-10`, `loot_chest.gd:27`) |
| `puzzle` content | BROKEN | wrong node path (`room_puzzle_content.gd:29` vs `:45`), `definition.puzzles` always `[]` (`:8`), no mesh |
| `npc_quest` content | BROKEN | wrong node path (`room_npc_quest_content.gd:26` vs `:42`), `questKeyId`/`dialogueId` never written, no mesh |
| `merchant` content | STUB | script works but `merchant` is unreachable: the weight table's cumulative total reaches 1.01 before it (`room_content_assigner.gd:150-164`) |
| `definition.puzzles` | ABSENT | hardcoded `[]` at `room_content_assigner.gd:113,384` and `procgen_placements.gd:38`; no writer anywhere |
| `rest` visual | PLACEHOLDER | untextured `BoxMesh` (`room_rest_content.gd:14-20`) |
| `RoomContentConfig.weight_locked_vault`, `weight_rest`, `weight_lore` | STUB | declared at `room_content_config.gd:12-14`, absent from the `weights` dictionary |
| `RoomContentValidator.simulate_collectibles` | STUB | no call sites; reads `questKeyId`/`flagId` that are never written (`room_content_validator.gd:75-100`) |
| `treasure` reservation | PARTIAL | `graph.treasure_id` is always empty on the primary path (see [`room-graph-procgen.md`](room-graph-procgen.md)), so the TREASURE branch of `_entry_for_special` never fires |
| Key room can be the stairs room | PARTIAL | `_place_locked_doors` excludes stairs as a lock endpoint (`:181`) but not as a key room, so `_apply_key_to_content` can overwrite the `stairs` content type (`:257`) |

## Related

- Improvement plan: [`../actual_improvements/room-content.md`](../actual_improvements/room-content.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — critical path and reserved slots
- [`procgen-placements.md`](procgen-placements.md) — the parallel enemy/loot/trap pass
- [`dungeon-builder.md`](dungeon-builder.md) — calls the spawner
- [`dungeon-traps.md`](dungeon-traps.md) — `spike_trap` and `poison_pool` scenes
- [`dialogue-quests.md`](dialogue-quests.md) — `dialogue_ui` contract
- [`inventory-service.md`](inventory-service.md) — dungeon key storage
- [`world-state.md`](world-state.md) — flag store
