# Pixel camera snap — improvement plan

## Status: FINISHED

## Current state

`PixelCameraSnap` quantizes the mirrored render camera's world-space origin on all three axes and its yaw/pitch onto a grid derived from `active_render_height` and the live spring-arm focus distance. See [`../existing_codebase/pixel-camera-snap.md`](../existing_codebase/pixel-camera-snap.md). `DEFAULT_CAMERA_SNAP` is `true`, the viewport passes `_focus_distance()` and `camera_snap_enabled`, rotation snap uses `snap_fov_hint`, and `pixel_camera_snap_suite.gd` covers every gap below.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PCS-01 | P0 | ~~The snap grid is camera-relative.~~ **Closed.** `snap_origin()` quantizes world `x`/`y`/`z`. | `pixel_camera_snap.gd:snap_origin` |
| PCS-02 | P1 | ~~The forward axis is never snapped.~~ **Closed.** All three world axes are quantized. | `pixel_camera_snap.gd:snap_origin` |
| PCS-03 | P1 | ~~Off by default and imperceptible at the default preset.~~ **Closed.** `DEFAULT_CAMERA_SNAP := true`; Settings label and tooltip report step in cm. | `pixel_diorama_settings.gd:35`, `settings_ui.gd:_camera_snap_step_tooltip` |
| PCS-04 | P1 | ~~`focus_distance` is the constant `5.0`.~~ **Closed.** Viewport passes `_focus_distance()`; gameplay snap uses `_smoothed_arm_length`. | `pixel_diorama_viewport.gd:_mirrored_transform`, `orbit_camera.gd:_apply_gameplay_pixel_snap` |
| PCS-05 | P1 | ~~Rotation is never quantized.~~ **Closed.** `snap_basis()` quantizes pitch/yaw; roll stays continuous. | `pixel_camera_snap.gd:snap_basis` |
| PCS-06 | P2 | ~~`snap_transform()` reads `camera_snap_enabled` internally.~~ **Closed.** `enabled` is an explicit parameter defaulting to `true`. | `pixel_camera_snap.gd:snap_transform` |
| PCS-07 | P2 | ~~No behavioural validation.~~ **Closed.** `pixel_camera_snap_suite.gd` registered in `validation_runner.gd`. | `validation_runner.gd` |

## Target design

Implemented as specified: world-axis three-axis `snap_origin()`, `snap_basis()` / `rotation_step_radians()`, live focus distance from `_focus_distance()` / `_smoothed_arm_length`, `snap_fov_hint` runtime static, `DEFAULT_CAMERA_SNAP := true`, Settings tooltip with live step in centimetres, and pure `enabled` parameter on all snap functions.

## Work plan

1. **World-axis three-axis origin snap** — done (`pixel_camera_snap.gd`, `pixel_diorama_viewport.gd`).
2. **Live focus distance** — done (`pixel_diorama_viewport.gd`, `orbit_camera.gd`).
3. **Rotation snap** — done (`pixel_camera_snap.gd`, `snap_fov_hint` in `pixel_diorama_settings.gd`).
4. **Default on** — done (`pixel_diorama_settings.gd`, `settings_ui.gd`).
5. **Validation** — done (`pixel_camera_snap_suite.gd`).

## Data and schema changes

- `LocalSave` meta block `pixel_diorama` key `camera_snap_enabled` defaults to `true` for new profiles; existing saves that persisted `false` keep it.
- `snap_fov_hint` is runtime-only, not persisted.
- No `content/schemas/` change. No `save_migrator.gd` bump.

## Acceptance criteria

- [x] With snap on, yawing the camera 360° around a stationary player produces a render-camera origin whose world x/y/z components are always exact multiples of `camera_snap_step()`. (PCS-01)
- [x] Walking straight toward a wall with snap on produces render-camera `origin.z` values that are exact multiples of the step. (PCS-02)
- [x] A fresh profile has `camera_snap_enabled == true`, and the Settings tooltip reports `2.8 cm` at the `480 x 270` preset and `0.7 cm` at `1920 x 1080`. (PCS-03)
- [x] Zooming the boom from 5.0 m to 2.0 m halves the reported step. (PCS-04)
- [x] With snap on, the render camera's yaw is always an exact multiple of `rotation_step_radians()` and its roll is unmodified. (PCS-05)
- [x] `snap_transform(t, 75.0, 5.0, false)` returns `t` unchanged without reading any `PixelDioramaSettings` static other than inside `camera_snap_step()`. (PCS-06)

## Validation

Suite `apps/game/client/scripts/validation/suites/pixel_camera_snap_suite.gd`, category `graphics`:

| Test id | Assertion |
|---------|-----------|
| `camera_snap.disabled_is_identity` | `snap_transform(t, 75.0, 5.0, false)` is `is_equal_approx(t)` for three arbitrary transforms including one with non-zero roll |
| `camera_snap.origin_on_world_grid` | For 64 random origins and `step = 0.0284`, every component of `snap_origin(o, step)` satisfies grid membership |
| `camera_snap.rotation_invariance` | Snapping the same origin under 36 yaw values yields the identical snapped origin every time |
| `camera_snap.depth_axis_snapped` | Advancing an origin by `step * 0.4` along `-Z` eight times produces exactly three distinct snapped `z` values |
| `camera_snap.step_scales_with_height` | `camera_snap_step(75.0, 5.0)` at `active_render_height` 180 / 270 / 1080 is within 1 % of `0.0426` / `0.0284` / `0.0071` |
| `camera_snap.step_scales_with_distance` | `camera_snap_step(75.0, 2.0)` is within 1 % of `0.4 * camera_snap_step(75.0, 5.0)` |
| `camera_snap.step_floors` | `camera_snap_step(5.0, 0.1)` clamps fov to 10° and distance to 0.5 m, and returns at least `0.001` |
| `camera_snap.basis_yaw_quantized` | `snap_basis()` output euler `y` is an exact multiple of `rotation_step_radians()`; euler `z` equals the input's |
| `camera_snap.default_enabled` | `PixelDioramaSettings.DEFAULT_CAMERA_SNAP == true` and settings wire default through `load_from_save` / `apply_beauty_defaults` |

Manual checklist (perceptual, not automatable):

- With snap on at `480 x 270`, orbit a full circle around the hub fountain: the checker pattern on the plaza floor must not shimmer or ripple.
- Walk the length of a `castle_hall` room: the running-bond brick on the side walls must not crawl along the wall.
- Toggle snap off and on mid-orbit: the difference must be visible, not merely plausible.

## Related
- Existing behaviour: [`../existing_codebase/pixel-camera-snap.md`](../existing_codebase/pixel-camera-snap.md)
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — supplies the live focus distance (`PDP-03`) and the fov hint
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — `camera_snap_step()`, `active_render_height`, the default preset change
- [`orbit-camera.md`](orbit-camera.md) — optional gameplay-camera snap path
- [`pixel-style.md`](pixel-style.md) — the world-space patterns being stabilised
