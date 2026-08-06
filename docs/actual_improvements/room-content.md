# Room content — improvement plan

## Status: FINISHED

## Current state

Post-layout tagging is wired end-to-end: off-path weights are normalized, keys live in `InventoryService` until the door consumes them, reward and vault chests roll loot at generation time, puzzles and NPC quests get data and authored dioramas, and validation simulates off-path key availability. See [`../existing_codebase/room-content.md`](../existing_codebase/room-content.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| RMC-01 | P0 | Locked doors auto-opened on key pickup | `room_locked_vault_content.gd:84-90` no longer sets lock flag; door uses `consume_dungeon_key` at `room_locked_door_content.gd:97-100` | FINISHED |
| RMC-02 | P0 | Reward chests empty | `room_reward_content.gd:11-12`, `room_locked_vault_content.gd:24-25`, assigner `_roll_chest_items` at `room_content_assigner.gd:467-485` | FINISHED |
| RMC-03 | P0 | Puzzle content inert | `room_puzzle_content.gd:17-48`, `room_content_assigner.gd:500-518`, `room_puzzle_gate_content.gd` | FINISHED |
| RMC-04 | P0 | NPC quest inert | `room_npc_quest_content.gd:14-31`, `dungeon_quest_catalog.gd`, assigner `_pick_dungeon_quest` | FINISHED |
| RMC-05 | P1 | Keys on critical path | `_find_key_room_layout` off-path scoring at `room_content_assigner.gd:318-378` | FINISHED |
| RMC-06 | P1 | `merchant` unreachable | normalized `_pick_content_type` at `room_content_assigner.gd:207-236` | FINISHED |
| RMC-07 | P1 | Unused config weights | `room_content_config.gd:6-15` all consumed in weight table | FINISHED |
| RMC-08 | P1 | Stairs room as key room | stairs excluded at `room_content_assigner.gd:334`, validator `room_content_validator.gd:95-98` | FINISHED |
| RMC-09 | P1 | `simulate_collectibles` unused | wired in `room_content_validator.gd:108-110`, `_validate_collectibles` | FINISHED |
| RMC-10 | P2 | Placeholder primitives | `DioramaInteractableSkin.build_bonfire/build_lectern/build_npc` + content scripts | FINISHED |
| RMC-11 | P2 | Hardcoded offsets | `RoomContentBase._anchor()` at `room_content_base.gd:16-27`, all nine scripts | FINISHED |
| RMC-12 | P2 | Misnamed validator helper | `_layout_to_semantic` at `room_content_validator.gd:218-222` | FINISHED |
| RMC-13 | P2 | Empty `TEMPLATE_BY_TYPE` entries | pruned in `room_content_types.gd:19-29`; spawner errors unknown templates at `room_content_spawner.gd:33-34` | FINISHED |

## Target design

Implemented as specified in the original plan: inventory-backed keys, off-path key rooms, `ProcgenLootRoller` chest items, `definition.puzzles` with lever gates, dungeon quest catalog, normalized weights, prop anchors with diorama fallbacks, and collectible validation.

## Work plan

1. **Key loop rewrite** — FINISHED (`room_locked_vault_content.gd`, `room_locked_door_content.gd`, `inventory_service.gd:107-115`).
2. **Key placement off-path** — FINISHED (`room_content_assigner.gd:318-405`).
3. **Reward loot** — FINISHED (`room_content_assigner.gd:467-485`, chest `configure` calls).
4. **Parenting fix** — FINISHED (`room_puzzle_content.gd`, `room_npc_quest_content.gd`).
5. **Weight table normalization** — FINISHED (`room_content_config.gd`, `room_content_assigner.gd:207-236`).
6. **Puzzle data** — FINISHED (`room_content_assigner.gd:500-556`, `room_puzzle_gate_content.gd`, spawner `spawn_puzzle_gates`).
7. **Quest data** — FINISHED (`content/quests/dungeon_quests.json`, `dungeon_quest_catalog.gd`).
8. **Prop anchors** — FINISHED (`room_content_base.gd:16-27`, all content scripts).
9. **Authored prop scenes** — FINISHED (diorama builders in `diorama_interactable_skin.gd:74-115`).
10. **Cleanup** — FINISHED (validator rename, spawner assertions, `TEMPLATE_BY_TYPE` prune).

## Data and schema changes

- `content/schemas/dungeon-definition.v2.json` — `roomContent` items, quest fields, full `dungeonPuzzle` shape (`content/schemas/dungeon-definition.v2.json:103-141`).
- `content/schemas/dungeon-quest.v1.json` — new catalog schema.
- `content/quests/dungeon_quests.json` — stranded scout entry for all ten biomes.
- No save migrator bump: keys never wrote `key_*` WorldState flags on pickup anymore.

## Acceptance criteria

- [x] Picking up a key does not open any door; a locked door only clears after `consume_dungeon_key` returns true (RMC-01). Evidence: `room_content_suite.gd` `room_content.key_requires_carry`.
- [x] After opening a locked door, `InventoryService.has_dungeon_key(keyId)` is false (RMC-01).
- [x] For every lock, the key room layout is not on the critical path (RMC-05). Evidence: `room_content.key_rooms_off_path`.
- [x] No key room layout is start, stairs, or boss (RMC-08). Evidence: `room_content.key_room_not_reserved`.
- [x] Every `reward` and `locked_vault` entry has non-empty `items` resolving in `ItemCatalog` (RMC-02). Evidence: `room_content.reward_items`.
- [x] Every `puzzle` room has a matching `definition.puzzles` entry with working levers (RMC-03). Evidence: `room_content.puzzle_entries`, `room_puzzle_content.gd:17-48`.
- [x] Every `npc_quest` entry has `questKeyId` and `dialogueId`; NPC interact resolves (RMC-04). Evidence: assigner `_pick_dungeon_quest`, `room_npc_quest_content.gd:14-31`.
- [x] Over 2000 seeds + 5000 off-path rolls, all listed content types appear including `merchant` (RMC-06). Evidence: `room_content.type_coverage`.
- [x] `RoomContentConfig` has no unread weight fields (RMC-07). Evidence: `room_content.weight_distribution`.
- [x] Same seed yields identical `content` across two assign calls; distant seed differs (determinism). Evidence: `room_content.assignment_determinism`.
- [x] Generated definitions include `roomContent`, `locks`, `puzzles` (schema). Evidence: `room_content.definition_fields`.
- [x] No content script uses a hardcoded `Vector3` prop offset (RMC-11). Evidence: all content scripts use `_anchor()`.
- [x] `validate()` runs collectible simulation and rejects missing quest rewards (RMC-09). Evidence: `room_content.collectible_simulation`.

## Validation

Extended `apps/game/client/scripts/validation/suites/room_content_suite.gd` — 15 tests, all passing (Godot 4.7.1 headless, `room_content_suite` 15/15).

## Related

- [`../existing_codebase/room-content.md`](../existing_codebase/room-content.md)
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`room-templates.md`](room-templates.md)
- [`procgen-placements.md`](procgen-placements.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`inventory-service.md`](inventory-service.md)
- [`world-state.md`](world-state.md)
- [`dialogue-quests.md`](dialogue-quests.md)
