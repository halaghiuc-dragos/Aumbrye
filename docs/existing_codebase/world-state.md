# World state

`WorldState` is a run-scoped key/value store for dungeon locks, levers, keys, and room content. It is on the live play path — dungeon interactables read and write it every run — but it is deliberately not persisted to the save file. Persistence happens indirectly: `castle_run.gd` copies `WorldState.all_flags()` into the `activeRun.snapshot.worldFlags` blob.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/app/world_state.gd` | Autoload `WorldState` — flag store, signals, lifecycle |
| `apps/game/client/scripts/app/world_flags.gd` | `WorldFlags` registry — namespaced id builders and validation |

## How it works

Backing store is one dictionary, `_flags`, declared at `world_state.gd:8`. Flag ids must be three-segment namespaced strings produced by `WorldFlags` builders; `set_flag` rejects anything that fails `WorldFlags.is_valid_id`.

| Member | Behaviour |
|--------|-----------|
| `flag_changed(flag_id, value)` | Emitted on every `set_flag` and `erase_flag` (value is `null` on erase) |
| `namespace_changed(namespace, flag_id, value)` | Emitted on every `set_flag` and `erase_flag` for cheap namespace filtering |
| `reset()` | `_flags.clear()` |
| `set_flag(flag_id, value = true)` | Validates id, deep-stores value, emits both signals |
| `has_flag(flag_id)` | `_flags.has(flag_id)` — presence, not truthiness |
| `is_flag_true(flag_id)` | `bool(_flags.get(flag_id, false))` |
| `get_flag(flag_id, default_value = null)` | Raw `Variant` read |
| `erase_flag(flag_id)` | Removes key; emits `flag_changed(id, null)` |
| `all_flags()` | `duplicate(true)` deep copy |
| `restore_flags(flags)` | Clears, validates keys and scalar/container values, returns rejection count |

### Lifecycle
`_ready()` (`world_state.gd:11-15`) sets `process_mode = PROCESS_MODE_ALWAYS` and connects to three `RunFlow` signals:

- `run_started` → `_on_run_started()`: returns early when `RunFlow.is_continue_restore()` is true, otherwise calls `reset()` and `InventoryService.clear_dungeon_keys()`.
- `run_ended` → `_on_run_ended()`: calls `reset()`.
- `returned_to_hub` → `_on_returned_to_hub()`: calls `reset()`.

### Persistence path
`WorldState` never touches `LocalSave`. The flags reach disk only through the run snapshot:

- Capture: `castle_run.gd:436` writes `"worldFlags": WorldState.all_flags()` into the snapshot returned by `_capture_run_snapshot()`.
- Restore on continue: `castle_run.gd:316` calls `WorldState.restore_flags(snapshot.get("worldFlags", {}))` and logs rejections.
- Restore on bonfire respawn: `run_flow.gd:837` calls `WorldState.restore_flags(checkpoint.get("worldFlags", {}))`.
- Migration: `save_migrator.gd` v4→v5 rewrites legacy `key_*` and `quest_*_active` ids to namespaced `WorldFlags` ids in both `snapshot.worldFlags` and `lastCheckpoint.worldFlags`.

`all_flags()` is a deep duplicate, so nested container values do not alias live state into the snapshot.

### Flag id registry
`WorldFlags` (`world_flags.gd`) defines namespaces `lock`, `lever`, `door`, `room`, `secret`, `chest`, `trap` and builders such as `lock_opened(lock_id)` → `lock.{lock_id}.opened`. Dungeon interactables use these builders exclusively.

## Contracts

**Autoload dependencies:** `RunFlow` (signals), `InventoryService` (`clear_dungeon_keys`).

**Signals emitted:** `flag_changed`, `namespace_changed`. `room_locked_door_content.gd` and `room_locked_vault_content.gd` subscribe to `namespace_changed` for the `lock` namespace.

**Save keys touched indirectly:** `activeRun.snapshot.worldFlags`, `activeRun.lastCheckpoint.worldFlags`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Run-scoped flag store, reset on run start, end, and hub return | IMPLEMENTED | `world_state.gd:17-88` |
| Snapshot capture / restore of `worldFlags` | IMPLEMENTED | `castle_run.gd:316`, `castle_run.gd:436`, `run_flow.gd:837` |
| `flag_changed` / `namespace_changed` reactive consumers | IMPLEMENTED | `room_locked_door_content.gd:24`, `room_locked_vault_content.gd:50` |
| Presence vs truthiness (`has_flag` / `is_flag_true`) | IMPLEMENTED | `world_state.gd:35-40` |
| Deep values captured by copy | IMPLEMENTED | `world_state.gd:56-57`, `world_state.gd:115-118` |
| Flag id registry / naming convention | IMPLEMENTED | `world_flags.gd` |
| Validated restore with rejection count | IMPLEMENTED | `world_state.gd:60-75` |
| `erase_flag` | IMPLEMENTED | `world_state.gd:47-53` |
| v4→v5 legacy worldFlags migration | IMPLEMENTED | `save_migrator.gd:79-108` |

## Related
- Improvement plan: [`../actual_improvements/world-state.md`](../actual_improvements/world-state.md)
- [`run-flow.md`](run-flow.md), [`local-save.md`](local-save.md), [`inventory-service.md`](inventory-service.md)
- Consumers documented elsewhere: [`castle-run.md`](castle-run.md), [`stair-lever.md`](stair-lever.md), [`dungeon-traps.md`](dungeon-traps.md), [`room-content.md`](room-content.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md)
