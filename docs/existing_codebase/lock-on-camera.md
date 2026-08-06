# Lock-on camera

The lock-on framing path: how `LockOn` drives `orbit_camera.gd` while a target is held. It spans two files and one per-frame call, `update_lock_on_frame(focus_world, player_eye, delta)`. It is on the live play path.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/camera/lock_on.gd` | Producer: `_update_lock_camera`, `_get_player_eye_position`, `_set_camera_lock_on_active`, `lock_occluded` signal, cached `get_target_height` |
| `apps/game/client/scripts/camera/orbit_camera.gd` | Consumer: `set_lock_on_active`, `update_lock_on_frame`, `_update_lock_on_frame_fp`, `set_lock_target_height`, `on_lock_occluded`, `get_lock_tuning_debug` |

## Tuning constants

All lock-on framing rates and clamps live as named constants on `orbit_camera.gd`:

| Constant | Default | Role |
|----------|---------|------|
| `LOCK_YAW_BLEND_RATE` | `8.0` | yaw tracking while locked |
| `LOCK_PIVOT_BLEND_RATE` | `6.0` | pivot offset lerp |
| `LOCK_SHIFT_PER_METRE` | `0.42` | horizontal framing shift per metre |
| `LOCK_SHIFT_HEIGHT_FACTOR` | `0.18` | extra shift per metre of target height |
| `LOCK_SHIFT_MIN` / `LOCK_SHIFT_MAX` | `0.35` / `2.0` m | framing shift clamp |
| `LOCK_PITCH_BLEND_RATE` | `8.0` | pitch tracking |
| `LOCK_PITCH_BIAS_GAIN` | `6.0` | stick pitch bias integration |
| `LOCK_PITCH_BIAS_DECAY` | `4.0` | pitch bias decay when idle |
| `LOCK_PITCH_BIAS_MAX` | `22` deg | unified mouse/stick pitch bias clamp |
| `LOCK_PITCH_BIAS_IDLE_TIME` | `0.25` s | idle time before decay |
| `LOCK_ACQUIRE_BLEND_RATE` | `18.0` | fast yaw/pitch during acquire window |
| `LOCK_ACQUIRE_TIME` | `0.18` s | acquire snap duration |
| `LOCK_ZOOM_BASE` | `3.6` m | base arm length while locked |
| `LOCK_ZOOM_PER_METRE` | `0.10` | zoom pull-back per planar metre |
| `LOCK_ZOOM_PER_HEIGHT` | `0.55` | zoom pull-back per target height |
| `LOCK_ZOOM_MAX` | `9.0` m | max arm length while locked |
| `LOCK_ZOOM_BLEND_RATE` | `4.0` | smooth zoom and wall pull |
| `LOCK_SPRING_MARGIN` | `0.35` m | spring-arm margin while locked in 3P |
| `LOCK_OCCLUSION_LIFT` | `10` deg | pitch lift during occlusion recovery |
| `LOCK_OCCLUSION_SHIFT` | `0.9` m | extra framing shift during occlusion |
| `LOCK_OCCLUSION_EASE_TIME` | `0.3` s | occlusion blend in/out |
| `_lock_pivot_base` | `Vector3(0, 1.6, 0)` | yaw pivot rest position |

Target height is cached per lock via `LockOn.get_target_height` (mesh AABB) and pushed with `set_lock_target_height`.

## How it works

**Entering.** `LockOn._set_lock` calls `_set_camera_lock_on_active(true)`, which calls `orbit_camera.set_lock_on_active(true)`. That clears pivot offset and pitch bias, starts the `LOCK_ACQUIRE_TIME` acquire window, raises spring margin in third person, connects `lock_occluded` to `on_lock_occluded`, and caches target height.

**Per frame.** `LockOn._update_lock_camera` computes the aim point from `get_target_aim_point(current_target)` and the eye position from `_get_player_eye_position`. It calls `update_lock_on_frame(aim, eye, delta * blend_boost)`.

`orbit_camera.update_lock_on_frame`:

1. Uses `LOCK_ACQUIRE_BLEND_RATE` for yaw/pitch while `_lock_acquire_timer > 0`, then falls back to tracking rates.
2. Routes first person to `_update_lock_on_frame_fp` (yaw + pitch only, no pivot shift or zoom).
3. In third person, blends yaw toward the target, lerps pivot offset with distance- and height-aware shift (plus occlusion bonus), and lerps `spring_length` toward the distance/size-aware zoom target at `LOCK_ZOOM_BLEND_RATE`.
4. Applies unified pitch bias (mouse and stick share `LOCK_PITCH_BIAS_MAX`, decay after idle) plus occlusion lift.
5. `_yaw_for_look_direction` always applies the first-person `+PI` offset when `_first_person` is true.

**Occlusion.** When line of sight fails but the `0.75` s grace timer is active, `LockOn` emits `lock_occluded(true)`. The camera raises pitch and shift; when LOS returns, `lock_occluded(false)` eases them back. The lock only breaks when grace expires.

**Input suppression while locked.** Mouse motion adjusts pitch bias only; stick look and manual zoom are frozen in `_physics_process`. Zoom while locked is driven by framing, not player input.

**Pause.** `LockOn._physics_process` returns when `get_tree().paused` or gameplay is blocked, so the locked camera does not move behind menus.

## Contracts

- `LockOn` requires the node at `CameraPivot/SpringArm3D` to expose `set_lock_on_active(bool)`, `update_lock_on_frame(Vector3, Vector3, float)`, `set_lock_target_height(float)`, `on_lock_occluded(bool)`, and `is_first_person()`.
- `orbit_camera` requires `yaw_pivot_path` to point at a `Node3D` whose parent is the player body.
- The camera writes to `_yaw_pivot.position`; nothing else may own `CameraPivot.position`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Yaw tracking, pitch tracking, player pitch bias | IMPLEMENTED | `orbit_camera.gd` |
| Two-subject framing via pivot offset | IMPLEMENTED | distance + height aware shift |
| Distance- and size-aware zoom while locked | IMPLEMENTED | `LOCK_ZOOM_*` in `update_lock_on_frame` |
| First-person lock-on yaw | IMPLEMENTED | `_update_lock_on_frame_fp`, fixed `_yaw_for_look_direction` |
| Acquire snap window | IMPLEMENTED | `LOCK_ACQUIRE_TIME` / `LOCK_ACQUIRE_BLEND_RATE` |
| Unified pitch bias (mouse + stick) | IMPLEMENTED | single `LOCK_PITCH_BIAS_MAX` + idle decay |
| Occlusion recovery before lock break | IMPLEMENTED | `lock_occluded` signal + lift/shift blend |
| Smooth wall pull while locked | IMPLEMENTED | `LOCK_SPRING_MARGIN` + `LOCK_ZOOM_BLEND_RATE` |
| Pause guard | IMPLEMENTED | `lock_on.gd` `_physics_process` |
| Debug tuning readout | IMPLEMENTED | `get_lock_tuning_debug` in F1 overlay |
| Camera toggle and zoom while locked | BROKEN as designed | input gated while locked; use Page Up/Down for zoom (see lock-on.md) |

## Related
- Improvement plan: [`../actual_improvements/lock-on-camera.md`](../actual_improvements/lock-on-camera.md) — **FINISHED**
- [`lock-on.md`](lock-on.md), [`orbit-camera.md`](orbit-camera.md), [`lock-on-movement.md`](lock-on-movement.md)
- [`pixel-camera-snap.md`](pixel-camera-snap.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md), [`ui/combat_hud.md`](ui/combat_hud.md)
