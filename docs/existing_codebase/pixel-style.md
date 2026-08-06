# Pixel style

`PixelDioramaStyle` plus five shaders in `apps/game/client/assets/shared/` define the game's pixel-diorama look: an 11-theme palette loaded from `content/art/palettes.json`, procedural and atlas-backed surface patterns, quantized emissives, a banded sky, and a screen finish. **Authored art path:** `apps/game/client/assets/textures/<theme>/tiles.png` (256Ã—256, 8Ã—8 grid of 32Ã—32 tiles) for floor and wall surfaces when present; procedural shaders remain the fallback. Room blockouts no longer reference `mat_*.tres` files â€” `CastleRoomScene` assigns materials from `BiomeRegistry` at runtime.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | Palette loader, material factories, `set_authored_param`, `build_structure`, hub tent/fountain/portal assemblies, legacy-mesh hiding |
| `content/art/palettes.json` | Single source of truth for 11 theme palettes and `biome_theme_map` |
| `content/schemas/palette.v1.json` | Schema for palette JSON |
| `content/art/structures/hub_tent.json` | Data-driven hub tent parts (generator `hub_tent`) |
| `content/schemas/structure.v1.json` | Schema for structure JSON |
| `apps/game/client/assets/shared/pixel_diorama_finish.gdshaderinc` | Shared GLSL helpers (`quantize_color`, `band_light`, triplanar UVs, etc.) |
| `apps/game/client/assets/shared/pixel_diorama_surface.gdshader` | Lit surface shader â€” procedural patterns, optional tile atlas, `color_levels` quantize |
| `apps/game/client/assets/shared/pixel_diorama_emissive.gdshader` | Unshaded quantized glow |
| `apps/game/client/assets/shared/pixel_sky.gdshader` | Banded sky (see [`visual-lighting.md`](visual-lighting.md)) |
| `apps/game/client/assets/shared/portal_ellipse.gdshader` | Portal interior (see [`portal-ellipse-shader.md`](portal-ellipse-shader.md)) |
| `apps/game/client/assets/textures/castle/tiles.png` | Reference 256Ã—256 tile atlas for castle theme |
| `apps/game/client/scripts/validation/suites/pixel_style_suite.gd` | Headless assertions for palette JSON, materials, structures, caches |

## How it works

### Palette

`THEME_IDS` (`pixel_diorama_style.gd:37-49`) lists the 11 string ids matching `PaletteTheme` enum order. `_ensure_palettes_loaded()` reads `content/art/palettes.json`, builds `_palette_rows` (8 `Color` slots per theme), `_biome_theme_map`, and optional per-theme `tuning` overrides. On load failure it falls back to embedded `_fallback_palette_rows()` with one warning.

`theme_from_biome(biome_id)` reads `biome_theme_map` from JSON instead of a hard-coded `match`. `get_palette(theme)` / `get_palette_color(theme, slot)` index the loaded rows.

### Surface materials

`make_surface_material(surface, theme, pattern_strength := -1.0)` (`:366-417`):
- Cache key: `"%d_%d_%.4f" % [theme, surface, pattern_strength]`.
- Calls `PixelDioramaSettings.apply_to_shader_material()` then assigns palette colours per `SurfaceKind`.
- When `pattern_strength >= 0`, uses `set_authored_param()` so `apply_all()` preserves the value (`PXS-02`).
- When `_theme_has_tile_atlas(theme)` and surface is `FLOOR` or `WALL`, loads `res://assets/textures/<theme>/tiles.png`, sets `use_tile_atlas`, `tile_row`, `tile_variants` via authored params.
- `_apply_palette_tuning()` applies optional JSON `tuning` overrides as authored params.

Wrappers: `make_floor_material`, `make_wall_material`, `make_ceiling_material` (darkened wall duplicate), `make_character_material` (`pattern_strength 0`, `use_vertex_color`).

`make_prop_material(theme, use_metal)` (`:444-455`) always `duplicate()`s the cached PROP surface material per `(theme, use_metal)` key â€” no shared-instance mutation (`PXS-10`).

`make_hub_materials()` (`:467-501`) returns 12 keyed materials with authored colour/pattern overrides for hub landmarks.

### Authored-param channel

