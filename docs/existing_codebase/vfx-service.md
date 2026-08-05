# VFX service

`VfxService` is the `*res://scripts/art/vfx/vfx_service.gd` autoload (`project.godot:48`) that owns every one-shot combat and locomotion effect: hit sparks, blood and impact decals, death bursts, footstep dust, weapon trail ribbons, and a floor telegraph glyph. It pools `CPUParticles3D`, `GPUParticles3D`, and `Decal` nodes under a single `VfxRoot` child. Every effect is a 0.2 m `BoxMesh` chunk or a procedurally generated 16×16 `ImageTexture` — there are no VFX assets in the repo. It also fires combat audio: five of its nine public methods call `AudioDirector.play_sfx()` directly.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/vfx/vfx_service.gd` | The whole service: pools, effect methods, particle material factory, decal texture generator |

## How it works

### Setup

`_ready()` (`:39-66`) creates a `Node3D` named `VfxRoot`, generates the two decal textures, then pre-allocates three pools:
- 16 `CPUParticles3D` named `BurstPool0..15`, `one_shot = true`, `top_level = true`, `visibility_aabb = AABB((-2,-1,-2), (4,4,4))`, mesh set to the shared `_pixel_chunk_mesh()`.
- 8 `GPUParticles3D` from `_make_gpu_burst()` named `GpuBurstPool0..7`.
- 12 `Decal` named `DecalPool0..11`, `visible = false`.

`_pixel_chunk_mesh()` (`:438-442`) lazily creates one `BoxMesh` of `0.2³` and returns the same instance to every particle system in the game.

### Public API and consumers

| Method | Effect | Audio | Callers |
|--------|--------|-------|---------|
| `resolve_combat_anchor(body) -> Array` (`:69-81`) | Returns `[position, forward]`, preferring `Facing/WeaponPivot/Hitbox`, then `Facing/WeaponPivot`, then body centre + 1 m up offset by `-forward` | — | `castle_enemy_base.gd:136`, `player_anim_director.gd:291`, `guard.gd:125`, `hurtbox.gd:122`, `weapon_controller.gd:356` |
| `play_attack_swing(pos, forward)` (`:84-87`) | Combat burst, warm yellow, emission 2.2 | `swing` | `weapon_controller.gd:357` |
| `play_block(pos, forward)` (`:89-92`) | Combat burst, cold blue, emission 0.8 | `block` | `hurtbox.gd:123` |
| `play_parry(pos, forward)` (`:94-97`) | Combat burst, gold, emission 0.85 | `parry` | `guard.gd:126` |
| `play_hit_spark(pos, direction)` (`:99-129`) | GPU burst of `24 * particle_amount_scale()` at 0.28 s, or a CPU burst when `particle_quality == 0` | — | `hitbox.gd:150` |
| `play_blood_decal(pos, direction)` (`:132-133`) | 0.42 m decal, 3.2 s | — | `hurtbox.gd:138`, and internally from `play_death` |
| `play_impact_decal(pos, direction)` (`:136-137`) | 0.28 m decal, 2.4 s | — | `guard.gd:127`, `hurtbox.gd:124,139` |
| `play_death(pos, tint)` (`:140-198`) | Two bursts (36-chunk at 0.65 s, 14-chunk mist at 0.9 s) plus a blood decal at a random yaw | `death` | `player_combat_reactions.gd:115`, `castle_enemy_base.gd:318` |
| `play_footstep(pos, forward)` (`:201-231`) | 10-chunk dust burst offset 0.18 m to the alternating foot side | `footstep` | `locomotion.gd:197`, `player_anim_director.gd:285` |
| `play_weapon_trail(pos, forward, tint, radius)` (`:234-280`) | A 14-segment `ImmediateMesh` triangle strip sweeping `TRAIL_ARC_DEGREES` (150°), width tapering 0.16 → 0.04, alpha 1.0 → 0.25, scaled down over `TRAIL_LIFETIME` (0.24 s) then freed | — | `castle_enemy_base.gd:137`, `player_anim_director.gd:292` |
| `play_telegraph(pos, radius, duration, tint, shape)` (`:284-361`) | 16-block ring plus a fill disc (`circle`), an 8-block wedge (`cone`), or a single bar (`line`), plus a pulsing centre marker | — | none |

`FOOTSTEP_INTERVAL_WALK` (0.42) and `FOOTSTEP_INTERVAL_SPRINT` (0.28) are read by `locomotion.gd:192`. `DEATH_BURST_LIFETIME` (0.65) is declared at `:25` and referenced only in a comment at `material_dissolve.gd:8`.

### Burst construction

`_make_burst_particles(name, world_pos, cfg)` (`:389-413`) acquires a pooled `CPUParticles3D`, renames it, writes 12 properties from the `cfg` dictionary (`amount`, `lifetime`, `explosiveness`, `randomness`, `direction`, `spread`, `flatness`, `gravity`, `velocity_min`, `velocity_max`, `scale_min`, `scale_max`, `color`), builds a **fresh** `StandardMaterial3D` via `_make_particle_material()`, positions it, `restart()`s, sets `emitting = true`, and schedules `emitting = false` after `lifetime + 0.15`.

`_COMBAT_BURST` (`:11-21`) is the shared 9-key config for swing/block/parry; `_play_combat_burst()` duplicates it, overrides `color`, `emission`, and `direction` to `-Z`, then yaws the node with `_orient_particles()` (`:471-474`, `rotation.y = atan2(forward.x, forward.z)`).

`_acquire_burst()` (`:416-427`) linearly scans the pool for a non-emitting instance and, when none is free, allocates a new one and appends it to the pool permanently. `_acquire_gpu_burst()` (`:531-539`) and `_acquire_decal()` (`:571-579`) do the same.

`_emit_gpu_burst()` (`:505-528`) additionally `duplicate()`s the pooled `ParticleProcessMaterial` on every call to set `direction` and `color`, and allocates a new draw `StandardMaterial3D` at emission energy 0.85.

### Particle material

`_make_particle_material(color, emission_energy)` (`:445-459`) builds a `StandardMaterial3D`: albedo from `_quantize(color)`, `TRANSPARENCY_ALPHA_SCISSOR` at 0.2, `CULL_DISABLED`, `SHADING_MODE_UNSHADED`, `SPECULAR_DISABLED`, `TEXTURE_FILTER_NEAREST`, and when `emission_energy > 0` an emission of the same quantized colour.

`_quantize(color, levels := 6.0)` (`:462-468`) is a CPU reimplementation of the shader's `quantize_color` with the level count hard-coded at the call site default rather than read from `PixelDioramaSettings.color_levels`.

### Decals

`_spawn_decal(pos, direction, texture, size, lifetime)` (`:550-568`) acquires a pooled `Decal`, sets `texture_albedo`, `size = Vector3(size, 0.12, size)`, positions it 0.02 m above the hit, `look_at()`s along the flattened direction, then forces `rotation.x = -PI * 0.5` so the projection always points straight down, makes it visible, and schedules `visible = false` after `lifetime`.

`_make_decal_texture(color, scatter)` (`:590-601`) creates a 16×16 `FORMAT_RGBA8` image, fills it transparent, and writes the colour into every pixel whose normalised distance from the centre is below `scatter + randf() * 0.08`. Two textures are made in `_ready()`: blood (`Color(0.55, 0.08, 0.06, 0.85)`, scatter 0.35) and impact (`Color(0.35, 0.32, 0.28, 0.7)`, scatter 0.55).

### Lifetime management

Three `_schedule_*` helpers each create a `SceneTreeTimer` and connect a lambda: `_schedule_pool_return` clears `emitting`, `_schedule_gpu_return` clears `emitting`, `_schedule_decal_return` clears `visible`, `_schedule_free` calls `queue_free`. Every effect therefore allocates one timer plus one lambda.

## Contracts

- Autoload name `VfxService` (`project.godot:48`); asserted present by `setup_suite.gd:27` and `pixel_pipeline_suite.gd:42`.
- `resolve_combat_anchor()` depends on the node path `Facing/WeaponPivot/Hitbox` and on `get_facing_direction()` where present (`_resolve_forward`, `:380-386`).
- `play_hit_spark()` and `play_death()` branch on `PixelDioramaSettings.particle_quality` and scale by `particle_amount_scale()`.
- `AudioDirector.play_sfx()` keys emitted from here: `swing`, `block`, `parry`, `death`, `footstep`.
- `_root` is named `VfxRoot`; pooled nodes are named `BurstPool<i>`, `GpuBurstPool<i>`, `DecalPool<i>` but are renamed to the effect name on use, so the pool names do not survive first use.
- All pooled nodes are `top_level = true`, so `global_position` writes are absolute.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Pooled CPU bursts, GPU bursts, decals | IMPLEMENTED | `vfx_service.gd:39-66`, `:416-427`, `:531-539`, `:571-579` |
| Nine effect entry points wired into combat, locomotion, and death | IMPLEMENTED | callers table above |
| Particle-quality branch and amount scaling | IMPLEMENTED | `:101-109`, `:141-157` |
| Weapon trail ribbon from `ImmediateMesh` | IMPLEMENTED | `:234-280` |
| All VFX geometry is one shared 0.2 m `BoxMesh` | PLACEHOLDER | `:438-442` — a footstep mote, a blood chunk, and a parry spark are the same cube at different scales |
| Decal art is a 16×16 procedural blob, one texture per kind | PLACEHOLDER | `:590-601` — every blood splat in the game is pixel-identical |
| Particles use `StandardMaterial3D`, not the pixel shaders | PARTIAL | `:445-459` — they bypass `PixelDioramaSettings.apply_to_shader_material()` entirely and do not react to `pixel_scale` or `color_levels` |
| `_quantize()` hard-codes 6 levels instead of reading settings | PARTIAL | `:462` vs `pixel_diorama_settings.gd:88` |
| `TEXTURE_FILTER_NEAREST` on an untextured particle material | PARTIAL | `:454` — no effect without a texture |
| A new `StandardMaterial3D` is allocated per burst | PARTIAL | `:405-408`, `:523` — every hit spark, footstep, and swing allocates a material |
| `_emit_gpu_burst()` duplicates the `ParticleProcessMaterial` per emission | PARTIAL | `:517-522` |
| Pools grow without bound and never shrink | PARTIAL | `:426`, `:538`, `:578` — `_burst_pool.append()` with no cap; heavy combat permanently raises the node count |
| One `SceneTreeTimer` plus one lambda per effect | PARTIAL | `:430-435`, `:477-479`, `:542-547`, `:582-587` |
| `play_telegraph()` | STUB | defined `:284-361` (78 lines); no caller. Every enemy telegraph is instead a `$TelegraphMesh` `SphereMesh` in the `.tscn` with a `StandardMaterial3D` (`castle_grunt.tscn:26-30`, `castle_enemy_base.gd:25`), and hazards use `DioramaInteractableSkin.make_telegraph_material()` (`crystal_pillar_hazard.gd:23`, `spike_trap.gd:32`, `falling_trap.gd:31`) |
| `DEATH_BURST_LIFETIME` | STUB | declared `:25`; referenced only by a comment at `material_dissolve.gd:8` |
| Decals do not fade out; they disappear | PARTIAL | `:582-587` sets `visible = false` with no alpha tween |
| Decals always project straight down | PARTIAL | `:566` forces `rotation.x = -PI * 0.5`, so a hit on a wall or slope produces a floor decal |
| Combat audio is emitted from the VFX service | PARTIAL | `:86`, `:91`, `:96`, `:198`, `:231` — audio and visuals cannot be triggered independently |
| No hit-stop, camera shake, or freeze-frame coordination | ABSENT | no `Engine.time_scale`, no camera shake call in this file; the damage vignette lives on `pixel_diorama_viewport.gd:239-251` instead |
| `visibility_aabb` is a fixed 4 m box while death bursts travel further | PARTIAL | `:52`, `:489` give `-2..2` in x/z; `DeathBurst` at `velocity_max 4.2` with `spread 58` over 0.65 s exceeds it, so late chunks can be culled |
| Validation coverage | FAKE | `perf_gate_suite.gd:13-26` only greps the source for the strings `_burst_pool` and `_acquire_burst`; `perf_gate_suite.gd:29-38` records `true` unconditionally with the comment that GPU profiling is deferred |

## Related
- Improvement plan: [`../actual_improvements/vfx-service.md`](../actual_improvements/vfx-service.md)
- [`pixel-style.md`](pixel-style.md) — the shaders these particles bypass; `make_glow_material()` used by the dead telegraph path
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — `particle_quality`, `particle_amount_scale()`, `color_levels`
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — owns the damage vignette that hit feedback should be coordinating with
- [`audio-director.md`](audio-director.md) — receives the five SFX keys fired from here
- [`hit-feedback.md`](hit-feedback.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`combat-core.md`](combat-core.md) — the callers
- [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md) — the other half of hit feedback
- [`visual-lighting.md`](visual-lighting.md) — the other particle owner (`AmbientMotes`)
- [`00-PLACEHOLDER-INVENTORY.md`](00-PLACEHOLDER-INVENTORY.md)
