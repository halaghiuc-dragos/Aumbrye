# Pixel style — improvement plan

## Current state

The look is 100 % procedural: `apps/game/client/assets/` contains five shaders, one shader include, 31 `.tres` materials, the audio tree, and READMEs — no textures, no sprites, no meshes. Every surface is a checkerboard, a running-bond brick pattern, or a hash speckle computed from `triplanar_pattern_uv` on a runtime `BoxMesh`. See [`../existing_codebase/pixel-style.md`](../existing_codebase/pixel-style.md) for the full inventory.

The procedural shaders are competently built — triplanar UVs give square pixels across mismatched box sizes, `band_light` gives genuinely stepped tonal ramps, the distance fade prevents pattern crawl. What they cannot do is carry authored art: a hash-driven brick wall looks the same in the crypt and the cathedral, and no artist can place a specific broken stone, a specific banner, or a specific mossy corner. The palette is duplicated across `PALETTES` in GDScript and 30 `.tres` files that have drifted to different tuning values. Six declared constants and two functions are dead. One shader uniform is pushed by settings, exposed as a Settings slider, and never read by the shader.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PXS-01 | P0 | The surface shader declares `color_levels` and never reads it. `PixelDioramaSettings` pushes it on every material and `settings_ui.gd` gives the player a "Colour levels" slider, so the single most visually descriptive pixel-art control does nothing on floors, walls, props, and accents — only on emissives. | declared `pixel_diorama_surface.gdshader:16`, unreferenced in `:31-139`; pushed `pixel_diorama_settings.gd:408`; slider `settings_ui.gd:268-271` |
| PXS-02 | P0 | `PixelDioramaSettings.apply_to_scene()` re-stamps the global `pattern_strength` onto every `ShaderMaterial` it walks, destroying the deliberate per-material overrides: props are authored at `0.28`, `make_material()` at `pattern_strength * 0.45`, `floor_alt`/`accent` at `0.34`/`0.42`. After any settings apply, planks, cloth, and stone all carry the same pattern weight. | overrides `pixel_diorama_style.gd:282`, `:302`, `:328`, `:332`, `:417`; clobbered `pixel_diorama_settings.gd:411` |
| PXS-03 | P0 | Two sources of truth for surface colour and tuning. `PALETTES` and the 30 biome `.tres` files carry the same colours, and the `.tres` files carry different tuning (`pattern_strength 0.58` vs `0.5`, `edge_strength 0.45` vs `0.24`, `stitch_strength 0.28` vs `0.16`, `light_wrap 0.25` vs `0.16`). Whether a wall gets script or `.tres` tuning depends on whether it was built by `PixelDioramaStyle` or fetched from `BiomeRegistry`, so the same biome renders two different ways in two different rooms. | `pixel_diorama_style.gd:75-197`; `assets/castle/mat_wall.tres:7-18`; `biome_registry.gd:71-84` |
| PXS-04 | P1 | Zero authored art. There is no texture, sprite, tileset, or mesh asset in the project, so no artist can contribute anything: every visual change requires a shader edit or a `Color` literal edit. | `apps/game/client/assets/` contains only `*.gdshader`, `*.gdshaderinc`, `*.tres`, `audio/`, `*.md` |
| PXS-05 | P1 | All hub geometry is 30+ hard-coded box literals inside a 240-line GDScript function (`add_hub_tent`), so the shape of a building is unreviewable and unauthorable. | `pixel_diorama_style.gd:570-813` |
| PXS-06 | P1 | Five of nine `assets/hub/*.tres` files (`mat_forge`, `mat_paper`, `mat_roof`, `mat_wood`, `mat_floor_alt`) have no reference anywhere. The four that are referenced sit on meshes that `hide_legacy_meshes()` hides at runtime, so all nine are effectively dead — and all nine are `StandardMaterial3D`, meaning they would render as smooth PBR next to banded pixel geometry if they ever became visible. | no repo reference for the five; `hub.tscn:15-19` and `hub_npc.tscn:5` for the rest; `hub_diorama.gd:400,495,535,574,615` |
| PXS-07 | P1 | `load_floor_material_template()` and its `assets/shared/mat_pixel_floor.tres` have no call site; `apply_theme_to_blockout()` has no call site. | `pixel_diorama_style.gd:385-386`, `:389-395` |
| PXS-08 | P1 | The fountain particles bypass the pixel shaders entirely, using a `StandardMaterial3D` with a CPU-side quantize and billboarded unshaded spheres. They receive no `PixelDioramaSettings` update and do not respond to `color_levels` or `pixel_scale`. | `pixel_diorama_style.gd:816-943` |
| PXS-09 | P2 | Eight declared constants are never read: `PERF_TARGET_FRAME_MS`, `PERF_PIXEL_STACK_BUDGET_MS`, `PIXEL_SCALE`, `PATTERN_STRENGTH`, `COLOR_LEVELS`, `EDGE_STRENGTH`, `UV_TILE_METERS`, `PROP_SNAP`. They restate settings defaults, so they are a third place a reader would look for the truth. | `pixel_diorama_style.gd:46-56` |
| PXS-10 | P2 | `make_prop_material(theme, false)` returns the shared cached instance while `make_prop_material(theme, true)` returns a duplicate. Any caller that mutates a wood prop material mutates every wood prop in the scene. | `pixel_diorama_style.gd:302-307` |
| PXS-11 | P2 | `hide_legacy_meshes()` hides by a hard-coded name blacklist, so any authored child mesh not named `DioramaVisual`, `DioramaVisuals`, or `Viewmodel` is silently hidden — the mechanism actively blocks introducing authored scene content. | `pixel_diorama_style.gd:970-979` |
| PXS-12 | P2 | The header comment points at `plan/systems/20-PERFORMANCE.md`; no `plan/` directory exists. Each of the 30 biome `.tres` files also carries a `texture_filter = 0` line that is not a `ShaderMaterial` property. | `pixel_diorama_style.gd:3`; `assets/castle/mat_floor.tres` |
| PXS-13 | P2 | `AUMBRYE_STD_MAT` silently replaces every `add_box()` material with flat grey. It is an undocumented debug switch inside the hottest function in the art layer, costing an `OS.has_environment()` call per box. | `pixel_diorama_style.gd:438-441` |
| PXS-14 | P2 | Validation asserts only that the two shader files exist and contain the substrings `flash_amount` and `dissolve_clip`. No palette, no material factory, no cache, and no uniform coverage is checked. | `pixel_pipeline_suite.gd:20`, `:60-77` |

