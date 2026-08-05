# Pixel style

`PixelDioramaStyle` plus five shaders in `apps/game/client/assets/shared/` define the game's entire visual identity: an 11-theme × 8-slot colour palette, four procedural surface patterns, a quantized emissive, a banded sky, and a screen finish. **There are no texture, sprite, or mesh asset files in the repo.** `apps/game/client/assets/` contains exactly 5 `.gdshader`, 1 `.gdshaderinc`, 31 `.tres` materials, the audio tree, and READMEs — nothing else. Every surface in the game is a shader-computed pattern on a `BoxMesh`, `CylinderMesh`, `SphereMesh`, or `QuadMesh` created at runtime. This is the reference definition of the pixel-diorama art direction; the shape of the geometry that carries it is documented in [`character-authoring.md`](character-authoring.md).

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | Palettes, material factories, primitive builders, hub tent/fountain/portal assemblies, legacy-mesh hiding |
| `apps/game/client/assets/shared/pixel_diorama_finish.gdshaderinc` | Shared GLSL: `cell_hash`, `quantize_color`, `voxel_edge_mask`, `bayer4`, `band_light`, `triplanar_pattern_uv`, `pixel_rim`, `apply_portal_finish` |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | The main lit surface shader — floor, wall, prop, and accent patterns plus banded `light()` |
| `apps/game/client/assets/shared/pixel_diorama_emissive.gdshader` | Unshaded quantized glow for torches, crystals, runes, portal trim |
| `apps/game/client/assets/shared/pixel_sky.gdshader` | Hard-banded sky with stepped sun and blocky cloud belt (see [`visual-lighting.md`](visual-lighting.md)) |
| `apps/game/client/assets/shared/portal_ellipse.gdshader` | Spiral portal interior (see [`portal-ellipse-shader.md`](portal-ellipse-shader.md)) |
| `apps/game/client/assets/shared/pixel_screen_finish.gdshader` | Screen-space grade (see [`pixel-diorama-settings.md`](pixel-diorama-settings.md)) |
| `apps/game/client/assets/shared/mat_pixel_floor.tres` | Floor `ShaderMaterial` template, reachable only via `load_floor_material_template()` |
| `apps/game/client/assets/<theme>/mat_floor.tres`, `mat_wall.tres`, `mat_accent.tres` | 30 files across `castle`, `crystal`, `swamp`, `frozen`, `cathedral`, `vault`, `prism`, `mire`, `hollow`, `umbral`; loaded by `BiomeRegistry.get_*_material()` |
| `apps/game/client/assets/hub/mat_*.tres` | 9 `StandardMaterial3D` files referenced only from `hub.tscn` and `hub_npc.tscn` |

## How it works

### Palette

`PALETTES` (`:75-197`) is an `Array` of 11 rows of 8 `Color` values. Row order is the `PaletteTheme` enum: `CASTLE, CRYSTAL, SWAMP, FROZEN, CATHEDRAL, VAULT, PRISM, MIRE, HOLLOW, UMBRAL, HUB`. Column order is the `PaletteSlot` enum: `FLOOR_BASE, FLOOR_SHADOW, WALL_BASE, WALL_SHADOW, ACCENT, PROP_WOOD, PROP_METAL, EMISSIVE`.

`theme_from_biome(biome_id)` (`:200-221`) maps the nine non-castle `BiomeRegistry` ids to themes and falls through to `CASTLE`. `HUB` has no biome id and is selected explicitly by `make_hub_materials()`.

`get_palette(theme)` returns a typed `Array[Color]` copy; `get_palette_color(theme, slot)` indexes directly.

### Surface materials

`SurfaceKind` is `{FLOOR, WALL, PROP, ACCENT}` and maps 1:1 to the shader's `surface_kind` integer (0–3).

