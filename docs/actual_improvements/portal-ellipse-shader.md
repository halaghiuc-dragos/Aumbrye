# Portal ellipse shader — improvement plan

## Current state

`portal_ellipse.gdshader` is the best-looking single piece of art in the project — an animated spiral of quantized pixel cells inside an elliptical mask — and it is invisible during actual gameplay. Its only consumers are the six hub portals and the debug arena's return portal. Every portal a player passes through during a run uses `DioramaInteractableSkin.build_portal()`, which is two boxes, a lintel, and a flat glowing slab. See [`../existing_codebase/portal-ellipse-shader.md`](../existing_codebase/portal-ellipse-shader.md).

It is also the one shader that `PixelDioramaSettings` cannot reach, its colours are a fourth independent palette, its theme vocabulary is five hub-specific strings that cannot name a biome, and the archway it sits inside is built by two duplicate implementations.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| POR-01 | P0 | The portal shader never appears in a run. `add_portal_interior()` is called only from `hub_diorama.gd:418` and `pixel_diorama_style.gd:561` (debug arena). In-run portals — the exit portal, the boss-room portal, the endless descent — use `DioramaInteractableSkin.build_portal()`, a box frame with a flat emissive slab. The most important traversal moment in the game gets the placeholder art and the safe hub gets the good art. | `hub_diorama.gd:418`; `arena_diorama.gd:170`; `diorama_interactable_skin.gd:67-89`; `room_merchant_content.gd:27` |
| POR-02 | P0 | `DioramaInteractableSkin.build_portal()` reads `glow.emission` where `glow` is the `ShaderMaterial` returned by `PixelStyle.make_emissive_material()`. `ShaderMaterial` has no `emission` property, so this is a runtime error every time a portal, loot pickup, or cannon is skinned. | `diorama_interactable_skin.gd:79`, `:101`, `:118`; `pixel_diorama_style.gd:374-382` returns a `ShaderMaterial` on `pixel_diorama_emissive.gdshader`, whose uniforms are `color_core`/`color_edge`/`emission_energy` (`pixel_diorama_emissive.gdshader`) |
| POR-03 | P1 | The portal is the only shader `PixelDioramaSettings` cannot reach. `make_portal_material()` never calls `apply_to_shader_material()`, and that function has no portal branch, so `pixel_scale` is pinned at the shader default 14.0 and the quantize is the literal `6.0`. Turning "Colour levels" to 4 changes every surface in the game except the portal. | `pixel_diorama_style.gd:446-484`; `pixel_diorama_settings.gd:406-419`; `portal_ellipse.gdshader:35` |
| POR-04 | P1 | Portal colours are a fourth palette. Fifteen `Color` literals in a `match` inside `make_portal_material()`, duplicating none of `PALETTES`, plus a fifth five-way table for the `PortalGlow` light colour in `hub_diorama.gd`. Retinting a portal means editing two `match` statements in two files. | `pixel_diorama_style.gd:449-483`; `hub_diorama.gd:453-464` |
| POR-05 | P1 | The theme vocabulary cannot name a biome. `make_portal_material()` accepts the five strings `castle`, `training`, `skies`, `cathedral`, `umbral`, which are hub landmark names, not biomes. A portal into Crystal Caverns or Frozen Reaches falls through to the umbral purple default. | `pixel_diorama_style.gd:449-483`; `hub_diorama.gd:37-42`; `biome_registry.gd:6-15` |
| POR-06 | P1 | The archway architecture exists twice. `hub_diorama.gd:397-435` and `pixel_diorama_style.gd:542-567` build the same 11 boxes at the same dimensions; `dress_portal_architecture()` has exactly one caller, in the debug arena, and both call sites then add an identical `PortalGlow` light by hand. | `hub_diorama.gd:408-435`; `pixel_diorama_style.gd:553-567`; `arena_diorama.gd:170-178` |
| POR-07 | P2 | The portal interior is a flat `QuadMesh` with no depth. Viewed off-axis — which is most of the time with an orbit camera — it reads as a painted decal on the archway rather than a hole. | `pixel_diorama_style.gd:496-497` |
| POR-08 | P2 | A fresh, uncached `ShaderMaterial` per portal: six hub portals produce six identical materials. `spiral_tightness` is never written from GDScript, so no theme can vary the spiral density. | `pixel_diorama_style.gd:500`; declared `portal_ellipse.gdshader:11` |
| POR-09 | P2 | No audio and no VFX on the portal. Standing in front of a dimensional tear is silent, and entering one produces no burst. | no `AudioDirector` or `VfxService` call in `hub_diorama.gd:397-435` or `pixel_diorama_style.gd:487-502` |
| POR-10 | P2 | No shader or material validation. The existing portal tests assert node names and `RunFlow` methods only. | `hub_suite.gd:37-42`; `hub_m4_suite.gd:25`; `m7_suite.gd:742-758`; `dungeon_suite.gd:90-99` |