## Target design

The goal is not to delete the procedural shaders — they are the correct base layer. The goal is to make authored art possible on top of them, and to collapse the three competing sources of truth into one.

### 1. Palette as data

Move `PALETTES` out of GDScript into `content/art/palettes.json`, validated by a new `content/schemas/palette.v1.json`.

```json
{
  "version": 1,
  "palettes": {
    "castle": {
      "display_name": "Forgotten Castle",
      "floor_base":   "#4a4550",
      "floor_shadow": "#2f2b38",
      "wall_base":    "#38333f",
      "wall_shadow":  "#221f2b",
      "accent":       "#8c6a3c",
      "prop_wood":    "#6b4a2c",
      "prop_metal":   "#6d7480",
      "emissive":     "#ffb45a",
      "tuning": { "pattern_strength": 0.5, "stitch_strength": 0.16, "edge_strength": 0.24, "light_wrap": 0.16 }
    }
  },
  "biome_theme_map": { "forgotten_castle": "castle", "crystal_caverns": "crystal" }
}
```

The schema requires all eight slot keys as `^#[0-9a-fA-F]{6}$`, `tuning` optional with each key in `[0,1]`, and `biome_theme_map` values constrained to declared palette names. `PixelDioramaStyle` keeps a `PALETTES` fallback constant used only if the JSON fails to load, and logs one warning naming the parse error. `theme_from_biome()` reads `biome_theme_map` instead of a hard-coded `match`, and the eight `PaletteSlot` enum values stay as the in-code index so no call site changes.

The 30 biome `.tres` files are deleted. `BiomeRegistry.get_floor_material()`, `get_wall_material()`, and `get_accent_material()` become one-line delegations to `PixelDioramaStyle.make_floor_material(theme_from_biome(id))` and friends. That closes PXS-03 in one direction: colour and tuning exist in exactly one file, tuning defaults come from `PixelDioramaSettings`, and per-palette `tuning` overrides are applied on top.

Rejected alternative: keeping the `.tres` files and generating them from the JSON with a tool. Rejected because it leaves two artefacts to review and two places for a merge to go wrong, and Godot `.tres` diffs are unreadable.

### 2. Authored tile atlases

