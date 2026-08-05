# VFX service — improvement plan

## Current state

`VfxService` has the right skeleton — pooled particle systems, a quality branch, a single autoload entry point — and placeholder content inside it. Every effect in the game is the same 0.2 m `BoxMesh` at a different scale and tint; every blood splat is the same procedurally generated 16×16 blob; the particle materials are `StandardMaterial3D` and so are the only surfaces in the game that ignore `PixelDioramaSettings`. Effect parameters are 9-to-12-key `Dictionary` literals inlined at each call site, so a designer cannot retune a hit spark. `play_telegraph()` is 78 lines of dead code because every enemy telegraph is a `SphereMesh` in a `.tscn` instead. See [`../existing_codebase/vfx-service.md`](../existing_codebase/vfx-service.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| VFX-01 | P0 | Particles are the only visual surface in the game that bypasses the pixel shaders. `_make_particle_material()` builds a `StandardMaterial3D` with a CPU quantize hard-coded to 6 levels, so changing "Colour levels" or "Pixel scale" in Settings changes every wall and torch but not a single spark. | `vfx_service.gd:445-459`, `:462`; contrast `pixel_diorama_settings.gd:401-425` |
| VFX-02 | P0 | Effect tuning is unreachable. Eight inline `Dictionary` literals of 9–12 keys each define every burst in the game (`_COMBAT_BURST`, hit spark, death burst, death mist, footstep). Retuning a hit spark means editing GDScript; there is no `content/` VFX data and no schema. | `vfx_service.gd:11-21`, `:114-128`, `:162-177`, `:181-196`, `:214-229` |
| VFX-03 | P1 | Two resources are allocated per effect. `_make_burst_particles()` creates a fresh `StandardMaterial3D` on every burst and `_emit_gpu_burst()` additionally `duplicate()`s the `ParticleProcessMaterial`, so a five-hit combo allocates ten materials. The pooling the perf gate claims to verify covers only the nodes, not the resources they need. | `vfx_service.gd:405-408`, `:517-524`; `perf_gate_suite.gd:19-26` |
| VFX-04 | P1 | Pools grow without bound and never shrink. Each `_acquire_*` that finds nothing free allocates and permanently appends, so a wave fight raises the resident node count for the rest of the session with no cap and no reclamation. | `vfx_service.gd:420-427`, `:535-539`, `:575-579` |
| VFX-05 | P1 | `play_telegraph()` is 78 lines with no caller. Enemy telegraphs are `$TelegraphMesh` spheres authored per `.tscn` with `StandardMaterial3D`, and hazards use `DioramaInteractableSkin.make_telegraph_material()`, so there are three unrelated telegraph implementations and the best-looking one is dead. | defined `vfx_service.gd:284-361`; alternatives `castle_grunt.tscn:26-30`, `castle_enemy_base.gd:25`, `crystal_pillar_hazard.gd:23`, `spike_trap.gd:32`, `falling_trap.gd:31` |
| VFX-06 | P1 | No hit-stop, no camera shake, no freeze frame. The service that owns impact feedback cannot pause time or kick the camera, and the damage vignette it should be coordinating with lives on `PixelDioramaViewport`. Impact reads as a colour flash and some cubes. | no `time_scale` or shake call in `vfx_service.gd`; vignette at `pixel_diorama_viewport.gd:239-251` |
| VFX-07 | P1 | Every VFX shape is the one shared 0.2 m cube (`_pixel_chunk_mesh()`), and every blood splat is the same 16×16 procedural blob generated once at boot. There is no authored VFX art of any kind. | `vfx_service.gd:438-442`, `:590-601` |
| VFX-08 | P2 | Decals always project straight down (`rotation.x = -PI * 0.5` overrides the `look_at()` on the line before) and vanish instantly rather than fading, so a wall hit leaves a floor splat that pops out of existence. | `vfx_service.gd:565-566`, `:582-587` |
| VFX-09 | P2 | Combat audio is fired from the VFX service: five methods call `AudioDirector.play_sfx()`. Muting or restyling combat audio requires editing the VFX layer, and a silent VFX preview is impossible. | `vfx_service.gd:86`, `:91`, `:96`, `:198`, `:231` |
| VFX-10 | P2 | Each effect allocates a `SceneTreeTimer` plus a capturing lambda for its pool return. At sustained combat rates that is a steady stream of short-lived objects where a single `_process` sweep over the pools would do. | `vfx_service.gd:430-435`, `:477-479`, `:542-547`, `:582-587` |
| VFX-11 | P2 | `visibility_aabb` is a fixed `-2..2` box in x/z for every pooled system, but `DeathBurst` at `velocity_max 4.2` and `spread 58` over 0.65 s travels further, so late chunks can be culled while still alive. `TEXTURE_FILTER_NEAREST` is set on an untextured material and does nothing. | `vfx_service.gd:52`, `:489`, `:166-169`, `:454` |
| VFX-12 | P2 | `DEATH_BURST_LIFETIME` has no reader; `material_dissolve.gd:8` duplicates the value in a comment instead of importing it, so the two can silently diverge. | `vfx_service.gd:25`; `material_dissolve.gd:8` |
| VFX-13 | P2 | The only VFX validation greps the source for the strings `_burst_pool` and `_acquire_burst`, and the frame-budget gate records `true` unconditionally. | `perf_gate_suite.gd:13-26`, `:29-38` |

## Target design

### 1. Effects as content data

Move every effect definition into `content/vfx/effects.json`, validated by `content/schemas/vfx-effect.v1.json`.

```json
{
  "version": 1,
  "effects": {
    "hit_spark": {
      "layers": [
        {
          "kind": "burst",
          "backend": "gpu",
          "amount": 24,
          "lifetime": 0.28,
          "explosiveness": 0.9,
          "spread": 42.0,
          "velocity": [2.2, 4.8],
          "gravity": [0.0, -9.0, 0.0],
          "scale": [0.05, 0.11],
          "chunk": "shard_small",
          "color": "#ffc759",
          "emission": 1.0,
          "align_to": "direction"
        },
        { "kind": "decal", "decal": "impact_small", "size": 0.28, "lifetime": 2.4, "fade": 0.5 },
        { "kind": "impact", "hitstop_ms": 45, "shake": 0.35, "shake_ms": 120 },
        { "kind": "sfx", "key": "hit" }
      ]
    }
  },
  "chunks": {
    "shard_small": { "mesh": "box", "size": [0.14, 0.14, 0.14] },
    "gib":         { "mesh": "box", "size": [0.22, 0.18, 0.22] },
    "dust_flake":  { "mesh": "quad", "size": [0.18, 0.18], "billboard": true }
  },
  "decals": { "impact_small": "res://assets/textures/vfx/impact_small.png" }
}
```

The schema requires `layers` non-empty, each layer's `kind` in `{burst, decal, ribbon, glyph, impact, sfx}`, colours as `^#[0-9a-fA-F]{6}$`, `velocity` and `scale` as two-element ascending arrays, `hitstop_ms` in `[0, 200]`, `shake` in `[0, 1]`. Unknown effect ids resolve to a `"fallback"` effect and log one warning naming the id.

Public API collapses to one dispatcher plus the existing convenience wrappers, so no caller changes:

```gdscript
## Plays a data-defined effect. `direction` orients direction-aligned layers.
## Unknown ids play the "fallback" effect and warn once per id.
func play(effect_id: String, world_pos: Vector3, direction: Vector3 = Vector3.UP,
        tint_override: Color = Color(0, 0, 0, 0)) -> void
```

`play_hit_spark()` becomes `play("hit_spark", pos, direction)`, `play_death()` becomes `play("death", pos, Vector3.UP, tint)`, and so on. Closes VFX-02, and makes VFX-06 and VFX-09 a matter of adding layer kinds rather than new plumbing.

Rejected alternative: keeping the dictionaries but hoisting them to consts at the top of the file. Rejected because it still requires a code change and a rebuild to retune, and gives no schema validation.

### 2. Particles on the pixel shaders

Replace `_make_particle_material()` with a cached factory on `pixel_diorama_emissive.gdshader`:

```gdscript
## Cached particle material on the pixel emissive shader, keyed by
## (quantized colour, emission energy). Registered with PixelDioramaSettings so
## a live settings change re-stamps pixel_scale and color_levels.
func _particle_material(color: Color, emission_energy: float) -> ShaderMaterial
```

Key is `"%s_%.2f" % [color.to_html(false), emission_energy]`. The material sets `color_core` to the tint, `color_edge` to `tint.darkened(0.25)`, `emission_energy`, and `grain_strength = 0.0` (particles are too small for grain to read), then routes through `PixelDioramaSettings.apply_to_shader_material()` so `pixel_scale` and `color_levels` arrive from the one source of truth. Because the emissive shader is `unshaded`, the current visual intent is preserved.

The cache is cleared from `PixelDioramaSettings.apply_all()` alongside `PixelDioramaStyle.clear_material_caches()`. Closes VFX-01, VFX-03 (materials are now shared, so no per-burst allocation), and VFX-11's filter no-op.

### 3. Bounded pools and a single sweep

```gdscript
const BURST_POOL_MAX := 32
const GPU_BURST_POOL_MAX := 16
const DECAL_POOL_MAX := 24
```

`_acquire_burst()` returns the **oldest emitting** instance when the pool is at its cap rather than allocating — stealing the oldest effect is invisible at these lifetimes and bounds the node count. Track acquisition order with a monotonically increasing counter stored in a parallel `PackedInt64Array`.

Replace the four `_schedule_*` timer helpers with one `_process(delta)` sweep over three small arrays holding `(node, expires_at)`. At the documented cap of 72 pooled nodes the sweep is negligible and it removes the per-effect timer and lambda. Closes VFX-04, VFX-10.

### 4. Impact feedback: hit-stop and shake

New layer kind `impact`, handled by two new pieces:

```gdscript
## Scales Engine.time_scale to `strength` for `duration_ms`, then restores it.
## Re-entrant: a new request extends rather than stacks, and the pre-hitstop
## scale is captured once so nested calls cannot ratchet time down.
func request_hitstop(duration_ms: int, strength: float = 0.05) -> void

## Additive camera kick. Consumed by OrbitCamera each frame and decayed.
func request_shake(amount: float, duration_ms: int) -> void
```

`request_shake()` accumulates into a `_shake_amount` float decayed by `_shake_amount = lerpf(_shake_amount, 0.0, delta * 9.0)`. `OrbitCamera` reads `VfxService.consume_shake()` in its `_process` and offsets its transform by `Vector3(randf_range(-1,1), randf_range(-1,1), 0) * amount * 0.06` in camera space, **before** `PixelCameraSnap` runs so the shake is itself pixel-quantized and does not reintroduce sub-pixel crawl (see [`pixel-camera-snap.md`](pixel-camera-snap.md)).

Hit-stop uses `Engine.time_scale` and is guarded so a hit during hit-stop extends the window rather than multiplying it. Both are gated by new settings `PixelDioramaSettings.hitstop_enabled` and `screen_shake_scale` (0.0–1.5, default 1.0), so an accessibility-minded player can disable both — see [`accessibility.md`](accessibility.md).

The `impact` layer also drives the existing `PixelDioramaViewport.pulse_damage_vignette()` when the effect declares `"vignette": 0.6`, which finally gives that function a gameplay caller. Closes VFX-06.

### 5. Authored VFX art

Add `apps/game/client/assets/textures/vfx/` with authored 32×32 nearest-filtered PNGs: `blood_small`, `blood_large`, `impact_small`, `impact_scorch`, `dust_ring`, drawn from the palette so they sit inside the pixel-diorama look. Decals pick randomly among the variants declared for their kind so two hits never leave identical splats.

`chunks` in the effect JSON let a burst pick a mesh other than the shared cube — a thin `quad` billboard for dust, a wider box for gibs — which is the difference between "particles" and "the same cube everywhere". Closes VFX-07.

### 6. Decal orientation and fade

`_spawn_decal()` takes a surface normal (already available from `hitbox.gd`'s collision result) and builds its basis from it, so a wall hit projects into the wall. Fade is a `Tween` on `Decal.modulate.a` over the layer's `fade` seconds before the pool return. Closes VFX-08.

### 7. Audio decoupling

The `sfx` layer kind moves audio into the data: `{"kind": "sfx", "key": "swing"}`. `VfxService` calls `AudioDirector.play_sfx(layer.key, world_pos)` from the generic dispatcher, so the mapping from effect to sound is designer-editable and a `--no-audio` preview simply skips `sfx` layers. Closes VFX-09.

### 8. Telegraph consolidation

`play_telegraph()` becomes the `glyph` layer kind and the single telegraph implementation. `castle_enemy_base.gd` and `training_grunt.gd` stop using `$TelegraphMesh` and call `VfxService.play("telegraph_circle", pos, forward)` with radius and duration from the attack definition; the `$TelegraphMesh` nodes and their `StandardMaterial3D` sub-resources are removed from the 20 enemy `.tscn` files. `DioramaInteractableSkin.make_telegraph_material()` stays for the persistent trap and hazard meshes, which are static geometry rather than one-shot effects, but it moves onto the pixel emissive shader for consistency. Closes VFX-05.

### 9. Small fixes

`visibility_aabb` is computed per layer from `velocity_max * lifetime + scale_max`, padded 25 %. `DEATH_BURST_LIFETIME` is deleted and `material_dissolve.gd` reads the `death` effect's longest burst lifetime from the effect data. Closes VFX-11, VFX-12.

## Work plan

1. **Pixel-shader particle materials with a cache** — independent, immediately visible, removes the per-burst allocation. Closes VFX-01, VFX-03.
2. **Bounded pools and the `_process` sweep** — independent. Closes VFX-04, VFX-10.
3. **Schema and JSON** — transcribe the eight existing dictionaries verbatim so this step is a no-visual-change refactor; add the `play()` dispatcher and rewrite the nine wrappers over it. Depends on 1 for the material factory signature. Closes VFX-02.
4. **Impact layer: hit-stop, shake, vignette** — new settings, `OrbitCamera` consumer. Depends on 3. Closes VFX-06.
5. **Decal orientation, fade, and normals** — `hitbox.gd` and `hurtbox.gd` pass the collision normal. Depends on 3. Closes VFX-08.
6. **`sfx` layer** — depends on 3. Closes VFX-09.
7. **Authored art and chunk variants** — depends on 3 for the `chunks` and `decals` blocks. Closes VFX-07.
8. **Telegraph consolidation** — depends on 3 for the `glyph` layer; touches 20 `.tscn` files and two enemy scripts. Closes VFX-05.
9. **AABB sizing, constant cleanup, validation** — Closes VFX-11, VFX-12, VFX-13.

Steps 1 and 2 are safe to land first and independently; step 3 is the hinge everything else hangs off.

## Data and schema changes

- New `content/schemas/vfx-effect.v1.json`; new `content/vfx/effects.json` with at least the effects `attack_swing`, `block`, `parry`, `hit_spark`, `death`, `footstep`, `weapon_trail`, `telegraph_circle`, `telegraph_cone`, `telegraph_line`, `fallback`.
- New authored assets under `apps/game/client/assets/textures/vfx/` (5 PNGs plus `.import`).
- New `LocalSave` `pixel_diorama` meta keys `hitstop_enabled` (bool, default `true`) and `screen_shake_scale` (float, default `1.0`). Absent in older saves, so the defaults apply and no migration is needed.
- 20 enemy `.tscn` files lose their `TelegraphMesh` node and two sub-resources each.
- `DEATH_BURST_LIFETIME` is removed from `vfx_service.gd`.
- No character-save field changes, so no `save_migrator.gd` version bump.

## Acceptance criteria

- [ ] Setting "Colour levels" to 4 visibly posterizes hit sparks and death chunks. (VFX-01)
- [ ] Changing `hit_spark.layers[0].amount` in `effects.json` changes the in-game spark count with no code edit. (VFX-02)
- [ ] Forty consecutive hits allocate zero new `StandardMaterial3D` or `ParticleProcessMaterial` instances. (VFX-03)
- [ ] A 60-second wave fight leaves the pooled node count at or below `BURST_POOL_MAX + GPU_BURST_POOL_MAX + DECAL_POOL_MAX`. (VFX-04)
- [ ] No `.tscn` in `scenes/enemies/` contains a `TelegraphMesh`, and enemy windups still show a floor glyph. (VFX-05)
- [ ] A landed heavy hit produces a visible time hitch and a camera kick, and both stop entirely with the accessibility toggles off. (VFX-06)
- [ ] Two consecutive blood decals use different textures. (VFX-07)
- [ ] A hit on a wall leaves a decal on the wall, and decals fade rather than pop. (VFX-08)
- [ ] Removing the `sfx` layer from `attack_swing` silences the swing without touching GDScript. (VFX-09)
- [ ] `rg "create_timer" apps/game/client/scripts/art/vfx/` returns no hits. (VFX-10)
- [ ] A death burst's last chunk remains visible until it expires when the camera is 12 m away. (VFX-11)

## Validation

New suite `apps/game/client/scripts/validation/suites/vfx_service_suite.gd`, category `graphics`, plus a real gate replacing `perf_gate_suite.gd:29-38`:

| Test id | Assertion |
|---------|-----------|
| `vfx.effects_json_loads` | `content/vfx/effects.json` parses and validates against `vfx-effect.v1.json` |
| `vfx.required_effects_present` | all 11 documented effect ids exist, and `fallback` exists |
| `vfx.layer_kinds_known` | every layer's `kind` is one of the six documented kinds |
| `vfx.chunk_refs_resolve` | every `chunk` and `decal` reference resolves to a declared entry, and every decal path passes `ResourceLoader.exists()` |
| `vfx.unknown_effect_is_safe` | `play("does_not_exist", pos)` plays `fallback`, warns once, and pushes no error on a second call |
| `vfx.materials_are_shader_materials` | after `play("hit_spark", ...)` every pooled system's `material_override` is a `ShaderMaterial` on `pixel_diorama_emissive.gdshader` |
| `vfx.material_cache_hits` | 40 `play("hit_spark", ...)` calls produce exactly one cache entry |
| `vfx.settings_reach_particles` | `color_levels = 4` then `apply_all()` leaves every cached particle material reporting `color_levels == 4` |
| `vfx.pool_bounded` | 200 bursts in one frame leave `_burst_pool.size() == BURST_POOL_MAX` |
| `vfx.pool_steals_oldest` | at cap, the acquired instance is the one acquired longest ago |
| `vfx.no_timers` | the source contains no `create_timer` |
| `vfx.aabb_covers_travel` | for every burst layer, `visibility_aabb` extent >= `velocity_max * lifetime + scale_max` |
| `vfx.hitstop_restores` | `request_hitstop(50)` returns `Engine.time_scale` to its pre-call value; two overlapping requests never multiply below `strength` |
| `vfx.hitstop_disabled` | with `hitstop_enabled == false`, `Engine.time_scale` is untouched |
| `vfx.shake_decays` | `request_shake(1.0, 100)` decays to below 0.01 within 0.5 s and `screen_shake_scale = 0.0` yields zero offset |
| `vfx.decal_uses_normal` | a decal spawned with a `Vector3.RIGHT` normal has its basis `y` within 0.01 of `Vector3.RIGHT` |
| `vfx.decal_fades` | decal `modulate.a` is strictly decreasing over the final `fade` seconds |
| `vfx.sfx_layers_map` | every `sfx` layer's `key` exists in `AudioDirector.SFX_PROFILES` or in the biome audio profile's file map |
| `vfx.telegraph_scene_free` | no file under `scenes/enemies/` contains the string `TelegraphMesh` |
| `perf.frame_budget` | replaces the unconditional `true`: reads `user://perf_baseline.json` and fails when the recorded p95 frame time exceeds 16.67 ms; skips with an explicit `skipped` status when the baseline file is absent, rather than passing |

Manual checklist:

- Land a heavy hit: the hitch, the shake, the vignette, the spark, and the sound must read as one event, not five.
- Watch a death at `particle_quality = 0` and `2`: both must read as a death, not one as a death and one as nothing.
- Hit a wall, a slope, and a floor: three correctly oriented decals.

## Related
- Existing behaviour: [`../existing_codebase/vfx-service.md`](../existing_codebase/vfx-service.md)
- [`pixel-style.md`](pixel-style.md) — the emissive shader particles move onto, and the authored-atlas direction the VFX art follows
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) — gains `hitstop_enabled` and `screen_shake_scale`; owns `particle_quality`
- [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md) — `pulse_damage_vignette()` gets its first gameplay caller here
- [`pixel-camera-snap.md`](pixel-camera-snap.md) — shake must be applied before the snap
- [`orbit-camera.md`](orbit-camera.md) — consumes `consume_shake()`
- [`audio-director.md`](audio-director.md) — the `sfx` layer target
- [`hit-feedback.md`](hit-feedback.md), [`combat-core.md`](combat-core.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`enemies.md`](enemies.md) — callers, and the telegraph migration surface
- [`accessibility.md`](accessibility.md) — hit-stop and shake toggles
- [`validation-suites.md`](validation-suites.md) — new suite and the replaced perf gate