## Target design

### 1. One portal builder, used everywhere

Promote the archway plus interior into a single function and delete both duplicates:

```gdscript
## Builds a complete portal: archway, interior quad, glow light, and optional
## theme accents. `def` is a portal definition resolved from content data.
## Returns the visuals root, always named "DioramaVisuals".
static func build_portal(parent: Node3D, def: Dictionary, scale: float = 1.0) -> Node3D
```

`hub_diorama.gd._dress_portal()` becomes `PixelDioramaStyle.build_portal(portal, PortalCatalog.resolve(theme_id))`; `arena_diorama.gd` calls the same; `DioramaInteractableSkin.build_portal()` and `build_exit_portal()` delegate to it with `scale` 1.0 and 0.85. That single change puts the spiral interior in front of the player at every exit portal, boss portal, and endless descent. Closes POR-01, POR-06.

`room_merchant_content.gd:27` currently borrows `build_portal()` for a merchant **stall**, which is why the stall looks like a portal. It moves to a new `build_merchant_stall()` — a counter, an awning, and two crates — so the portal shape stops doubling as furniture.

### 2. Portal definitions in content

`content/art/portals.json`, validated by `content/schemas/portal.v1.json`:

```json
{
  "version": 1,
  "portals": {
    "forgotten_castle": {
      "display_name": "Forgotten Castle",
      "palette_theme": "castle",
      "interior": {
        "color_inner": "#8cc7ff", "color_outer": "#29479e", "color_accent": "#e6f5ff",
        "ellipse": [0.72, 1.0], "spin_speed": 2.2, "spiral_tightness": 5.5, "depth": 0.35
      },
      "glow": { "color": "#d9b873", "energy": 1.0, "range": 4.0 },
      "accents": ["torch_pair"],
      "sfx": { "ambient": "portal_hum_castle", "enter": "portal_enter" }
    }
  },
  "aliases": { "castle": "forgotten_castle", "training": "arena_training", "skies": "skies_ascent" }
}
```

One entry per biome (all ten) plus `arena_training`, `skies_ascent`, `cathedral_ascent`, and `hub_return`. `aliases` preserves the five legacy hub strings for one release so `hub.tscn` needs no simultaneous change. `palette_theme` ties the archway's frame and accent materials back to the single palette source proposed in [`pixel-style.md`](pixel-style.md), so the frame stops needing its own `_portal_frame_material()` table.

```gdscript
## Resolves a portal id or legacy alias to a definition. Unknown ids return the
## "hub_return" definition and warn once, so a missing biome never crashes a run.
static func resolve(portal_id: String) -> Dictionary
```

Closes POR-04, POR-05.

### 3. Settings integration

Add `PORTAL_SHADER_SUFFIX := "portal_ellipse.gdshader"` and a branch in `apply_to_shader_material()`:

```gdscript
elif shader_path.ends_with(PORTAL_SHADER_SUFFIX):
    mat.set_shader_parameter("pixel_scale", pixel_scale * (14.0 / DEFAULT_PIXEL_SCALE))
    mat.set_shader_parameter("color_levels", color_levels)
```

The ratio preserves today's relative density — the portal is authored 1.75× finer than surfaces — while making it track the user's pixel scale. The shader replaces its literal with a uniform:

```glsl
uniform float color_levels : hint_range(4.0, 16.0) = 6.0;
...
col.rgb = quantize_color(col.rgb, max(2.0, color_levels));
```

`make_portal_material()` calls `PixelDioramaSettings.apply_to_shader_material(mat)` after writing the theme values, and caches by portal id in a `_portal_material_cache` cleared from `clear_material_caches()`. Closes POR-03, POR-08.

### 4. Depth

Replace the `QuadMesh` with three stacked quads at `z` offsets `0.0`, `-depth * 0.5`, `-depth`, each at 92 % / 84 % of the front size, with `spin_speed` scaled `1.0` / `0.72` / `0.5` and alpha `1.0` / `0.7` / `0.45`. That is enough parallax to read as a tunnel from an orbit camera without a render-to-texture or a portal camera, and it costs three transparent draws.