`set_authored_param(mat, param, value)` (`:75-80`) sets a shader parameter and records it in material meta `authored_params`. `PixelDioramaSettings._set_shader_param_unless_authored()` skips listed params during `apply_all()`.

### Emissive and particles

`make_glow_material` / `make_emissive_material` route through the emissive shader and settings apply. Fountain particles use `_make_fountain_particle_material()` (`:1401-1407`) â€” emissive `ShaderMaterial` tracked by settings, not `StandardMaterial3D` (`PXS-08`).

### Structures

`build_structure(parent, def_name, mats, overrides)` (`:939-951`) loads `content/art/structures/<name>.json`. Generator `hub_tent` delegates to `_build_hub_tent()` which reproduces the full tent child-name set; `add_hub_tent()` is a thin wrapper (`:1276`).

### Primitive builders

`add_box()` (`:553-570`) honours `PixelDioramaSettings._debug_flat_cached` (replaces `AUMBRYE_STD_MAT` env var, `PXS-13`). `hide_legacy_meshes()` (`:1434-1458`) hides meshes with `legacy_blockout` meta or deprecated name blacklist (`Floor`, `Body`, etc.); unlisted `MeshInstance3D` children stay visible (`PXS-11`).

### Surface shader

`color_levels` is applied in `fragment()` via `quantize_color(col, max(2.0, color_levels))` after pattern/atlas sampling (`pixel_diorama_surface.gdshader:155`, `PXS-01`).

Tile atlas uniforms: `tile_atlas`, `use_tile_atlas`, `tile_row`, `tile_variants`. When enabled, atlas sampling replaces procedural `shade_floor` / `shade_wall` for floors and walls.

### BiomeRegistry delegation

`BiomeRegistry.get_floor_material()` / `get_wall_material()` / `get_accent_material()` / `get_ceiling_material()` delegate to `PixelDioramaStyle.make_*_material(theme_from_biome(id))` (`biome_registry.gd:212-221`). No `.tres` loading (`PXS-03`).

## Contracts

- Shader paths: `SHADER_PATH`, `EMISSIVE_SHADER_PATH`, `PORTAL_SHADER_PATH` (`pixel_diorama_style.gd:51-53`).
- `surface_kind` integers 0â€“3 match shader branches.
- `flash_amount` / `dissolve_clip` consumed by `material_flash.gd` and `material_dissolve.gd`.
- `make_hub_materials()` 12 keys consumed by `hub_diorama.gd`.
- `CastleRoomScene._ready()` assigns null blockout materials from `BiomeRegistry` (`castle_room_scene.gd:22-29`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Palette JSON + biome map | IMPLEMENTED | `content/art/palettes.json`; `pixel_diorama_style.gd:83-106` |
| Single material factory (no biome `.tres`) | IMPLEMENTED | `biome_registry.gd:212-221`; `mat_*.tres` deleted |
| `color_levels` on surface shader | IMPLEMENTED | `pixel_diorama_surface.gdshader:155` |
| Authored-param survives `apply_all()` | IMPLEMENTED | `set_authored_param`; `pixel_diorama_settings.gd:538-545` |
| Castle + 10 theme tile atlases | IMPLEMENTED | `assets/textures/<theme>/tiles.png` (256Ã—256) |
| Hub tent JSON + `build_structure` | IMPLEMENTED | `content/art/structures/hub_tent.json`; `_build_hub_tent` |
| Fountain on emissive shader | IMPLEMENTED | `_make_fountain_particle_material` |
| Procedural geometry (runtime meshes) | PLACEHOLDER | `add_box`, `add_cylinder` â€” blockout boxes remain |
| `pixel_style_suite.gd` validation | IMPLEMENTED | `validation_runner.gd:66` |

## Related
- Improvement plan: [`../actual_improvements/pixel-style.md`](../actual_improvements/pixel-style.md) - **FINISHED**
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) â€” uniform push and `authored_params` skip
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) â€” low-res render target
- [`biome-registry.md`](biome-registry.md) â€” material delegation
- [`character-authoring.md`](character-authoring.md) â€” character mesh blockouts
- [`diorama-room-dressing.md`](diorama-room-dressing.md) â€” largest `add_box()` consumer
