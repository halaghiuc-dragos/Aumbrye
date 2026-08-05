# Visual lighting — improvement plan

## Current state

`VisualLighting` owns three GDScript-literal outdoor presets, an indoor `Environment` tuner, a soft-omni helper, and a per-biome mote pass. See [`../existing_codebase/visual-lighting.md`](../existing_codebase/visual-lighting.md).

The pixel-art intent is well judged — thin fog so silhouettes stay crisp at 480×270, `fog_sky_affect = 0.0` so the banded sky is not washed out, quantized sun halo, blocky clouds. What is missing is everything that makes lighting read as authored: nothing animates, indoor scenes have no shadow-casting light of any kind, the ten biomes get their lighting from a completely different data source with a different shape, and lighting values live in three GDScript files rather than in `content/`. A player standing in a torch-lit crypt sees a perfectly static, perfectly shadowless room.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| LIT-01 | P0 | Indoor scenes cast no shadows at all. `configure_soft_omni()` hard-codes `shadow_enabled = false` for every torch, sconce, brazier, and room fill, and `biome_registry.gd:229` hides the `DirectionalLight3D` for `MODE_CASTLE` and `MODE_ENDLESS`. Nothing in a dungeon interior grounds a character or a prop, so the diorama reads as flat cut-outs — the exact problem the SSAO in `pixel_diorama_settings.gd:341-353` was added to compensate for. | `visual_lighting.gd:138`; `biome_registry.gd:228-229`; `diorama_room_dressing.gd:129,318,333,347,417` |
| LIT-02 | P0 | Two incompatible lighting data sources. `OUTDOOR_PRESETS` carries 15 keys per entry for three scenes; `BiomeRegistry.get_lighting_profile()` carries 5 keys per entry for ten biomes. Neither can express what the other does, so a biome cannot specify a sun angle or a sky and a scene cannot specify a fog volume. No biome can be given a distinct light character without editing a `match` in a second file. | `visual_lighting.gd:27-85` vs `biome_registry.gd:112-193` |
| LIT-03 | P1 | Nothing animates. There is no flicker, pulse, or time of day: no `create_tween` and no post-setup `light_energy` write in `visual_lighting.gd` or `diorama_room_dressing.gd`. Torches are steady lamps, which is the single most obvious tell that the lighting is placeholder. | `visual_lighting.gd:133-138`; `diorama_room_dressing.gd` has no `flicker` or `create_tween` match |
| LIT-04 | P1 | Lighting lives in GDScript literals across three files with no schema, no validation, and no way for a designer to change a biome's mood without a code change. | `visual_lighting.gd:27-85`; `biome_registry.gd:112-193`; `pixel_diorama_settings.gd:341-380` |
| LIT-05 | P1 | Ambient motes and the biome fog volume are created once, parented at the scene root's local origin, with a fixed 48×8×48 fog box and a `visibility_aabb` centred on the origin. Walk 40 m into a dungeon and the atmosphere is behind you. | `visual_lighting.gd:211-237`, `:251` |
| LIT-06 | P1 | Three of the sky shader's expressive uniforms — `horizon_falloff`, `sun_size`, `sun_glow` — are never set by `_make_sky()`, so every scene shares one sun size and one horizon curve. A sunset arena and a noon meadow cannot differ in the two parameters that most say "different time of day". | declared `pixel_sky.gdshader:11,13,14`; not written `visual_lighting.gd:165-180` |
| LIT-07 | P2 | `_apply_environment()` allocates a new `Environment` and a new `Sky` on every call, discarding the previous radiance bake. Called from scene setup today, so the cost is hidden — but it makes the function unusable for a live settings re-apply. | `visual_lighting.gd:148-150` |
| LIT-08 | P2 | `apply_indoor_environment()` calls `configure_environment()` and then overwrites the `tonemap_white` it just set (1.2/1.0 becomes 1.2/1.42), so indoor and outdoor scenes grade differently for no documented reason. | `visual_lighting.gd:124-130` vs `pixel_diorama_settings.gd:322-327` |
| LIT-09 | P2 | `max(ambient_energy * 0.82, 0.5)` floors indoor ambient at 0.5, so umbral (0.34) and cathedral (0.35) cannot be as dark as their profiles ask. The two darkest biomes in the game are silently brightened to match the brightest. | `visual_lighting.gd:115`; `biome_registry.gd:140,180` |
| LIT-10 | P2 | `SHELL_TORCH_ENERGY` has no reader; the `hub` preset's `fill_energy` is `0.0`, so `_apply_fill` creates a light that does nothing. | `visual_lighting.gd:19`, `:44` |
| LIT-11 | P2 | Validation only asserts the script exists and that biome profiles carry an `ambient_color`. No preset key coverage, no sky uniform coverage, no node-name coverage. | `pixel_pipeline_suite.gd:21`; `m5_suite.gd:88-111`; `m6_suite.gd:84-94` |

