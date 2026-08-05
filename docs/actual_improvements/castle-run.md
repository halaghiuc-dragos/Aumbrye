# Castle run — improvement plan

## Current state

Production castle and endless runs load `castle_run.tscn`, build from a procgen definition, and support boss door, stairs, escape portal, and save/continue. Floor transitions write a `run_snapshot` with `floorTransition: true`, but `_restore_saved_snapshot` deletes that meta before `_apply_floor_transition_spawn` can place the player at the stairs — so every floor change drops the player at the entrance. The hand-authored `forgotten_castle_slice` is disconnected from `RunFlow`. See [`../existing_codebase/castle-run.md`](../existing_codebase/castle-run.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CST-01 | P0 | Floor-transition spawn never runs: `_restore_saved_snapshot` removes `run_snapshot` before `_apply_floor_transition_spawn` | `castle_run.gd:47-48`, `:311`, `:284-287`; snapshot built at `run_flow.gd:577-587` |
| CST-02 | P1 | Stairs room lookup accepts `type == "corridor"` but lever setup only matches `_stairs` template suffix | `run_floor_config.gd:47-53` vs `dungeon_builder.gd:615` |
| CST-03 | P1 | Entry menu Continue ignores `runMode`; endless save shows enabled then `continue_castle_run` rejects | `castle_entry_menu.gd:106-107` vs `run_flow.gd:106-109` |
| CST-04 | P1 | `stair_lever` Shift+descend gated on `_can_ascend` instead of `_can_descend` | `stair_lever.gd:57-58` |
| CST-05 | P2 | `forgotten_castle_slice` has no RunFlow, combat, or save; hardcoded portal paths | `forgotten_castle_slice.gd` (51 lines) |
| CST-06 | P2 | Slice CombatHUD lacks `LockReticle`; no InventoryUI / DebugOverlay | `forgotten_castle_slice.tscn` vs `castle_run.tscn` |
| CST-07 | P2 | `inventory_ui_path` export unused | `castle_run.gd:16` |
| CST-08 | P2 | Fixture `secrets` entry missing `parentRoomId` — mechanisms never spawn from fixture | `content/fixtures/forgotten_castle_slice.json` |
| CST-09 | P2 | Bonfire respawn has no in-scene outcome overlay (`run_respawn_results` ABSENT) | `run_flow.gd:815-847`; grep `run_respawn_results` empty under client |
| CST-10 | P2 | Debug label still says "M2 Castle Run"; `ROOM_SCENES` / `BiomeBox` unused | `castle_run.tscn`; `forgotten_castle_slice.gd:5-14`; `castle_entry_menu.tscn` |

## Target design

### Floor transition spawn (CST-01)

Chosen approach: apply floor-transition spawn **inside** `_restore_saved_snapshot` / `_apply_snapshot` before removing the meta, using the same snapshot dictionary already in hand.

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

Delete the separate `_apply_floor_transition_spawn` call from `_ready`, or make it a no-op that only runs if meta still exists (defense in depth). Rejected alternative: stop removing the meta in restore and rely on call order — fragile if another path restores without transition.

Also extend `_build_floor_transition_snapshot` to omit fake `player` pose keys so continue-restore cannot confuse entrance coords with stair intent.

### Stairs id parity (CST-02)

Single helper used by both objective lookup and lever setup:

```gdscript
# run_floor_config.gd
static func is_stairs_room(room: Dictionary) -> bool:
    var tid := str(room.get("templateId", room.get("template_id", "")))
    return tid.ends_with("_stairs")
```

Drop the `type == "corridor"` branch, or require procgen to always emit `_stairs` template ids. Lever setup calls the same helper. Chosen: tighten the matcher — corridor-without-stairs was never intended to host a lever.

### Continue button honesty (CST-03)

`CastleEntryMenu._refresh` enables Continue only when `has_continuable_run()` **and** `str(LocalSave.get_active_run().get("runMode", "castle")) in ["castle", ""]`. Endless continue stays on the endless portal menu.

### Slice retirement (CST-05, CST-06, CST-08)

Chosen: keep the scene as a **editor/validation fixture** only. Document that in the scene root comment and room README; do not wire it to `RunFlow`. Fix fixture `parentRoomId` so `DungeonBuilder.build()` validation stays useful. Rejected: converting the slice into a second play path — duplicates boss door / save / HUD work already on `castle_run`.

### Bonfire outcome toast (CST-09)

Align with run-flow RFL-05: `_bonfire_death_respawn` sets root meta `run_respawn_results`; `castle_run._ready` reads once, shows a non-blocking HUD banner (XP granted / deferred / loot stripped), clears meta. Land after the shared `RunLifecycle.build_results` work so the dictionary shape matches results screen keys.

## Work plan

1. **Fix floor-transition spawn ordering** — `castle_run.gd`. Closes CST-01.
2. **Unify stairs room predicate** — `run_floor_config.gd`, `dungeon_builder.gd`. Closes CST-02.
3. **Filter Continue by runMode** — `castle_entry_menu.gd`. Closes CST-03.
4. **Fix Shift+descend gate** — `stair_lever.gd`. Closes CST-04.
5. **Fixture parentRoomId + slice comments** — fixture JSON + `forgotten_castle_slice.gd` header. Closes CST-05 (as "fixture only"), CST-08.
6. **Remove dead exports / stale label / unused BiomeBox** — `castle_run.gd`, `.tscn`, menu scene. Closes CST-07, CST-10.
7. **Bonfire respawn results meta + HUD read** — `run_flow.gd`, `castle_run.gd`, combat HUD. Closes CST-09 (coordinate with RFL-05).

## Data and schema changes

No content schema change. Fixture JSON gains `parentRoomId` on secrets (CST-08). Bonfire overlay uses runtime meta only; if `activeRun` shape changes for respawn honesty, follow `save_migrator` bump defined in run-flow RFL-06 (v4→v5) — do not invent a parallel migrator here.

## Acceptance criteria

- [ ] Ascending from floor N to N+1 places the player at the ascending stair spawn of floor N+1, not the entrance. (CST-01)
- [ ] Descending places the player at the descending stair spawn. (CST-01)
- [ ] Every room returned by `find_stairs_room_id` has a `StairLever` after build. (CST-02)
- [ ] With an endless `activeRun`, the castle entry Continue button is disabled. (CST-03)
- [ ] Shift+interact on a descend-only lever calls `descend_floor`. (CST-04)
- [ ] Fixture build places secret mechanisms when `parentRoomId` is set. (CST-08)
- [ ] Bonfire death shows XP/loot summary without leaving the dungeon scene. (CST-09)

## Validation

| Assertion id | Suite | Checks |
|--------------|-------|--------|
| `castle.floor_transition.stair_spawn` | `flow_suite` or castle suite | Simulate transition snapshot meta, call restore path, assert player near stair spawn |
| `castle.stairs.lever_parity` | procgen / builder suite | For generated defs floors 1–3, every stairs room id has a lever child |
| `castle.menu.continue_mode_filter` | hub suite | Endless activeRun → Continue disabled on castle menu |
| `castle.stair_lever.shift_descend` | unit on lever | With `_can_descend` only, Shift path invokes descend |

## Related

- Existing state: [`../existing_codebase/castle-run.md`](../existing_codebase/castle-run.md)
- [`run-flow.md`](run-flow.md) (RFL-04 cache, RFL-05 bonfire), [`stair-lever.md`](stair-lever.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md), [`dungeon-builder.md`](dungeon-builder.md)
