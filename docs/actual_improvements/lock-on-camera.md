# Lock-on camera framing — improvement plan

## Status: FINISHED

## Current state

The framing path is `LockOn._update_lock_camera` (`apps/game/client/scripts/camera/lock_on.gd:161-174`) calling `update_lock_on_frame(aim, player_eye, delta)` on the spring arm (`apps/game/client/scripts/camera/orbit_camera.gd:135-176`). It blends yaw toward the target, shifts the yaw pivot sideways so both combatants sit in frame, derives pitch from the aim vector, and allows a bounded manual pitch bias. See [`../existing_codebase/lock-on-camera.md`](../existing_codebase/lock-on-camera.md).

Third-person framing is good. First-person locked framing is broken by 180 degrees: `blend_look_direction` is called with `apply_fp_offset = not _lock_on_active`, which is exactly `false` while locked, so the `+PI` correction that first person requires is skipped and the camera faces away from the target. On top of that, the whole framing has no distance-aware zoom, no target-size awareness, and a validation suite that asserts a method which does not exist.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| LKC-01 | P0 | Locking on in first person points the camera 180 deg away from the target. `update_lock_on_frame` calls `blend_look_direction(flat_dir, ...)`, which computes `_yaw_for_look_direction(dir, not _lock_on_active)`; while locked that argument is `false`, so the `_first_person` `+PI` branch is skipped, unlike `snap_look_direction` and `snap_camera_forward` which both apply it | `orbit_camera.gd:116`, `:179-184`, `:146`, `:100-107`, `:196-200` |
| LKC-02 | P0 | The validation suite asserts a method that does not exist. `lock_on_suite.gd` requires `_update_lock_on_frame_fp` on `orbit_camera.gd`; grep finds no such function, so either the suite passes vacuously or it is a stale assertion masking LKC-01 | `apps/game/client/scripts/validation/suites/lock_on_suite.gd`, absence in `orbit_camera.gd:1-284` |
| LKC-03 | P1 | Zoom is frozen while locked. `_physics_process` returns early on `_lock_on_active`, so `spring_length` stops lerping toward `_target_zoom` and the arm holds whatever length it had at lock time. There is no distance-aware pull-back for a large or distant target | `orbit_camera.gd:68-74` |
| LKC-04 | P1 | Framing ignores target size. The shift is `clampf(planar_dist * 0.42, 0.35, 2.0)` with no term for the target's height or width, so a boss fills the screen at the same offset used for a rat | `orbit_camera.gd:158` |
| LKC-05 | P1 | Every framing rate and gain is an inline literal: `8.0` yaw blend, `6.0` pivot lerp, `0.42` shift factor, `0.35`/`2.0` clamp, `8.0` pitch lerp, `6.0` bias gain, `4.0` bias decay. None are named or documented, so the camera cannot be tuned deliberately | `orbit_camera.gd:146`, `:158`, `:160`, `:168`, `:173`, `:175` |
| LKC-06 | P1 | The spring arm keeps `collision_mask = 1` while locked in third person, so a wall behind the player pulls the camera in and the framing shift fights the wall pull with no dedicated behaviour | `orbit_camera.gd:253-255` |
| LKC-07 | P2 | No acquire transition. `set_lock_on_active(true)` resets the pivot instantly and the yaw then blends at the same rate used for tracking, so acquiring a target off to one side swings at tracking speed rather than with a deliberate snap | `orbit_camera.gd:120-132`, `:146` |
| LKC-08 | P2 | The manual pitch bias has two independent gains and two different clamps for mouse and stick (`LOCK_PITCH_MOUSE_MAX = 28` deg, `LOCK_PITCH_BIAS_MAX = 12` deg) and the mouse path never decays, so mouse and pad players get different framing control | `orbit_camera.gd:29-30`, `:85-91`, `:167-173` |
| LKC-09 | P2 | The framing runs while the game is paused because `LockOn` uses `PROCESS_MODE_ALWAYS` with no `paused` guard in `_physics_process` | `lock_on.gd:33`, `:59-69` |
| LKC-10 | P2 | Occlusion is not handled. If the target moves behind geometry the camera keeps aiming at the same point with only a `0.75` s grace before the lock drops entirely; there is no lift or side-step to regain the view | `lock_on.gd:153-158`, no occlusion handling in `update_lock_on_frame` |

## Target design

**Fix first person.** `update_lock_on_frame` must apply the first-person offset like every other yaw setter. The cleanest form removes the ambiguous flag entirely: `_yaw_for_look_direction` always applies the `_first_person` offset, and the one caller that genuinely wants the un-offset value asks for it explicitly by name. Replace line 116 with a direct call that passes `true`, and delete the `apply_fp_offset` parameter once no caller needs `false`. Then add the missing first-person branch in `update_lock_on_frame`: in first person there is no pivot shift and no arm length, only yaw and pitch, so give it a named path `_update_lock_on_frame_fp(focus_world, player_eye, delta)` — which also makes the existing suite assertion true rather than stale.