## Target design

### 1. One lighting profile shape, in content

Replace both data sources with `content/art/lighting.json`, validated by `content/schemas/lighting-profile.v1.json`. One shape serves outdoor scenes and biome interiors; the `sky` block is optional and its absence means an interior.

```json
{
  "version": 1,
  "profiles": {
    "hub": {
      "display_name": "Aumbrye Hub",
      "ambient": { "color": "#9e8f85", "energy": 0.12 },
      "fog":     { "enabled": true, "color": "#d2a880", "density": 0.0032, "aerial": 0.22, "sky_affect": 0.0 },
      "sun":     { "color": "#ffe0a8", "energy": 1.7, "rotation_deg": [-28.6, 97.4, 0.0], "shadows": true },
      "fill":    { "color": "#80a0e6", "energy": 0.18, "rotation_deg": [-14.3, -120.3, 0.0] },
      "sky": {
        "zenith": "#4a6bad", "horizon": "#edb875", "ground": "#3d3130",
        "bands": 8.0, "horizon_falloff": 2.4,
        "sun_size": 0.045, "sun_glow": 0.4,
        "cloud_amount": 0.5, "cloud_color": "#fae0c2"
      },
      "atmosphere": {
        "motes": { "tint": "#b8a37a", "alpha": 0.28, "amount": 24, "radius": 11.0, "fall_speed": 0.15 },
        "fog_volume": { "enabled": false }
      },
      "torch": { "color": "#ffb45a", "energy": 0.92, "range": 13.5, "flicker": 0.12, "flicker_hz": 7.5 }
    },
    "umbral": {
      "ambient": { "color": "#2e1f42", "energy": 0.34 },
      "fog": { "enabled": true, "color": "#0f0a1a", "density": 0.024 },
      "sun": { "energy": 0.0, "shadows": false },
      "key_light": { "color": "#8a6ad0", "energy": 0.55, "rotation_deg": [-52.0, 34.0, 0.0], "shadows": true },
      "atmosphere": { "motes": { "tint": "#735a9e", "alpha": 0.3, "amount": 28, "radius": 9.0, "fall_speed": 0.18 } },
      "torch": { "color": "#a878ff", "energy": 0.8, "range": 12.0, "flicker": 0.18, "flicker_hz": 5.5 }
    }
  },
  "biome_profile_map": { "forgotten_castle": "castle_interior", "umbral_depths": "umbral" }
}
```

Rotations are degrees, not radians, so a designer can read them. `sun.energy: 0.0` plus `key_light` is how an interior gets a shadow-casting light without a sky. The schema requires `ambient` and `fog`, makes `sun`, `fill`, `key_light`, `sky`, `atmosphere`, and `torch` optional, constrains colours to `^#[0-9a-fA-F]{6}$`, energies to `[0, 8]`, `bands` to `[2, 24]`, `flicker` to `[0, 1]`, and `biome_profile_map` values to declared profile names.

Loader API:

```gdscript
## Applies a named lighting profile to a scene root, creating or reusing the
## WorldEnvironment / DirectionalLight3D / FillLight / KeyLight children.
## Unknown ids fall back to "hub" and push one warning naming the id.
static func apply_profile(root: Node3D, profile_id: String) -> void

## Resolves the profile id for a biome via biome_profile_map.
static func profile_for_biome(biome_id: String) -> String
```