`make_surface_material(surface, theme, pattern_strength := -1.0)` (`:243-284`):
- `pattern_strength < 0.0` means "use `PixelDioramaSettings.pattern_strength`".
- Cache key is `"%d_%d_%.4f" % [theme, surface, pattern_strength]` in `_surface_material_cache`.
- Loads `SHADER_PATH` (`res://assets/shared/pixel_diorama_surface.gdshader`), then `PixelDioramaSettings.apply_to_shader_material(mat)`.
- Assigns colours per kind: `FLOOR` uses `FLOOR_BASE`/`FLOOR_SHADOW`/`ACCENT`; `WALL` uses `WALL_BASE`/`WALL_SHADOW`/`ACCENT`; `PROP` uses `PROP_WOOD`/`PROP_METAL`/`ACCENT`; `ACCENT` uses `ACCENT`/`WALL_SHADOW`/`EMISSIVE`.

Thin wrappers: `make_floor_material(theme)`, `make_wall_material(theme)`.

`make_prop_material(theme, use_metal := false)` (`:295-310`) requests `SurfaceKind.PROP` at `pattern_strength = 0.28`. The metal branch `duplicate()`s and overrides `color_base` to `PROP_METAL` and `color_shadow` to `WALL_SHADOW`; the non-metal branch returns the shared cached instance. Cached separately in `_prop_material_cache` under `"%d_%s" % [theme, use_metal]`.

`make_accent_material(theme)` caches by theme in `_accent_material_cache`.

`make_material(color, emission := Color.BLACK)` (`:404-419`) is the ad-hoc path for props and NPCs that are not palette driven. With emission it returns a glow material; otherwise it builds a surface material with `surface_kind = 2`, `color_shadow = color.darkened(0.3)`, `color_accent = color.lightened(0.2)`, and `pattern_strength = PixelDioramaSettings.pattern_strength * 0.45`, cached under `"solid_<html>"` in `_prop_material_cache`.

### Emissive materials

`make_glow_material(core, edge, energy, pulse_speed := 0.0)` (`:354-367`) loads `EMISSIVE_SHADER_PATH` and sets `color_core`, `color_edge`, `emission_energy`, `pulse_speed`, then routes through `PixelDioramaSettings.apply_to_shader_material()`. It is not cached.

`make_custom_emissive(color, energy := 1.1)` → `make_glow_material(color.lightened(0.14), color.darkened(0.22), energy)`.

`make_emissive_material(theme, energy := 1.6)` (`:374-382`) uses the theme's `EMISSIVE` slot for core and `.darkened(0.3)` for edge; cached by `"%d_%.4f" % [theme, energy]` in `_emissive_material_cache`.

`clear_material_caches()` (`:69-73`) empties all four dictionaries. Called from `PixelDioramaSettings.apply_all()` (`pixel_diorama_settings.gd:183`).

### Hub material set

`make_hub_materials()` (`:322-349`) returns a 12-key `Dictionary`: `floor`, `floor_alt`, `wall`, `accent`, `wood`, `roof`, `umbral`, `training`, `dragon`, `cathedral`, `forge`, `paper`. `floor_alt`, `accent`, and `paper` are `duplicate()`d surface materials with overridden colours (`paper` is `Color(0.92, 0.86, 0.68)` on `Color(0.78, 0.72, 0.55)`). Consumed by `hub_diorama.gd:55` and, in a reduced five-key form, built independently by `arena_diorama.gd:20-34`.

### Primitive builders

| Function | Mesh | Notes |
|----------|------|-------|
| `add_box(parent, size, position, material, node_name := "")` (`:422-443`) | `BoxMesh` | Sets `material_override`. Honours the `AUMBRYE_STD_MAT` environment variable by replacing the material with a flat `StandardMaterial3D(0.62, 0.56, 0.5)` |
| `add_cylinder(parent, top_radius, bottom_radius, height, position, material, node_name := "")` (`:946-967`) | `CylinderMesh` | Used only by `add_hub_fountain()` |
| `add_collision_box(parent, size, position, node_name := "Collision")` (`:505-518`) | `BoxShape3D` | |
| `add_portal_interior(parent, size, position, theme, node_name := "PortalInterior")` (`:487-502`) | `QuadMesh` | See [`portal-ellipse-shader.md`](portal-ellipse-shader.md) |

