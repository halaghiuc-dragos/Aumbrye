# Castle run — improvement plan

## Status: FINISHED

## Current state

Production castle and endless runs load `castle_run.tscn`, build from a procgen definition, and support boss door, stairs, escape portal, and save/continue. Floor transitions apply stair-side spawn inside `_restore_saved_snapshot` before the `run_snapshot` meta is removed. The hand-authored `forgotten_castle_slice` remains an editor/validation fixture only. See [`../existing_codebase/castle-run.md`](../existing_codebase/castle-run.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| CST-01 | P0 | Floor-transition spawn never runs: `_restore_saved_snapshot` removes `run_snapshot` before `_apply_floor_transition_spawn` | FINISHED |
| CST-02 | P1 | Stairs room lookup accepts `type == "corridor"` but lever setup only matches `_stairs` template suffix | FINISHED |
| CST-03 | P1 | Entry menu Continue ignores `runMode`; endless save shows enabled then `continue_castle_run` rejects | FINISHED |
| CST-04 | P1 | `stair_lever` Shift+descend gated on `_can_ascend` instead of `_can_descend` | FINISHED |
| CST-05 | P2 | `forgotten_castle_slice` has no RunFlow, combat, or save; hardcoded portal paths | FINISHED |
| CST-06 | P2 | Slice CombatHUD lacks `LockReticle`; no InventoryUI / DebugOverlay | FINISHED |
| CST-07 | P2 | `inventory_ui_path` export unused | FINISHED |
| CST-08 | P2 | Fixture `secrets` entry missing `parentRoomId` — mechanisms never spawn from fixture | FINISHED |
| CST-09 | P2 | Bonfire respawn has no in-scene outcome overlay (`run_respawn_results` ABSENT) | FINISHED |
| CST-10 | P2 | Debug label still says "M2 Castle Run"; `ROOM_SCENES` / `BiomeBox` unused | FINISHED |

## Target design

### Floor transition spawn (CST-01)

Apply floor-transition spawn **inside** `_restore_saved_snapshot` before removing the meta, using the same snapshot dictionary already in hand.

```gdscript
func _restore_saved_snapshot() -> void:
    ...
    _apply_snapshot(snapshot)
    if bool(snapshot.get("floorTransition", false)):
        _place_at_stair_from_snapshot(snapshot)
    root.remove_meta("run_snapshot")

func _place_at_stair_from_snapshot(snapshot: Dictionary) -> void:
    var ascending := bool(snapshot.get("ascending", true))
    var stair_id := RunFloorConfig.find_stairs_room_id(_resolve_dungeon_definition())
    var spawn_info := _builder.get_stair_spawn_global(stair_id, ascending)
    if spawn_info.is_empty():
        return
    _player.global_position = spawn_info.get("position", _player.global_position)
    _player.rotation.y = float(spawn_info.get("rotationY", _player.rotation.y))
    player_room_id = stair_id
```

`_apply_floor_transition_spawn` remains as defense-in-depth when meta still exists. `_build_floor_transition_snapshot` omits fake `player` pose keys so continue-restore cannot confuse entrance coords with stair intent.

### Stairs id parity (CST-02)

Single helper used by both objective lookup and lever setup:

```gdscript
# run_floor_config.gd
static func is_stairs_room(room: Dictionary) -> bool:
    var tid := str(room.get("templateId", room.get("template_id", "")))
    return tid.ends_with("_stairs")
```

Lever setup and `find_stairs_room_id` both call `is_stairs_room`.

### Continue button honesty (CST-03)

`CastleEntryMenu._refresh_continue_state` enables Continue only when `has_continuable_run()` **and** `str(LocalSave.get_active_run().get("runMode", "castle")) in ["castle", ""]`. Endless continue stays on the endless portal menu.

### Slice retirement (CST-05, CST-06, CST-08)

`forgotten_castle_slice` is documented as an **editor/validation fixture** only in the scene script header and `scenes/rooms/castle/README.md`. Not wired to `RunFlow`. Fixture `parentRoomId` on secrets keeps `DungeonBuilder.build()` validation useful.

### Bonfire outcome toast (CST-09)

`_bonfire_death_respawn` sets root meta `run_respawn_results`; `castle_run._ready` reads once via `_show_respawn_outcome_if_needed`, shows a non-blocking HUD banner through `CombatHUD.show_respawn_outcome`, clears meta.

## Work plan

1. **Fix floor-transition spawn ordering** — `castle_run.gd`. Closes CST-01. FINISHED
2. **Unify stairs room predicate** — `run_floor_config.gd`, `dungeon_builder.gd`. Closes CST-02. FINISHED
3. **Filter Continue by runMode** — `castle_entry_menu.gd`. Closes CST-03. FINISHED
4. **Fix Shift+descend gate** — `stair_lever.gd`. Closes CST-04. FINISHED
5. **Fixture parentRoomId + slice comments** — fixture JSON + `forgotten_castle_slice.gd` header. Closes CST-05 (as "fixture only"), CST-08. FINISHED
6. **Remove dead exports / stale label / unused BiomeBox** — `castle_run.gd`, `.tscn`, menu scene. Closes CST-07, CST-10. FINISHED
7. **Bonfire respawn results meta + HUD read** — `run_flow.gd`, `castle_run.gd`, `combat_hud.gd`. Closes CST-09. FINISHED

## Data and schema changes

Fixture JSON gains `parentRoomId`, `mechanism`, and `wallDirection` on `placements.secrets[]` in `content/fixtures/forgotten_castle_slice.json` (CST-08). Bonfire overlay uses runtime meta only; no save migrator bump.

## Acceptance criteria

- [x] Ascending from floor N to N+1 places the player at the ascending stair spawn of floor N+1, not the entrance. (CST-01)
- [x] Descending places the player at the descending stair spawn. (CST-01)
- [x] Every room returned by `find_stairs_room_id` has a `StairLever` after build. (CST-02)
- [x] With an endless `activeRun`, the castle entry Continue button is disabled. (CST-03)
- [x] Shift+interact on a descend-only lever calls `descend_floor`. (CST-04)
- [x] Fixture build places secret mechanisms when `parentRoomId` is set. (CST-08)
- [x] Bonfire death shows XP/loot summary without leaving the dungeon scene. (CST-09)

## Validation

| Assertion id | Suite | Checks |
|--------------|-------|--------|
| `castle.floor_transition.stair_spawn` | `flow_suite` | Simulate transition snapshot meta, call restore path, assert player near stair spawn |
| `castle.stairs.lever_parity` | `dungeon_suite` | For generated defs floors 1–3, every stairs room id has a lever child |
| `castle.menu.continue_mode_filter` | `hub_suite` | Endless activeRun → Continue disabled on castle menu |
| `castle.stair_lever.shift_descend` | `m7_suite` | With `_can_descend` only, Shift path invokes descend |
| `castle.fixture.secret_parent_room` | `dungeon_suite` | Fixture build spawns `IllusoryWall` in parent courtyard |

## Related

- Existing state: [`../existing_codebase/castle-run.md`](../existing_codebase/castle-run.md)
- [`run-flow.md`](run-flow.md) (RFL-04 cache, RFL-05 bonfire), [`stair-lever.md`](stair-lever.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md), [`dungeon-builder.md`](dungeon-builder.md)
