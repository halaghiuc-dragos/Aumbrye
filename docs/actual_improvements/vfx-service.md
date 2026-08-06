# VFX service — improvement plan

## Status: FINISHED

## Current state

`VfxService` is data-driven: all combat and locomotion effects resolve through `play(effect_id, …)` backed by `content/vfx/effects.json`. Particles use cached `pixel_diorama_emissive.gdshader` materials tracked by `PixelDioramaSettings`. Pools are capped and swept in `_process()`; hit-stop, camera shake, and damage vignette are `impact` layers. Enemy windups call `play_telegraph()` — `TelegraphMesh` nodes were removed from all `scenes/enemies/`. Authored decal PNGs live under `assets/textures/vfx/`. `vfx_service_suite.gd` and real `perf_gate_suite.gd` gates replace the old string-grep stubs. See [`../existing_codebase/vfx-service.md`](../existing_codebase/vfx-service.md).

## Gaps

| ID | Sev | Gap | Evidence | Status |
|----|-----|-----|----------|--------|
| VFX-01 | P0 | Particles bypassed pixel shaders | was `vfx_service.gd` `StandardMaterial3D` | **FINISHED** — `_particle_material()` cache on emissive shader |
| VFX-02 | P0 | Effect tuning unreachable in GDScript dicts | was inline `_COMBAT_BURST` literals | **FINISHED** — `content/vfx/effects.json` + `play()` dispatcher |
| VFX-03 | P1 | Per-burst material allocation | was fresh `StandardMaterial3D` per emit | **FINISHED** — shared cached `ShaderMaterial` |
| VFX-04 | P1 | Pools grew without bound | was `_burst_pool.append()` | **FINISHED** — `BURST_POOL_MAX` steal-oldest at cap |
| VFX-05 | P1 | `play_telegraph()` dead; scene `TelegraphMesh` duplicates | was 78-line unused path + enemy `.tscn` spheres | **FINISHED** — glyph layers; enemy scenes cleaned |
| VFX-06 | P1 | No hit-stop, shake, or vignette coordination | was absent | **FINISHED** — `impact` layers + `OrbitCamera.consume_shake()` |
| VFX-07 | P1 | All VFX geometry one 0.2 m cube | was `_pixel_chunk_mesh()` only | **FINISHED** — `chunks` + authored decal PNGs |
| VFX-08 | P2 | Decals projected down and popped off | was `rotation.x = -PI/2` + instant hide | **FINISHED** — normal basis + alpha fade tween |
| VFX-09 | P2 | Combat audio fired from VFX methods | was `AudioDirector` in burst helpers | **FINISHED** — `sfx` layers in JSON |
| VFX-10 | P2 | `SceneTreeTimer` per effect | was `_schedule_*` timers | **FINISHED** — `_sweep_pools()` in `_process()` |
| VFX-11 | P2 | Fixed `visibility_aabb`; dead `TEXTURE_FILTER_NEAREST` | was `-2..2` box | **FINISHED** — `_burst_visibility_aabb()` per layer |
| VFX-12 | P2 | `DEATH_BURST_LIFETIME` duplicated | was const + comment in `material_dissolve.gd` | **FINISHED** — `get_death_burst_lifetime()` |
| VFX-13 | P2 | Validation grepped pool strings; frame budget `true` | was `perf_gate_suite.gd:13-38` stubs | **FINISHED** — `vfx_service_suite.gd` + real perf gates |

## Target design

Implemented as specified in the original plan: effects as JSON with six layer kinds, pixel-shader particle cache, bounded pools with process sweep, impact feedback (hit-stop/shake/vignette), authored art, normal-oriented fading decals, sfx layers, glyph telegraph consolidation, and AABB sizing from burst parameters.

## Work plan

All nine steps completed in a single pass (pixel materials → pools → JSON dispatcher → impact → decals → sfx → art → telegraphs → validation).

## Data and schema changes

- `content/schemas/vfx-effect.v1.json` and `content/vfx/effects.json` (11 required effect ids + extras).
- `apps/game/client/assets/textures/vfx/` — five PNG decals with `.import` sidecars.
- `PixelDioramaSettings.hitstop_enabled` and `screen_shake_scale` (existing keys).
- 36 enemy `.tscn` files — `TelegraphMesh` nodes removed.
- `DEATH_BURST_LIFETIME` removed; `material_dissolve.gd` uses `VfxService.get_death_burst_lifetime()`.

## Acceptance criteria

- [x] Setting "Colour levels" to 4 posterizes hit sparks (`vfx.settings_reach_particles`). (VFX-01)
- [x] Changing `hit_spark.layers[0].amount` in JSON changes spark count. (VFX-02)
- [x] 40 consecutive hits share one material cache entry (`vfx.material_cache_hits`). (VFX-03)
- [x] 200 bursts leave pool ≤ `BURST_POOL_MAX` (`vfx.pool_bounded`). (VFX-04)
- [x] No `TelegraphMesh` in `scenes/enemies/`; windups use `play_telegraph()`. (VFX-05)
- [x] Hit-stop and shake gated by settings (`vfx.hitstop_restores`, `vfx.shake_decays`). (VFX-06)
- [x] Blood decals pick randomly among declared PNG variants. (VFX-07)
- [x] Decals align to supplied normal and fade (`vfx.decal_uses_normal`, `vfx.decal_fades`). (VFX-08)
- [x] Removing `sfx` layer from `attack_swing` silences swing without code edit. (VFX-09)
- [x] No `create_timer` in `vfx_service.gd` (`vfx.no_timers`). (VFX-10)
- [x] Burst AABB covers travel (`vfx.aabb_covers_travel`). (VFX-11)

## Validation

`apps/game/client/scripts/validation/suites/vfx_service_suite.gd` (category `graphics`, 20 tests) and `perf_gate_suite.gd` (`perf.vfx_burst_pool`, `perf.frame_budget` with skip when baseline absent).

Run:

```powershell
powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd -- --suite=vfx_service_suite
```

## Related

- Existing behaviour: [`../existing_codebase/vfx-service.md`](../existing_codebase/vfx-service.md)
- [`pixel-style.md`](pixel-style.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`orbit-camera.md`](orbit-camera.md), [`audio-director.md`](audio-director.md), [`material-dissolve.md`](material-dissolve.md)