`apply_hub()`, `apply_arena()`, `apply_waves_outdoors()` become one-line wrappers over `apply_profile()`. `BiomeRegistry.get_lighting_profile()` is deleted and `apply_run_presentation()` calls `VisualLighting.apply_profile(parent, profile_for_biome(biome_id))`, keeping its `run_mode` overrides as profile ids (`waves_arena`, `castle_interior`). Closes LIT-02, LIT-04, LIT-06, LIT-09 (the 0.5 floor disappears because the profile value is used directly).

Rejected alternative: extending `OUTDOOR_PRESETS` with the ten biomes and leaving it in GDScript. Rejected because it leaves the schema unvalidated and keeps designers out.

### 2. Interior key light and shadows

Every interior profile gets a `key_light`: a single shadow-casting `DirectionalLight3D` named `KeyLight`, low energy (0.4–0.7), angled steeply so it grounds characters and props without lighting the whole room. `PixelDioramaSettings.configure_directional_shadow(key, profile.key_light.shadows)` applies the existing blocky-shadow tuning, so the pixel look is preserved and the player's shadow-quality setting still governs.

`configure_soft_omni()` gains an opt-in:

```gdscript
## `cast_shadows` is opt-in per light. Only hero torches should pass true: at
## 480x270 more than a handful of shadow-casting omnis produces noisy edges
## and costs more than the read is worth.
static func configure_soft_omni(light: OmniLight3D, color: Color, energy: float,
        light_range: float, cast_shadows: bool = false) -> void
```

When `cast_shadows` and `PixelDioramaSettings.shadow_quality > 0`: `shadow_enabled = true`, `shadow_bias = 0.03`, `shadow_normal_bias = 1.4`, `shadow_opacity = 0.85`, `distance_fade_enabled = true`, `distance_fade_begin = 18.0`. `diorama_room_dressing.gd` passes `true` for the two brightest torches per room and `false` for fills — the budget is stated in the profile as `"max_shadow_omnis": 2` and enforced by the dressing pass. Closes LIT-01.

Rejected alternative: turning shadows on for every omni. Rejected because 8+ shadow-casting omnis per room at 480×270 both costs frame time and produces the noisy shadow edges the `SOFT_OMNI_ATTENUATION` comment (`:11-12`) exists to avoid.

### 3. Flicker

A tiny per-light driver, so the animation lives in one place and respects a settings kill switch:

```gdscript
## Attaches a deterministic flicker to an OmniLight3D. `amount` is the fraction
## of base energy the light swings by; `hz` is the dominant frequency. Uses a
## two-octave sine so it reads as fire rather than a strobe. No-op when
## PixelDioramaSettings.light_animation is false.
static func attach_flicker(light: OmniLight3D, amount: float, hz: float, phase: float) -> void
```

Implementation is a small `Node` script `LightFlicker` added as a child, with `_process(delta)` computing `base_energy * (1.0 + amount * (sin(t * hz * TAU + phase) * 0.6 + sin(t * hz * 2.7 * TAU + phase * 1.7) * 0.4) * 0.5)`. `phase` is derived from the light's global position so two adjacent torches never beat in sync: `phase = fposmod(pos.x * 12.9898 + pos.z * 78.233, TAU)`.

Cost control: `LightFlicker` sets `process_mode = PROCESS_MODE_PAUSABLE` and disables itself when the light is culled, checked every 0.25 s rather than every frame. New setting `PixelDioramaSettings.light_animation: bool = true`, persisted in the `pixel_diorama` meta block, exposed in Settings as "Animated lights". Closes LIT-03.

### 4. Atmosphere that follows the player

`apply_biome_atmosphere()` becomes `attach_atmosphere(root, profile_id, follow: Node3D)`. The `BiomeAtmosphere` holder gets a `_process` that copies `follow.global_position` snapped to a 4 m grid (so the mote field does not visibly slide with the camera), and the `FogVolume` follows the same snapped position. `visibility_aabb` is centred on the holder rather than the world origin. When `follow` is null the current static behaviour is kept.