Add one 256×256 indexed-colour PNG atlas per palette theme at `apps/game/client/assets/textures/<theme>/tiles.png`, laid out as a 8×8 grid of 32×32 pixel tiles with a fixed slot contract:

| Row | Tiles |
|-----|-------|
| 0 | floor variants A–D, floor damaged A–D |
| 1 | wall brick A–D, wall damaged A–D |
| 2 | wall trim, wall band, wall vent, wall inscription, 4 spare |
| 3 | prop wood A–B, prop metal A–B, prop cloth A–B, 2 spare |
| 4–7 | reserved |

The atlas is drawn with the palette's eight colours only, so it stays consistent with the shader-side quantize. Import settings: `filter = Nearest`, `mipmaps = off`, `compress/mode = Lossless`.

`pixel_diorama_surface.gdshader` gains:

```glsl
uniform sampler2D tile_atlas : source_color, filter_nearest, repeat_enable;
uniform bool use_tile_atlas = false;
uniform int tile_row = 0;
uniform int tile_variants = 4;
```

In `fragment()`, when `use_tile_atlas` is true, `cell` selects a variant with `int(cell_hash(cell) * float(tile_variants))`, the tile's sub-UV is `fract(uv) / 8.0` plus the tile origin, and the sampled colour replaces the `shade_*` result. The procedural `shade_*` path stays as the fallback for materials with no atlas, and stays the path used by `make_material()` for ad-hoc colours. `detail` multiplies the *variant count* down to 1 at distance rather than fading the pattern, so distant walls stay one clean tile instead of a hash mosaic.

This is the crucial structural change: it makes the difference between "an artist can draw a wall" and "an artist can only pick two colours". It does not require replacing the shaders and can land one theme at a time — a theme with no `tiles.png` keeps today's exact look.

Failure behaviour: `make_surface_material()` checks `ResourceLoader.exists()` for the atlas path once per theme, caches the answer, and leaves `use_tile_atlas` false when the file is missing. No error, no warning spam.

### 3. Fix `color_levels`

Apply the quantize at the end of `fragment()`, after `flash_amount`:

```glsl
ALBEDO = quantize_color(col, max(2.0, color_levels));
```

`quantize_color` is already in the include (`pixel_diorama_finish.gdshaderinc:14`). Because the banded `light()` multiplies afterwards, the albedo quantize is the correct place: it makes the palette itself stepped without flattening the tonal ramp. Default stays `6.0`; the Settings slider becomes truthful. Closes PXS-01.

### 4. Per-material tuning that survives a settings apply

Add an explicit override channel so `apply_to_scene()` can tell "author set this" from "global default":

```gdscript
## Records a deliberate per-material override so PixelDioramaSettings will not
## overwrite it on the next apply_all().
static func set_authored_param(mat: ShaderMaterial, param: String, value: Variant) -> void:
    mat.set_shader_parameter(param, value)
    var authored: Array = mat.get_meta("authored_params", [])
    if not authored.has(param):
        authored.append(param)
    mat.set_meta("authored_params", authored)
```

`PixelDioramaSettings._configure_shader_material()` skips any parameter listed in the material's `authored_params` meta. Every `set_shader_parameter("pattern_strength", ...)` in `pixel_diorama_style.gd` becomes `set_authored_param(...)`. Closes PXS-02.

Rejected alternative: making `apply_to_scene()` scale the authored value by a ratio. Rejected because the ratio is unrecoverable once the value has been stamped once.

### 5. Authored building geometry

Replace `add_hub_tent()`'s 30 box literals with a data-driven builder reading `content/art/structures/<name>.json`:

```json
{
  "version": 1,
  "name": "hub_tent",
  "parts": [
    { "name": "Plinth", "size": [5.0, 0.22, 4.2], "pos": [0, 0.11, 0], "mat": "floor" },
    { "name": "RoofPanelN", "size": [5.2, 0.14, 2.4], "pos": [0, 2.6, -1.1], "rot_deg": [-24, 0, 0], "mat": "roof" }
  ],
  "collision": [ { "size": [5.0, 2.4, 0.3], "pos": [0, 1.2, -2.1] } ],
  "params": { "width": 5.0, "depth": 4.2, "wall_height": 2.2, "entrance_width": 1.8, "roof_peak": 1.2 }
}
```