`add_box` is the single most-used function in the art layer; `DioramaCharacterSkin`, `DioramaInteractableSkin`, `hub_diorama.gd`, and `arena_diorama.gd` all build their geometry from it.

### Composite assemblies

- `add_portal_column(parent, center, frame_mat, accent_mat, height, column_w := 0.62, node_name := "Column")` (`:521-539`) — pillar plus a capital `1.48 ×` wider and `0.62 ×` as tall as the column width.
- `dress_portal_architecture(visuals, mats, theme, origin := Vector3.ZERO)` (`:542-567`) — 11 boxes plus a portal quad: `Base` 4.2×0.22×2.2, `Step`, two columns at ±1.75 m, `Lintel` at y 3.95, `ArchKeystone`, two buttresses, the portal interior at y 1.55, and `Pad`. The `"training"` theme adds two embers and two torches. Only caller: `arena_diorama.gd:170`.
- `add_hub_tent(landmark, mats, width, depth, wall_height, entrance_width, roof_peak := 1.2, facing_yaw := 0.0)` (`:570-813`) — a 30+ box building: plinth, four corner columns, entry columns/lintel/keystone/buttresses, ridge and cap, four rotated roof panels sized by `sqrt(half² + roof_peak²)` and rotated by `atan2(roof_peak, half)`, awning trim, back/left/right walls, front lips either side of the entrance, two flaps, and a pad. It also builds or rebuilds a `TentCollision` `StaticBody3D` on layer 1 with mask 0 holding three to five collision boxes. Four callers in `hub_diorama.gd` (`:503`, `:539`, `:577`, `:619`).
- `add_hub_fountain(parent, mats, position)` (`:816-913`) — four cylinders plus three `CPUParticles3D` emitters (`WaterSpray` 88 particles, `WaterFall` 64, `WaterMist` 32) and a `WaterGlow` `OmniLight3D` at 0.42 energy / 3.2 range. Particle meshes are 6-segment 4-ring `SphereMesh`; particle materials are built by `_make_fountain_particle_material()`, a `StandardMaterial3D` with a CPU-side 6-level colour quantize, `SHADING_MODE_UNSHADED`, `BILLBOARD_ENABLED`, and alpha transparency.

### `hide_legacy_meshes(root)`

(`:970-979`) Hides capsule/blockout `MeshInstance3D` children so a diorama rig can replace them. It skips subtrees named `DioramaVisual`, `DioramaVisuals`, or `Viewmodel`, and stops recursing into children named `InteractArea`, `PortalLabel`, `Label`, `DoorLabel`, or `NameLabel`. Callers: `hub_diorama.gd:400,495,535,574,615`, `arena_diorama.gd:157`, `diorama_character_skin.gd:91,160,174`.

### Shader include

`pixel_diorama_finish.gdshaderinc` provides:

| Function | Behaviour |
|----------|-----------|
| `cell_hash(vec2)` | `fract(sin(dot(cell, vec2(12.9898, 78.233))) * 43758.5453)` |
| `quantize_color(vec3, levels)` | `floor(color * levels + 0.5) / levels` |
| `voxel_edge_mask(vec2 uv)` | 1.0 within 0.11 of a cell boundary on either axis |
| `bayer4(vec2 frag_coord)` | 4×4 ordered Bayer matrix in [0,1) |
| `band_light(value, bands, dither_amount, frag_coord)` | Quantizes a 0–1 lighting term into `max(2, bands)` hard steps, dithered along the terminator by `(bayer4 - 0.5) * dither/bands` |
| `triplanar_pattern_uv(pos, normal, scale)` | Picks the dominant normal axis plane so every face gets square, equally dense pixels — avoids the UV stretch that differently sized box meshes produce |
| `pixel_rim(normal, view, steps)` | `floor(pow(1 - dot(n, v), 3.0) * steps) / steps` |
| `apply_portal_finish(col, uv, accent, px_scale, strength)` | Static spiral grain; used only by `portal_ellipse.gdshader:34` |