```gdscript
## Layered portal interior. `depth` is the total z extent of the stack; 0.0
## produces the single-quad behaviour for cheap or distant portals.
static func add_portal_interior(parent: Node3D, size: Vector2, position: Vector3,
        portal_id: String, depth: float = 0.35, node_name: String = "PortalInterior") -> Node3D
```

The shader gains `uniform float layer_alpha = 1.0` multiplying `ALPHA`, and `render_mode depth_draw_never` so the three layers cannot fight each other in the depth buffer. Closes POR-07.

Rejected alternative: a real portal camera rendering the destination. Rejected because the destination scene does not exist until the run is generated, and a second `SubViewport` would double the cost of the pixel pipeline for a decorative effect.

### 5. Fix the emissive misuse

`DioramaInteractableSkin` stops reading `glow.emission`. `_add_orb()` takes a `Color` directly, and callers pass `PixelStyle.get_palette_color(theme, PixelStyle.PaletteSlot.EMISSIVE)`, which is what the property access was reaching for. Three sites: `:79`, `:101`, `:118`. Closes POR-02, and see [`diorama-room-dressing.md`](diorama-room-dressing.md) for the rest of that file's problems.

### 6. Audio and VFX

The `sfx.ambient` key attaches an `AudioStreamPlayer3D` to the portal with `unit_size` 6.0 and a looping hum; `sfx.enter` fires on traversal. Entering plays `VfxService.play("portal_enter", pos)` — a ring burst tinted from `interior.color_accent`. Both are declared in the portal definition, so a new portal needs no code. Closes POR-09.

## Work plan

1. **Fix `glow.emission`** — three lines in `diorama_interactable_skin.gd`. Independent, fixes a live runtime error. Closes POR-02.
2. **Settings branch and `color_levels` uniform** — `pixel_diorama_settings.gd`, `portal_ellipse.gdshader`, `make_portal_material()` caching. Independent. Closes POR-03, POR-08.
3. **Schema and JSON** — `content/schemas/portal.v1.json`, `content/art/portals.json` with 14 entries transcribing today's five colour sets plus ten biome entries; `PortalCatalog.resolve()`. Depends on the palette work in [`pixel-style.md`](pixel-style.md) only for `palette_theme` resolution, and can land with the current `PaletteTheme` enum in the interim. Closes POR-04, POR-05.
4. **Unified `build_portal()`** — new `PixelDioramaStyle.build_portal()`, delete `hub_diorama.gd._dress_portal()`'s box list and `dress_portal_architecture()`, repoint `DioramaInteractableSkin`, add `build_merchant_stall()`. Depends on 3. Closes POR-01, POR-06.
5. **Layered depth** — shader `layer_alpha` and `depth_draw_never`, `add_portal_interior()` stack. Depends on 2. Closes POR-07.
6. **Audio and enter VFX** — depends on 3 and on the `sfx` layer kind from [`vfx-service.md`](vfx-service.md). Closes POR-09.
7. **Validation** — Closes POR-10.

Step 1 is a one-sitting bug fix and should land immediately regardless of the rest.

## Data and schema changes

- New `content/schemas/portal.v1.json`; new `content/art/portals.json` with 14 portal definitions and the five legacy aliases.
- `portal_ellipse.gdshader` gains `color_levels` and `layer_alpha` uniforms and `depth_draw_never`.
- `pixel_diorama_settings.gd` gains `PORTAL_SHADER_SUFFIX` and a fourth dispatch branch.
- `pixel_diorama_style.gd` loses `dress_portal_architecture()` and gains `build_portal()`, `build_merchant_stall()`, and `_portal_material_cache`.
- No save-format change, so no `save_migrator.gd` version bump.
- New audio keys `portal_hum_<theme>` and `portal_enter` — see [`audio-director.md`](audio-director.md).

## Acceptance criteria

