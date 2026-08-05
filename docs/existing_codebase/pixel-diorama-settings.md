# Pixel diorama settings

`PixelDioramaSettings` is a `RefCounted` class with only static members. It is the single source of truth for every tunable that shapes the pixel look — internal render resolution, surface shader uniforms, shading bands, environment/shadow tuning, and the screen finish pass — and it persists them in the `LocalSave` meta block `pixel_diorama`. It is on the live play path: `PixelDioramaBootstrap.prime()` loads it at boot in four scenes, and `PixelDioramaViewport`, `PixelDioramaStyle`, `VisualLighting`, and `settings_ui.gd` all read from it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd` | The whole system: constants, statics, load/save, and every `apply_*` helper |
| `apps/game/client/scripts/ui/settings_ui.gd` | The only UI that writes these statics (`:194-377`) |
| `apps/game/client/assets/shared/pixel_screen_finish.gdshader` | Loaded by `make_screen_finish_material()` |

## How it works

### Persisted statics

24 statics, each loaded in `load_from_save()` (`:109-140`) and written in `save()` (`:143-173`) under `SAVE_KEY = "pixel_diorama"`:

| Static | Default constant | Value |
|--------|------------------|-------|
| `pixel_scale` | `DEFAULT_PIXEL_SCALE` | `8.0` |
| `color_levels` | `DEFAULT_COLOR_LEVELS` | `6.0` |
| `edge_strength` | `DEFAULT_EDGE_STRENGTH` | `0.24` |
| `stitch_strength` | `DEFAULT_STITCH_STRENGTH` | `0.16` |
| `pattern_strength` | `DEFAULT_PATTERN_STRENGTH` | `0.5` |
| `shade_bands` | `DEFAULT_SHADE_BANDS` | `4.0` |
| `shade_dither` | `DEFAULT_SHADE_DITHER` | `0.55` |
| `light_wrap` | `DEFAULT_LIGHT_WRAP` | `0.16` |
| `rim_strength` | `DEFAULT_RIM_STRENGTH` | `0.08` |
| `linear_tonemap` | `DEFAULT_LINEAR_TONEMAP` | `true` |
| `glow_enabled` | `DEFAULT_GLOW_ENABLED` | `true` |
| `ambient_occlusion_enabled` | `DEFAULT_AMBIENT_OCCLUSION` | `true` |
| `nearest_texture_filter` | `DEFAULT_NEAREST_TEXTURE_FILTER` | `false` |
| `anti_aliasing_off` | `DEFAULT_ANTI_ALIASING_OFF` | `false` |
| `low_res_viewport_enabled` | `DEFAULT_LOW_RES_VIEWPORT` | `true` |
| `viewport_width` / `viewport_height` | `DEFAULT_VIEWPORT_WIDTH/HEIGHT` | `1920` / `1080` |
| `camera_snap_enabled` | `DEFAULT_CAMERA_SNAP` | `false` |
| `screen_finish_enabled` | `DEFAULT_SCREEN_FINISH` | `true` |
| `screen_contrast` | `DEFAULT_CONTRAST` | `1.08` |
| `screen_saturation` | `DEFAULT_SATURATION` | `1.06` |
| `vignette_strength` | `DEFAULT_VIGNETTE` | `0.18` |
| `posterize_levels` | `DEFAULT_POSTERIZE_LEVELS` | `0.0` (off) |
| `shadow_quality` | `DEFAULT_SHADOW_QUALITY` | `1` |
| `particle_quality` | `DEFAULT_PARTICLE_QUALITY` | `1` |

`active_render_height` (`:106`) is not persisted; `PixelDioramaViewport._apply_internal_size()` writes it with the height the `SubViewport` actually renders at.

### Resolution presets

`RESOLUTION_PRESETS` (`:47-76`) holds six 16:9 entries. The first four carry only `label`/`width`/`height`:

`320 x 180 (chunky)`, `480 x 270 (chunky)`, `640 x 360 (fine)`, `854 x 480 (soft)`.

The last two carry `native: true` plus six shader overrides:

| Preset | `pixel_scale` | `color_levels` | `shade_bands` | `edge_strength` | `pattern_strength` | `shade_dither` |
|--------|---------------|----------------|---------------|-----------------|--------------------|----------------|
| `1280 x 720 (HD)` | `3.0` | `12.0` | `6.0` | `0.14` | `0.28` | `0.35` |
| `1920 x 1080 (Full HD, default)` | `2.0` | `16.0` | `8.0` | `0.1` | `0.2` | `0.25` |

`_apply_native_hd_shader_tuning(preset)` (`:262-270`) copies those six values into the statics and additionally forces `nearest_texture_filter = false` and `anti_aliasing_off = false`. It is called from `set_resolution_preset()` (`:246-247`), from `apply_beauty_defaults()` (`:212-214`), and — importantly — from `load_from_save()` (`:138-140`) whenever the saved size matches a native preset.

`is_native_hd_preset()`, `_preset_for_size()`, and `current_resolution_preset()` match presets by exact `width`/`height`; `current_resolution_preset()` returns `-1` for a size that matches nothing, which `settings_ui.gd:221-225` renders as a `Custom (w x h)` item.

`viewport_internal_size()` clamps to a floor of `160 x 90` (`:236-237`).

### Application entry points

- `apply_all()` (`:181-190`) — `apply_rendering_project_settings()`, then `PixelDioramaStyle.clear_material_caches()`, then `PixelDioramaViewport.apply_settings()` via `has_method`, then `apply_to_scene(tree.current_scene)`.
- `save_and_apply()` (`:176-178`) — `save()` then `apply_all()`. Every control in `settings_ui.gd` routes through this via `_toggle()` (`:433`) and `_labeled_slider()` (`:490`).
- `apply_beauty_defaults()` (`:194-223`) — resets all 24 statics to their `DEFAULT_*` constants, re-applies native tuning if the resulting size is native, and calls `save_and_apply()`. Wired to the "Restore recommended look" button (`settings_ui.gd:366-372`).
- `apply_to_scene(root)` (`:451-455`) — `_apply_world_environments()` then `_apply_materials_recursive()`, both full recursive walks.

### Project settings

`apply_rendering_project_settings()` (`:289-316`) writes four `ProjectSettings` keys at runtime:

| Key | `nearest_texture_filter` / `anti_aliasing_off` true | false |
|-----|------|-------|
| `rendering/textures/default_filters/texture_filter` | `TEXTURE_FILTER_NEAREST` | `TEXTURE_FILTER_LINEAR` |
| `rendering/textures/default_filters/anisotropic_filtering_level` | `0` | `2` |
| `rendering/textures/canvas_textures/default_texture_filter` | `TEXTURE_FILTER_NEAREST` | `TEXTURE_FILTER_LINEAR` |
| `rendering/anti_aliasing/quality/msaa_3d` | `0` | `2` |
| `rendering/anti_aliasing/quality/screen_space_aa` | `0` | `1` |

Values are set on the in-memory `ProjectSettings` singleton; `ProjectSettings.save()` is never called, and no `Viewport` property is written.

### Environment and shadows

`configure_environment(environment)` (`:319-335`): `TONE_MAPPER_LINEAR` with `tonemap_white = 1.2` when `linear_tonemap`, otherwise `TONE_MAPPER_FILMIC` with `1.0`. Glow, when enabled, is deliberately tight — `glow_intensity = 0.55`, `glow_bloom = 0.05`, `glow_hdr_threshold = 1.0`, `GLOW_BLEND_MODE_ADDITIVE` — so it haloes emissives instead of softening silhouettes. Then `_configure_occlusion()`.

`_configure_occlusion()` (`:341-353`) sets short-radius SSAO: `ssao_radius = 0.85`, `ssao_intensity = 2.4`, `ssao_power = 1.4`, `ssao_detail = 0.0`, `ssao_horizon = 0.16`, `ssao_sharpness = 1.0`, `ssao_light_affect = 0.1`, `ssao_ao_channel_affect = 0.0`. The comment records the intent: contact shadows, not a dirt wash.

`configure_directional_shadow(light, enable_shadows := true)` (`:361-380`):

| `shadow_quality` | `directional_shadow_max_distance` | `shadow_bias` | `shadow_normal_bias` |
|------------------|----------------------------------|---------------|----------------------|
| `0` | shadows off (early return at `:366-367`) | — | — |
| `1` (default) | `24.0` | `0.01` | `0.2` |
| `2` | `32.0` | `0.008` | `0.18` |

`shadow_opacity = 1.0` and `SHADOW_ORTHOGONAL` in both enabled cases. Normal bias carries the load because large flat box tops sit near-parallel to the sun.

`_apply_world_environments()` (`:458-469`) retunes every `WorldEnvironment` in the tree, and every `DirectionalLight3D` **that already has `shadow_enabled`** — fill lights stay shadowless.

### Material application

`apply_to_shader_material(mat)` (`:401-425`) dispatches on the shader's `resource_path` suffix:

| Suffix constant | Value | Parameters pushed |
|-----------------|-------|-------------------|
| `SURFACE_SHADER_SUFFIX` | `pixel_diorama_surface.gdshader` | `pixel_scale`, `color_levels`, `edge_strength`, `stitch_strength`, `pattern_strength`, `shade_bands`, `shade_dither`, `light_wrap`, `rim_strength` |
| `EMISSIVE_SHADER_SUFFIX` | `pixel_diorama_emissive.gdshader` | `pixel_scale`, `color_levels` |
| `LEGACY_SHADER_SUFFIX` | `pixel_diorama.gdshader` | `pixel_scale` via `pixel_scale_for_pattern_type()`, `color_levels`, `edge_strength`, `stitch_strength`, `pattern_strength` |

Anything else — including `portal_ellipse.gdshader` and `pixel_sky.gdshader` — is left untouched. No file named `pixel_diorama.gdshader` exists in `apps/game/client/assets/`, so the legacy branch and `pixel_scale_for_pattern_type()` (`:383-390`) are unreachable.

`apply_to_standard_material(mat)` (`:428-431`) sets only `texture_filter` from `texture_filter_mode()`.

`_apply_materials_recursive(node)` (`:472-489`) walks the tree and, for every `MeshInstance3D`, applies to `material_override` and to each surface material of the mesh.

### Screen finish

`make_screen_finish_material()` loads `SCREEN_FINISH_SHADER_PATH` (`res://assets/shared/pixel_screen_finish.gdshader`) and calls `apply_to_screen_finish()`, which pushes `contrast`, `saturation`, `vignette_strength`, `posterize_levels`, and resets `damage_pulse` to `0.0` (`:441-448`). The shader's `lift`, `shadow_tint`, `shadow_tint_amount`, `highlight_tint`, `highlight_tint_amount`, `vignette_softness`, and `damage_tint` uniforms are never written from GDScript and keep their shader defaults.

