# Orbit camera

`orbit_camera.gd` is the script on `Player/CameraPivot/SpringArm3D`. It owns mouse and stick look, pitch clamping, zoom, the first-person toggle and its persistence, lock-on framing, gameplay pixel snapping, shoulder offset, asymmetric spring-arm smoothing, and centralized camera shake/punch/dip/death framing. It is the only gameplay camera in the repo and is on the live play path in every scene that instances `player.tscn`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/camera/orbit_camera.gd` | `extends SpringArm3D` |
| `apps/game/client/scenes/player/player.tscn:106-116` | `CameraPivot` at `(0, 1.6, 0)`, `SpringArm3D` with `spring_length = 4.0`, `collision_mask = 1`, `yaw_pivot_path = "..`, and a `Camera3D` with `current = true` |
| `apps/game/client/scripts/save/local_save.gd` | `is_first_person_camera()` / `set_first_person_camera()` |
| `apps/game/client/scripts/accessibility/accessibility_settings.gd` | Six camera settings with save keys and `settings_changed` listeners |
| `apps/game/client/scripts/art/characters/diorama_viewmodel_pass.gd` | Dedicated SubViewport compositing first-person arms |

## Tuning constants

| Constant | Value |
|----------|-------|
| `MOUSE_SENSITIVITY_BASE` | `0.003` rad per pixel (× `cameraMouseSensitivity`) |
| `STICK_SENSITIVITY_BASE` | `2.5` rad/s (× `cameraStickSensitivity`, stick curve/deadzone) |
| Third-person pitch | `-45`° / `+60`° |
| First-person pitch | `-80`° / `+80`° (blended over `CAMERA_MODE_BLEND_TIME = 0.22` s) |
| `FIRST_PERSON_FOV` | `82.0`° (scaled by `cameraFov` setting) |
| `FIRST_PERSON_NEAR` | `0.02` m |
| `MIN_ZOOM` / `MAX_ZOOM` | `2.5` / `7.0` m |
| `SHOULDER_OFFSET_X` | `0.45` m (third person only) |
| `ARM_PULL_IN_RATE` / `ARM_PUSH_OUT_RATE` | `24.0` / `6.0` |

## How it works

`_ready()` seeds zoom from authored `spring_length`, resolves yaw pivot and `Camera3D`, applies saved first-person preference, connects `AccessibilitySettings.settings_changed`, and captures the mouse only when `PlayerInput.blocked()` is false (via `PlayerControls.capture_mouse_if_allowed()`).

**Look input.** Mouse and stick deltas scale through the six accessibility camera settings. Stick magnitude passes `stick_curve_magnitude()` with `cameraStickDeadzone` and `cameraStickCurve` before scaling. Invert-Y reads `cameraInvertY` for free look and lock pitch bias.

**First person.** Mode toggles blend arm length, FOV, near plane, pitch limits, and shoulder offset over `0.22` s. `DioramaViewmodel` builds arms into a dedicated `SubViewport` (`diorama_viewmodel_pass.gd`) with `near = 0.01`, `fov = 60.0`, composited over the main view. Torso hiding and `AnimDirector.sync_camera_mode()` still run through `DioramaCharacterSkin`.

**Pixel snapping.** When `PixelDioramaSettings.gameplay_camera_snap_enabled` is true (default), `_process` snaps the gameplay `Camera3D` global transform through `PixelCameraSnap` at `SNAP_FOCUS_DISTANCE = 5.0`. The low-res pipeline mirror camera still uses `camera_snap_enabled` separately.

**Lock-on.** `set_lock_on_active()` / `update_lock_on_frame()` frame the target. Mouse wheel zoom and `toggle_camera` work while locked; toggling camera calls `_break_player_lock()` then switches mode. `capture_state()` / `apply_state()` round-trip `lockTargetPath` and re-acquire via `LockOn.request_lock()`.

**Camera effects.** `apply_shake`, `apply_punch`, `apply_landing_dip`, `enter_death_framing`, and `exit_death_framing` centralize offsets on this node, scaled by `AccessibilitySettings.reduce_camera_shake`. `HitFeedback` resolves `camera_path` to the spring arm and calls `apply_punch` / `apply_shake` instead of writing `Camera3D` offsets.

## Contracts

- Must be a `SpringArm3D` at `Player/CameraPivot/SpringArm3D` with a `Camera3D` child named `Camera3D`.
- `yaw_pivot_path` must resolve to a `Node3D` direct child of the player body (`CameraPivot`).
- Public API: `get_yaw_basis()`, `snap_look_direction()`, `blend_look_direction()`, `snap_camera_forward()`, `set_lock_on_active()`, `update_lock_on_frame()`, `is_first_person()`, `capture_state()`, `apply_state()`, plus the five camera-effect entry points.
- `HitFeedback.camera_path` points to `CameraPivot/SpringArm3D`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Settings-driven sensitivity, invert-Y, FOV, stick curve/deadzone | IMPLEMENTED | `accessibility_settings.gd`, `orbit_camera.gd`, `settings_ui.gd` |
| Gameplay camera pixel snap toggle | IMPLEMENTED | `pixel_diorama_settings.gd` `gameplayCameraSnap`, `orbit_camera.gd` |
| First-person FOV/near/pitch blend | IMPLEMENTED | `orbit_camera.gd` `_fp_blend`, `camera_suite.gd` |
| Viewmodel SubViewport pass | IMPLEMENTED | `diorama_viewmodel.gd`, `diorama_viewmodel_pass.gd` |
| Shoulder offset and asymmetric arm rates | IMPLEMENTED | `orbit_camera.gd` |
| Centralized shake/punch | IMPLEMENTED | `orbit_camera.gd`, `hit_feedback.gd` |
| Toggle/zoom while locked | IMPLEMENTED | `orbit_camera.gd` `_unhandled_input` |
| Lock state in camera blob | IMPLEMENTED | `capture_state` / `apply_state` `lockTargetPath` |
| Mouse capture gated on UI | IMPLEMENTED | `orbit_camera.gd`, `player_controls.gd` |

## Related
- Improvement plan: [`../actual_improvements/orbit-camera.md`](../actual_improvements/orbit-camera.md) — **FINISHED**
- [`lock-on-camera.md`](lock-on-camera.md), [`lock-on.md`](lock-on.md), [`locomotion.md`](locomotion.md)
- [`pixel-camera-snap.md`](pixel-camera-snap.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`hit-feedback.md`](hit-feedback.md), [`accessibility.md`](accessibility.md)