### Surface shader

`pixel_diorama_surface.gdshader`, `render_mode specular_disabled`.

Uniforms: `color_base`, `color_shadow`, `color_accent`, `pixel_scale` (default 8.0), `pattern_strength` (0.58), `stitch_strength` (0.28), `color_levels` (6.0), `edge_strength` (0.45), `shade_bands` (4.0), `shade_dither` (0.55), `light_wrap` (0.25), `rim_strength` (0.08), `flash_amount` (0.0), `dissolve_clip` (1.0), `surface_kind` (0).

`vertex()` exports `v_local_pos`, `v_local_normal`, `v_world_pos`, `v_world_normal`.

`pattern_coords()` (`:43-48`) — floors and walls sample **world space** at `pixel_scale * WORLD_CELL_RATIO` where `WORLD_CELL_RATIO = 0.25`, so tiling continues across mesh seams and gives roughly 0.5 m tiles at the default scale. Props and accents sample **object space** at the full `pixel_scale`, so the pattern stays locked to moving geometry.

Pattern functions:
- `shade_floor` (`:50-57`) — checkerboard from `mod(cell.x + cell.y, 2)`, plus a mortar line where either `fract(uv)` is under 0.06, plus an accent speckle where `grain > 0.9`.
- `shade_wall` (`:59-70`) — running-bond brick: `row = floor(uv.y * 0.5)`, every other row offset by half a brick; per-brick shade from `cell_hash`; mortar under 0.05 / 0.07; accent speckle above 0.94.
- `shade_prop` (`:72-79`) — checkerboard plus a plank stripe at `step(0.72, fract(uv.y * 0.5 + grain * 0.12))`.
- `shade_accent` (`:81-89`) — repeating 6-step sparkle from `mod(cell.x * 7 + cell.y * 11, 6)`, described in the source as kept from the retired legacy accent shader.

`fragment()` (`:91-131`): computes `detail = 1.0 - smoothstep(9.0, 26.0, length(VERTEX))`, which in Godot 4 is view-space distance, so pattern detail fades out between 9 m and 26 m from the camera — past that a cell is smaller than a rendered pixel and would turn into crawling noise. Then a `stitch` overlay (`cell_hash(cell + vec2(3,7)) > 0.9`), a `voxel_edge_mask` darkening, an optional `dissolve_clip` dither discard keyed on `v_world_pos.xz`, and a `flash_amount` lerp to white. Writes `ALBEDO`, `ROUGHNESS = 1.0`, `METALLIC = 0.0`, `SPECULAR = 0.0`.

`light()` (`:133-139`): `ndl = dot(NORMAL, LIGHT)` remapped by `light_wrap`, then `band_light(clamp(ndl * 0.5 + 0.5, 0, 1), shade_bands, shade_dither, FRAGCOORD.xy)`, plus `pixel_rim(NORMAL, VIEW, 4.0) * rim_strength`, accumulated into `DIFFUSE_LIGHT` scaled by `ATTENUATION * LIGHT_COLOR`.

`color_levels` is declared at `:16` and never referenced anywhere in the shader body.

### Emissive shader

`pixel_diorama_emissive.gdshader`, `render_mode unshaded, specular_disabled`. Samples object-space `triplanar_pattern_uv`, mixes `color_edge` → `color_core` at `grain > 0.35`, brightens `1.15×` above `grain > 0.86` scaled by `grain_strength`, applies a 4-step `pulse` when `pulse_speed > 0.001`, then `quantize_color(col, color_levels)` and writes both `ALBEDO` and `EMISSION = quantized * emission_energy * pulse`. Its uniforms are `color_core`, `color_edge`, `pixel_scale`, `color_levels`, `emission_energy`, `grain_strength`, `pulse_speed`, `pulse_amount` — there is no `emission` uniform.

