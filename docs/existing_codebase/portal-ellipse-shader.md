# Portal ellipse shader

`portal_ellipse.gdshader` draws the swirling interior of a portal: an elliptical discard mask, a spiralling hashed grain that rotates with `TIME`, an expanding ring, and a 6-level colour quantize. It is reached only through `PixelDioramaStyle.make_portal_material()` and `add_portal_interior()`, and those are reached only from the hub's six portals and the debug arena's training portal. Portals inside a run use a different, unshaded box-and-orb skin, so the shader never appears in dungeon gameplay.

## Files
| Path | Role |
|------|------|
| `apps/game/client/assets/shared/portal_ellipse.gdshader` | The shader |
| `apps/game/client/assets/shared/pixel_diorama_finish.gdshaderinc` | Supplies `cell_hash`, `quantize_color`, and `apply_portal_finish` |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `PORTAL_SHADER_PATH` (`:60`), `make_portal_material()` (`:446-484`), `add_portal_interior()` (`:487-502`), `dress_portal_architecture()` (`:542-567`) |

## How it works

### Shader

`shader_type spatial; render_mode blend_mix, cull_disabled, unshaded;`

Uniforms: `color_inner`, `color_outer`, `color_accent`, `pixel_scale` (4–32, default 14.0), `spin_speed` (0–6, default 2.2), `spiral_tightness` (1–12, default 5.5), `ellipse_x` (0.5–2, default 0.72), `ellipse_y` (0.5–2, default 1.0).

`fragment()` (`:15-40`):
1. `centered = UV * 2.0 - 1.0`, then `elliptical = vec2(centered.x / ellipse_x, centered.y / ellipse_y)`. Anything with `length(elliptical) > 1.0` is `discard`ed, so the quad reads as an ellipse whose aspect is set by the two uniforms rather than by the mesh.
2. `spiral_phase = angle + dist * spiral_tightness - TIME * spin_speed`, and the pixel grid is sampled along `vec2(cos, sin)(spiral_phase) * dist * pixel_scale`, floored to a cell. This is what makes the grain spiral inward rather than rotate rigidly.
3. Colour is `mix(color_outer, color_inner, cell_hash(cell))`, then `color_accent` where the hash exceeds 0.82 weighted by `(1 - dist)` so accents concentrate at the centre, then a `fract(dist * 6.0 - TIME * spin_speed * 0.35)` ring pushed 25 % toward `color_inner`.
4. `apply_portal_finish(col.rgb, centered, color_accent.rgb, pixel_scale, 1.0)` adds a second, static spiral grain layer.
5. `quantize_color(col.rgb, 6.0)` — the level count is a literal, not a uniform.
6. `ALPHA = smoothstep(1.0, 0.82, dist)`, so the outer 18 % of the ellipse fades out; `ALBEDO` is the quantized colour. Being `unshaded`, no light touches it.

`apply_portal_finish()` (`pixel_diorama_finish.gdshaderinc:60-71`) reproduces the same spiral construction without the `TIME` term at `px_scale * 1.15`, mixes `accent` in at `step(0.82, grain) * strength * 0.42`, and adds a static ring at `strength * 0.2`. Its header comment says it is derived from this shader; `portal_ellipse.gdshader:34` is its only call site.

### Material factory

`make_portal_material(theme: String) -> ShaderMaterial` (`pixel_diorama_style.gd:446-484`) creates a fresh `ShaderMaterial` on `PORTAL_SHADER_PATH` and fills it from a `match` on a **string** theme:

| Theme | `color_inner` | `color_outer` | `color_accent` | `ellipse_x` | `ellipse_y` | `spin_speed` |
|-------|---------------|---------------|----------------|-------------|-------------|--------------|
| `castle` | `(0.55, 0.78, 1.0)` | `(0.16, 0.28, 0.62)` | `(0.9, 0.96, 1.0)` | 0.72 | 1.0 | shader default 2.2 |
| `training` | `(1.0, 0.62, 0.18)` | `(0.58, 0.22, 0.05)` | `(1.0, 0.82, 0.42)` | 0.7 | 0.98 | 1.2 |
| `skies` | `(0.98, 0.42, 0.12)` | `(0.42, 0.08, 0.06)` | `(1.0, 0.72, 0.22)` | 0.74 | 1.02 | 2.1 |
| `cathedral` | `(1.0, 0.96, 0.78)` | `(0.82, 0.72, 0.28)` | `(1.0, 1.0, 0.92)` | 0.7 | 0.96 | 0.9 |
| anything else (umbral) | `(0.62, 0.38, 0.92)` | `(0.22, 0.1, 0.38)` | `(0.85, 0.55, 1.0)` | 0.68 | 0.95 | 1.8 |

The function does **not** call `PixelDioramaSettings.apply_to_shader_material()`, and `apply_to_shader_material()` only recognises the surface, emissive, and legacy shader suffixes (`pixel_diorama_settings.gd:406-419`), so neither `pixel_scale` nor `color_levels` ever reaches the portal.

`add_portal_interior(parent, size: Vector2, position, theme, node_name := "PortalInterior")` (`:487-502`) creates a `MeshInstance3D` with a `QuadMesh` of that size and a fresh `make_portal_material(theme)` as its `material_override`. No caching: every portal gets its own material and its own copy of the theme colours.

### Where portals actually appear

| Call site | Portal | Theme string |
|-----------|--------|--------------|
| `hub_diorama.gd:418` via `_dress_portal(portal, mats, theme)` | `CastlePortal` | `castle` |
| same | `UmbralEndlessPortal`, `UmbralWavesPortal` | `umbral` |
| same | `ArenaDoor` | `training` |
| same | `SkiesPortal` | `skies` |
| same | `CathedralPortal` | `cathedral` |
| `pixel_diorama_style.gd:561` via `dress_portal_architecture()`, called from `arena_diorama.gd:170` | debug arena return portal | `training` |