**Named framing constants.** All seven literals become tuning constants with the current values as defaults, so behaviour is unchanged on the first commit and tunable after:

| Named constant | Default | Replaces |
|----------------|---------|----------|
| `LOCK_YAW_BLEND_RATE` | `8.0` | the `8.0` at `:146` |
| `LOCK_PIVOT_BLEND_RATE` | `6.0` | the `6.0` at `:160` |
| `LOCK_SHIFT_PER_METRE` | `0.42` | the `0.42` at `:158` |
| `LOCK_SHIFT_MIN` | `0.35` m | the clamp floor at `:158` |
| `LOCK_SHIFT_MAX` | `2.0` m | the clamp ceiling at `:158` |
| `LOCK_PITCH_BLEND_RATE` | `8.0` | the `8.0` at `:175` |
| `LOCK_PITCH_BIAS_GAIN` | `6.0` | the `6.0` at `:168` |
| `LOCK_PITCH_BIAS_DECAY` | `4.0` | the `4.0` at `:173` |
| `LOCK_ACQUIRE_BLEND_RATE` | `18.0` | new, used for `LOCK_ACQUIRE_TIME` after acquiring |
| `LOCK_ACQUIRE_TIME` | `0.18` s | new, duration of the fast acquire swing |

**Distance-aware and size-aware framing.** Restore the zoom lerp while locked and drive `_target_zoom` from the target:

```
desired_zoom = clamp(
	LOCK_ZOOM_BASE + planar_dist * LOCK_ZOOM_PER_METRE + target_height * LOCK_ZOOM_PER_HEIGHT,
	MIN_ZOOM, LOCK_ZOOM_MAX)
```

| Named constant | Default |
|----------------|---------|
| `LOCK_ZOOM_BASE` | `3.6` m |
| `LOCK_ZOOM_PER_METRE` | `0.10` |
| `LOCK_ZOOM_PER_HEIGHT` | `0.55` |
| `LOCK_ZOOM_MAX` | `9.0` m |
| `LOCK_ZOOM_BLEND_RATE` | `4.0` |

`target_height` comes from the aim-point AABB that `LockOn._aim_point_from_meshes` already computes; cache it per lock rather than per frame. The framing shift also scales with it: `shift = clamp(planar_dist * LOCK_SHIFT_PER_METRE + target_height * 0.18, LOCK_SHIFT_MIN, LOCK_SHIFT_MAX)`. A 1.8 m humanoid at 4 m then zooms to `5.0` m with a `1.0` m shift; a 4.0 m boss at 8 m zooms to `6.6` m with a `1.5` m shift.

**One pitch-bias model.** Merge the mouse and stick paths: one clamp `LOCK_PITCH_BIAS_MAX = deg_to_rad(22.0)`, one gain, and the same decay applied to both when the input is idle for more than `0.25` s. Mouse and pad players then frame identically.

**Occlusion recovery before dropping the lock.** When the aim point is occluded, try to recover before the `0.75` s grace expires: raise the pitch bias by up to `LOCK_OCCLUSION_LIFT = deg_to_rad(10.0)` and increase the framing shift by up to `LOCK_OCCLUSION_SHIFT = 0.9` m over `0.3` s, both easing back once the view clears. Only if the target is still occluded when the grace expires does the lock break. This turns most pillar breaks into a small camera adjustment.

**Wall handling.** While locked in third person, keep `collision_mask = 1` but raise the spring arm margin to `LOCK_SPRING_MARGIN = 0.35` m and blend `spring_length` at `LOCK_ZOOM_BLEND_RATE` rather than snapping, so the wall pull reads as a smooth push-in rather than a jolt against the framing shift.

**Acquire snap.** For `LOCK_ACQUIRE_TIME` after `set_lock_on_active(true)`, use `LOCK_ACQUIRE_BLEND_RATE` for yaw and pitch, then fall back to the tracking rates. Acquiring a target 90 deg off centre then completes in `0.18` s instead of drifting for half a second.

**Pause guard.** Fixed in [`lock-on.md`](lock-on.md) by guarding `_physics_process`; noted here because the visible symptom is a moving camera behind a menu.

## Work plan

