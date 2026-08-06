# Pixel diorama settings — improvement plan

**Status: FINISHED** (implementation synced to [`../existing_codebase/pixel-diorama-settings.md`](../existing_codebase/pixel-diorama-settings.md))

## Current state

`PixelDioramaSettings` is a static-only `RefCounted` that owns 24 persisted tunables and every `apply_*` helper for environment, shadows, materials, and the screen finish. See [`../existing_codebase/pixel-diorama-settings.md`](../existing_codebase/pixel-diorama-settings.md). Three things are actually broken rather than merely rough: `load_from_save()` overwrites the player's saved shader tuning every launch when the resolution is a native preset; `apply_rendering_project_settings()` writes `ProjectSettings` keys that Godot has already consumed, so the texture-filter and MSAA toggles do nothing while the UI claims they apply at runtime; and `apply_to_scene()` mutates the shared `load()`ed instances of the 30 biome `mat_*.tres` files, so a settings change silently rewrites the on-disk resources' in-memory state for every scene.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PDS-01 | P0 | `load_from_save()` reads the saved statics and then calls `_apply_native_hd_shader_tuning()` when the saved size is a native preset, destroying six user-tuned values (`pixel_scale`, `color_levels`, `shade_bands`, `edge_strength`, `pattern_strength`, `shade_dither`) plus `nearest_texture_filter` and `anti_aliasing_off` on every launch. At the shipped default size of `1920 x 1080` this happens for every player. | `pixel_diorama_settings.gd:138-140`, `:262-270`, `:32-33` |
| PDS-02 | P0 | The "Nearest texture filtering" and "Disable MSAA / screen AA" toggles are inert. `apply_rendering_project_settings()` writes five `ProjectSettings` keys in memory and never touches a `Viewport` property or calls `ProjectSettings.save()`; the Settings screen tells the player they apply at runtime. | `pixel_diorama_settings.gd:289-316`; `settings_ui.gd:252-261`, `:374-377` |
| PDS-03 | P0 | `apply_to_scene()` reaches into shared resources. `BiomeRegistry.get_floor_material()` / `get_wall_material()` / `get_accent_material()` return the `load()` singleton for each `mat_*.tres` with no `duplicate()`, and `_apply_materials_recursive()` calls `set_shader_parameter()` on whatever it finds in `material_override`. One settings change rewrites the parameters of the materials every room in every biome shares. | `pixel_diorama_settings.gd:472-489`; `biome_registry.gd:71-84` |
| PDS-04 | P1 | `apply_all()` calls `PixelDioramaStyle.clear_material_caches()` on every slider tick. Dragging one `HSlider` fires `save_and_apply()` per step (`settings_ui.gd:487-491`), so each step discards all four material caches, re-`load()`s the shaders, rebuilds every material, walks the whole scene tree twice, and writes the save file. | `pixel_diorama_settings.gd:181-190`; `settings_ui.gd:487-491`; `:143-173` |
| PDS-05 | P1 | `LEGACY_SHADER_SUFFIX` (`pixel_diorama.gdshader`) and `pixel_scale_for_pattern_type()` are dead. No such shader exists in `apps/game/client/assets/`, so the branch and its three-way `pattern_type` scaling can never run. | `pixel_diorama_settings.gd:14`, `:383-390`, `:419-425` |
| PDS-06 | P1 | `apply_to_screen_finish()` pushes 5 of `pixel_screen_finish.gdshader`'s 12 uniforms. `lift`, `shadow_tint`, `shadow_tint_amount`, `highlight_tint`, `highlight_tint_amount`, `vignette_softness`, and `damage_tint` are hardcoded in the shader and unreachable from data or UI, even though the split-tone pair is what gives the palette its depth. | `pixel_diorama_settings.gd:441-448`; `assets/shared/pixel_screen_finish.gdshader:9-17` |
| PDS-07 | P1 | `nearest_texture_filter` defaults to `false` and `posterize_levels` defaults to `0.0`. A pixel-art game ships with bilinear filtering and the palette-posterize pass off. | `pixel_diorama_settings.gd:29`, `:39` |
| PDS-08 | P1 | `camera_snap_step()` reads `active_render_height`, which `PixelDioramaViewport` only writes while `low_res_viewport_enabled` is true. With the low-res viewport off, the value keeps its stale last write (or the `1080` default), so the snap grid silently uses the wrong scale. | `pixel_diorama_settings.gd:106`, `:283-286`; `pixel_diorama_viewport.gd:87-88`, `:194`, `:204` |
| PDS-09 | P2 | The `pixel_diorama` meta block has no version field and no migration. Renaming or re-ranging any key silently falls back to the default with no way to detect an old block. `save_migrator.gd` versions the character save's `schemaVersion` and does not see meta. | `pixel_diorama_settings.gd:143-173`; `save_migrator.gd:11-26` |
| PDS-10 | P2 | The unreachable `match` arm `0: light.shadow_enabled = false` in `configure_directional_shadow()` — `shadows_on` already gated on `shadow_quality > 0` and returned early. | `pixel_diorama_settings.gd:364-371` |
| PDS-11 | P2 | No validation suite asserts any settings behaviour; the only reference is a file-existence check. | `pixel_pipeline_suite.gd:19` |