```gdscript
## Instantiates a JSON-authored structure. `mats` keys are looked up by the
## part's `mat` field; an unknown key falls back to `mats.wall` and warns once.
static func build_structure(parent: Node3D, def_name: String, mats: Dictionary,
        overrides: Dictionary = {}) -> Node3D
```

`overrides` lets a caller change `width` / `roof_peak` without a new file; the loader recomputes derived parts (roof panel length and pitch) from `params` exactly as the current code does. The four `hub_diorama.gd` call sites keep their signatures via a thin `add_hub_tent()` wrapper that forwards to `build_structure("hub_tent", ...)`. Closes PXS-05, and unblocks authored props for [`diorama-room-dressing.md`](diorama-room-dressing.md) and authored characters for [`character-authoring.md`](character-authoring.md), which need the same part-list format.

### 6. Cleanup

- Delete the nine `assets/hub/*.tres` files, remove the four references from `hub.tscn` and `hub_npc.tscn`, and let `hub_diorama.gd`'s `make_hub_materials()` set be the only hub material source. Closes PXS-06.
- Delete `load_floor_material_template()`, `assets/shared/mat_pixel_floor.tres`, and `apply_theme_to_blockout()`. Closes PXS-07.
- Delete the eight unused constants at `:46-56` and fix the header comment path. Closes PXS-09, PXS-12.
- `make_prop_material()` duplicates in both branches and caches both, so `_prop_material_cache` always hands out per-key instances. Closes PXS-10.
- Fountain particles move to a `ShaderMaterial` on `pixel_diorama_emissive.gdshader` with `emission_energy` 0.5 and `color_levels` from settings, registered so `apply_to_scene()` reaches them. Closes PXS-08.
- Replace `AUMBRYE_STD_MAT` with `PixelDioramaSettings.debug_flat_materials`, read once into a static at `apply_all()` time rather than per box, and surface it in the debug overlay. Closes PXS-13.
- `hide_legacy_meshes()` inverts its rule: hide only meshes whose owner scene marked them, via a `legacy_blockout` boolean meta set in the `.tscn`, keeping the current name list as a deprecated fallback for one release. Closes PXS-11.

## Work plan

1. **`color_levels` quantize** — one shader line. Independent, immediately visible. Closes PXS-01.
2. **Authored-param meta** — `pixel_diorama_style.gd` + `pixel_diorama_settings.gd`. Independent. Closes PXS-02.
3. **Cleanup pass** — dead constants, dead functions, dead `.tres`, prop cache, debug flag. Independent. Closes PXS-06, PXS-07, PXS-09, PXS-10, PXS-12, PXS-13.
4. **Palette JSON + schema** — `content/art/palettes.json`, `content/schemas/palette.v1.json`, `PixelDioramaStyle` loader, `BiomeRegistry` delegation, delete 30 `.tres`. Depends on step 2 (tuning overrides need the authored-param channel). Closes PXS-03.
5. **Tile atlas** — shader uniforms, `make_surface_material()` atlas probe, one authored `castle/tiles.png` as the reference theme, then the remaining ten. Depends on step 4 for the palette the atlas is drawn against. Closes PXS-04.
6. **Structure JSON** — `content/art/structures/hub_tent.json`, `build_structure()`, `add_hub_tent()` wrapper. Independent of 4 and 5. Closes PXS-05.
7. **Fountain particles on the emissive shader** — depends on step 3. Closes PXS-08.
8. **`hide_legacy_meshes()` inversion** — depends on step 6, since authored structures are the reason the inversion matters. Closes PXS-11.
9. **Validation suite** — after each step lands its assertions.

## Data and schema changes

- New `content/schemas/palette.v1.json`; new `content/art/palettes.json`.
- New `content/schemas/structure.v1.json`; new `content/art/structures/hub_tent.json`.
- Deleted: 30 `apps/game/client/assets/<theme>/mat_*.tres`, 9 `apps/game/client/assets/hub/mat_*.tres`, `apps/game/client/assets/shared/mat_pixel_floor.tres`.
- New binary assets: `apps/game/client/assets/textures/<theme>/tiles.png` (11 files) plus `.import` files.
- No character-save field changes, so no `save_migrator.gd` version bump. The `LocalSave` `pixel_diorama` meta block is untouched.

## Acceptance criteria