### Material `.tres` files

The 30 biome files are `ShaderMaterial` resources on `pixel_diorama_surface.gdshader` with `surface_kind` 0/1/3 for floor/wall/accent. Their colour values duplicate `PALETTES` (for example `castle/mat_wall.tres:7` is `Color(0.22, 0.2, 0.28)`, identical to `PALETTES[CASTLE][WALL_BASE]`). Their tuning values are the shader defaults, not the `PixelDioramaSettings` defaults:

| Parameter | `.tres` value | `PixelDioramaSettings` default |
|-----------|---------------|-------------------------------|
| `pattern_strength` | `0.58` | `0.5` |
| `stitch_strength` | `0.28` | `0.16` |
| `edge_strength` | `0.45` | `0.24` |
| `light_wrap` | `0.25` | `0.16` |

Each file also carries a `texture_filter = 0` line, which is not a `ShaderMaterial` property.

The 9 `assets/hub/*.tres` files are `StandardMaterial3D`, not shader materials. `mat_floor.tres`, `mat_accent.tres`, and `mat_wall.tres` are referenced by `hub.tscn:15-17`, `mat_umbral.tres` by `hub.tscn:19`, and `mat_accent.tres` again by `hub_npc.tscn:5`. `mat_forge.tres`, `mat_paper.tres`, `mat_roof.tres`, `mat_wood.tres`, and `mat_floor_alt.tres` have no reference anywhere in the repo. Because `hub_diorama.gd` calls `hide_legacy_meshes()` on the hub buildings and rebuilds them with `make_hub_materials()`, the referenced hub `.tres` files are attached to meshes that are hidden at runtime.

## Contracts