`color_levels` is pushed into the surface material at `pixel_diorama_settings.gd:408` but the surface shader never reads it. That gap is owned by [`pixel-style.md`](pixel-style.md) as `PXS-01` because the fix is in the shader.

## Target design

### Preset overrides become explicit, not destructive

Native presets stop mutating the shader statics. Instead the preset carries an optional `tuning` sub-dictionary that is applied *only* when the player selects the preset, never on load:

```gdscript
{
    "label": "1920 x 1080 (Full HD, default)",
    "width": 1920, "height": 1080, "native": true,
    "tuning": {
        "pixel_scale": 2.0, "color_levels": 16.0, "shade_bands": 8.0,
        "edge_strength": 0.1, "pattern_strength": 0.2, "shade_dither": 0.25,
    },
}
```

`set_resolution_preset(index)` applies `tuning` and sets a new persisted flag `tuning_is_preset_default := true`. Any subsequent slider change clears that flag. `load_from_save()` never calls `_apply_native_hd_shader_tuning()`; it applies `tuning` only when `tuning_is_preset_default` is true *and* the saved size matches the preset — which reproduces today's behaviour for players who never touched a slider and preserves the tuning of players who did.

Rejected alternative: dropping preset tuning entirely and shipping one global set of shader values. Rejected because a 320x180 frame genuinely needs a coarser `pixel_scale` than a 1080-line frame; the density has to scale with the render height.

### Filter and AA are viewport properties

`apply_rendering_project_settings()` is replaced by `apply_render_quality(root: Viewport, sub: SubViewport)`, called from `PixelDioramaViewport.apply_settings()`:

```gdscript
static func apply_render_quality(viewports: Array[Viewport]) -> void:
    var msaa := Viewport.MSAA_DISABLED if anti_aliasing_off else Viewport.MSAA_2X
    var ss_aa := Viewport.SCREEN_SPACE_AA_DISABLED if anti_aliasing_off else Viewport.SCREEN_SPACE_AA_FXAA
    for vp in viewports:
        if vp == null:
            continue
        vp.msaa_3d = msaa
        vp.screen_space_aa = ss_aa
```

Texture filtering is handled where it is actually observable: `texture_filter_mode()` already exists and is applied per-material by `apply_to_standard_material()`, and the `SubViewportContainer.texture_filter` is already set from `nearest_texture_filter` in `_apply_internal_size()`. The `ProjectSettings` writes are deleted and the Settings note at `settings_ui.gd:374-377` is rewritten to "Filtering and AA apply immediately." The `rendering/textures/*` keys stay in `project.godot` as the import-time default only.

Note for honesty: with zero texture assets in the repo (see [`pixel-style.md`](pixel-style.md), `PXS-02`), `nearest_texture_filter` currently has almost nothing to filter. It becomes meaningful the moment authored textures land, which is why the setting stays rather than being deleted.

### Materials are never shared across scenes

