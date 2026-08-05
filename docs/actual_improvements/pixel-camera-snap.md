# Pixel camera snap — improvement plan

## Current state

`PixelCameraSnap.snap_transform()` quantizes the mirrored render camera's origin along the camera's own right and up axes onto a grid whose size is one rendered pixel at a fixed 5 m focus distance. See [`../existing_codebase/pixel-camera-snap.md`](../existing_codebase/pixel-camera-snap.md). Three things make it ineffective as shipped: it is off by default, the forward axis is never quantized so walking toward or away from a wall still slides sub-pixel, and the snap axes are taken from the camera basis, so orbiting the camera rotates the grid itself and reintroduces exactly the crawl the module exists to remove. The `focus_distance` argument is a hard-coded constant at the only call site rather than the live `SpringArm3D` length.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PCS-01 | P0 | The snap grid is camera-relative. `right` and `up` come from `source.basis` (`:14-15`), so as the orbit camera yaws the two snap axes rotate with it and the quantized positions sweep continuously. During camera rotation — the dominant case for a third-person orbit camera — the feature provides no stabilisation at all. | `pixel_camera_snap.gd:13-21`; [`orbit-camera.md`](orbit-camera.md) |
| PCS-02 | P1 | The forward axis is never snapped. Only `basis.x` and `basis.y` projections are quantized, so translation along the view direction is continuous and world-space floor and wall patterns crawl when the player walks toward or away from the camera. | `pixel_camera_snap.gd:14-20` |
| PCS-03 | P1 | Off by default and imperceptible at the default preset. `DEFAULT_CAMERA_SNAP := false`, and at `active_render_height = 1080` the step is ≈ 0.0071 m, well below the scale at which pattern crawl is visible — so a player who enables the toggle at the shipped resolution sees no difference and concludes it does nothing. | `pixel_diorama_settings.gd:34`, `:215`, `:283-286`; `pixel_diorama_settings.gd:32-33` |
| PCS-04 | P1 | `focus_distance` is the constant `SNAP_FOCUS_DISTANCE = 5.0` at the only call site, not the live boom. The grid is therefore wrong whenever the camera zooms, whenever lock-on pulls the camera back, and whenever a boss arena widens the framing. | `pixel_diorama_viewport.gd:12`, `:106-111` |
| PCS-05 | P1 | Rotation is never quantized. Because `Transform3D(source.basis, snapped_origin)` keeps the basis, the projected screen position of a static vertex still moves by sub-pixel amounts every frame the camera rotates, which is the same artefact the origin snap removes for translation. | `pixel_camera_snap.gd:21` |
| PCS-06 | P2 | `snap_transform()` reads `PixelDioramaSettings.camera_snap_enabled` internally, so it cannot be exercised in isolation and a test must mutate a global static to cover either branch. | `pixel_camera_snap.gd:8-9` |
| PCS-07 | P2 | No behavioural validation. `pixel_pipeline_suite.gd` only asserts the script file exists. | `pixel_pipeline_suite.gd:18` |

## Target design

### World-axis grid, all three axes

Quantize in world space, not camera space. The pattern the snap protects is itself world-space for floors and walls (`pixel_diorama_surface.gdshader:44-46` uses `v_world_pos` for `surface_kind` 0 and 1), so the grid must be world-aligned to be stable under rotation.

```gdscript
## Quantizes a camera origin onto a world-axis grid of `step` metres.
## `enabled` is passed in so the function is pure and testable.
static func snap_origin(origin: Vector3, step: float, enabled: bool = true) -> Vector3:
    if not enabled or step <= 0.0:
        return origin
    return Vector3(
        snappedf(origin.x, step),
        snappedf(origin.y, step),
        snappedf(origin.z, step)
    )
```

`snap_transform()` becomes a thin wrapper that keeps the existing signature for the viewport, plus the explicit `enabled` parameter:

```gdscript
static func snap_transform(
    source: Transform3D,
    fov_degrees: float,
    focus_distance: float,
    enabled: bool = true
) -> Transform3D:
    var step := PixelDioramaSettings.camera_snap_step(fov_degrees, focus_distance)
    return Transform3D(snap_basis(source.basis, enabled), snap_origin(source.origin, step, enabled))
```