- [ ] The exit portal in a castle run shows the animated spiral interior, not a flat glowing slab. (POR-01)
- [ ] Skinning a portal, a loot pickup, and a cannon produces no `Invalid get index 'emission'` error. (POR-02)
- [ ] Setting "Colour levels" to 4 visibly posterizes the portal interior, and "Pixel scale" changes its cell size. (POR-03)
- [ ] Changing `forgotten_castle.interior.color_inner` in `portals.json` retints the portal and its glow light with no code edit. (POR-04)
- [ ] A portal into every one of the ten biomes has its own colours; none falls through to purple. (POR-05)
- [ ] `rg "dress_portal_architecture"` returns no hits outside docs, and the hub portals are pixel-identical to before the merge. (POR-06)
- [ ] Orbiting 60° around a portal shows parallax between the three interior layers. (POR-07)
- [ ] Six hub portals share one cached material per distinct portal id. (POR-08)
- [ ] Approaching a portal fades in a hum; entering plays a burst and a sound. (POR-09)
- [ ] A merchant stall no longer looks like a portal. (POR-01)

## Validation

New suite `apps/game/client/scripts/validation/suites/portal_suite.gd`, category `graphics`:

| Test id | Assertion |
|---------|-----------|
| `portal.json_loads` | `content/art/portals.json` parses and validates against `portal.v1.json` |
| `portal.biome_coverage` | every `BiomeRegistry.BIOME_*` id has a portal definition |
| `portal.aliases_resolve` | each of `castle`, `training`, `skies`, `cathedral`, `umbral` resolves to a declared portal |
| `portal.unknown_id_safe` | `PortalCatalog.resolve("nope")` returns the `hub_return` definition, warns once, and does not warn again |
| `portal.colors_well_formed` | every colour matches `^#[0-9a-fA-F]{6}$`; `ellipse` values are in `[0.5, 2.0]`; `spin_speed` in `[0, 6]`; `spiral_tightness` in `[1, 12]` |
| `portal.material_uniform_coverage` | every `uniform` in `portal_ellipse.gdshader` is written either by `make_portal_material()` or by `apply_to_shader_material()` |
| `portal.settings_reach_shader` | `color_levels = 4` then `apply_all()` leaves a portal material reporting `color_levels == 4`, and `pixel_scale` scaled by the documented 1.75 ratio |
| `portal.material_cached` | two `make_portal_material("forgotten_castle")` calls return the same object |
| `portal.builder_single_source` | neither `hub_diorama.gd` nor `arena_diorama.gd` contains the string `add_box(visuals, Vector3(4.2, 0.22, 2.2)` — the archway literal now lives only in `pixel_diorama_style.gd` |
| `portal.build_child_names` | `build_portal()` yields the documented child set (`Base`, `Step`, `PillarL`, `PillarR`, `CapitalL`, `CapitalR`, `Lintel`, `ArchKeystone`, `ButtressL`, `ButtressR`, `Pad`, `PortalInterior`, `PortalGlow`) with no duplicates |
| `portal.interior_layers` | `depth = 0.35` yields three `MeshInstance3D` children with strictly decreasing `layer_alpha` and distinct `z` |
| `portal.interior_flat_when_zero` | `depth = 0.0` yields exactly one interior quad |
| `portal.no_emission_property_access` | `diorama_interactable_skin.gd` contains no `.emission` member access on a `PixelStyle` result |
| `portal.exit_portal_uses_shader` | a built exit portal contains a `PortalInterior` whose material's shader path ends with `portal_ellipse.gdshader` |
| `portal.merchant_not_portal` | `room_merchant_content.gd` calls `build_merchant_stall`, and the built stall has no `PortalInterior` child |
| `portal.sfx_keys_exist` | every `sfx.ambient` and `sfx.enter` key resolves in `AudioDirector` |

Manual checklist:

- Walk into a castle exit portal and confirm the spiral is the last thing you see before the transition.
- Orbit a hub portal a full circle: the interior must not visibly flatten into a decal at any angle.
- Compare the six hub portals: all six must be individually recognisable by colour.

## Related
- Existing behaviour: [`../existing_codebase/portal-ellipse-shader.md`](../existing_codebase/portal-ellipse-shader.md)
- [`pixel-style.md`](pixel-style.md) — the palette `palette_theme` resolves against; the shader include holding `apply_portal_finish`
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — gains the fourth dispatch branch
- [`hub.md`](hub.md) — loses its duplicate archway builder
- [`debug-arenas.md`](debug-arenas.md) — the other duplicate
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — `DioramaInteractableSkin`, including the `glow.emission` fix
- [`boss-door-exit-portal.md`](boss-door-exit-portal.md), [`run-flow.md`](run-flow.md) — the in-run portals that gain the shader
- [`room-content.md`](room-content.md) — the merchant stall that stops being a portal
- [`vfx-service.md`](vfx-service.md), [`audio-director.md`](audio-director.md) — the enter burst and the portal hum
