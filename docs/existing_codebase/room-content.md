# Room content

Post-layout content tagging: `RoomContentAssigner` labels every room with a `contentType`, places lock-and-key pairs with off-path key rooms, writes `definition.puzzles`, and `RoomContentValidator` proves the boss remains reachable when keys are collected via detours. `RoomContentSpawner` instantiates one scripted node per tagged room plus locked doors and puzzle gates at build time.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/dungeon/procgen/room_content_assigner.gd` | Content types, locks, puzzles, loot items, quest fields |
| `apps/game/client/scripts/dungeon/procgen/room_content_config.gd` | Normalized off-path weights (sum 1.0) |
| `apps/game/client/scripts/dungeon/procgen/room_content_types.gd` | Constants and `TEMPLATE_BY_TYPE` (nine spawnable types) |
| `apps/game/client/scripts/dungeon/procgen/room_content_validator.gd` | Path simulation with off-path keys, collectible checks |
| `apps/game/client/scripts/dungeon/procgen/procgen_loot_roller.gd` | Chest item rolls for reward/vault entries |
| `apps/game/client/scripts/quests/dungeon_quest_catalog.gd` | Loads `content/quests/dungeon_quests.json` |
| `apps/game/client/scripts/dungeon/room_content/room_content_spawner.gd` | Spawns content nodes, locks, puzzle gates |
| `apps/game/client/scripts/dungeon/room_content/room_content_base.gd` | `_content_root()`, `_anchor(index)` |
| `apps/game/client/scripts/dungeon/room_content/room_{trap,hazard,puzzle,npc_quest,locked_vault,reward,rest,lore,merchant}_content.gd` | Nine content behaviors |
| `apps/game/client/scripts/dungeon/room_content/room_locked_door_content.gd` | Door barrier; consumes inventory key |
| `apps/game/client/scripts/dungeon/room_content/room_puzzle_gate_content.gd` | Puzzle branch barrier |

## How it works

### Content types

`RoomContentTypes` defines 13 constants. Nine have `TEMPLATE_BY_TYPE` entries and spawn nodes; `combat`, `empty`, `boss`, and `stairs` omit `templateId` and rely on placements or other builders.

### Assignment

`RoomContentAssigner.assign()` (`room_content_assigner.gd:9`) accepts optional `biome_id` for loot rolls. Off-path `_pick_content_type()` (`:207-236`) uses a normalized cumulative table from `room_content_config.gd` (`combat` 0.45, `empty` 0.14, `trap` 0.09, `hazard` 0.07, `reward` 0.06, `lore` 0.06, `rest` 0.05, `puzzle` 0.05, `npc_quest` 0.02, `merchant` 0.01).

Locks (`:143-158`): candidates on the critical path excluding stairs endpoints; key rooms chosen by off-path depth via `_find_key_room_layout` (`:318-378`) among rooms reachable from start without crossing the locked edge. Empty lock sets are allowed (floor simply has no locks).

`_finalize_content_entries` (`:437-465`) rolls chest `items` through `ProcgenLootRoller`, assigns `questKeyId`/`dialogueId` from `DungeonQuestCatalog`, builds `definition.puzzles` for lever-gate rooms, and ensures quest reward items appear on the floor.

### Validation

`RoomContentValidator.validate()` (`room_content_validator.gd:78`) checks key rooms are off the critical path and not reserved layouts, then `_simulate_path` (`:111-143`) treats every lock's `keyId` as obtainable via off-path detour before the locked step. `_validate_collectibles` (`:167-195`) ensures NPC quest reward items exist in floor loot.

### Spawning

`RoomContentSpawner.spawn_all()` (`room_content_spawner.gd:20`) errors on unknown `templateId`. `spawn_locks()` and `spawn_puzzle_gates()` parent barriers on the puzzle/lock `from` room socket (`dungeon_builder.gd:682-684`).

### Behaviors

| Script | Behavior | Status |
|--------|----------|--------|
| `room_locked_vault_content.gd` | Key pickup adds `InventoryService` key only; optional chest loot via `configure` | IMPLEMENTED |
| `room_locked_door_content.gd` | Barrier until `consume_dungeon_key`; then `WorldFlags.lock_opened` | IMPLEMENTED |
| `room_reward_content.gd` | Chest at `_anchor(0)` with rolled `items` | IMPLEMENTED |
| `room_puzzle_content.gd` | Diorama levers, order check, sets `WorldFlags.lever_pulled(flagId)` | IMPLEMENTED |
| `room_puzzle_gate_content.gd` | Clears when puzzle flag set | IMPLEMENTED |
| `room_npc_quest_content.gd` | Diorama NPC, dialogue, quest flag | IMPLEMENTED |
| `room_rest_content.gd` | Diorama bonfire, `RunFlow.rest_at_bonfire` | IMPLEMENTED |
| `room_lore_content.gd` | Diorama lectern, dialogue | IMPLEMENTED |
| `room_trap_content.gd` / `room_hazard_content.gd` | Trap scenes at anchors | IMPLEMENTED |
| `room_merchant_content.gd` | Diorama stall, `merchant_ui` | IMPLEMENTED |

Props use `RoomContentBase._anchor(index)` (`room_content_base.gd:16-27`), falling back to the `Props` root with `push_warning` when `PropAnchor_<n>` markers are absent.

## Contracts

- `definition.roomContent[]`: `{roomId, layoutId, contentType, templateId?}` plus `{keyId, lockId, keyLabel, items?, questKeyId?, dialogueId?, flagId?}`.
- `definition.locks[]`: `{lockId, from, to, keyId, keyRoomId, keyLayoutId, keyLabel}`.
- `definition.puzzles[]`: `{puzzleId, roomId, kind, flagId, gateRoomId, gateLayoutId, leverCount, solutionOrder}`.
- `InventoryService.add_dungeon_key` / `has_dungeon_key` / `consume_dungeon_key` / `dungeon_keys_for_floor` / `clear_dungeon_keys`.
- `WorldState` flags: `WorldFlags.lock_opened(lockId)` on door open; `WorldFlags.lever_pulled(flagId)` on puzzle solve; `WorldFlags.secret_opened(questKeyId)` on NPC talk.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Content tagging | IMPLEMENTED | `room_content_assigner.gd:84-132` |
| Normalized off-path weights | IMPLEMENTED | `room_content_assigner.gd:207-236`, `room_content_config.gd:6-15` |
| Off-path key placement | IMPLEMENTED | `room_content_assigner.gd:318-405` |
| Inventory key loop | IMPLEMENTED | `room_locked_vault_content.gd:84-90`, `room_locked_door_content.gd:97-100` |
| Reward/vault loot | IMPLEMENTED | `room_content_assigner.gd:467-485`, `room_reward_content.gd:11-12` |
| Puzzles | IMPLEMENTED | `room_content_assigner.gd:500-556`, `room_puzzle_content.gd`, `room_puzzle_gate_content.gd` |
| NPC quests | IMPLEMENTED | `dungeon_quest_catalog.gd`, `room_npc_quest_content.gd` |
| Prop anchors | IMPLEMENTED | `room_content_base.gd:16-27` |
| Diorama props | IMPLEMENTED | `diorama_interactable_skin.gd:74-115` |
| Collectible validation | IMPLEMENTED | `room_content_validator.gd:167-195` |
| `merchant` reachable | IMPLEMENTED | weight 0.01 in normalized table |

## Related

- Improvement plan: [`../actual_improvements/room-content.md`](../actual_improvements/room-content.md)
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`procgen-placements.md`](procgen-placements.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`inventory-service.md`](inventory-service.md)
- [`world-state.md`](world-state.md)
