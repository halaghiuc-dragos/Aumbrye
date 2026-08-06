# Pixel style — improvement plan

## Status: FINISHED

Implementation synced to [`../existing_codebase/pixel-style.md`](../existing_codebase/pixel-style.md).

## Current state

Palette colours, biome theme mapping, and optional per-theme tuning live in `content/art/palettes.json`. `PixelDioramaStyle` loads that file at first use; `BiomeRegistry.get_*_material()` delegates to `make_*_material(theme_from_biome())` with no `.tres` files. Surface shader applies `quantize_color` with `color_levels`; authored `pattern_strength` and other overrides survive `PixelDioramaSettings.apply_all()` via `set_authored_param` / `authored_params` meta. Castle (and other themes) can use `assets/textures/<theme>/tiles.png` atlases; missing atlases fall back to procedural patterns. Hub tents build from `content/art/structures/hub_tent.json` via `build_structure()`. Fountain particles use the emissive shader. Validation: `pixel_style_suite.gd` plus PXS assertions in `pixel_pipeline_suite.gd`.

## Gaps (resolved)

| ID | Sev | Resolution |
|----|-----|------------|
| PXS-01 | P0 | `color_levels` quantize in surface `fragment()` — `pixel_diorama_surface.gdshader:155` |
| PXS-02 | P0 | `set_authored_param` + `_set_shader_param_unless_authored` — `pixel_diorama_style.gd:75-80`, `pixel_diorama_settings.gd:538-545` |
| PXS-03 | P0 | `palettes.json` + deleted `mat_*.tres`; `BiomeRegistry` delegation |
| PXS-04 | P1 | Tile atlas uniforms + `tiles.png` per theme; procedural fallback when file absent |
| PXS-05 | P1 | `hub_tent.json` + `build_structure()` / `_build_hub_tent()` |
| PXS-06 | P1 | Deleted `assets/hub/mat_*.tres`; stripped scene refs |
| PXS-07 | P1 | Removed `load_floor_material_template`, `apply_theme_to_blockout`, `mat_pixel_floor.tres` |
| PXS-08 | P1 | Fountain particles on emissive `ShaderMaterial` — `_make_fountain_particle_material` |
| PXS-09 | P2 | Dead constants removed; caches cleared via `clear_material_caches()` |
| PXS-10 | P2 | `make_prop_material` always duplicates; per-key cache |
| PXS-11 | P2 | `hide_legacy_meshes` uses `legacy_blockout` meta + deprecated name list |
| PXS-12 | P2 | Header comment fixed; `.tres` `texture_filter` lines removed with files |
| PXS-13 | P2 | `PixelDioramaSettings.debug_flat_materials` replaces `AUMBRYE_STD_MAT` |
| PXS-14 | P2 | `pixel_style_suite.gd` + `pixel_pipeline_suite.gd` PXS assertions |

## Target design

Delivered as specified in the original plan: palette-as-data, optional tile atlases on procedural shaders, authored-param channel, structure JSON for hub tent, emissive fountain particles, and headless validation suite.

## Work plan (completed)

1. `color_levels` quantize in surface shader.
2. Authored-param meta in style + settings.
3. Cleanup: dead code, hub `.tres`, prop cache, debug flat materials.
4. `palettes.json` + schema; BiomeRegistry delegation; delete biome `.tres`.
5. Tile atlas shader path + `castle/tiles.png` reference (all themes now have atlases).
6. `hub_tent.json` + `build_structure()`.
7. Fountain emissive materials.
8. `hide_legacy_meshes` inversion.
9. `pixel_style_suite.gd` + extend `pixel_pipeline_suite.gd`.

## Data and schema changes

- Added `content/art/palettes.json`, `content/schemas/palette.v1.json`.
- Added `content/art/structures/hub_tent.json`, `content/schemas/structure.v1.json`.
- Deleted all `assets/**/mat_*.tres` and `assets/shared/mat_pixel_floor.tres`.
- Added `assets/textures/<theme>/tiles.png` (+ `.import`) for 11 themes.
- No `save_migrator.gd` bump.

## Acceptance criteria

- [x] Settings colour-levels slider posterizes floors and walls (`color_levels` in surface `fragment()`).
- [x] After `apply_all()`, authored `pattern_strength` on props survives; plain materials take global value.
- [x] No `mat_wall.tres`; `BiomeRegistry.get_wall_material("forgotten_castle")` matches `palettes.json` castle colours.
- [x] Castle walls use tile atlas when `tiles.png` present; missing file disables atlas without error.
- [x] `build_structure("hub_tent")` emits documented child names.
- [x] No `assets/hub/mat_` or `load_floor_material_template` references in code.
- [x] Fountain spray uses emissive shader materials tracked by settings.
- [x] `make_prop_material` returns distinct instances per theme/branch.
- [x] Unlisted `MeshInstance3D` children in hub scenes remain visible after `hide_legacy_meshes()`.

## Validation

`pixel_style_suite.gd` (category `graphics`):

| Test id | Assertion |
|---------|-----------|
| `style.palette_json_loads` | palettes.json validates; 11 themes declared |
| `style.palette_slots_complete` | eight hex slots per palette |
| `style.biome_map_total` | all `BiomeRegistry` ids mapped |
| `style.no_tres_materials` | no `mat_*.tres` under `assets/` |
| `style.authored_param_survives` | authored `pattern_strength` survives `apply_all()` |
| `style.atlas_probe_missing_ok` | missing atlas → `use_tile_atlas false` |
| `style.atlas_dimensions` | present atlases are 256×256 |
| `style.structure_json_loads` | `hub_tent.json` mat keys resolve |
| `style.structure_child_names` | documented hub tent child names |
| `style.material_cache_keys` | cache key separation |
| `style.cache_cleared_on_apply` | four caches clear |
| `style.no_standard_material` | `add_box` keeps `ShaderMaterial` |
| `style.prop_material_no_alias` | prop materials do not alias |

`pixel_pipeline_suite.gd` additionally asserts `style.color_levels_used` and `style.surface_uniform_coverage`.

Headless run (`--suite=pixel_style_suite,pixel_pipeline_suite`): all PXS tests pass; runner coverage gates fail on filtered runs (expected — full CI uses all suites).

## Related

- Existing behaviour: [`../existing_codebase/pixel-style.md`](../existing_codebase/pixel-style.md)
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md)
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md)
- [`biome-registry.md`](biome-registry.md)
- [`character-authoring.md`](character-authoring.md)
- [`diorama-room-dressing.md`](diorama-room-dressing.md)
