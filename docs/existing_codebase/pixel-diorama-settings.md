# Pixel diorama settings

`PixelDioramaSettings` is a `RefCounted` class with only static members. It is the single source of truth for every tunable that shapes the pixel look — internal render resolution, surface shader uniforms, shading bands, environment/shadow tuning, and the screen finish pass — and it persists them in the `LocalSave` meta block `pixel_diorama`. It is on the live play path: `PixelDioramaBootstrap.prime()` loads it at boot in four scenes, and `PixelDioramaViewport`, `PixelDioramaStyle`, `VisualLighting`, and `settings_ui.gd` all read from it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd` | Constants, statics, load/save/migrate, `track()` / `restamp_tracked()`, and every `apply_*` helper |
| `apps/game/client/scripts/ui/settings_ui.gd` | The only UI that writes these statics (`_populate_pixel_diorama_section`) |
| `apps/game/client/assets/shared/pixel_screen_finish.gdshader` | Loaded by `make_screen_finish_material()` |
| `apps/game/client/scripts/validation/suites/pixel_settings_suite.gd` | Graphics validation for preset tuning, render quality, tracked materials, and screen finish |

## How it works

### Persisted statics

31 statics (plus `active_render_height`), loaded in `load_from_save()` and written in `save()` under `SAVE_KEY = "pixel_diorama"`. The block carries `version` (`SETTINGS_VERSION = 1`) and `tuning_is_preset_default`.

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
| `nearest_texture_filter` | `DEFAULT_NEAREST_TEXTURE_FILTER` | `true` |
| `anti_aliasing_off` | `DEFAULT_ANTI_ALIASING_OFF` | `false` |
| `low_res_viewport_enabled` | `DEFAULT_LOW_RES_VIEWPORT` | `true` |
| `viewport_width` / `viewport_height` | `DEFAULT_VIEWPORT_WIDTH/HEIGHT` | `480` / `270` |
| `camera_snap_enabled` | `DEFAULT_CAMERA_SNAP` | `false` |
| `screen_finish_enabled` | `DEFAULT_SCREEN_FINISH` | `true` |
| `screen_contrast` | `DEFAULT_CONTRAST` | `1.08` |
| `screen_saturation` | `DEFAULT_SATURATION` | `1.06` |
| `vignette_strength` | `DEFAULT_VIGNETTE` | `0.18` |
| `posterize_levels` | `DEFAULT_POSTERIZE_LEVELS` | `24.0` |
| `shadow_quality` | `DEFAULT_SHADOW_QUALITY` | `1` |
| `particle_quality` | `DEFAULT_PARTICLE_QUALITY` | `1` |
| `tuning_is_preset_default` | — | `false` (migrated v0 saves → `true`) |
| `screen_lift` | `DEFAULT_SCREEN_LIFT` | `0.0` |
| `shadow_tint` | `DEFAULT_SHADOW_TINT` | `Color(0.18, 0.16, 0.26)` |
| `shadow_tint_amount` | `DEFAULT_SHADOW_TINT_AMOUNT` | `0.14` |
| `highlight_tint` | `DEFAULT_HIGHLIGHT_TINT` | `Color(1.0, 0.94, 0.82)` |
| `highlight_tint_amount` | `DEFAULT_HIGHLIGHT_TINT_AMOUNT` | `0.1` |
| `vignette_softness` | `DEFAULT_VIGNETTE_SOFTNESS` | `0.85` |
| `pulse_tint` | `DEFAULT_PULSE_TINT` | `Color(0.62, 0.08, 0.08)` (runtime only; not persisted) |

`active_render_height` is not persisted; `PixelDioramaViewport._apply_internal_size()` and `_disable_pipeline()` write the height the game actually renders at (SubViewport divisor when low-res is on, window height when off).

### Resolution presets

`RESOLUTION_PRESETS` holds six 16:9 entries. Native HD presets (`1280×720`, `1920×1080`) carry a `tuning` sub-dictionary with six shader values. `set_resolution_preset()` applies `tuning` and sets `tuning_is_preset_default := true`. `load_from_save()` reapplies `tuning` only when `tuning_is_preset_default` is true and the saved size matches — never overwriting user-edited values. Any shader slider change calls `mark_tuning_user_edited()` to clear the flag.

### Application entry points

- `apply_all()` — `restamp_tracked()`, `_notify_viewport()` (calls `PixelDioramaViewport.apply_settings()`), then `apply_to_scene()` for world environments only.
- `apply_live()` — `restamp_tracked()` + `_notify_viewport()`; used by settings sliders/toggles.
- `request_save()` — debounced persist (`SAVE_DEBOUNCE_SEC = 0.35`); pairs with `apply_live()` from the settings UI.
- `save_and_apply()` — synchronous `save()` + `apply_all()`; used for discrete commits (preset select, quality dropdowns, beauty defaults).
- `apply_beauty_defaults()` — resets statics, reapplies native `tuning` when applicable, `save_and_apply()`.
- `track(mat)` / `restamp_tracked()` — weak-ref registry stamped by `apply_to_shader_material()` without walking the scene tree or clearing material caches.
- `bootstrap_scene_materials(root)` — one-time walk to `track()` materials already authored in `.tscn`.

### Render quality

`apply_render_quality(viewports)` sets `msaa_3d` and `screen_space_aa` on each `Viewport`. Called from `PixelDioramaViewport.apply_settings()` and `PixelDioramaBootstrap.prime()`. Texture filtering is per-material via `texture_filter_mode()` and on `SubViewportContainer.texture_filter`. No `ProjectSettings` writes at runtime.

### Tracked materials

`PixelDioramaStyle.make_surface_material()`, `make_glow_material()`, and `make_portal_material()` route results through `track()`. `BiomeRegistry._load_material()` returns `duplicate()`d instances, also tracked. Settings changes restamp live materials without mutating shared `.tres` singletons.

### Screen finish

`apply_to_screen_finish()` pushes all twelve `pixel_screen_finish.gdshader` uniforms. Global statics supply contrast, saturation, lift, split-tone tints, vignette, posterize, and base `pulse_tint`. Per-biome `grade` objects in `content/biomes/*.json` override shadow/highlight tints when `BiomeRegistry.apply_run_presentation()` calls `set_biome_screen_grade()`. Runtime damage/heal/parry pulses set `pulse_tint` and `damage_pulse` via `PixelDioramaViewport.pulse_screen()`.

### Meta migration

`_migrate_settings(data, from_version)` routes unknown-or-zero blocks: v0 → v1 sets `tuning_is_preset_default := true` (safe default for saves that cannot distinguish preset tuning from user edits).

## Contracts

- `LocalSave` meta key `pixel_diorama` holds a versioned dictionary. Colours persist as `[r, g, b]` float arrays.
- Shader path suffixes dispatch `apply_to_shader_material()`. New pixel shaders must register their suffix.
- `active_render_height` is written by `PixelDioramaViewport` and read by `camera_snap_step()`.
- `configure_environment()` and `configure_directional_shadow()` are consumed by `VisualLighting` and `BiomeRegistry`.
- `QUALITY_LABELS` is read directly by `settings_ui.gd` for shadow and particle quality dropdowns.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Load/save with version + migration | IMPLEMENTED | `pixel_diorama_settings.gd` `SETTINGS_VERSION`, `_migrate_settings()` |
| Non-destructive native preset tuning | IMPLEMENTED | `tuning_is_preset_default`, `set_resolution_preset()`, `load_from_save()` |
| Viewport-level MSAA / screen AA | IMPLEMENTED | `apply_render_quality()`; `pixel_diorama_viewport.gd:apply_settings()` |
| Tracked duplicate biome materials | IMPLEMENTED | `track()`, `BiomeRegistry._load_material()` `duplicate()` |
| Debounced slider persist | IMPLEMENTED | `apply_live()`, `request_save()`, `settings_ui.gd` |
| Full screen-finish grade | IMPLEMENTED | six new statics + biome `grade` table |
| Pixel-honest defaults | IMPLEMENTED | `DEFAULT_NEAREST_TEXTURE_FILTER = true`, `DEFAULT_POSTERIZE_LEVELS = 24.0` |
| `active_render_height` when pipeline off | IMPLEMENTED | `_apply_internal_size()` early return, `_disable_pipeline()` |
| Validation suite | IMPLEMENTED | `pixel_settings_suite.gd` |

## Related
- Improvement plan: [`../actual_improvements/pixel-diorama-settings.md`](../actual_improvements/pixel-diorama-settings.md) — **FINISHED**
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — `pulse_screen()`, `active_render_height`
- [`pixel-style.md`](pixel-style.md) — material factories that call `track()`
- [`pixel-camera-snap.md`](pixel-camera-snap.md) — consumer of `camera_snap_step()`
- [`visual-lighting.md`](visual-lighting.md) — per-biome grade consumer
- [`biome-registry.md`](biome-registry.md) — duplicated material getters
- [`local-save.md`](local-save.md) — meta block storage
