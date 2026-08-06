# Stair lever and floor menu — improvement plan

## Status: FINISHED

## Current state

The stair lever is an authored scene instantiated per `_stairs` room, unlocked when the floor boss dies, and driven through a `MenuShell` modal that pauses the run and exposes explicit `floor_options()` / `use()` APIs. Floor-transition arrival reads the `run_snapshot` meta once in `CastleRun._ready` and passes it to both restore and stair spawn. All ten `<theme>_stairs.tscn` scenes ship `SpawnPoints/LeverSpawn`. See [`../existing_codebase/stair-lever.md`](../existing_codebase/stair-lever.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| STL-01 | P0 | `_restore_saved_snapshot` removed `run_snapshot` before `_apply_floor_transition_spawn` could read it | FINISHED |
| STL-02 | P0 | Only the last lever was retained and unlocked | FINISHED |
| STL-03 | P1 | Nine themes lacked `LeverSpawn`; builder guessed west-wall offset | FINISHED |
| STL-04 | P1 | `StairMenu` did not pause the tree | FINISHED |
| STL-05 | P1 | No gamepad focus on menu buttons | FINISHED |
| STL-06 | P1 | Dead modifier-key fallback in `stair_lever.gd` | FINISHED |
| STL-07 | P1 | Generic prompt with no floor or lock explanation | FINISHED |
| STL-08 | P2 | `StairMenu` read lever private fields | FINISHED |
| STL-09 | P2 | No pull/unlock animation, audio, or VFX | FINISHED |
| STL-10 | P2 | `find_stairs_room_id` disagreed with builder stairs rule | FINISHED |
| STL-11 | P2 | `stairs_spawn_facing_y` null deref | FINISHED |
| STL-12 | P2 | `lever_used` had no listeners | FINISHED |
| STL-13 | P2 | Lever built node-by-node instead of from a scene | FINISHED |
| STL-14 | P2 | Suites only checked script load / source substring | FINISHED |
| STL-15 | P2 | Lever input stayed live while menu open | FINISHED |
| STL-16 | P2 | `close_menu` always re-captured mouse | FINISHED |

## Target design

Implemented as specified in the original plan: `_take_run_snapshot_meta()` in `castle_run.gd`, `_stair_levers: Dictionary` keyed by room id, `stair_lever.tscn` with `AnimationPlayer` and `AudioStreamPlayer3D`, mandatory `LeverSpawn` markers, `MenuShell` buttons with focus ring and pause restore, public `floor_options()` / `use()` API, and `AchievementService.notify("stair_lever_used")` on the `lever_used` signal.

## Work plan

1. **Snapshot meta lifetime** — `castle_run.gd:_take_run_snapshot_meta`, `_restore_saved_snapshot(snapshot)`, `_apply_floor_transition_spawn(snapshot)`. STL-01 FINISHED (`castle_run.gd:46-48`, `:294-325`).
2. **Lever dictionary** — `dungeon_builder.gd:_stair_levers`, `get_stair_lever()` via `find_stairs_room_id`, `push_error` on duplicate stairs room. STL-02 FINISHED (`dungeon_builder.gd:790-868`).
3. **Menu on shell** — pause, focus ring, mouse restore, `_menu_open` guard. STL-04, STL-05, STL-15, STL-16 FINISHED (`stair_menu.gd:25-120`, `stair_lever.gd:45-52`).
4. **Explicit options API** — `floor_options()`, `use()`, per-row `reason`. STL-07, STL-08 FINISHED (`stair_lever.gd:72-118`, `stair_menu.gd:67-115`).
5. **Delete modifier path** — STL-06 FINISHED (`stair_lever.gd` has no `Input.is_key_pressed`).
6. **Authored scene + markers** — `stair_lever.tscn`, all ten `_stairs` scenes. STL-03, STL-13 FINISHED.
7. **Animation, audio, VFX** — `locked_idle`, `unlock`, `pull` animations; `lever_pull` / `lever_unlock` SFX; `VfxService.play_hit_spark` on pull. STL-09 FINISHED (`stair_lever.gd:63-67`, `:175-220`, `audio_director.gd:47-48`).
8. **Helper cleanup** — `find_stairs_room_id` returns `""`; `stairs_spawn_facing_y(null)` returns `0.0`; `lever_used` → `AchievementService`. STL-10, STL-11, STL-12 FINISHED (`run_floor_config.gd:52-63`, `stair_lever.gd:228-230`).
9. **Suite rewrite** — `m7_suite.gd:_test_stair_lever_suite`. STL-14 FINISHED.

## Data and schema changes

- New scene `apps/game/client/scenes/dungeon/stair_lever.tscn`.
- All ten `apps/game/client/scenes/rooms/<theme>/<theme>_stairs.tscn` include `SpawnPoints/LeverSpawn` and top-of-ramp `PlayerSpawn`.
- `audio_director.gd` `SFX_PROFILES` adds `lever_pull` and `lever_unlock` keys.
- No save-format change; unlock remains derived from snapshot `bossDefeated`.

## Acceptance criteria

- [x] After `ascend_floor()`, the player spawns inside the new floor's stair room and remains there after the deferred safety pass (STL-01). Evidence: `flow_suite.gd:376-404`, `castle_run.gd:46-48`.
- [x] A definition with two `_stairs` rooms produces two levers, both unlocked on boss defeat (STL-02). Evidence: `dungeon_suite.gd:894-921`, `m7_suite.gd:451-476`.
- [x] All 10 `<theme>_stairs.tscn` contain `SpawnPoints/LeverSpawn`; `_place_stair_lever_on_wall` has no fallback offset (STL-03). Evidence: `dungeon_builder.gd:836-847`, `m7_suite.gd:383-428`.
- [x] `get_tree().paused` is true while the menu is open and returns to its previous value on close (STL-04). Evidence: `stair_menu.gd:32-52`, `m7_suite.gd:507-528`.
- [x] Opening the menu focuses the first enabled button; up/down move focus in a ring (STL-05). Evidence: `stair_menu.gd:99-118`, `m7_suite.gd:531-552`.
- [x] `stair_lever.gd` contains no `Input.is_key_pressed` call (STL-06). Evidence: `stair_lever.gd:115-120`.
- [x] The unlocked prompt names the current floor; the locked prompt names the boss requirement (STL-07). Evidence: `stair_lever.gd:139-154`, `m7_suite.gd:555-575`.
- [x] `stair_menu.gd` contains no `_lever.get(` and no `_lever.call("_use_lever"` (STL-08). Evidence: `stair_menu.gd:67-115`.
- [x] Pulling the lever plays the `pull` animation and exactly one audio cue before the scene change (STL-09). Evidence: `stair_lever.gd:100-104`, `:214-220`.
- [x] `find_stairs_room_id` returns `""` for a definition with no stairs room; builder and helper agree (STL-10). Evidence: `run_floor_config.gd:52-56`, `dungeon_builder.gd:822-825`.
- [x] `stairs_spawn_facing_y(null)` returns `0.0` without an error (STL-11). Evidence: `run_floor_config.gd:59-61`, `m7_suite.gd:493-504`.

## Validation

`m7_suite.gd:_test_stair_lever_suite` — lever-per-biome build, locked start, dual-lever unlock, `floor_options` shape, null facing helper, menu pause/focus/disabled-reason rows.

`flow_suite.gd:_test_floor_transition_stair_spawn` — stair-side spawn after snapshot restore (STL-01).

`dungeon_suite.gd:_test_stair_levers_all_tracked` — two-lever dictionary unlock (STL-02).

## Related

- [`../existing_codebase/stair-lever.md`](../existing_codebase/stair-lever.md)
- [`dungeon-builder.md`](dungeon-builder.md)
- [`room-templates.md`](room-templates.md)
- [`castle-run.md`](castle-run.md)
- [`ui/menu_shell.md`](ui/menu_shell.md)