### Derived helpers

- `particle_amount_scale()` (`:226-233`) — `0.45` / `1.0` / `1.35` for `particle_quality` 0 / 1 / 2.
- `camera_snap_step(fov_degrees := 75.0, focus_distance := 5.0)` (`:283-286`) — `2.0 * max(0.5, focus_distance) * tan(fov/2) / max(90, active_render_height)`, floored at `0.001`. At the shipped default (`active_render_height = 1080`, fov 75, 5 m) this is ≈ `0.0071` m; at 180 lines it is ≈ `0.0426` m.
- `texture_filter_mode()` (`:393-398`) — `TEXTURE_FILTER_NEAREST` or `TEXTURE_FILTER_LINEAR`.

## Contracts

- `LocalSave` meta key `pixel_diorama` holds a flat 24-key `Dictionary`. Every read uses `data.get(key, DEFAULT)`, so missing keys are tolerated; there is no version field.
- Shader path suffixes are the dispatch contract for `apply_to_shader_material()`. A new pixel shader must have its suffix registered here or it receives no settings.
- `active_render_height` is written by `PixelDioramaViewport` and read by `camera_snap_step()`.
- `PixelDioramaStyle.clear_material_caches()` is called from `apply_all()`; the two modules are mutually dependent (`PixelDioramaStyle._configure_shader_material()` calls back into `apply_to_shader_material()`).
- `configure_environment()` and `configure_directional_shadow()` are the sanctioned tuning entry points, consumed by `VisualLighting` (`visual_lighting.gd:124`, `:161`, `:192`) and `BiomeRegistry` (`biome_registry.gd:221`, `:233`).
- `QUALITY_LABELS` (`["Low", "Medium", "High"]`) is read directly by `settings_ui.gd:319`, `:333`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Load/save of 24 statics | IMPLEMENTED | `pixel_diorama_settings.gd:109-173` |
| Environment / SSAO / glow tuning | IMPLEMENTED | `pixel_diorama_settings.gd:319-353` |
| Directional shadow tuning | IMPLEMENTED | `pixel_diorama_settings.gd:361-380` |
| Screen finish parameter push | PARTIAL | `:441-448` pushes 5 of the shader's 12 uniforms |
| Runtime `ProjectSettings` writes for texture filter and MSAA | FAKE | `:289-316` writes the in-memory singleton only; `settings_ui.gd:375` tells the player "Filter and AA changes apply at runtime via project settings." |
| Native presets overwrite saved shader tuning on every load | BROKEN | `:138-140` runs `_apply_native_hd_shader_tuning()` after reading the saved values |
| `pixel_scale_for_pattern_type()` and the `LEGACY_SHADER_SUFFIX` branch | STUB | `:383-390`, `:419-425`; no `pixel_diorama.gdshader` exists under `apps/game/client/assets/` |
| `color_levels` reaches the surface shader but is never read by it | BROKEN | pushed at `:408`; declared unused at `assets/shared/pixel_diorama_surface.gdshader:16` — see [`pixel-style.md`](pixel-style.md) |
| `nearest_texture_filter` defaults to `false` | PLACEHOLDER | `:29` |
| `posterize_levels` defaults to `0.0` (pass disabled) | PLACEHOLDER | `:39` |
| `apply_all()` clears all material caches and re-walks the whole scene | PARTIAL | `:181-190`, `:472-489` |
| `apply_to_scene()` mutates shared `load()`ed `.tres` instances | PARTIAL | `:476-487`; `biome_registry.gd:71-84` returns un-duplicated `load()` results |
| Meta block versioning / migration | ABSENT | no version key in `save()` (`:143-171`); `save_migrator.gd:11-26` versions the character save's `schemaVersion` only |
| Validation coverage | ABSENT | `pixel_pipeline_suite.gd:19` only asserts the script file exists |

## Related
- Improvement plan: [`../actual_improvements/pixel-diorama-settings.md`](../actual_improvements/pixel-diorama-settings.md)
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — writes `active_render_height`, consumes `apply_settings()`
- [`pixel-style.md`](pixel-style.md) — the material factories these settings stamp
- [`pixel-camera-snap.md`](pixel-camera-snap.md) — consumer of `camera_snap_step()`
- [`visual-lighting.md`](visual-lighting.md) — consumer of `configure_environment()` / `configure_directional_shadow()`
- [`ui/display_settings.md`](ui/display_settings.md), [`ui/settings.md`](ui/settings.md) — the controls
- [`local-save.md`](local-save.md) — the meta store