`PixelDioramaSettings.apply_all()` calls a new `VisualLighting.refresh_atmosphere()` that rebuilds or frees the holder so a mid-session `particle_quality` change takes effect. Closes LIT-05.

### 5. Environment reuse and grade consistency

`_apply_environment()` reuses the existing `Environment` and `Sky` when the `WorldEnvironment` child already has one, mutating uniforms in place instead of reallocating. `apply_indoor_environment()` stops writing `tonemap_exposure` / `tonemap_white`; those move into `configure_environment()` so there is exactly one grade. If interiors genuinely need a different white point it becomes a profile field `grade.white`, defaulted to the outdoor value. Closes LIT-07, LIT-08.

### 6. Cleanup

Delete `SHELL_TORCH_ENERGY`; set the hub profile's `fill.energy` to `0.18` so the `FillLight` earns its existence, or omit the `fill` block and let `apply_profile()` skip creating the node. Closes LIT-10.

## Work plan

1. **Schema and JSON** — `content/schemas/lighting-profile.v1.json`, `content/art/lighting.json` with all 13 profiles (3 outdoor + 10 biome), transcribing today's values exactly so step 1 is a no-visual-change refactor. Independent.
2. **Loader** — `apply_profile()`, `profile_for_biome()`, wrappers, `BiomeRegistry` delegation, delete `get_lighting_profile()`. Depends on 1. Closes LIT-02, LIT-04, LIT-06, LIT-09.
3. **Grade and reuse** — `_apply_environment()` in-place mutation, tonemap consolidation. Independent of 1 and 2. Closes LIT-07, LIT-08.
4. **Interior key light and opt-in omni shadows** — `configure_soft_omni()` signature, `KeyLight` node, `diorama_room_dressing.gd` passing `true` for at most `max_shadow_omnis` lights per room. Depends on 2. Closes LIT-01.
5. **Flicker** — `LightFlicker` node script, `attach_flicker()`, `light_animation` setting and Settings row, `diorama_room_dressing.gd` attaching it to every torch. Depends on 2 for the `torch.flicker` profile fields. Closes LIT-03.
6. **Following atmosphere** — `attach_atmosphere()`, `refresh_atmosphere()`, `apply_all()` hook. Depends on 2. Closes LIT-05.
7. **Cleanup and validation** — Closes LIT-10, LIT-11.

Step 1 plus step 2 is the load-bearing change; steps 4, 5, and 6 each become small once the profile shape exists.

## Data and schema changes

- New `content/schemas/lighting-profile.v1.json`; new `content/art/lighting.json` with 13 profiles.
- `BiomeRegistry.get_lighting_profile()` is removed. `m5_suite.gd:88-111` and `m6_suite.gd:84-94` must be updated to read the new profile source.
- New `LocalSave` `pixel_diorama` meta key `light_animation` (bool, default `true`). Loading an older save yields the default, so no migration is needed.
- New script `apps/game/client/scripts/art/lighting/light_flicker.gd`.
- No character-save field changes, so no `save_migrator.gd` version bump.

## Acceptance criteria

- [ ] In a `MODE_CASTLE` run the player casts a visible shadow on the floor, and at most two omnis per room cast shadows. (LIT-01)
- [ ] `content/art/lighting.json` is the only lighting data file; `rg "OUTDOOR_PRESETS|get_lighting_profile"` returns no hits outside the loader and docs. (LIT-02)
- [ ] Two adjacent torches visibly flicker out of phase, and setting "Animated lights" to off freezes both at base energy. (LIT-03)
- [ ] Changing `umbral.ambient.energy` in the JSON changes the in-game ambient with no code edit, and the value `0.34` is used verbatim rather than floored to `0.5`. (LIT-04, LIT-09)
- [ ] Walking 60 m from a run's spawn keeps the player inside the mote field and the biome fog volume. (LIT-05)
- [ ] Two profiles with different `sun_size` and `horizon_falloff` render visibly different suns and horizons. (LIT-06)
- [ ] Calling `apply_profile()` twice on the same root does not create a second `Environment` or `Sky` instance. (LIT-07)
- [ ] `tonemap_white` is identical in a hub scene and a castle interior. (LIT-08)
- [ ] No omni or directional light is created for a profile block that is absent from the JSON. (LIT-10)