- [ ] Moving the Settings "Colour levels" slider from 16 to 4 visibly posterizes floors and walls, not only torches. (PXS-01)
- [ ] After `PixelDioramaSettings.apply_all()`, a prop material still reports `pattern_strength == 0.28` and a floor material reports the global value. (PXS-02)
- [ ] `castle/mat_wall.tres` no longer exists, `BiomeRegistry.get_wall_material("forgotten_castle")` returns a material whose `color_base` equals `palettes.json` `castle.wall_base`, and its `edge_strength` equals the settings value. (PXS-03)
- [ ] With `castle/tiles.png` present, a `castle_hall` wall shows four distinguishable authored brick variants; deleting the file restores the current procedural look with no error. (PXS-04)
- [ ] `add_hub_tent()` produces a node tree with the same child names and the same `TentCollision` shape count as before the JSON migration. (PXS-05)
- [ ] A repo-wide search for `assets/hub/mat_` and for `load_floor_material_template` returns no hits outside docs. (PXS-06, PXS-07)
- [ ] Fountain spray responds to `color_levels`. (PXS-08)
- [ ] `make_prop_material(theme, false)` returns two objects that are not `==` across two calls with different themes and does not alias. (PXS-10)
- [ ] Adding an unlisted `MeshInstance3D` child to `hub.tscn` leaves it visible after `hide_legacy_meshes()`. (PXS-11)

## Validation

Extend `apps/game/client/scripts/validation/suites/pixel_pipeline_suite.gd`, category `graphics`, and add `pixel_style_suite.gd` for the data-driven parts:

| Test id | Assertion |
|---------|-----------|
| `style.palette_json_loads` | `content/art/palettes.json` parses, validates against `palette.v1.json`, and declares exactly the 11 themes the `PaletteTheme` enum names |
| `style.palette_slots_complete` | every palette declares all eight slot keys and every value matches `^#[0-9a-fA-F]{6}$` |
| `style.biome_map_total` | every `BiomeRegistry.BIOME_*` id appears in `biome_theme_map` and maps to a declared palette |
| `style.no_tres_materials` | no file matches `assets/**/mat_*.tres` |
| `style.color_levels_used` | the surface shader source contains `quantize_color` inside `fragment()` |
| `style.authored_param_survives` | `set_authored_param(mat, "pattern_strength", 0.28)` then `PixelDioramaSettings.apply_all()` leaves the value at `0.28`; a non-authored material takes the global value |
| `style.surface_uniform_coverage` | every `uniform` name declared in `pixel_diorama_surface.gdshader` appears at least once in the shader body below its declaration |
| `style.atlas_probe_missing_ok` | `make_surface_material()` for a theme with no `tiles.png` returns `use_tile_atlas == false` and pushes no error |
| `style.atlas_dimensions` | every present `tiles.png` is exactly 256×256 |
| `style.structure_json_loads` | `hub_tent.json` validates against `structure.v1.json`; every `mat` key exists in `make_hub_materials()` |
| `style.structure_child_names` | `build_structure("hub_tent", mats)` produces the documented child name set with no duplicate names |
| `style.material_cache_keys` | four distinct `(theme, surface, pattern_strength)` requests produce four cache entries and a repeat request produces no fifth |
| `style.cache_cleared_on_apply` | `clear_material_caches()` empties all four dictionaries |
| `style.no_standard_material` | no `add_box()` call path yields a `StandardMaterial3D` when `debug_flat_materials` is false |

Manual checklist:

- Stand in a `castle_hall` and a `cathedral_nave` and confirm the walls no longer read as the same brick with a different hue.
- Confirm a wall 30 m away shows one flat authored tile rather than a hash mosaic.
- Confirm the hub tents are visually unchanged after the JSON migration by A/B screenshot.

## Related
- Existing behaviour: [`../existing_codebase/pixel-style.md`](../existing_codebase/pixel-style.md)
- [`character-authoring.md`](character-authoring.md) — characters are ~10 `BoxMesh` primitives; they need the same part-list format proposed in step 6, and the same authored-atlas path
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — owns the uniform push that PXS-02 and PXS-01 depend on
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — the low-res target these patterns are sized for
- [`portal-ellipse-shader.md`](portal-ellipse-shader.md) — the fifth shader, same quantize treatment
- [`visual-lighting.md`](visual-lighting.md) — sky shader and the light bands `light()` steps
- [`biome-registry.md`](biome-registry.md) — loses its `.tres` loading in step 4
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — the largest `add_box()` consumer, next in line for authored parts
- [`content-data.md`](content-data.md), [`content-catalog.md`](content-catalog.md) — where the new JSON lives
