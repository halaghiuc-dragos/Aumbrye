# Visual lighting

`VisualLighting` is a `RefCounted` static-only helper that owns three outdoor lighting presets, the indoor `Environment` tuning, the soft-omni configuration used by every torch and fill light, and the per-biome ambient particle and fog-volume pass. It is the only place that loads `pixel_sky.gdshader`. Every light it creates is static: there is no flicker, no animation, and no time of day anywhere in the repo. Indoor scenes have no shadow-casting light at all.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/lighting/visual_lighting.gd` | Presets, sun/fill/environment/sky construction, `configure_soft_omni`, biome atmosphere |
| `apps/game/client/assets/shared/pixel_sky.gdshader` | Banded sky, stepped sun disc and halo, blocky cloud belt |

Consumers:

| Caller | Entry point |
|--------|-------------|
| `hub_diorama.gd:61` | `apply_hub()` |
| `arena_diorama.gd:13` | `apply_arena()` |
| `waves_outdoors_diorama.gd:15` | `apply_waves_outdoors()` |
| `biome_registry.gd:217` | `apply_indoor_environment()` |
| `biome_registry.gd:244` | `apply_biome_atmosphere()` |
| `diorama_room_dressing.gd:129,318,333,347,417` | `configure_soft_omni()` plus the torch/fill constants |

## How it works

### Outdoor presets

`OUTDOOR_PRESETS` (`:27-85`) is a `Dictionary` of three entries — `hub`, `arena`, `waves_outdoors` — each with 15 keys: `sky_zenith`, `sky_horizon`, `sky_ground`, `sky_bands`, `cloud_amount`, `cloud_color`, `ambient`, `ambient_energy`, `fog_color`, `fog_density`, `fog_aerial`, `sun_color`, `sun_energy`, `sun_rotation`, `fill_color`, `fill_energy`, `fill_rotation`.

`apply_outdoor(root, preset_id)` (`:100-106`) looks the preset up with a `hub` fallback, then runs `_apply_environment`, `_apply_sun`, `_apply_fill`. `apply_hub`, `apply_arena`, and `apply_waves_outdoors` are one-line wrappers.

`_apply_environment` (`:141-162`) finds or creates a `WorldEnvironment` child named exactly `WorldEnvironment`, then builds a **brand new** `Environment` every call: `BG_SKY`, a fresh `Sky` from `_make_sky()`, `AMBIENT_SOURCE_COLOR`, fog on with `fog_sky_affect = 0.0` so the banded gradient is not washed out, then `PixelDioramaSettings.configure_environment(env)` for tonemap, glow, and SSAO.

`_apply_sun` (`:183-192`) finds or creates `DirectionalLight3D`, sets colour, energy, and Euler rotation from the preset, then hands shadow tuning to `PixelDioramaSettings.configure_directional_shadow()`.

`_apply_fill` (`:195-204`) finds or creates a second `DirectionalLight3D` named `FillLight` with `shadow_enabled = false`.

Fog densities are deliberately low (0.0018–0.0032). The comment at `:24-26` states that at 480×270 dense fog flattens distant silhouettes, and depth is meant to come from the banded sky instead.

### Sky

`_make_sky(preset)` (`:165-180`) builds a `ShaderMaterial` on `pixel_sky.gdshader` and sets seven uniforms: `zenith_color`, `horizon_color`, `ground_color`, `bands`, `sun_color`, `cloud_amount`, `cloud_color`. The returned `Sky` uses `PROCESS_MODE_AUTOMATIC` and `RADIANCE_SIZE_32`.

The shader (`pixel_sky.gdshader`):
- Below the horizon (`EYEDIR.y < 0`) it returns `ground_color` flat.
- Above it, `t = pow(clamp(elevation), 1/horizon_falloff)` is quantized to `floor(t * bands) / (bands - 1)` and used to `mix(horizon_color, zenith_color)`.
- The cloud belt (`:48-57`) samples a two-octave value noise on a fixed angular grid — `atan(EYEDIR.x, EYEDIR.z) * 26.0` and `elevation * 62.0`, floored — so puffs keep the same apparent size regardless of camera direction. The belt is masked by `(1 - smoothstep(0.06, 0.34, elevation)) * smoothstep(0.0, 0.05, elevation)`, i.e. it only exists between roughly 0 and 0.34 elevation. Two thresholds produce a body colour at `cloud_color * 0.86` and a rim at full `cloud_color`.
- The sun (`:59-65`) is a hard `step` disc at `1 - sun_size²` plus a 4-step quantized halo from `pow(d, 42)`.

`horizon_falloff` (2.4), `sun_size` (0.045), and `sun_glow` (0.4) are declared uniforms that `_make_sky()` never sets, so every preset shares the shader defaults.

### Indoor environment

`apply_indoor_environment(environment, lighting_profile)` (`:109-130`) reads a `BiomeRegistry.get_lighting_profile()` dictionary:
- `background_color` = `ambient_color.lerp(Color(0.1, 0.09, 0.12), 0.68)`
- `ambient_light_color` = `ambient_color.lerp(Color(0.78, 0.68, 0.55), 0.42)`
- `ambient_light_energy` = `max(ambient_energy * 0.82, 0.5)` — the floor of 0.5 means a biome authored below 0.61 ambient energy cannot get darker
- fog from `fog_enabled` / `fog_color` / `fog_density` with `fog_sky_affect = 0.0`
- `PixelDioramaSettings.configure_environment(environment)`, then it **re-writes** `tonemap_exposure` and `tonemap_white` to 1.0/1.2 (linear) or 1.02/1.42 (filmic), overriding the 1.2/1.0 that `configure_environment` just set

It is reached only from `biome_registry.gd:216-217`, and only when `run_mode` is `MODE_CASTLE` or `MODE_ENDLESS`. In that branch `biome_registry.gd:228-229` also sets `sun.visible = false`.

### Soft omnis

`configure_soft_omni(light, color, energy, light_range)` (`:133-138`) sets colour, energy, range, `omni_attenuation = SOFT_OMNI_ATTENUATION` (1.48), and `shadow_enabled = false` unconditionally.

Constants at `:13-20`: `SOFT_OMNI_ATTENUATION` 1.48, `TORCH_OMNI_RANGE` 13.5, `TORCH_OMNI_ENERGY` 0.92, `WALL_TORCH_ENERGY` 0.78, `WALL_TORCH_RANGE` 10.0, `ROOM_FILL_ENERGY` 0.88, `SHELL_TORCH_ENERGY` 0.72, `SHELL_TORCH_SPACING` 16.0. All are consumed by `diorama_room_dressing.gd` except `SHELL_TORCH_ENERGY`, which has no reader.

### Biome atmosphere

`apply_biome_atmosphere(root, biome_id)` (`:208-237`):
- Returns immediately if `PixelDioramaSettings.particle_quality <= 0` or a child named `BiomeAtmosphere` already exists.
- Creates the `BiomeAtmosphere` holder and calls `_add_ambient_particles()` with one of five hard-coded tint/amount/range/fall-speed tuples chosen by a `match` on `biome_id`: swamp+mire (48 motes), frozen+hollow (64), crystal+prism (36), umbral+cathedral (28), everything else (24).
- If the biome's lighting profile has `fog_enabled`, adds a `FogVolume` named `BiomeFogVolume` of size 48×8×48 at y 3.0 with `FogMaterial.density = profile.fog_density * 0.35`.

`_add_ambient_particles` (`:240-267`) builds a `GPUParticles3D` named `AmbientMotes` with `amount * PixelDioramaSettings.particle_amount_scale()`, a 6 s lifetime, a `visibility_aabb` spanning `range_size` in x/z, an 0.08 m `BoxMesh` draw pass, and a `ParticleProcessMaterial` with a box emission shape of extents `(range_size, 3.0, range_size)`, downward direction, 18° spread, `gravity (0, -0.35, 0)`, and scale 0.04–0.1.

Both the particles and the fog volume are parented to the scene root at local origin.

## Contracts

- Node names `WorldEnvironment`, `DirectionalLight3D`, `FillLight`, `BiomeAtmosphere`, `AmbientMotes`, `BiomeFogVolume` are looked up by exact name and are the reuse contract with `hub.tscn` and the run scene roots.
- `biome_registry.gd:226-233` looks up `DirectionalLight3D` by the same name and toggles `visible` / re-tunes energy, so the two systems share that node.
- `apply_indoor_environment()` expects the `BiomeRegistry.get_lighting_profile()` shape: `ambient_color`, `ambient_energy`, `fog_enabled`, `fog_color`, `fog_density`.
- `_make_sky()` expects `pixel_sky.gdshader` to declare `zenith_color`, `horizon_color`, `ground_color`, `bands`, `sun_color`, `cloud_amount`, `cloud_color`.
- Shadow policy is delegated: `configure_directional_shadow()` for the sun, hard-coded `false` for fills and every omni.
- `Sky.PROCESS_MODE_AUTOMATIC` plus `RADIANCE_SIZE_32` is the stated workaround for realtime radiance-size warnings (`:177-179`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Three outdoor presets with sky, sun, fill, fog, ambient | IMPLEMENTED | `visual_lighting.gd:27-85`, `:100-204` |
| Banded sky with stepped sun and blocky clouds | IMPLEMENTED | `assets/shared/pixel_sky.gdshader:35-68` |
| Soft-omni helper and indoor environment tuning | IMPLEMENTED | `visual_lighting.gd:109-138` |
| Biome ambient motes and fog volume | PARTIAL | `visual_lighting.gd:208-267` — five hard-coded tuples, built once at scene origin, never follows the player |
| No light animation anywhere: no flicker, no pulse, no time of day | PLACEHOLDER | no `create_tween`, no `light_energy` write outside setup in `visual_lighting.gd` or `diorama_room_dressing.gd` |
| Indoor scenes have no shadow-casting light | PARTIAL | `configure_soft_omni` forces `shadow_enabled = false` (`:138`); `biome_registry.gd:229` hides the sun for `MODE_CASTLE`/`MODE_ENDLESS` |
| Two independent lighting data sources | PARTIAL | `OUTDOOR_PRESETS` (`:27-85`) for outdoors, `BiomeRegistry.get_lighting_profile()` (`biome_registry.gd:112-193`) for the ten biomes, with no shared shape |
| Lighting data is GDScript literals, not content data | PLACEHOLDER | `visual_lighting.gd:27-85`; no `content/` lighting file exists |
| `SHELL_TORCH_ENERGY` | STUB | declared `:19`; no reader in the repo |
| `hub` preset `fill_energy` is 0.0 | PARTIAL | `:44` — the `FillLight` node is created and contributes nothing |
| `horizon_falloff`, `sun_size`, `sun_glow` never set from a preset | PARTIAL | declared `pixel_sky.gdshader:11`, `:13-14`; not written in `_make_sky()` (`:165-180`) |
| `_apply_environment` allocates a new `Environment` and `Sky` on every call | PARTIAL | `:148-150` — each call triggers a fresh radiance bake |
| `apply_indoor_environment` overwrites the tonemap white point that `configure_environment` just set | PARTIAL | `:124-130` vs `pixel_diorama_settings.gd:322-327` |
| Indoor `ambient_light_energy` floor of 0.5 | PARTIAL | `:115` — umbral (0.34) and cathedral (0.35) profiles cannot render as dark as authored |
| `apply_biome_atmosphere` ignores later `particle_quality` changes | PARTIAL | `:209-212` — guarded by node existence, and `PixelDioramaSettings.apply_all()` does not rebuild it |
| Sky is unreachable indoors | IMPLEMENTED (by design) | `biome_registry.gd:201` uses `BG_COLOR` for runs; only the three outdoor presets use `BG_SKY` |
| Validation coverage | PARTIAL | `pixel_pipeline_suite.gd:21` asserts the script file exists; `m5_suite.gd:88-111` and `m6_suite.gd:84-94` assert every biome profile has an `ambient_color` and that profiles are distinct. No preset, sky-uniform, or light-node assertion exists — searched all of `apps/game/client/scripts/validation/` for `VisualLighting` and `pixel_sky` |

## Related
- Improvement plan: [`../actual_improvements/visual-lighting.md`](../actual_improvements/visual-lighting.md)
- [`pixel-style.md`](pixel-style.md) — the banded `light()` these lights feed
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — owns tonemap, glow, SSAO, directional shadow tuning, and `particle_quality`
- [`biome-registry.md`](biome-registry.md) — the second lighting data source and the only `apply_indoor_environment` caller
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — every `configure_soft_omni` caller
- [`hub.md`](hub.md), [`debug-arenas.md`](debug-arenas.md), [`waves-run.md`](waves-run.md) — the three outdoor preset consumers
- [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