Both call sites build the same 11-box architecture around the quad — `Base`, `Step`, `PillarL/R`, `CapitalL/R`, `Lintel`, `ArchKeystone`, `ButtressL/R`, `Pad` — at the same dimensions and offsets. `hub_diorama.gd:397-435` and `pixel_diorama_style.gd:542-567` are two independent implementations of that layout; the hub one adds `_add_portal_theme_accents()` and a `PortalGlow` `OmniLight3D`, and `arena_diorama.gd:172-178` adds an identical light by hand.

Run and dungeon portals do not use this shader at all. `DioramaInteractableSkin.build_portal()` (`diorama_interactable_skin.gd:67-83`) builds two wall pillars, a lintel, a floor pad, an emissive orb, and a flat `1.6 × 0.08 × 1.6` glow box on `pixel_diorama_emissive.gdshader`. `build_exit_portal()` (`:86-89`) is the same at 0.85 scale, and `room_merchant_content.gd:27` reuses `build_portal()` for a merchant stall.

## Contracts

- `PORTAL_SHADER_PATH = "res://assets/shared/portal_ellipse.gdshader"` (`pixel_diorama_style.gd:60`).
- The shader must declare `color_inner`, `color_outer`, `color_accent`, `ellipse_x`, `ellipse_y`, `spin_speed`; `make_portal_material()` writes those six and nothing else.
- The theme vocabulary is the five strings `castle`, `training`, `skies`, `cathedral`, `umbral`, produced by `hub_diorama.gd:37-42` and `arena_diorama.gd:170`. It is disjoint from `PixelDioramaStyle.PaletteTheme` and from the ten `BiomeRegistry.BIOME_*` ids.
- `add_portal_interior()` names its node `PortalInterior` by default, which is not on `hide_legacy_meshes()`'s stop list but is created inside a `DioramaVisuals` subtree, so it survives (`pixel_diorama_style.gd:972`).
- `blend_mix` plus `cull_disabled` plus `unshaded`: the quad is transparent and sorted with other transparents, and is visible from both sides.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Animated spiral portal interior with elliptical mask and quantized palette | IMPLEMENTED | `portal_ellipse.gdshader:15-40` |
| Five themed colour sets | IMPLEMENTED | `pixel_diorama_style.gd:449-483` |
| Never used inside a run | PARTIAL | only callers are `hub_diorama.gd:418` and `arena_diorama.gd:170`; run portals use `diorama_interactable_skin.gd:67-89` |
| Ignores every pixel setting | BROKEN | `make_portal_material()` (`:446-484`) never calls `apply_to_shader_material()`, and `pixel_diorama_settings.gd:406-419` has no portal branch, so `pixel_scale` stays 14.0 and the quantize stays a literal `6.0` (`portal_ellipse.gdshader:35`) |
| `color_levels` is not a uniform | PARTIAL | hard-coded `quantize_color(col.rgb, 6.0)` at `portal_ellipse.gdshader:35` |
| Theme colours are a fourth colour source | PARTIAL | 15 `Color` literals in `make_portal_material()` that duplicate no `PALETTES` row (`pixel_diorama_style.gd:75-197`) |
| Theme vocabulary cannot express a biome | PARTIAL | five hub-specific strings vs ten biome ids; a Crystal Caverns portal would fall through to the umbral default (`:477-483`) |
| Portal architecture is implemented twice | PARTIAL | `hub_diorama.gd:397-435` and `pixel_diorama_style.gd:542-567` build the same 11 boxes; `dress_portal_architecture()` has one caller, in the debug arena |
| A fresh `ShaderMaterial` per portal, uncached | PARTIAL | `:500` — six hub portals produce six materials and six shader parameter sets |
| The portal is a flat `QuadMesh` with no depth or parallax | PLACEHOLDER | `:496-497` — viewed off-axis it reads as a painted decal on the archway |
| `spiral_tightness` is never set from GDScript | PARTIAL | declared `portal_ellipse.gdshader:11`; not written in `make_portal_material()` |
| `PortalGlow` light colour is a third theme table | PARTIAL | `hub_diorama.gd:453-464` has its own five-way `match` unrelated to the shader colours |
| No audio, no particles, no interaction feedback on the portal itself | ABSENT | no `AudioDirector` or `VfxService` call in `_dress_portal` (`hub_diorama.gd:397-435`) or `add_portal_interior` |
| Validation coverage | ABSENT | `hub_suite.gd:37-42`, `hub_m4_suite.gd:25`, `m7_suite.gd:742-758`, and `dungeon_suite.gd:90-99` assert portal node names and run-flow wiring only. Searched all of `apps/game/client/scripts/validation/` for `portal_ellipse`, `make_portal_material`, and `add_portal_interior` — no match |

## Related
- Improvement plan: [`../actual_improvements/portal-ellipse-shader.md`](../actual_improvements/portal-ellipse-shader.md)
- [`pixel-style.md`](pixel-style.md) — `PORTAL_SHADER_PATH`, the shader include, the palette this shader does not use
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — the settings dispatch that skips this shader
- [`hub.md`](hub.md) — the six hub portals and the duplicated architecture builder
- [`debug-arenas.md`](debug-arenas.md) — the only `dress_portal_architecture()` caller
- [`run-portals.md`](ui/run_portals.md), [`boss-door-exit-portal.md`](boss-door-exit-portal.md) — the in-run portals that use the box-and-orb skin instead
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — `DioramaInteractableSkin.build_portal()`
- [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