- Shader paths: `SHADER_PATH`, `EMISSIVE_SHADER_PATH`, `PORTAL_SHADER_PATH`, `FLOOR_MATERIAL_PATH` (`:58-61`). `PixelDioramaSettings.apply_to_shader_material()` dispatches on the surface and emissive filenames, so any new material must use one of those two shaders to receive settings.
- `surface_kind` integers 0–3 are the contract between `SurfaceKind` and the shader's `if` chain.
- `flash_amount` and `dissolve_clip` uniforms are the contract for `material_flash.gd:6` and `material_dissolve.gd:6-7`; `pixel_pipeline_suite.gd:60-77` asserts both substrings exist in the shader source.
- `hide_legacy_meshes()` skip names `DioramaVisual`, `DioramaVisuals`, `Viewmodel` and stop names `InteractArea`, `PortalLabel`, `Label`, `DoorLabel`, `NameLabel`.
- `add_hub_tent()` creates or rebuilds a child `StaticBody3D` named `TentCollision` on collision layer 1, mask 0.
- `make_hub_materials()`'s 12 keys are indexed by name (some with `.` access, e.g. `mats.wall`) in `hub_diorama.gd`, so a missing key is a runtime error.
- `AUMBRYE_STD_MAT` environment variable overrides every `add_box()` material (`:438-441`).
- `PixelDioramaStyle` and `PixelDioramaSettings` are mutually dependent: `_configure_shader_material()` calls into settings, and `apply_all()` calls `clear_material_caches()`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| 11×8 palette and theme mapping | IMPLEMENTED | `pixel_diorama_style.gd:75-232` |
| Four procedural surface patterns + banded lighting | IMPLEMENTED | `assets/shared/pixel_diorama_surface.gdshader:50-139` |
| Triplanar square-pixel UVs across differently sized boxes | IMPLEMENTED | `assets/shared/pixel_diorama_finish.gdshaderinc:41-50` |
| Distance detail fade | IMPLEMENTED | `assets/shared/pixel_diorama_surface.gdshader:99` |
| Zero texture, sprite, or mesh assets in the repo | PLACEHOLDER | `apps/game/client/assets/` holds only 5 `.gdshader`, 1 `.gdshaderinc`, 31 `.tres`, audio, and READMEs |
| All geometry is runtime `BoxMesh`/`CylinderMesh`/`SphereMesh`/`QuadMesh` | PLACEHOLDER | `pixel_diorama_style.gd:422-443`, `:487-502`, `:916-922`, `:946-967` |
| `color_levels` declared but never read by the surface shader | BROKEN | declared `pixel_diorama_surface.gdshader:16`; no reference in `:31-139`; pushed at `pixel_diorama_settings.gd:408`; slider at `settings_ui.gd:268-271` |
| Palette duplicated between `PALETTES` and 30 `.tres` files, with divergent tuning | PARTIAL | `pixel_diorama_style.gd:75-197` vs `assets/castle/mat_wall.tres:7-18` |
| `assets/hub/mat_forge/paper/roof/wood/floor_alt.tres` unreferenced | PLACEHOLDER | no match in the repo outside docs |
| Referenced hub `.tres` materials sit on meshes hidden at runtime | PARTIAL | `hub.tscn:15-19`; `hub_diorama.gd:400,495,535,574,615` |
| `load_floor_material_template()` and `assets/shared/mat_pixel_floor.tres` | STUB | defined `:385-386`; no call site |
| `apply_theme_to_blockout(blockout, biome_id)` | STUB | defined `:389-395`; no call site |
| `make_prop_material()` non-metal branch returns the shared cached instance | PARTIAL | `:302-307`; the metal branch duplicates, the wood branch does not |
| Per-material `pattern_strength` overrides are overwritten by `apply_to_scene()` | BROKEN | overrides set at `:282`, `:302`, `:328`, `:332`, `:417`; re-stamped from the global static at `pixel_diorama_settings.gd:411` |
| `AUMBRYE_STD_MAT` replaces every box material with flat grey | PLACEHOLDER | `:438-441` |
| Fountain and particle materials bypass the pixel shaders | PARTIAL | `_make_fountain_particle_material()` `:925-943` builds a `StandardMaterial3D` with a CPU quantize |
| `PERF_TARGET_FRAME_MS`, `PERF_PIXEL_STACK_BUDGET_MS`, `PIXEL_SCALE`, `PATTERN_STRENGTH`, `COLOR_LEVELS`, `EDGE_STRENGTH`, `UV_TILE_METERS`, `PROP_SNAP` | STUB | declared `:46-56`; no reads anywhere |
| `plan/systems/20-PERFORMANCE.md` referenced in the header comment | ABSENT | no `plan/` directory exists in the repo |
| `hide_legacy_meshes()` name blacklist | PARTIAL | `:972`, `:978`; any new authored child not on the list is hidden |
| Validation coverage | PARTIAL | `pixel_pipeline_suite.gd:20`, `:60-77` — file existence plus two shader substrings |

## Related
- Improvement plan: [`../actual_improvements/pixel-style.md`](../actual_improvements/pixel-style.md)
- [`character-authoring.md`](character-authoring.md) — the ~10-`BoxMesh` character construction this palette dresses
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — the single source of truth for shader uniforms
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — the low-res frame these shaders render into
- [`portal-ellipse-shader.md`](portal-ellipse-shader.md) — the fifth shader
- [`visual-lighting.md`](visual-lighting.md) — sky shader and the lights `light()` bands
- [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md) — consumers of `flash_amount` / `dissolve_clip`
- [`biome-registry.md`](biome-registry.md) — loads the 30 biome `.tres` files
- [`diorama-room-dressing.md`](diorama-room-dressing.md), [`hub.md`](hub.md) — the biggest `add_box()` consumers
- [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