`BiomeRegistry.get_floor_material()` / `get_wall_material()` / `get_accent_material()` return `duplicate()`d instances, and `PixelDioramaSettings` gains a registry of live materials so `apply_all()` can re-stamp them without walking the tree:

```gdscript
static var _tracked: Array[WeakRef] = []

static func track(mat: ShaderMaterial) -> ShaderMaterial:
    _tracked.append(weakref(mat))
    return mat

static func restamp_tracked() -> void:
    var alive: Array[WeakRef] = []
    for ref in _tracked:
        var mat := ref.get_ref() as ShaderMaterial
        if mat != null:
            apply_to_shader_material(mat)
            alive.append(ref)
    _tracked = alive
```

Every factory in `PixelDioramaStyle` (`make_surface_material`, `make_glow_material`, `make_portal_material`) and `BiomeRegistry`'s three getters route their result through `track()`. `apply_all()` calls `restamp_tracked()` instead of `clear_material_caches()` + `apply_to_scene()`; `apply_to_scene()` shrinks to `_apply_world_environments()` and is kept for scenes with materials authored directly in `.tscn`.

Rejected alternative: `duplicate()` per `MeshInstance3D`. Rejected because a 40x40 room has hundreds of boxes and each duplicate is a separate draw batch; sharing one material per (theme, surface) is what keeps the box-diorama batchable.

### Slider commits are debounced

`save_and_apply()` splits into an immediate visual apply and a debounced persist:

```gdscript
const SAVE_DEBOUNCE_SEC := 0.35

static func apply_live() -> void:
    restamp_tracked()
    _notify_viewport()

static func request_save() -> void:   # restarts a one-shot SceneTree timer
```

`settings_ui.gd`'s `_labeled_slider()` and `_toggle()` call `apply_live()` then `request_save()`. `apply_beauty_defaults()` and `set_resolution_preset()` still call `save()` synchronously because those are discrete commits.

### Screen finish gains a data-driven grade

The seven unreachable uniforms become persisted statics with the shader's current values as defaults, and a `grade` sub-block in the meta:

| Static | Default | Shader uniform |
|--------|---------|----------------|
| `screen_lift` | `0.0` | `lift` |
| `shadow_tint` | `Color(0.18, 0.16, 0.26)` | `shadow_tint` |
| `shadow_tint_amount` | `0.14` | `shadow_tint_amount` |
| `highlight_tint` | `Color(1.0, 0.94, 0.82)` | `highlight_tint` |
| `highlight_tint_amount` | `0.1` | `highlight_tint_amount` |
| `vignette_softness` | `0.85` | `vignette_softness` |

`apply_to_screen_finish()` pushes all of them. Only `screen_lift` and the two tint amounts get UI sliders; the colours are exposed through a small per-biome grade table so `umbral_chapel` can cool its shadows further than `frozen_fortress` (see [`visual-lighting.md`](visual-lighting.md)). `damage_tint` becomes `pulse_tint`, owned by [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) `PDP-08`.

### Defaults that match the art direction

`DEFAULT_NEAREST_TEXTURE_FILTER := true` and `DEFAULT_POSTERIZE_LEVELS := 24.0`. 24 levels is chosen so the finish pass tightens the ramp without visibly banding skin-tone-adjacent palette entries; at 16 the hub's `mat_paper` cream (`Color(0.92, 0.86, 0.68)`) visibly steps.

### Meta versioning

