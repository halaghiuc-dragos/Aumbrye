# Portal ellipse shader

## Status: FINISHED

`portal_ellipse.gdshader` draws the swirling interior of a portal: an elliptical discard mask, a spiralling hashed grain that rotates with `TIME`, an expanding ring, and a `color_levels`-driven quantize. It is reached through `PixelDioramaStyle.make_portal_material()` and `add_portal_interior()`, and every portal in the game â€” hub, debug arena, run exit, boss room, and endless descent â€” is built by `PixelDioramaStyle.build_portal()` with definitions from `content/art/portals.json`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/assets/shared/portal_ellipse.gdshader` | The shader (`color_levels`, `layer_alpha`, `depth_draw_never`) |
| `apps/game/client/assets/shared/pixel_diorama_finish.gdshaderinc` | Supplies `cell_hash`, `quantize_color`, and `apply_portal_finish` |
| `content/art/portals.json` | 14 portal definitions plus five legacy aliases |
| `content/schemas/portal.v1.json` | JSON schema for portal definitions |
| `apps/game/client/scripts/content/portal_catalog.gd` | `PortalCatalog.resolve()`, `portal_id_for_biome()` |
| `apps/game/client/scripts/art/style/pixel_diorama_style.gd` | `PORTAL_SHADER_PATH` (`:60`), `make_portal_material()` (`:573-591`), `add_portal_interior()` (`:602-636`), `build_portal()` (`:661-715`), `build_merchant_stall()` (`:718-742`) |
| `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd` | `PORTAL_SHADER_SUFFIX` and portal branch in `apply_to_shader_material()` (`:552-554`) |
| `apps/game/client/scripts/art/props/diorama_interactable_skin.gd` | `build_portal()` / `build_exit_portal()` delegate to `PixelStyle.build_portal()` |
| `apps/game/client/scripts/dungeon/exit_portal.gd` | Enter SFX and `VfxService.play_portal_enter()` on traversal |
| `apps/game/client/scripts/validation/suites/portal_shader_suite.gd` | 16 headless assertions (category `graphics`) |

## How it works

### Shader

`shader_type spatial; render_mode blend_mix, cull_disabled, unshaded, depth_draw_never;`

Uniforms: `color_inner`, `color_outer`, `color_accent`, `pixel_scale` (4â€“32, default 14.0), `spin_speed` (0â€“6, default 2.2), `spiral_tightness` (1â€“12, default 5.5), `ellipse_x` (0.5â€“2, default 0.72), `ellipse_y` (0.5â€“2, default 1.0), `color_levels` (4â€“16, default 6.0), `layer_alpha` (0â€“1, default 1.0).

`fragment()` (`portal_ellipse.gdshader:17-42`):
1. Elliptical discard mask from `ellipse_x` / `ellipse_y`.
2. Spiral grain via `spiral_phase = angle + dist * spiral_tightness - TIME * spin_speed`.
3. `apply_portal_finish()` second grain layer.
4. `quantize_color(col.rgb, max(2.0, color_levels))` â€” posterize level is a uniform, not a literal.
5. `ALPHA = edge_fade * layer_alpha` for layered depth stacks.

### Material factory

`make_portal_material(portal_id: String) -> ShaderMaterial` (`pixel_diorama_style.gd:573-591`):
- Resolves colours and tuning from `PortalCatalog.resolve(portal_id).interior`.
- Calls `PixelDioramaSettings.apply_to_shader_material(mat)` so `pixel_scale` and `color_levels` track the settings UI.
- Caches by `portal_id` in `_portal_material_cache`; cleared from `clear_material_caches()`.

`make_portal_layer_material()` duplicates the cached material and sets per-layer `spin_speed` scale and `layer_alpha`.

### Layered interior

`add_portal_interior(parent, size, position, portal_id, depth := 0.35)` (`:602-636`):
- `depth <= 0.0` â€” single `QuadMesh` (cheap/distant portals).
- `depth > 0.0` â€” three stacked quads at `z` offsets `0.0`, `-depth * 0.5`, `-depth` with size scales `1.0` / `0.92` / `0.84`, spin scales `1.0` / `0.72` / `0.5`, and alphas `1.0` / `0.7` / `0.45`.

### Unified builder

`build_portal(parent, def, scale := 1.0, hub_mats := {})` (`:661-715`) builds the 11-box archway (`Base`, `Step`, `PillarL/R`, `CapitalL/R`, `Lintel`, `ArchKeystone`, `ButtressL/R`, `Pad`), layered `PortalInterior`, theme accents from `def.accents`, `PortalGlow` `OmniLight3D` from `def.glow`, and an ambient loop via `AudioDirector.attach_loop_emitter()` when `def.sfx.ambient` is set.

Call sites:
| Call site | Portal | Resolution |
|-----------|--------|------------|
| `hub_diorama.gd:_dress_portal()` | six hub portals | `PortalCatalog.resolve(theme)` + hub `mats` |
| `arena_diorama.gd` | debug return portal | `PortalCatalog.resolve("training")` |
| `diorama_interactable_skin.gd:build_portal()` | in-run portals | biome id â†’ `PortalCatalog.portal_id_for_biome()` |
| `diorama_interactable_skin.gd:build_exit_portal()` | exit portal | same at `scale` 0.85 |

`build_merchant_stall()` (`:718-742`) builds a counter, awning, and two crates â€” no `PortalInterior`.

### Content catalog

`PortalCatalog.resolve(portal_id)` (`portal_catalog.gd:13-28`):
- Follows `aliases` (`castle` â†’ `forgotten_castle`, etc.).
- Unknown ids warn once and return the `hub_return` definition.

`content/art/portals.json` defines one entry per biome (ten) plus `arena_training`, `skies_ascent`, `cathedral_ascent`, and `hub_return`.

### Settings integration

`pixel_diorama_settings.gd:552-554`:
```gdscript
elif shader_path.ends_with(PORTAL_SHADER_SUFFIX):
    mat.set_shader_parameter("pixel_scale", pixel_scale * (14.0 / DEFAULT_PIXEL_SCALE))
    mat.set_shader_parameter("color_levels", color_levels)