Rejected alternative: keeping camera-relative axes and adding a third camera-relative axis. Rejected because the world-space patterns are anchored to world axes; snapping along rotating axes cannot stabilise them.

### Rotation quantization

Yaw and pitch are quantized to a step derived from the render height, so the same rendered pixel budget governs both translation and rotation:

```gdscript
## One rendered pixel of angular travel at the frame's vertical resolution.
static func rotation_step_radians(fov_degrees: float) -> float:
    var height := float(maxi(90, PixelDioramaSettings.active_render_height))
    return deg_to_rad(clampf(fov_degrees, 10.0, 170.0)) / height

static func snap_basis(basis: Basis, enabled: bool = true) -> Basis:
    if not enabled:
        return basis
    var step := rotation_step_radians(PixelDioramaSettings.snap_fov_hint)
    var euler := basis.get_euler()
    return Basis.from_euler(Vector3(snappedf(euler.x, step), snappedf(euler.y, step), euler.z))
```

Roll (`euler.z`) is left continuous: the orbit camera does not roll, and quantizing it would fight any future camera-shake implementation. At `active_render_height = 270` and fov 75° the step is ≈ 0.0048 rad ≈ 0.28°, which is small enough that camera control still feels analogue while removing the sub-pixel sweep.

Rejected alternative: quantizing the look-at target instead of the basis. Rejected because the render camera is a mirror with no target of its own, and reconstructing one introduces a second source of truth for orientation.

### Live focus distance

The viewport supplies the real boom length; see [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) `PDP-03` for the `_focus_distance()` helper. `PixelCameraSnap` gains no knowledge of the rig — it stays a pure function of `(transform, fov, distance, enabled)`.

### Defaults and honesty

`DEFAULT_CAMERA_SNAP := true`. With the default preset moving to `480 x 270` (see [`pixel-diorama-settings.md`](pixel-diorama-settings.md)) the step becomes ≈ 0.0284 m, which is coarse enough that the difference is visible on the hub fountain rim and the tent roof panels. `apply_beauty_defaults()` stops hard-coding `camera_snap_enabled = false` at `:215` and uses `DEFAULT_CAMERA_SNAP` like every other static.

The Settings label changes from "Snap camera to pixel grid" to "Snap camera to pixel grid (recommended)" and gains a tooltip stating the current step in centimetres, computed live from `camera_snap_step()`, so the player can see why it has no effect at 1080 lines.

### Purity

Every function takes `enabled` explicitly and defaults it to `true`. `PixelDioramaViewport._mirrored_transform()` passes `PixelDioramaSettings.camera_snap_enabled`. This makes both branches reachable in a test without mutating a global.

## Work plan

1. **World-axis three-axis origin snap** — `pixel_camera_snap.gd`: add `snap_origin()`, rewrite `snap_transform()` to use it, add the explicit `enabled` parameter defaulting to `true`; `pixel_diorama_viewport.gd:106-111` passes `PixelDioramaSettings.camera_snap_enabled`. Closes PCS-01, PCS-02, PCS-06.
2. **Live focus distance** — depends on `PDP-03`. `pixel_diorama_viewport.gd` passes `_focus_distance()` instead of `SNAP_FOCUS_DISTANCE`. Closes PCS-04.
3. **Rotation snap** — `pixel_camera_snap.gd`: add `rotation_step_radians()` and `snap_basis()`; add `PixelDioramaSettings.snap_fov_hint` (a plain static updated by the viewport each time it copies `fov`, so the snap module needs no rig access). Closes PCS-05.
4. **Default on** — `pixel_diorama_settings.gd`: `DEFAULT_CAMERA_SNAP := true`, remove the literal `false` at `:215`. `settings_ui.gd:246-250`: new label and a live tooltip showing `camera_snap_step()` in centimetres. Closes PCS-03.
5. **Validation** — new suite, assertions below. Closes PCS-07.

Each step is independently landable. Step 1 alone already fixes the dominant artefact; step 3 depends on step 1 only for the shared `enabled` plumbing.