## Validation

New suite `apps/game/client/scripts/validation/suites/visual_lighting_suite.gd`, category `graphics`:

| Test id | Assertion |
|---------|-----------|
| `lighting.json_loads` | `content/art/lighting.json` parses and validates against `lighting-profile.v1.json` |
| `lighting.biome_map_total` | every `BiomeRegistry.BIOME_*` id resolves through `biome_profile_map` to a declared profile |
| `lighting.scene_profiles_present` | `hub`, `arena`, `waves_outdoors`, `waves_arena`, `castle_interior` all exist |
| `lighting.colors_well_formed` | every colour string matches `^#[0-9a-fA-F]{6}$`; every energy is in `[0, 8]` |
| `lighting.profiles_distinct` | no two biome profiles have identical `ambient.color` and `ambient.energy` (the property `m5_suite.gd:111` already checks, preserved) |
| `lighting.apply_creates_nodes` | `apply_profile(root, "hub")` yields exactly one `WorldEnvironment`, one `DirectionalLight3D`, one `FillLight`, and no `KeyLight` |
| `lighting.apply_is_idempotent` | a second `apply_profile()` call adds no children and reuses the same `Environment` object id |
| `lighting.interior_has_key_light` | `apply_profile(root, "umbral")` yields a `KeyLight` with `shadow_enabled == true` at `shadow_quality > 0`, and no `Sky` |
| `lighting.sky_uniform_coverage` | every `uniform` declared in `pixel_sky.gdshader` is written by `_make_sky()` for a profile that declares a `sky` block |
| `lighting.shadow_budget` | dressing a `castle_hall` yields at most `max_shadow_omnis` omnis with `shadow_enabled == true` |
| `lighting.flicker_phase_differs` | two lights 2 m apart produce `phase` values differing by more than 0.5 rad |
| `lighting.flicker_bounded` | over 600 simulated frames a flickering light's energy stays within `base * (1 +- amount)` and never goes negative |
| `lighting.flicker_disabled` | with `light_animation == false`, `attach_flicker()` adds no child and energy is constant |
| `lighting.atmosphere_follows` | moving the follow target 40 m moves `BiomeAtmosphere` to within 4 m of it |
| `lighting.atmosphere_respects_quality` | `particle_quality = 0` then `apply_all()` frees the holder; setting it back to 2 recreates it |
| `lighting.grade_consistent` | `tonemap_mode` and `tonemap_white` match between an outdoor and an interior profile |
| `lighting.no_unused_constants` | `visual_lighting.gd` declares no constant without a reader (guards LIT-10 from recurring) |

Manual checklist:

- Stand in a torch-lit `castle_hall`: the player's shadow must be visible and blocky, not soft or absent.
- Watch two torches for ten seconds: the flicker must read as fire, not as a strobe or a synchronised pulse.
- Compare the hub sky at `sun_size 0.045` and `0.12`: the disc must visibly change size.

## Related
- Existing behaviour: [`../existing_codebase/visual-lighting.md`](../existing_codebase/visual-lighting.md)
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — owns shadow quality, SSAO, glow, tonemap, `particle_quality`, and gains `light_animation`
- [`pixel-style.md`](pixel-style.md) — the banded `light()` that turns these lights into steps; palettes and lighting should be authored against each other
- [`biome-registry.md`](biome-registry.md) — loses `get_lighting_profile()` in step 2
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — attaches flicker and enforces the shadow budget
- [`vfx-service.md`](vfx-service.md) — the other particle owner; shares `particle_amount_scale()`
- [`content-data.md`](content-data.md) — where `content/art/lighting.json` lives
- [`validation-suites.md`](validation-suites.md) — new `visual_lighting_suite`
