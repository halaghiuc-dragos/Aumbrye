# World state

`WorldState` is a 52-line autoload holding a flat run-scoped key/value dictionary for dungeon locks, levers, keys, and room content. It is on the live play path — dungeon interactables read and write it every run — but it is deliberately not persisted to the save file. Persistence happens indirectly: `castle_run.gd` copies `WorldState.all_flags()` into the `activeRun.snapshot.worldFlags` blob.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/app/world_state.gd` | Autoload `WorldState` — the entire system |

## How it works

Backing store is one dictionary, `_flags`, declared at `world_state.gd:7`. There is no schema, no namespace convention, and no type constraint on values.

| Member | Line | Behaviour |
|--------|------|-----------|
| `flag_changed(flag_id: String, value: Variant)` | 5 | Emitted on every `set_flag` |
| `reset()` | 16 | `_flags.clear()` |
| `set_flag(flag_id, value = true)` | 20 | Assigns and emits `flag_changed` |
| `has_flag(flag_id)` | 25 | `bool(_flags.get(flag_id, false))` — a flag set to `0`, `""`, or `false` reads as absent |
| `get_flag(flag_id, default_value = false)` | 29 | Raw `Variant` read |
| `all_flags()` | 33 | Shallow `duplicate()` |
| `restore_flags(flags)` | 37 | Clears, then copies every key from the supplied dictionary |

### Lifecycle
`_ready()` (`world_state.gd:10-13`) sets `process_mode = PROCESS_MODE_ALWAYS` and connects to two `RunFlow` signals:

- `run_started` → `_on_run_started()` (line 43): returns early when `RunFlow.is_continue_restore()` is true, otherwise calls `reset()` and `InventoryService.clear_dungeon_keys()`.
- `run_ended` → `_on_run_ended()` (line 50): calls `reset()`.

`returned_to_hub` is not connected, so retreating (`RunFlow.retreat_to_hub`) and abandoning (`RunFlow.abandon_active_run`) leave `_flags` populated while the player is in the hub.

### Persistence path
`WorldState` never touches `LocalSave`. The flags reach disk only through the run snapshot:

- Capture: `castle_run.gd:435` writes `"worldFlags": WorldState.all_flags()` into the snapshot returned by `_capture_run_snapshot()`.
- Restore on continue: `castle_run.gd:315` calls `WorldState.restore_flags(snapshot.get("worldFlags", {}))`.
- Restore on bonfire respawn: `run_flow.gd:835` calls `WorldState.restore_flags(checkpoint.get("worldFlags", {}))`.
- Migration default: `save_migrator.gd:67-70` inserts `snapshot.worldFlags = {}` when upgrading a v3 save to v4.

`all_flags()` is a *shallow* duplicate, so a flag whose value is a Dictionary or Array is captured by reference into the snapshot.

## Contracts

**Autoload dependencies:** `RunFlow` (signals), `InventoryService` (`clear_dungeon_keys`).

**Signal emitted:** `flag_changed(flag_id, value)`. No consumer connects to it anywhere under `apps/game/client/scripts/`.

**Save keys touched indirectly:** `activeRun.snapshot.worldFlags`, `activeRun.lastCheckpoint.worldFlags`.

**Flag id namespace:** none enforced. Ids are plain strings supplied by callers; there is no registry, no prefix rule, and no validation that a read matches a write.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Run-scoped flag store, reset on run start and end | IMPLEMENTED | `world_state.gd:16-51` |
| Snapshot capture / restore of `worldFlags` | IMPLEMENTED | `castle_run.gd:435`, `castle_run.gd:315`, `run_flow.gd:835` |
| `flag_changed` signal | STUB | Declared at `world_state.gd:5`, emitted at `world_state.gd:22`, no connection anywhere under `apps/game/client/scripts/` |
| Flags survive retreat / abandon into the hub | PARTIAL | `returned_to_hub` is not connected in `world_state.gd:10-13`; only `run_started` and `run_ended` clear state |
| `has_flag` conflates "unset" with "falsy" | PARTIAL | `world_state.gd:26` returns `bool(...)`, so `set_flag(id, 0)` is indistinguishable from never setting it |
| Deep values captured by reference | PARTIAL | `all_flags()` uses `duplicate()` without `true` (`world_state.gd:34`), so nested containers alias the live flag |
| Flag id registry / naming convention | ABSENT | No constant list, prefix rule, or validation exists in `world_state.gd` or anywhere that calls it |

## Related
- Improvement plan: [`../actual_improvements/world-state.md`](../actual_improvements/world-state.md)
- [`run-flow.md`](run-flow.md), [`local-save.md`](local-save.md), [`inventory-service.md`](inventory-service.md)
- Consumers documented elsewhere: [`castle-run.md`](castle-run.md), [`stair-lever.md`](stair-lever.md), [`dungeon-traps.md`](dungeon-traps.md), [`room-content.md`](room-content.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md)