```

The `14.0 / DEFAULT_PIXEL_SCALE` ratio preserves the portal's authored finer cell density relative to surfaces.

### Traversal feedback

- Ambient hum: `AudioDirector.attach_loop_emitter(visuals, sfx.ambient, 6.0)` at build time (`pixel_diorama_style.gd:710-713`).
- Enter burst: `exit_portal.gd:70-73` plays `portal_enter` SFX and `VfxService.play_portal_enter()` tinted from `interior.color_accent`.

## Contracts

- `PORTAL_SHADER_PATH = "res://assets/shared/portal_ellipse.gdshader"` (`pixel_diorama_style.gd:60`).
- Portal definitions live in `content/art/portals.json`; schema at `content/schemas/portal.v1.json`.
- `make_portal_material()` writes theme uniforms; `apply_to_shader_material()` writes `pixel_scale` and `color_levels`.
- `build_portal()` always names its root `DioramaVisuals`.
- `DioramaInteractableSkin._add_orb()` takes a `Color` directly â€” no `ShaderMaterial.emission` access.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Animated spiral portal interior with elliptical mask and quantized palette | IMPLEMENTED | `portal_ellipse.gdshader:17-42` |
| Portal definitions in content JSON (14 entries, 5 aliases) | IMPLEMENTED | `content/art/portals.json`; `portal_catalog.gd` |
| Shader used in hub, arena, and in-run portals | IMPLEMENTED | `build_portal()` callers; `portal_shader_suite.gd:portal.exit_portal_uses_shader` |
| Settings `pixel_scale` and `color_levels` reach portal shader | IMPLEMENTED | `pixel_diorama_settings.gd:552-554`; `portal_shader_suite.gd:portal.settings_reach_shader` |
| Material cached per portal id | IMPLEMENTED | `_portal_material_cache`; `portal_shader_suite.gd:portal.material_cached` |
| Three-layer depth stack with parallax | IMPLEMENTED | `add_portal_interior()`; `portal_shader_suite.gd:portal.interior_layers` |
| Single archway builder (no duplicate box lists) | IMPLEMENTED | `build_portal()` only; `portal_shader_suite.gd:portal.builder_single_source` |
| Ambient hum and enter SFX/VFX | IMPLEMENTED | `build_portal()` ambient; `exit_portal.gd:70-73` |
| Merchant stall distinct from portal | IMPLEMENTED | `build_merchant_stall()`; `room_merchant_content.gd:27` |
| `glow.emission` runtime error fixed | IMPLEMENTED | `diorama_interactable_skin.gd` â€” no `.emission` access |
| Validation suite (16 tests) | IMPLEMENTED | `portal_shader_suite.gd`; `validation_runner.gd:69` |

## Related
- Improvement plan: [`../actual_improvements/portal-ellipse-shader.md`](../actual_improvements/portal-ellipse-shader.md) - **FINISHED**
- [`pixel-style.md`](pixel-style.md) â€” palette `palette_theme` resolution for archway materials
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) â€” portal shader dispatch branch
- [`hub.md`](hub.md) â€” six hub portals via `_dress_portal()`
- [`debug-arenas.md`](debug-arenas.md) â€” arena return portal
- [`diorama-room-dressing.md`](diorama-room-dressing.md) â€” `DioramaInteractableSkin`
- [`boss-door-exit-portal.md`](boss-door-exit-portal.md), [`run-flow.md`](run-flow.md) â€” in-run portals
- [`vfx-service.md`](vfx-service.md), [`audio-director.md`](audio-director.md) â€” enter burst and portal hum
