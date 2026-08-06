# Pixel camera snap

## Status: FINISHED

`PixelCameraSnap` quantizes a camera's world-space origin on all three axes and its pitch/yaw onto a pixel-derived grid so surface patterns stop crawling as the camera translates or rotates. It is on the play path when `PixelDioramaSettings.camera_snap_enabled` is true (default): `PixelDioramaViewport._mirrored_transform()` snaps the mirrored render camera every frame. Optional gameplay-camera snap runs in `orbit_camera.gd` when `gameplay_camera_snap_enabled` is true.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/pipeline/pixel_camera_snap.gd` | `snap_origin()`, `snap_basis()`, `rotation_step_radians()`, `snap_transform()` |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_viewport.gd` | Render-camera caller; sets `snap_fov_hint`, passes `_focus_distance()` and `camera_snap_enabled` |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd` | `camera_snap_step()`, `camera_snap_enabled`, `snap_fov_hint`, `active_render_height` |
| `apps/game/client/scripts/camera/orbit_camera.gd` | Optional gameplay-camera snap via `_apply_gameplay_pixel_snap()` |
| `apps/game/client/scripts/ui/settings_ui.gd` | Toggle label and live step tooltip |
| `apps/game/client/scripts/validation/suites/pixel_camera_snap_suite.gd` | Headless behavioural tests |

## How it works

### Origin snap (`snap_origin`)

Quantizes `origin.x`, `origin.y`, and `origin.z` independently with `snappedf(component, step)` on a world-axis grid. `step` comes from `PixelDioramaSettings.camera_snap_step(fov_degrees, focus_distance)`:

`max(0.001, 2.0 * max(0.5, focus_distance) * tan(clamp(fov, 10, 170) / 2) / max(90, active_render_height))`.

Concrete values at fov 75Â° and `focus_distance = 5.0`:

| `active_render_height` | Step |
|-----------------------|------|
| `180` | â‰ˆ 0.0426 m |
| `270` | â‰ˆ 0.0284 m |
| `1080` | â‰ˆ 0.0071 m |

### Rotation snap (`snap_basis`)

`rotation_step_radians(fov_degrees)` returns one rendered pixel of angular travel: `deg_to_rad(clamp(fov, 10, 170)) / max(90, active_render_height)`. `snap_basis()` quantizes euler `x` (pitch) and `y` (yaw) to that step; euler `z` (roll) is left continuous.

`PixelDioramaSettings.snap_fov_hint` is updated by the viewport (and gameplay snap) each frame with the source camera fov so `snap_basis()` needs no rig access.

### `snap_transform(source, fov_degrees, focus_distance, enabled := true)`

1. Returns `source` when `enabled` is false (`pixel_camera_snap.gd`).
2. Computes `step` via `camera_snap_step()`; returns `source` if `step <= 0.0`.
3. Returns `Transform3D(snap_basis(source.basis, enabled), snap_origin(source.origin, step, enabled))`.

### Callers

**Render camera** (`pixel_diorama_viewport.gd:_mirrored_transform`):

```gdscript
PixelDioramaSettings.snap_fov_hint = _source_camera.fov
return PixelCameraSnap.snap_transform(
    _source_camera.global_transform,
    _source_camera.fov,
    _focus_distance(),
    PixelDioramaSettings.camera_snap_enabled
)
```

`_focus_distance()` returns `max(0.5, _spring_arm.spring_length)` when the spring arm resolves, else `SNAP_FOCUS_DISTANCE_FALLBACK` (`5.0`).

Snapping applies to the mirrored render camera only â€” snapping the gameplay `CameraPivot` decoupled yaw from player movement and broke `SpringArm3D` follow (`pixel_diorama_viewport.gd:167-168`).

**Gameplay camera** (`orbit_camera.gd:_apply_gameplay_pixel_snap`): when `gameplay_camera_snap_enabled` is true, snaps `_camera.global_transform` with focus `max(0.5, _smoothed_arm_length)`.

## Contracts

- All snap functions take an explicit `enabled` flag (default `true`); callers pass `PixelDioramaSettings.camera_snap_enabled` for the render path.
- `camera_snap_step()` depends on `active_render_height`, written by `PixelDioramaViewport._apply_internal_size()` while `low_res_viewport_enabled` is true.
- Settings toggle: "Snap camera to pixel grid (recommended)" with tooltip `"Grid step at current resolution: X.X cm"` from `_camera_snap_step_tooltip()` (`settings_ui.gd`). Persisted via `PixelDioramaSettings.save_and_apply()`.
- `DEFAULT_CAMERA_SNAP := true` (`pixel_diorama_settings.gd:35`); `apply_beauty_defaults()` restores it.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| World-axis three-axis origin snap | IMPLEMENTED | `pixel_camera_snap.gd:snap_origin` |
| Rotation quantization (pitch/yaw) | IMPLEMENTED | `pixel_camera_snap.gd:snap_basis`, `rotation_step_radians` |
| On by default | IMPLEMENTED | `pixel_diorama_settings.gd:35`, `:318` |
| Live focus distance (render) | IMPLEMENTED | `pixel_diorama_viewport.gd:_focus_distance`, `_mirrored_transform` |
| Live focus distance (gameplay) | IMPLEMENTED | `orbit_camera.gd:_apply_gameplay_pixel_snap` |
| Pure `enabled` parameter | IMPLEMENTED | `pixel_camera_snap.gd:snap_transform` |
| Behavioural validation | IMPLEMENTED | `pixel_camera_snap_suite.gd` |

## Related
- Improvement plan: [`../actual_improvements/pixel-camera-snap.md`](../actual_improvements/pixel-camera-snap.md) - **FINISHED**
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) â€” SubViewport mirror and focus distance
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) â€” `camera_snap_enabled`, `camera_snap_step()`, `active_render_height`
- [`orbit-camera.md`](orbit-camera.md) â€” gameplay camera rig and optional snap
- [`pixel-style.md`](pixel-style.md) â€” world-space surface patterns whose crawl this stops