## Data and schema changes

- `LocalSave` meta block `pixel_diorama` key `camera_snap_enabled` changes default from `false` to `true`. Existing saves that persisted `false` keep it; that is intentional, since a player who turned it off should stay off.
- `snap_fov_hint` is a runtime-only static, not persisted, so no new save key.
- No `content/schemas/` change. No character-save change, so no `save_migrator.gd` version bump.

## Acceptance criteria

- [ ] With snap on, yawing the camera 360° around a stationary player produces a render-camera origin whose world x/y/z components are always exact multiples of `camera_snap_step()`. (PCS-01)
- [ ] Walking straight toward a wall with snap on produces render-camera `origin.z` values that are exact multiples of the step. (PCS-02)
- [ ] A fresh profile has `camera_snap_enabled == true`, and the Settings tooltip reports `2.8 cm` at the `480 x 270` preset and `0.7 cm` at `1920 x 1080`. (PCS-03)
- [ ] Zooming the boom from 5.0 m to 2.0 m halves the reported step. (PCS-04)
- [ ] With snap on, the render camera's yaw is always an exact multiple of `rotation_step_radians()` and its roll is unmodified. (PCS-05)
- [ ] `snap_transform(t, 75.0, 5.0, false)` returns `t` unchanged without reading any `PixelDioramaSettings` static other than inside `camera_snap_step()`. (PCS-06)

## Validation

New suite `apps/game/client/scripts/validation/suites/pixel_camera_snap_suite.gd`, category `graphics`:

| Test id | Assertion |
|---------|-----------|
| `camera_snap.disabled_is_identity` | `snap_transform(t, 75.0, 5.0, false)` is `is_equal_approx(t)` for three arbitrary transforms including one with non-zero roll |
| `camera_snap.origin_on_world_grid` | For 64 random origins and `step = 0.0284`, every component of `snap_origin(o, step)` satisfies `absf(fposmod(c, step)) < 1e-5` or `absf(fposmod(c, step) - step) < 1e-5` |
| `camera_snap.rotation_invariance` | Snapping the same origin under 36 yaw values (10° apart) yields the identical snapped origin every time — the property camera-relative axes violated |
| `camera_snap.depth_axis_snapped` | Advancing an origin by `step * 0.4` along `-Z` eight times produces exactly three distinct snapped `z` values (no continuous slide) |
| `camera_snap.step_scales_with_height` | `camera_snap_step(75.0, 5.0)` at `active_render_height` 180 / 270 / 1080 is within 1 % of `0.0426` / `0.0284` / `0.0071` |
| `camera_snap.step_scales_with_distance` | `camera_snap_step(75.0, 2.0)` is within 1 % of `0.4 * camera_snap_step(75.0, 5.0)` |
| `camera_snap.step_floors` | `camera_snap_step(5.0, 0.1)` clamps fov to 10° and distance to 0.5 m, and returns at least `0.001` |
| `camera_snap.basis_yaw_quantized` | `snap_basis()` output euler `y` is an exact multiple of `rotation_step_radians()`; euler `z` equals the input's |
| `camera_snap.default_enabled` | `PixelDioramaSettings.DEFAULT_CAMERA_SNAP == true` and `apply_beauty_defaults()` leaves `camera_snap_enabled == true` |

Manual checklist (perceptual, not automatable):

- With snap on at `480 x 270`, orbit a full circle around the hub fountain: the checker pattern on the plaza floor must not shimmer or ripple.
- Walk the length of a `castle_hall` room: the running-bond brick on the side walls must not crawl along the wall.
- Toggle snap off and on mid-orbit: the difference must be visible, not merely plausible.

## Related
- Existing behaviour: [`../existing_codebase/pixel-camera-snap.md`](../existing_codebase/pixel-camera-snap.md)
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — supplies the live focus distance (`PDP-03`) and the fov hint
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — `camera_snap_step()`, `active_render_height`, the default preset change
- [`orbit-camera.md`](orbit-camera.md) — the unsnapped gameplay rig
- [`pixel-style.md`](pixel-style.md) — the world-space patterns being stabilised