1. **Fix the first-person yaw.** Add `_update_lock_on_frame_fp`, route `update_lock_on_frame` into it when `_first_person`, always apply the first-person yaw offset, and remove the `apply_fp_offset` parameter. Closes LKC-01 and LKC-02.
2. **Name the eight existing literals** as constants with identical defaults, in one commit with no behaviour change, so the following steps are reviewable. Closes LKC-05.
3. **Restore the zoom lerp while locked** and add the five `LOCK_ZOOM_*` constants driven by distance and cached target height. Closes LKC-03.
4. **Scale the framing shift by target height.** Closes LKC-04.
5. **Merge the pitch-bias model** into one clamp, gain, and decay. Closes LKC-08.
6. **Add the acquire snap window.** Closes LKC-07.
7. **Add occlusion recovery** with `LOCK_OCCLUSION_LIFT` and `LOCK_OCCLUSION_SHIFT`, driven by a new `LockOn.lock_occluded(occluded: bool)` signal emitted from the existing line-of-sight check. Closes LKC-10.
8. **Add `LOCK_SPRING_MARGIN`** and the smoothed wall pull. Closes LKC-06.
9. **Add the pause guard** in `lock_on.gd`. Closes LKC-09.

## Data and schema changes

- No JSON, schema, or save change. Every value is a named constant on `orbit_camera.gd`, except the target height which is derived from geometry already computed by `LockOn`.
- `LockOn` gains one signal, `lock_occluded(occluded: bool)`.
- The camera tuning constants should be surfaced in the debug overlay so they can be tuned in a running build; that is a debug-only read of existing values, not new data.

## Acceptance criteria

- [x] Locking on in first person points the camera at the target, not 180 deg away, and tracking follows it. (LKC-01)
- [x] `orbit_camera.gd` has a `_update_lock_on_frame_fp` method and the suite assertion passes for a real reason. (LKC-02)
- [x] A 1.8 m target at 4 m frames at `5.0` m arm length; a 4.0 m target at 8 m frames at `6.6` m; both are reached within `0.5` s. (LKC-03, LKC-04)
- [x] All eight former literals are named constants and the pre-change camera behaviour is bit-identical at their defaults. (LKC-05)
- [x] Backing into a wall while locked pushes the camera in smoothly rather than snapping. (LKC-06)
- [x] Acquiring a target 90 deg off centre completes the swing in `0.18` s +/- 0.03 s. (LKC-07)
- [x] Mouse and stick pitch bias share one `22` deg clamp and both decay to zero within `0.5` s of releasing the input. (LKC-08)
- [x] With the pause menu open, the locked camera does not move. (LKC-09)
- [x] A target stepping behind a `0.6` m pillar lifts the camera by up to `10` deg and holds the lock instead of dropping it. (LKC-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/lock_on_suite.gd`:

- `lock_on_camera.first_person_yaw_faces_target` — enter first person, lock a target `90` deg to the left, run 30 physics frames, and assert the camera forward dot the direction to the target is greater than `0.98`. This is the direct regression guard for LKC-01.
- `lock_on_camera.third_person_yaw_faces_target` — the same assertion in third person, so the fix cannot regress the working path.
- `lock_on_camera.fp_frame_method_exists` — assert `orbit_camera.gd` has `_update_lock_on_frame_fp` and that it is reached when `_first_person` is `true`.
- `lock_on_camera.zoom_tracks_distance_and_size` — table-drive `(planar_dist, target_height)` pairs `(4.0, 1.8)` and `(8.0, 4.0)` and assert the settled `spring_length` is `5.0` and `6.6` within `0.15`.
- `lock_on_camera.framing_shift_scales_with_height` — assert the shift for a `4.0` m target exceeds the shift for a `1.8` m target at the same distance.
- `lock_on_camera.pitch_bias_single_clamp` — drive the mouse path past `22` deg and assert the clamp; release and assert decay to under `1` deg within `0.5` s.
- `lock_on_camera.acquire_snap_window` — lock a target `90` deg off centre and assert the yaw error is under `5` deg after `0.18` s.
- `lock_on_camera.occlusion_lifts_before_break` — place an occluder, assert the pitch bias rose and `is_locked` is still `true` after `0.5` s, then remove the occluder and assert the bias returns to zero.
- `lock_on_camera.paused_camera_static` — capture the camera transform, pause, feed 10 frames of stick input, and assert the transform is unchanged.

## Related
- Existing state: [`../existing_codebase/lock-on-camera.md`](../existing_codebase/lock-on-camera.md)
- [`lock-on.md`](lock-on.md), [`orbit-camera.md`](orbit-camera.md), [`lock-on-movement.md`](lock-on-movement.md), [`player-controls.md`](player-controls.md)
- [`pixel-camera-snap.md`](pixel-camera-snap.md), [`bosses.md`](bosses.md), [`enemies.md`](enemies.md), [`validation-suites.md`](validation-suites.md)
