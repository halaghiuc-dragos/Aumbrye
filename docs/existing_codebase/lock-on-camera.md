# Lock-on camera

The lock-on framing path: how `LockOn` drives `orbit_camera.gd` while a target is held. It spans two files and one per-frame call, `update_lock_on_frame(focus_world, player_eye, delta)`. It is on the live play path.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/camera/lock_on.gd` | Producer: `_update_lock_camera` (`:161-173`), `_get_player_eye_position` (`:176-183`), `_set_camera_lock_on_active` (`:186-188`) |
| `apps/game/client/scripts/camera/orbit_camera.gd` | Consumer: `set_lock_on_active` (`:120-132`), `update_lock_on_frame` (`:135-176`), `blend_look_direction` (`:110-117`), `_yaw_for_look_direction` (`:179-184`) |

## Tuning constants

| Constant | Value | Where |
|----------|-------|-------|
| `LOCK_PITCH_BIAS_MAX` | `deg_to_rad(12.0)` | stick pitch bias clamp, `orbit_camera.gd:29` |
| `LOCK_PITCH_MOUSE_MAX` | `deg_to_rad(28.0)` | mouse pitch bias clamp, `orbit_camera.gd:30` |
| `MIN_PITCH` / `MAX_PITCH` | `deg_to_rad(-45.0)` / `deg_to_rad(60.0)` | final pitch clamp, `orbit_camera.gd:5-6` |
| yaw blend rate | `8.0 * delta` | `orbit_camera.gd:146` |
| pitch blend rate | `8.0 * delta` | `orbit_camera.gd:175` |
| pivot offset blend rate | `6.0 * delta` | `orbit_camera.gd:160` |
| pivot shift | `clamp(planar_dist * 0.42, 0.35, 2.0)` m | `orbit_camera.gd:158` |
| switch blend boost | `1.0 + _switch_blend_boost * 3.0` | `lock_on.gd:167` |
| `_lock_pivot_base` | `Vector3(0, 1.6, 0)` | `orbit_camera.gd:27` |

## How it works

**Entering.** `LockOn._set_lock` calls `_set_camera_lock_on_active(true)` (`lock_on.gd:106`), which calls `orbit_camera.set_lock_on_active(true)`. That clears `_lock_pivot_offset` and `_lock_pitch_bias` and resets `_yaw_pivot.position` to `_lock_pivot_base` (`orbit_camera.gd:120-132`). Both branches of that function do the same thing apart from also clearing `_lock_focus` on exit.

**Per frame.** `LockOn._update_lock_camera(delta)` (`:161`) computes the aim point from `get_target_aim_point(current_target)` and the eye position from `_get_player_eye_position()` — the live `Camera3D.global_position` in first person, otherwise `player + (0, 1.6, 0)`. It then calls `update_lock_on_frame(aim, eye, delta * blend_boost)`, where `blend_boost` is `1.0` normally and up to `4.0` for one second after a target switch. If the spring has no `update_lock_on_frame`, it falls back to `blend_look_direction(dir, 8.0 * delta)` (`:169-173`).

`orbit_camera.update_lock_on_frame` (`:135`) then:

1. Stores `_lock_focus` and, in first person only, pins `_yaw_pivot.position` back to `_lock_pivot_base`.
2. Flattens the focus-minus-eye vector and calls `blend_look_direction(flat_dir, 8.0 * delta)`.
3. In third person only, computes the focus and eye in the player body's local space, and lerps `_lock_pivot_offset` toward a shift of `clamp(planar_dist * 0.42, 0.35, 2.0)` along the local aim direction, then writes `_yaw_pivot.position = _lock_pivot_base + _lock_pivot_offset`. This slides the boom toward the target so both combatants stay framed.
4. Computes `target_pitch = asin(aim_dir.y)` from the pivot to the focus, clamped to `MIN_PITCH`/`MAX_PITCH`.
5. Adds a player pitch bias: the right stick's Y integrates into `_lock_pitch_bias` at `LOCK_PITCH_BIAS_MAX * delta * 6.0`, clamped to `+/-12` deg, and decays back to zero at `4.0 * delta` when `abs(stick.y) < 0.15`. Mouse motion feeds the same field through `_apply_lock_pitch_look` with the wider `+/-28` deg clamp (`orbit_camera.gd:85-91`).
6. Lerps `_pitch` toward the biased target at `8.0 * delta` and writes `rotation.x`.

**Input suppression while locked.** `orbit_camera._unhandled_input` routes mouse motion to `_apply_lock_pitch_look` and marks it handled — mouse yaw is dropped entirely — then returns before the `toggle_camera`, `zoom_in`, and `zoom_out` handlers (`orbit_camera.gd:52-58`). `_physics_process` also returns immediately while locked, so stick look and the `spring_length` zoom lerp are both frozen (`orbit_camera.gd:69-74`).

## Contracts

- `LockOn` requires the node at `CameraPivot/SpringArm3D` to expose `set_lock_on_active(bool)` and either `update_lock_on_frame(Vector3, Vector3, float)` or `blend_look_direction(Vector3, float)`, plus `is_first_person()` for the eye position.
- `orbit_camera` requires `yaw_pivot_path` to point at a `Node3D` whose parent is the player body — `update_lock_on_frame` calls `_yaw_pivot.get_parent()` and uses it as the local frame (`:149`).
- The camera writes to `_yaw_pivot.position`, so nothing else may own `CameraPivot.position`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Yaw tracking, pitch tracking, player pitch bias | IMPLEMENTED | `orbit_camera.gd:141-176` |
| Two-subject framing via pivot offset | IMPLEMENTED | `orbit_camera.gd:148-161` |
| Faster blend for one second after a target switch | IMPLEMENTED | `lock_on.gd:64-65`, `:167` |
| First-person lock-on yaw | BROKEN | `blend_look_direction` calls `_yaw_for_look_direction(dir, not _lock_on_active)` (`orbit_camera.gd:116`), so while locked on the first-person `yaw += PI` correction at `:182-183` is skipped. Every other first-person yaw path applies it (`:198-199`). The two paths differ by 180 degrees and only one can be right |
| First-person lock-on helper asserted by validation | ABSENT | `scripts/validation/suites/lock_on_suite.gd:26-39` requires `func _update_lock_on_frame_fp` in `orbit_camera.gd`; the function does not exist and `lock_on.fp_policy` fails |
| Camera collision while locked | PARTIAL | `collision_mask` is only changed by first-person toggling (`orbit_camera.gd:253-255`). While locked in third person the `SpringArm3D` still collides with `world`, so the pivot offset can push the boom into geometry and snap the length |
| Camera toggle and zoom while locked | BROKEN as designed | `orbit_camera.gd:57-58` returns before handling `toggle_camera`, `zoom_in`, and `zoom_out`, so the player cannot switch view or zoom without dropping the lock. Nothing tells the player why |
| Distance-aware framing | ABSENT | `spring_length` is never adjusted for target distance or size while locked; the boom stays at whatever the player last zoomed to (`orbit_camera.gd:74` is skipped while locked) |
| Vertical framing for large bosses | PARTIAL | Pitch tracks the aim point, but `MAX_PITCH = 60` deg caps upward framing and there is no per-target height compensation |
| Behaviour while paused | BROKEN | `LockOn.process_mode = PROCESS_MODE_ALWAYS` (`lock_on.gd:33`) keeps calling `update_lock_on_frame` behind the pause menu |
| Lock-on FOV, vignette, or letterbox emphasis | ABSENT | No `fov` or post-effect change on lock; `pulse_damage_vignette` is the only screen effect hook (`pixel_diorama_viewport.gd:239`) |

## Related
- Improvement plan: [`../actual_improvements/lock-on-camera.md`](../actual_improvements/lock-on-camera.md)
- [`lock-on.md`](lock-on.md), [`orbit-camera.md`](orbit-camera.md), [`lock-on-movement.md`](lock-on-movement.md)
- [`pixel-camera-snap.md`](pixel-camera-snap.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md), [`ui/combat_hud.md`](ui/combat_hud.md)
