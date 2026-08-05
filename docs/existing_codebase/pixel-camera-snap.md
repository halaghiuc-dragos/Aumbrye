# Pixel camera snap

`PixelCameraSnap` is a 21-line `RefCounted` with one static function. It quantizes a camera's origin onto the world-space pixel grid so surface patterns stop crawling as the camera translates. It is on the play path only when the player has enabled it: `PixelDioramaSettings.camera_snap_enabled` defaults to `false`, and the function returns its input unchanged in that case.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/pipeline/pixel_camera_snap.gd` | The whole system: `snap_transform()` |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_viewport.gd` | Only caller, at `:107` |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd` | Supplies `camera_snap_enabled` (`:95`) and `camera_snap_step()` (`:283-286`) |

## How it works

`snap_transform(source: Transform3D, fov_degrees: float, focus_distance: float) -> Transform3D`:

1. Returns `source` untouched if `PixelDioramaSettings.camera_snap_enabled` is false (`:8-9`).
2. Asks `PixelDioramaSettings.camera_snap_step(fov_degrees, focus_distance)` for the world-space height of one rendered pixel; returns `source` if that is `<= 0.0` (`:10-12`).
3. Takes the camera basis's `x` (right) and `y` (up) vectors and projects the origin onto each: `lateral = right.dot(origin)`, `vertical = up.dot(origin)` (`:13-17`).
4. Adds back the difference between the `snappedf()` projection and the raw projection along each of those two axes (`:19-20`).
5. Returns `Transform3D(source.basis, snapped_origin)` — the basis is never modified (`:21`).

The step is derived in `PixelDioramaSettings.camera_snap_step()` as
`max(0.001, 2.0 * max(0.5, focus_distance) * tan(clamp(fov, 10, 170) / 2) / max(90, active_render_height))`.

Concrete values at fov 75° and `focus_distance = 5.0`:

| `active_render_height` | Step |
|-----------------------|------|
| `180` | ≈ 0.0426 m |
| `270` | ≈ 0.0284 m |
| `1080` (shipped default) | ≈ 0.0071 m |

The single caller is `PixelDioramaViewport._mirrored_transform()`:

```gdscript
return PixelCameraSnap.snap_transform(
    _source_camera.global_transform,
    _source_camera.fov,
    SNAP_FOCUS_DISTANCE
)
```

`SNAP_FOCUS_DISTANCE` is the constant `5.0` (`pixel_diorama_viewport.gd:12`), described in the file as "roughly the third-person camera boom". Snapping is applied to the mirrored render camera only — the header comment at `pixel_diorama_viewport.gd:104-105` records that snapping the gameplay `CameraPivot` decoupled yaw from player movement and broke `SpringArm3D` follow.

## Contracts

- `PixelCameraSnap.snap_transform()` is pure: it reads two statics from `PixelDioramaSettings` and mutates nothing.
- It reads `PixelDioramaSettings.camera_snap_enabled` directly rather than taking an enable flag, so callers cannot force snapping.
- The returned basis is bit-identical to the input basis; callers may rely on rotation being untouched.
- `PixelDioramaSettings.camera_snap_step()` depends on `PixelDioramaSettings.active_render_height`, which `PixelDioramaViewport._apply_internal_size()` writes only while `low_res_viewport_enabled` is true.
- The Settings toggle is "Snap camera to pixel grid" (`settings_ui.gd:246-250`), routed through `_toggle()` which calls `PixelDioramaSettings.save_and_apply()` (`settings_ui.gd:431-434`), so the flag is persisted.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Lateral + vertical origin snap | IMPLEMENTED | `pixel_camera_snap.gd:13-21` |
| Depth (forward) axis snap | ABSENT | only `basis.x` and `basis.y` are used (`:14-20`); nothing quantizes along `basis.z` |
| Rotation quantization | ABSENT | `Transform3D(source.basis, snapped_origin)` returns the basis unchanged (`:21`) |
| Off by default | PLACEHOLDER | `pixel_diorama_settings.gd:34` `DEFAULT_CAMERA_SNAP := false`; `apply_beauty_defaults()` re-asserts `false` at `:215` |
| Snap grid is camera-relative, so it rotates with the camera | PARTIAL | axes come from `source.basis` (`:14-15`), not from world axes |
| Focus distance is a caller-side constant, not the live boom length | FAKE | `pixel_diorama_viewport.gd:12`, `:106-111`; the real value is `CameraPivot/SpringArm3D.spring_length` |
| Behavioural validation | ABSENT | `pixel_pipeline_suite.gd:18` asserts only that the file exists |

## Related
- Improvement plan: [`../actual_improvements/pixel-camera-snap.md`](../actual_improvements/pixel-camera-snap.md)
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — the only caller
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — `camera_snap_enabled`, `camera_snap_step()`, `active_render_height`
- [`orbit-camera.md`](orbit-camera.md) — the gameplay camera rig that is deliberately not snapped
- [`pixel-style.md`](pixel-style.md) — the world-space surface patterns whose crawl this is meant to stop
