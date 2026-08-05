# Lock-on

`LockOn` is the target acquisition, retention, and switching system. It picks a target from group `lockable`, keeps it while range and line of sight hold, cycles between targets, and every physics frame hands an aim point to the camera. It is on the live play path: the node ships in `player.tscn` and the reticle is driven from `combat_hud.gd`.

This doc covers acquisition and retention. The camera framing it drives is in [`lock-on-camera.md`](lock-on-camera.md); the movement it changes is in [`lock-on-movement.md`](lock-on-movement.md).

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/camera/lock_on.gd` | `class_name LockOn extends Node` |
| `apps/game/client/scenes/player/player.tscn:101-104` | Node `LockOn`, `player_path = ".."`, `facing_path = "Facing"` |
| `apps/game/client/scripts/ui/combat_hud.gd` | Reticle projection (`:387-415`) |

## Tuning constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `LOCK_RANGE` | `18.0` | m; acquisition uses flattened distance, retention uses 3D distance |
| `ORBIT_RADIUS` | `1.75` | m; returned by `get_orbit_radius()` for strafe correction |
| `SWITCH_THRESHOLD` | `0.55` | right-stick magnitude that triggers a switch |
| `SWITCH_COOLDOWN` | `0.15` | s between switches |
| `TOGGLE_COOLDOWN` | `0.2` | s between lock/unlock presses |
| `LOS_GRACE_TIME` | `0.75` | s of blocked line of sight tolerated before dropping |
| `LOCK_PICK_CONE_DEG` | `75.0` | half-angle around the camera forward for initial acquisition |

`lock_on.gd:4-13`.

## How it works

`_ready()` (`:32`) sets `process_mode = PROCESS_MODE_ALWAYS`, resolves `_player` from `player_path` (falling back to the parent), `_facing` from `_player`, and `_camera_spring` from `_player.get_node_or_null("CameraPivot/SpringArm3D")`.

`_unhandled_input` (`:44`) returns while `get_tree().paused` or `_is_ui_focused()`. It toggles the lock on `lock_on`, and while locked consumes raw `MOUSE_BUTTON_WHEEL_UP` / `WHEEL_DOWN` to switch targets.

`_physics_process` (`:59`) ticks the three cooldowns and the switch blend boost, then while locked runs `_update_lock`, `_handle_target_switch`, `_update_lock_camera`.

**Acquisition.** `_toggle_lock` (`:81`) tries `_find_best_target(true)` (line of sight required) and falls back to `_find_best_target(false)`. `_find_best_target` (`:268`) iterates group `lockable`, skips defeated nodes, skips anything beyond `LOCK_RANGE` in flattened distance, optionally requires line of sight, rejects anything more than `LOCK_PICK_CONE_DEG` off `_get_lock_search_direction()` (the camera forward flattened, else the facing yaw), and keeps the nearest, breaking ties on the smaller angle.

**Retention.** `_update_lock` (`:140`) drops the lock when the target becomes invalid, advances to another target when it is defeated, drops it beyond `LOCK_RANGE` in true 3D distance, and refreshes `_los_grace_timer` to `LOS_GRACE_TIME` on every frame with clear sight — otherwise it counts down and drops at zero.

`_has_line_of_sight_to` (`:297`) raycasts from `player + (0, 1, 0)` to `get_target_aim_point(target)` on `collision_mask = 1` (`world`), bodies only, excluding the player, the target, and every defeated `lockable`.

**Switching.** `_handle_target_switch` (`:191`) reads `Input.get_vector("look_left", "look_right", "look_up", "look_down")`. A horizontal crossing of `SWITCH_THRESHOLD` calls `_switch_target(+/-1)`, which sorts candidates by `atan2` of their offset in facing-local space and steps one index. A vertical push above the threshold with `abs(stick.x) < 0.2` calls `_switch_target_vertical`, which picks the nearest target above or below the current aim height. Both set `_switch_cooldown` and `_switch_blend_boost = 1.0`, which multiplies the camera blend rate by up to `4.0` for one second (`:167`).

**Aim point.** The static `get_target_aim_point(target)` (`:340`) prefers `target.get_lock_aim_point()`, then the merged AABB centre of the visible meshes under `DioramaVisual`, then the merged AABB of the whole node, then `position + (0, 1.2, 0)`. `_should_skip_lock_aim_mesh` (`:379`) excludes meshes named `TelegraphMesh` or `MeshInstance3D` and anything under a `Hitbox`, `Hurtbox`, `AttackPivot`, or `WeaponPivot`, so the reticle sits on the body rather than on a blockout capsule or a telegraph sphere.

**Death handling.** `_set_lock` connects `Health.died` on the target; `_advance_lock_after_defeat` (`:132`) re-runs `_find_best_target(false, true)` with the cone ignored and breaks the lock if nothing is left.

## Contracts

- Node name `LockOn` under the player body. Looked up by `locomotion.gd:32`, `weapon_controller.gd:82`, `dodge.gd:113`, `player_combat_reactions.gd:133`, `orbit_camera.gd:281`, `combat_hud.gd`.
- Targets must be in group `lockable` and be `Node3D`. Enemy scenes declare it in `groups=[...]` (for example `scenes/enemies/castle_knight.tscn:39`).
- Optional target API: `get_lock_aim_point() -> Vector3`, `is_dead() -> bool`, child node `Health`.
- Signal `lock_changed(target: Node3D, locked: bool)`; consumed by `combat_hud.gd:92-93`.
- Public API: `get_orbit_radius()`, `break_lock()`, static `get_target_aim_point(Node3D)`. Fields `is_locked`, `current_target` are read directly by `weapon_controller.gd:461` and `LockOnMovement`.
- Requires the camera spring to expose `set_lock_on_active(bool)` and either `update_lock_on_frame(...)` or `blend_look_direction(...)` (`:161-173`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Acquisition cone, nearest-target pick, line-of-sight fallback | IMPLEMENTED | `lock_on.gd:81-93`, `:268-294` |
| Retention with LOS grace | IMPLEMENTED | `lock_on.gd:140-158` |
| Horizontal and vertical target switching | IMPLEMENTED | `lock_on.gd:191-253` |
| Auto-advance on target death | IMPLEMENTED | `lock_on.gd:127-137`; covered by `scripts/validation/suites/lock_on_suite.gd:75-147` |
| Mesh-centre aim point | IMPLEMENTED | `lock_on.gd:340-390`; covered by `lock_on_suite.gd:42-70` |
| First-person lock-on policy | BROKEN as validated | `lock_on_suite.gd:26-39` asserts `orbit_camera.gd` contains `func _update_lock_on_frame_fp`. No such function exists, so `lock_on.fp_policy` fails on every run |
| UI gating | PARTIAL | `_is_ui_focused()` checks only `PlayerControls.is_inventory_open()` plus "any Control has focus" (`:415-419`); `is_settings_open`, `is_talents_open`, `is_loadout_open`, `is_pause_open` are ignored even though `PlayerControls.is_player_meta_ui_open()` exists |
| Behaviour while paused | BROKEN | `process_mode = PROCESS_MODE_ALWAYS` (`:33`) keeps `_physics_process` running while `get_tree().paused`, so `_update_lock_camera` continues blending the camera behind the pause menu |
| Range consistency | PARTIAL | Acquisition flattens Y (`:277-278`) while retention does not (`:149`), so a target acquired at 18 m horizontally and 4 m below is dropped on the next frame |
| Reticle presence | PARTIAL | `LockReticle` exists in `scenes/dungeon/castle_run.tscn:61` and `scenes/debug/combat_arena.tscn:204`; it is absent from the `CombatHUD` in `scenes/hub/hub.tscn:269` and `scenes/dungeon/forgotten_castle_slice.tscn:101`, so those scenes show no reticle |
| Gamepad binding | PARTIAL | `lock_on` uses joypad `button_index: 5`, which is `JOY_BUTTON_GUIDE` (`project.godot:183`), and keyboard `Enter`, which is also `ui_accept` (`project.godot:85`) |
| Lock-on SFX or acquisition feedback | ABSENT | No `AudioDirector` call in `lock_on.gd`; `lock_changed` is consumed only by the reticle |
| Target priority weighting (threat, boss, aggression) | ABSENT | `_find_best_target` scores on distance then angle only (`:290`) |

## Related
- Improvement plan: [`../actual_improvements/lock-on.md`](../actual_improvements/lock-on.md)
- [`lock-on-camera.md`](lock-on-camera.md), [`lock-on-movement.md`](lock-on-movement.md), [`orbit-camera.md`](orbit-camera.md)
- [`player-combat.md`](player-combat.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md), [`ui/combat_hud.md`](ui/combat_hud.md), [`validation-suites.md`](validation-suites.md)
