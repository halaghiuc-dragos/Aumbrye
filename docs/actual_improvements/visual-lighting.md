# Visual lighting — improvement plan

## Status: FINISHED

## Current state

`VisualLighting` loads every outdoor and interior profile from `content/art/lighting.json`, applies sun/fill/key lights, torch flicker, and a player-following atmosphere pass. `BiomeRegistry.apply_run_presentation()` delegates to `VisualLighting.apply_profile()`. See [`../existing_codebase/visual-lighting.md`](../existing_codebase/visual-lighting.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| LIT-01 | P0 | Indoor scenes cast no shadows | FINISHED — `KeyLight` + opt-in omni shadows with `max_shadow_omnis` budget |
| LIT-02 | P0 | Two incompatible lighting data sources | FINISHED — unified `content/art/lighting.json` |
| LIT-03 | P1 | Nothing animates | FINISHED — `LightFlicker` + `PixelDioramaSettings.light_animation` |
| LIT-04 | P1 | Lighting in GDScript literals | FINISHED — `lighting-profile.v1.json` schema + content file |
| LIT-05 | P1 | Atmosphere fixed at scene origin | FINISHED — `BiomeAtmosphereFollow` snaps to follow target |
| LIT-06 | P1 | Sky uniforms never set | FINISHED — `horizon_falloff`, `sun_size`, `sun_glow` written per profile |
| LIT-07 | P2 | Environment reallocated every call | FINISHED — in-place `Environment`/`Sky` reuse |
| LIT-08 | P2 | Indoor tonemap overwrite | FINISHED — single `configure_environment()` grade path |
| LIT-09 | P2 | Indoor ambient floor of 0.5 | FINISHED — profile `ambient.energy` used verbatim |
| LIT-10 | P2 | Dead constants / zero hub fill | FINISHED — `SHELL_TORCH_ENERGY` removed; hub `fill.energy` 0.18 |
| LIT-11 | P2 | Thin validation | FINISHED — `visual_lighting_suite.gd` (17 assertions) |

## Validation

`visual_lighting_suite.gd` (category `graphics`): JSON load, biome map, scene profiles, color/energy bounds, profile distinctness, node creation, idempotent apply, interior `KeyLight`, sky uniform coverage, shadow budget, flicker phase/bounds/disable, atmosphere follow/quality, grade consistency, no legacy constants.

Run: `powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=visual_lighting_suite`

## Related

- Existing behaviour: [`../existing_codebase/visual-lighting.md`](../existing_codebase/visual-lighting.md)
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — `light_animation`, shadow quality, `refresh_atmosphere()` hook
- [`diorama-room-dressing.md`](diorama-room-dressing.md) — torch flicker and shadow budget enforcement
- [`biome-registry.md`](biome-registry.md) — `apply_run_presentation()` profile delegation
