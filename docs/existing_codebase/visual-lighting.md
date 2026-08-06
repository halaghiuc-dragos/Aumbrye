# Visual lighting

## Status: FINISHED

`VisualLighting` is a `RefCounted` static-only helper that loads lighting profiles from `content/art/lighting.json`, applies environment/sun/fill/key lights, configures torch omnis (with optional shadows and flicker), and attaches a per-biome atmosphere pass that follows the player. It is the only place that loads `pixel_sky.gdshader`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/art/lighting/visual_lighting.gd` | Profile loader, environment/light construction, atmosphere, flicker attach |
| `apps/game/client/scripts/art/lighting/light_flicker.gd` | Per-torch deterministic flicker driver |
| `apps/game/client/scripts/art/lighting/biome_atmosphere_follow.gd` | Snaps `BiomeAtmosphere` holder to a follow target on a 4 m grid |
| `content/art/lighting.json` | 14 profiles (3 outdoor + `waves_arena` + 10 biome interiors) and `biome_profile_map` |
| `content/schemas/lighting-profile.v1.json` | Schema for the lighting catalog |
| `apps/game/client/assets/shared/pixel_sky.gdshader` | Banded sky, stepped sun disc and halo, blocky cloud belt |

Consumers:

| Caller | Entry point |
|--------|-------------|
| `hub_diorama.gd:61` | `apply_hub()` â†’ `apply_profile("hub")` |
| `arena_diorama.gd:13` | `apply_arena()` |
| `waves_outdoors_diorama.gd:15` | `apply_waves_outdoors()` |
| `biome_registry.gd:131` | `apply_run_presentation()` â†’ `apply_profile()` + `attach_atmosphere()` |
| `diorama_room_dressing.gd` | `configure_soft_omni()`, `attach_flicker()`, shadow budget |

## How it works

### Profile loading

`ContentLoader.load_json("content/art/lighting.json")` is cached in `_data_cache` (`visual_lighting.gd`). `profile_for_biome(biome_id)` resolves through `biome_profile_map`, falling back to `"hub"` with a warning. `apply_profile(root, profile_id)` is the single apply entry point.

Outdoor profiles declare a `sky` block â†’ `Environment.BG_SKY`, `DirectionalLight3D` sun, optional `FillLight`. Interior profiles omit `sky` â†’ `Environment.BG_COLOR`, `sun.energy: 0`, shadow-casting `KeyLight` `DirectionalLight3D`.

### Environment reuse

`_apply_environment()` reuses the existing `WorldEnvironment.environment` and mutates it in place. When a sky is needed, the existing `Sky` material is updated via `_update_sky()` rather than allocating a new `Environment`/`Sky` pair (`visual_lighting.gd`).

### Sky uniforms

`_make_sky` / `_update_sky` write all ten `pixel_sky.gdshader` uniforms: `zenith_color`, `horizon_color`, `ground_color`, `bands`, `horizon_falloff`, `sun_color`, `sun_size`, `sun_glow`, `cloud_amount`, `cloud_color`.

### Indoor grade

`apply_indoor_environment()` and `apply_profile()` both end with `PixelDioramaSettings.configure_environment()` only â€” no secondary `tonemap_white` overwrite. Umbral `ambient.energy` 0.34 is applied verbatim (no 0.5 floor).

### Soft omnis and flicker

`configure_soft_omni(light, color, energy, range, cast_shadows=false)` sets `SOFT_OMNI_ATTENUATION` 1.48. When `cast_shadows` and `shadow_quality > 0`, blocky omni shadow tuning is applied. `attach_flicker()` adds a `LightFlicker` child unless `PixelDioramaSettings.light_animation` is false.

`diorama_room_dressing.gd` enforces `max_shadow_omnis` (default 2) per room via `_take_shadow_slot()` and attaches flicker on every torch.

### Atmosphere

`attach_atmosphere(root, profile_id, follow)` creates a `BiomeAtmosphere` holder with `BiomeAtmosphereFollow` script. Mote tint/amount/radius and optional `BiomeFogVolume` come from the profile `atmosphere` block. `PixelDioramaSettings.apply_all()` calls `VisualLighting.refresh_atmosphere()` so `particle_quality` changes rebuild the holder.

Constants retained for dressing: `TORCH_OMNI_RANGE` 13.5, `TORCH_OMNI_ENERGY` 0.92, `WALL_TORCH_ENERGY` 0.78, `WALL_TORCH_RANGE` 10.0, `ROOM_FILL_ENERGY` 0.88, `SHELL_TORCH_SPACING` 16.0.

## Contracts

- Node names: `WorldEnvironment`, `DirectionalLight3D`, `FillLight`, `KeyLight`, `BiomeAtmosphere`, `AmbientMotes`, `BiomeFogVolume`, `LightFlicker`.
- `biome_registry.gd` hides `DirectionalLight3D` (outdoor sun) for `MODE_CASTLE` / `MODE_ENDLESS`; interiors rely on `KeyLight`.
- `PixelDioramaSettings.light_animation` (default `true`, persisted in `pixel_diorama` meta) gates flicker.
- Shadow policy: `configure_directional_shadow()` for sun/key; opt-in omni shadows capped by profile `torch.max_shadow_omnis`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Unified `content/art/lighting.json` profiles | IMPLEMENTED | `visual_lighting.gd`; `content/art/lighting.json` |
| Outdoor sky + sun + fill | IMPLEMENTED | `apply_profile()` hub/arena/waves_outdoors |
| Interior key light + shadows | IMPLEMENTED | `KeyLight` in biome profiles; `visual_lighting_suite.gd` |
| Torch flicker | IMPLEMENTED | `light_flicker.gd`; `attach_flicker()` |
| Player-following atmosphere | IMPLEMENTED | `biome_atmosphere_follow.gd`; `attach_atmosphere()` |
| Environment reuse on re-apply | IMPLEMENTED | `_apply_environment()` in-place mutation |
| Consistent tonemap grade | IMPLEMENTED | no post-`configure_environment` overwrite |
| Validation | IMPLEMENTED | `visual_lighting_suite.gd` (17 tests) |

## Related

- Improvement plan: [`../actual_improvements/visual-lighting.md`](../actual_improvements/visual-lighting.md) - **FINISHED**
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) â€” shadow quality, `light_animation`, `particle_quality`, tonemap
- [`biome-registry.md`](biome-registry.md) â€” `apply_run_presentation()` caller
- [`diorama-room-dressing.md`](diorama-room-dressing.md) â€” torch spawn and shadow budget
- [`pixel-style.md`](pixel-style.md) â€” banded `light()` these lights feed
