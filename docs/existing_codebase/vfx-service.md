# VFX service

## Status: FINISHED

`VfxService` is the `res://scripts/art/vfx/vfx_service.gd` autoload (`project.godot`) that owns one-shot combat and locomotion effects. Effect definitions live in `content/vfx/effects.json`; the public `play(effect_id, world_pos, direction, …)` dispatcher executes `burst`, `decal`, `ribbon`, `glyph`, `impact`, and `sfx` layers. Particle draw materials use `pixel_diorama_emissive.gdshader` through a cached factory registered with `PixelDioramaSettings.track()`. Pools are capped at `BURST_POOL_MAX` 32 / `GPU_BURST_POOL_MAX` 16 / `DECAL_POOL_MAX` 24 with oldest-steal acquisition; lifetimes are swept in `_process` (no `create_timer`).

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/vfx/vfx_service.gd` | Autoload: `play()` dispatcher, pools, impact feedback, telegraph glyphs |
| `content/vfx/effects.json` | Effect definitions, chunk mesh table, decal texture paths |
| `content/schemas/vfx-effect.v1.json` | JSON schema for effects data |
| `apps/game/client/assets/textures/vfx/*.png` | Authored 32×32 decal atlases (`blood_small`, `blood_large`, `impact_small`, `impact_scorch`, `dust_ring`) |
| `apps/game/client/scripts/validation/suites/vfx_service_suite.gd` | Headless graphics validation |

## How it works

### Setup

`_ready()` loads `content/vfx/effects.json`, creates `VfxRoot`, pre-allocates capped pools, and connects `PixelDioramaViewport.world_attached` to reparent `VfxRoot` into the active scene.

### Public API

| Method | Maps to | Callers |
|--------|---------|---------|
| `play(effect_id, pos, direction, …)` | Generic dispatcher | internal |
| `resolve_combat_anchor(body)` | — | `castle_enemy_base.gd`, `player_anim_director.gd`, `guard.gd`, `hurtbox.gd`, `weapon_controller.gd` |
| `play_attack_swing` / `play_block` / `play_parry` | `attack_swing`, `block`, `parry` | `weapon_controller.gd`, `hit_feedback.gd`, `guard.gd` |
| `play_hit_spark(pos, dir, normal)` | `hit_spark` (+ impact layer) | `hitbox.gd`, `hit_feedback.gd`, `player_heal.gd`, interactables |
| `play_blood_decal` / `play_impact_decal` | `blood_decal` / `impact_decal` | `hurtbox.gd`, `guard.gd` |
| `play_death(pos, tint, debris)` | `death` | `material_dissolve.gd`, `castle_enemy_base.gd` |
| `play_footstep(pos, forward, surface)` | `footstep*` variants | `locomotion.gd`, `player_anim_director.gd` |
| `play_weapon_trail` | `weapon_trail` ribbon layer | `castle_enemy_base.gd`, `player_anim_director.gd` |
| `play_telegraph(pos, radius, duration, tint, shape, forward)` | `telegraph_*` glyph layers | `castle_enemy_base.gd`, `training_grunt.gd` |
| `request_hitstop(ms, strength)` / `request_shake(amount, ms)` / `consume_shake()` | `impact` layers + camera | `OrbitCamera` consumes shake each frame |

`FOOTSTEP_INTERVAL_WALK` (0.42) and `FOOTSTEP_INTERVAL_SPRINT` (0.28) are read by `locomotion.gd`. `get_death_burst_lifetime()` reads the longest `death` burst lifetime from JSON for `material_dissolve.gd`.

### Particle materials

`_particle_material(color, emission)` builds a cached `ShaderMaterial` on `pixel_diorama_emissive.gdshader`, sets `grain_strength = 0`, and registers with `PixelDioramaSettings.track()` so `apply_all()` restamps `pixel_scale` and `color_levels`.

### Decals

`_spawn_decal()` orients from the supplied surface normal, picks a random variant when the JSON entry is an array, and tweens `modulate.a` over the layer `fade` seconds before pool return.

### Impact feedback

`impact` layers call `request_hitstop`, `request_shake`, and `PixelDioramaViewport.pulse_damage_vignette()`. Gated by `PixelDioramaSettings.hitstop_enabled`, `screen_shake_scale`, and `AccessibilitySettings`.

## Contracts

- Autoload name `VfxService`; asserted by `setup_suite.gd` and `pixel_pipeline_suite.gd`.
- `resolve_combat_anchor()` prefers `Facing/WeaponPivot/Hitbox`, then `Facing/WeaponPivot`, then body centre.
- `play_hit_spark()` / `play_death()` GPU bursts require `PixelDioramaSettings.particle_quality > 0`; CPU fallback otherwise.
- `sfx` layers call `AudioDirector.play_sfx(key, world_pos)`; skipped when `OS.has_feature("no_audio")`.
- Enemy windups use `VfxService.play_telegraph()`; no `TelegraphMesh` nodes remain under `scenes/enemies/`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Data-driven effects JSON + schema | IMPLEMENTED | `content/vfx/effects.json`, `vfx-effect.v1.json` |
| Pixel-shader particle materials | IMPLEMENTED | `_particle_material()`, `vfx_service_suite.gd` `vfx.materials_are_shader_materials` |
| Cached materials, capped pools | IMPLEMENTED | `_particle_material_cache`, `BURST_POOL_MAX`, `_acquire_from_pool()` |
| Hit-stop, shake, vignette | IMPLEMENTED | `impact` layers, `request_hitstop`, `OrbitCamera` + `consume_shake()` |
| Authored decal textures + chunk variants | IMPLEMENTED | `assets/textures/vfx/`, `chunks` block in JSON |
| Surface-normal decals with fade | IMPLEMENTED | `_spawn_decal()`, `hurtbox.gd` / `hitbox.gd` normal pass-through |
| Audio via `sfx` layers only | IMPLEMENTED | `effects.json` `sfx` layers, no direct `AudioDirector` calls in wrappers |
| Enemy telegraph via VfxService | IMPLEMENTED | `castle_enemy_base.gd` `_show_attack_telegraph()`, zero `TelegraphMesh` in enemy scenes |
| Validation | IMPLEMENTED | `vfx_service_suite.gd`, `perf_gate_suite.gd` `perf.vfx_burst_pool` + `perf.frame_budget` |

## Related
- Improvement plan: [`../actual_improvements/vfx-service.md`](../actual_improvements/vfx-service.md) - **FINISHED**
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — `particle_quality`, `hitstop_enabled`, `screen_shake_scale`
- [`pixel-style.md`](pixel-style.md) — emissive shader, `make_glow_material()` for telegraph glyphs
- [`audio-director.md`](audio-director.md) — `sfx` layer keys
- [`material-dissolve.md`](material-dissolve.md), [`hit-feedback.md`](hit-feedback.md)