`save()` writes `"version": SETTINGS_VERSION` (starting at `1`). `load_from_save()` reads it and routes unknown-or-zero blocks through `_migrate_settings(data, from_version)`, which for version 0 → 1 does exactly one thing: sets `tuning_is_preset_default` to `true` (old saves cannot distinguish preset tuning from user tuning, and preserving today's behaviour is the safe default).

### Cleanups

- Delete `LEGACY_SHADER_SUFFIX`, `pixel_scale_for_pattern_type()`, and the legacy branch of `apply_to_shader_material()`.
- Delete the unreachable `0:` arm in `configure_directional_shadow()`.
- `active_render_height` is written by `_apply_internal_size()` unconditionally, including the disabled-pipeline path, so `camera_snap_step()` is always correct.

## Work plan

1. **Preset tuning is non-destructive** — `pixel_diorama_settings.gd`: add `tuning` sub-dictionaries and the `tuning_is_preset_default` static, rewrite `set_resolution_preset()` and `load_from_save()`, delete `_apply_native_hd_shader_tuning()`'s call from load. Add the version key and `_migrate_settings()`. Closes PDS-01, PDS-09.
2. **Viewport-level filter and AA** — add `apply_render_quality(viewports)`, delete `apply_rendering_project_settings()`, call the new function from `PixelDioramaViewport.apply_settings()` and `PixelDioramaBootstrap.prime()`, rewrite the Settings note. Closes PDS-02.
3. **Tracked materials** — add `track()` / `restamp_tracked()`; route `PixelDioramaStyle` factories and `BiomeRegistry`'s three getters through it; add `duplicate()` in the three `BiomeRegistry` getters; rewrite `apply_all()`. Closes PDS-03.
4. **Debounced persist** — split `save_and_apply()` into `apply_live()` + `request_save()`; migrate `settings_ui.gd:_toggle()` and `_labeled_slider()`. Closes PDS-04.
5. **Dead-code removal** — drop `LEGACY_SHADER_SUFFIX`, `pixel_scale_for_pattern_type()`, and the unreachable shadow-quality arm. Closes PDS-05, PDS-10.
6. **Full screen-finish grade** — add the six statics, push all uniforms in `apply_to_screen_finish()`, add three sliders in `settings_ui.gd`. Closes PDS-06.
7. **Honest defaults** — flip `DEFAULT_NEAREST_TEXTURE_FILTER` and `DEFAULT_POSTERIZE_LEVELS`. Closes PDS-07.
8. **`active_render_height` always current** — write it in both branches of `_apply_internal_size()` and in `_disable_pipeline()`. Closes PDS-08.
9. **Validation** — new suite file, assertions below. Closes PDS-11.

Steps 1–8 are independently landable; step 3 must land before step 4 because `apply_live()` calls `restamp_tracked()`.

## Data and schema changes

- `LocalSave` meta block `pixel_diorama` gains: `version` (int, `1`), `tuning_is_preset_default` (bool), `screen_lift` (float), `shadow_tint` (Color), `shadow_tint_amount` (float), `highlight_tint` (Color), `highlight_tint_amount` (float), `vignette_softness` (float). Colours are stored as `Color`, which `LocalSave`'s JSON round-trip must handle — if it does not, store them as 3-element float arrays and convert in `load_from_save()`.
- No `content/schemas/` file governs these; they are per-machine display settings. The per-biome grade table added in step 6 lives in `content/biomes/<biome_id>.json` under a new `"grade"` object and requires `content/schemas/biome.v1.json` to gain `grade: {shadowTint, shadowTintAmount, highlightTint, highlightTintAmount}` with `additionalProperties: false`.
- No character-save format change, so no `save_migrator.gd` version bump. The settings block carries its own `version` and is migrated in `_migrate_settings()`.

## Acceptance criteria

- [x] Set `pixel_scale` to `9.5` at the `1920 x 1080` preset, restart, and the value is still `9.5`. (PDS-01)
- [x] Toggling "Disable MSAA / screen AA" changes `PixelDioramaViewport.get_subviewport().msaa_3d` between `MSAA_DISABLED` and `MSAA_2X` within one frame, and no `ProjectSettings.set_setting` call remains in `pixel_diorama_settings.gd`. (PDS-02)
- [x] `BiomeRegistry.get_wall_material("forgotten_castle")` called twice returns two distinct `Resource` instances, and mutating one does not change the other. (PDS-03)
- [x] Dragging the "Pattern strength" slider from 0.0 to 1.0 in one gesture produces exactly one `LocalSave.autosave()` call and zero `clear_material_caches()` calls. (PDS-04)
- [x] `pixel_diorama_settings.gd` contains no reference to `pixel_diorama.gdshader` and no `pattern_type` handling. (PDS-05)
- [x] All 12 uniforms of `pixel_screen_finish.gdshader` are written by `apply_to_screen_finish()` or `pulse_screen()`. (PDS-06)
- [x] A profile with no `pixel_diorama` meta block boots with `nearest_texture_filter == true` and `posterize_levels == 24.0`. (PDS-07)
- [x] With `low_res_viewport_enabled == false` in a 1440-line window, `camera_snap_step(75.0, 5.0)` uses `active_render_height == 1440`. (PDS-08)
- [x] Loading a meta block with no `version` key yields `tuning_is_preset_default == true` and preserves all other saved values. (PDS-09)

## Validation

New suite `apps/game/client/scripts/validation/suites/pixel_settings_suite.gd`, category `graphics`:

| Test id | Assertion |
|---------|-----------|
| `pixel_settings.preset_tuning_not_destructive` | Save `pixel_scale = 9.5` with `viewport_width/height = 1920/1080` and `tuning_is_preset_default = false`; `load_from_save()` returns `9.5` |
| `pixel_settings.preset_tuning_applied_on_select` | `set_resolution_preset(5)` sets `pixel_scale == 2.0` and `tuning_is_preset_default == true` |
| `pixel_settings.no_project_settings_writes` | The source of `pixel_diorama_settings.gd` contains no `ProjectSettings.set_setting` occurrence |
| `pixel_settings.render_quality_applied` | `apply_render_quality([vp])` with `anti_aliasing_off = true` sets `vp.msaa_3d == Viewport.MSAA_DISABLED` and `vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED` |
| `pixel_settings.biome_materials_are_copies` | `BiomeRegistry.get_wall_material(b)` twice returns `!=` instances for all 10 ids in `BiomeRegistry.ALL_BIOMES` |
| `pixel_settings.restamp_tracked` | Track a material, change `pattern_strength`, call `restamp_tracked()`, assert the material's `pattern_strength` parameter matches; then free the material and assert `restamp_tracked()` prunes the dead `WeakRef` |
| `pixel_settings.screen_finish_full_coverage` | Every uniform name parsed out of `pixel_screen_finish.gdshader` is present in the set of parameters written by `apply_to_screen_finish()` plus `{"pulse_tint", "damage_pulse"}` |
| `pixel_settings.defaults_are_pixel_honest` | `DEFAULT_NEAREST_TEXTURE_FILTER == true`, `DEFAULT_POSTERIZE_LEVELS >= 16.0` |
| `pixel_settings.snap_step_scales` | `camera_snap_step(75.0, 5.0)` at `active_render_height = 270` is within 1 % of `0.0284`; at `1080` within 1 % of `0.0071` |
| `pixel_settings.meta_migration_v0` | A block without `version` migrates to `version == 1` with `tuning_is_preset_default == true` and all other keys unchanged |
| `pixel_settings.no_dead_legacy_branch` | `pixel_diorama_settings.gd` has no `pixel_scale_for_pattern_type` symbol |
| `pixel_settings.shadow_quality_matrix` | For `shadow_quality` 0/1/2, `configure_directional_shadow()` produces `shadow_enabled` false/true/true and `directional_shadow_max_distance` `-`/`24.0`/`32.0` |

Extend `content_suite.gd` with `content.biome_grade_<biome_id>` asserting each biome JSON's optional `grade` object validates against `biome.v1.json`.

## Related
- Existing behaviour: [`../existing_codebase/pixel-diorama-settings.md`](../existing_codebase/pixel-diorama-settings.md)
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — owns `pulse_tint` and calls `apply_render_quality()`
- [`pixel-style.md`](pixel-style.md) — owns `PXS-01` (`color_levels`) and the material factories that must call `track()`
- [`pixel-camera-snap.md`](pixel-camera-snap.md) — consumer of `camera_snap_step()`
- [`visual-lighting.md`](visual-lighting.md) — consumer of the per-biome grade table
- [`biome-registry.md`](biome-registry.md) — the three material getters that must duplicate
- [`local-save.md`](local-save.md) — meta block storage and Color round-tripping
