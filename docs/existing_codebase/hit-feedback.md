# Hit feedback

`HitFeedback` is the player-side impact layer: hitstop, camera punch and shake, gamepad vibration, damage vignette, an audio hook, and damage-number spawning. It is mounted only on `player.tscn` (`:97`). Material flashing and world VFX are driven separately from `Hurtbox` and `Hitbox`.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/combat/hit_feedback.gd` | `HitFeedback` node: hitstop, shake, vibration, vignette, damage numbers |
| `apps/game/client/scripts/art/characters/material_flash.gd` | `MaterialFlash`: `flash_amount` shader-uniform pulse on every mesh under a node |
| `apps/game/client/scripts/art/vfx/vfx_service.gd` | `VfxService` autoload: particle bursts and decals |
| `apps/game/client/scripts/combat/damage_number.gd` | Floating `Label3D` spawner |

## How it works

### Who calls what

Three separate call sites drive feedback, and they do not coordinate:

| Trigger | Caller | Effects |
|---------|--------|---------|
| A hitbox connects | `hitbox.gd:150-153` | `VfxService.play_hit_spark` at the target, then `HitFeedback.on_hit(...)` on the **attacker's** `HitFeedback` child |
| A hit is blocked | `hurtbox.gd:118-127` | `VfxService.play_block`, `play_impact_decal`, then `HitFeedback.on_hit_blocked(...)` on the victim |
| A hit lands damage | `hurtbox.gd:130-142` | `MaterialFlash.flash(body)`, `VfxService.play_blood_decal`, `play_impact_decal`, then `HitFeedback.on_hit_received(...)` on the victim |
| A parry succeeds | `guard.gd:124-127` + `hit_feedback.gd:36` | `VfxService.play_parry`, `play_impact_decal`, and a "PARRIED" label |
| An attack becomes active | `weapon_controller.gd:355-357` | `VfxService.play_attack_swing` |

Because no enemy scene mounts a `HitFeedback` node, the `on_hit` branch at `hitbox.gd:151` only fires when the player is the attacker, and `on_hit_received` only fires when the player is the victim. `MaterialFlash` and the `VfxService` decals do run for enemies, since `Hurtbox` calls them directly.

### `on_hit` (player landed a hit)

`hit_feedback.gd:49`. Emits `hit_landed(target, damage)`, then:

- `weight = clampf(damage / 20.0, 0.85, 1.35)`.
- `_apply_local_hitstop(weight)` sets `_hitstop_timer = max(timer, DEFAULT_HITSTOP * feedback_intensity * weight)` with `DEFAULT_HITSTOP := 0.09`.
- `_apply_camera_punch(direction, weight)`.
- `_apply_vibration()`.
- `_play_sfx_hook()`.
- `_spawn_damage_number(target, damage)` when `show_damage_numbers`.

The `damage` argument comes from `hitbox.gd:153`, which passes `damage_amount` â€” the value configured by `set_attack_values` â€” not `final_damage` (post-crit) and not what `Hurtbox` actually applied after block, backstab, defense and resistances.

### `on_hit_received` (player was hit)

`hit_feedback.gd:60`. Hitstop at weight 1.0, camera punch, vibration, SFX hook, `_pulse_damage_vignette()`, and a damage number at `Vector3(-0.2, 0.15, 0.0)` off the player. The `damage` argument here *is* the mitigated figure (`hurtbox.gd:142`).

### `on_hit_blocked`

`hit_feedback.gd:72`. Spawns a "BLOCKED" text label in `COLOR_BLOCK := Color(0.45, 0.78, 1.0)` and, when `chip_damage > 0.0`, a second damage number at `Vector3(0.35, -0.15, 0.0)`. It is called from `hurtbox.gd:127` in the middle of `receive_hit`, *before* backstab, defense and resistances run â€” so the chip number it shows is not the final figure. `_emit_victim_feedback` then runs at the end of the same `receive_hit` and calls `on_hit_received`, which spawns a third label. A single blocked hit therefore produces up to three floating labels with two different numbers.

### Hitstop

`_process(delta)` (`:40`) counts `_hitstop_timer` down and calls `_apply_animation_speed()` while it is positive, `_restore_animation_speed()` otherwise. Both reach `AnimDirector.set_speed_scale(...)` â€” 0.05 during hitstop, 1.0 otherwise. `_restore_animation_speed()` runs on every idle frame, so any other system that sets a speed scale is overwritten within one frame.

The effect is local to the player's own animation director. `Engine.time_scale` is never touched, and the *target's* animation is not slowed.

### Camera punch and shake

`_apply_camera_punch(direction, weight)` (`:115`) returns immediately when `AccessibilitySettings.reduce_camera_shake`. It sets `_shake_direction`, `_shake_strength = DEFAULT_CAMERA_PUNCH * feedback_intensity * weight` with `DEFAULT_CAMERA_PUNCH := 0.15`, and `_shake_timer = 0.11`. When `weight >= 1.1` it additionally pulls `_camera.fov` down by `1.5 * weight` and tweens it back over 0.12 s.

`_apply_camera_shake(delta)` (`:132`) runs every frame. With no active shake it writes `h_offset = 0.0` and `v_offset = 0.0` unconditionally. During a shake it samples a `FastNoiseLite` (`TYPE_SIMPLEX`, `frequency = 4.0`) at `Time.get_ticks_msec() * 0.02` and writes `h_offset` and `v_offset` on the `Camera3D` resolved from the `camera_path` export (`CameraPivot/SpringArm3D/Camera3D` in `player.tscn:99`).

### Vibration and vignette

`_apply_vibration()` (`:156`) scales by `AccessibilitySettings.vibration_intensity`, returns when it is 0 or no joypad is connected, and calls `Input.start_joy_vibration(joypad, 0.0, intensity * 0.45, 0.12)`.

`_pulse_damage_vignette()` (`:166`) calls `PixelDioramaViewport.pulse_damage_vignette(0.72 * feedback_intensity)` when the autoload exposes it.

### Audio

`_play_sfx_hook()` (`:171`) calls `AudioDirector.play_combat_sfx("hit")` for every hit â€” landed or received, any weapon, any damage, any material. `VfxService` separately plays `"swing"`, `"block"` and `"parry"` cues from `play_attack_swing`, `play_block` and `play_parry`.

### MaterialFlash

`material_flash.gd`. `flash(node, strength = 1.0)` walks every `MeshInstance3D` under the node and, for each, kills any live flash tween, saves the current `material_override`, duplicates the active `ShaderMaterial`, assigns the duplicate as `material_override`, sets the `flash_amount` uniform to `strength`, and tweens it to 0 over `FLASH_DURATION := 0.25` before restoring the saved override. Meshes whose active material is not a `ShaderMaterial` are skipped, so the flash only shows on `pixel_diorama_surface` materials. `restore_all(node)` is the cleanup path, used by `player_combat_reactions.gd:80`.

Every flashed mesh allocates one `ShaderMaterial` duplicate and one `Tween` per hit.

### VfxService

Autoload (`project.godot:48`). Pools 16 `CPUParticles3D`, 8 `GPUParticles3D` and 12 `Decal` nodes under a `VfxRoot`. `resolve_combat_anchor(body)` returns `[position, forward]`, preferring `Facing/WeaponPivot/Hitbox`, then `Facing/WeaponPivot`, then the body position +1 m offset backward. Combat entry points: `play_attack_swing`, `play_block`, `play_parry`, `play_hit_spark`, `play_blood_decal`, `play_impact_decal`, `play_death`. `play_hit_spark` branches on `PixelDioramaSettings.particle_quality` between a GPU burst scaled by `particle_amount_scale()` and a CPU burst of 24 particles over 0.28 s.

## Contracts

- **Node name:** `HitFeedback` as a child of the attacking or victim `CharacterBody3D`. Resolved by literal name at `hitbox.gd:151` and `hurtbox.gd:125,140`.
- **`@export`s:** `camera_path` (`NodePath` to a `Camera3D`), `feedback_intensity` (float, default 1.0).
- **Duck-typed methods:** `on_hit(target, damage, direction)`, `on_hit_received(damage, direction)`, `on_hit_blocked(blocker, chip_damage)`.
- **Signal:** `hit_landed(target, damage)`.
- **Sibling nodes:** `AnimDirector` (for `set_speed_scale`), `Guard` (for the `parry_success` connection at `:35-37`).
- **Autoloads used:** `PixelDioramaViewport`, `AudioDirector`. `AccessibilitySettings` and `PixelDioramaSettings` are `class_name` statics, not autoloads.
- **Shader contract:** `MaterialFlash` requires a `flash_amount` uniform on the active `ShaderMaterial`; see [`material-flash.md`](material-flash.md) and [`pixel-style.md`](pixel-style.md).
- **Scene contract:** `res://scenes/combat/damage_number.tscn` with a `Label3D` child and `show_amount` / `show_text` methods.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Hitstop on landing and receiving hits | PARTIAL | `hit_feedback.gd:100-112` â€” applied only to the player's own `AnimDirector` speed scale; the target is never slowed and `Engine.time_scale` is untouched |
| Camera punch, noise shake, FOV kick | IMPLEMENTED | `hit_feedback.gd:115-154` |
| Gamepad vibration with accessibility scaling | IMPLEMENTED | `hit_feedback.gd:156-163` |
| Damage vignette on taking damage | IMPLEMENTED | `hit_feedback.gd:166-168` |
| Material flash on the victim | IMPLEMENTED | `hurtbox.gd:136`, `material_flash.gd:12-67` |
| Hit sparks, blood and impact decals | IMPLEMENTED | `hitbox.gd:150`, `hurtbox.gd:138-139`, `vfx_service.gd:99-137` |
| Damage numbers | BROKEN | The attacker's number is `damage_amount` (`hitbox.gd:153`), the pre-crit, pre-mitigation configured value, so the number the player reads is not the damage dealt |
| Blocked-hit labels | BROKEN | `hurtbox.gd:51` calls `_emit_block_feedback` mid-pipeline and `hurtbox.gd:60` calls `_emit_victim_feedback` at the end, producing up to three labels ("BLOCKED", a chip number, and a second damage number) for one blocked hit |
| Dodge confirmation | ABSENT | `hurtbox.gd:37-39` returns before every feedback path; no i-frame success cue exists anywhere |
| Poise-break feedback | PARTIAL | `player_combat_reactions.gd:124-129` scales the mesh; there is no dedicated VFX, audio cue or label, and `HitFeedback` is not involved |
| Combat audio variety | PLACEHOLDER | `hit_feedback.gd:172-173` plays one `"hit"` cue for every hit regardless of weapon, damage, material or crit |
| `_restore_animation_speed()` cost and clobbering | PARTIAL | `hit_feedback.gd:44-45` calls `set_speed_scale(1.0)` on every non-hitstop frame, overwriting any other speed-scale writer |
| `MaterialFlash` allocation | PARTIAL | `material_flash.gd:42-48` duplicates a `ShaderMaterial` and creates a `Tween` per mesh per hit |
| Enemy-side `HitFeedback` | ABSENT | No enemy scene under `apps/game/client/scenes/enemies/` mounts one, so `hitbox.gd:151` is a no-op for enemy attackers |
| `feedback_intensity` accessibility binding | ABSENT | `hit_feedback.gd:13` is an `@export` with no writer; `AccessibilitySettings` exposes only `reduce_camera_shake` and `vibration_intensity` (`accessibility_settings.gd:9,12`) |
| Damage-type coloring | ABSENT | `damage_number.gd:35` hardcodes `Color(1.0, 0.35, 0.25)`; `AccessibilitySettings.get_damage_color()` (`accessibility_settings.gd:37`) is called only by `m6_suite.gd:281` |
| `camera_path` in non-player contexts | PARTIAL | `hit_feedback.gd:30-31` â€” a null camera silently disables punch, shake and FOV kick |

## Related

- Improvement plan: [`../actual_improvements/hit-feedback.md`](../actual_improvements/hit-feedback.md) - **FINISHED**
- [`material-flash.md`](material-flash.md) â€” the `flash_amount` shader pulse in detail
- [`vfx-service.md`](vfx-service.md) â€” pools, bursts and decals
- [`hit-hurtboxes.md`](hit-hurtboxes.md) â€” where `on_hit` is called from
- [`combat-core.md`](combat-core.md) â€” the mitigation the numbers should reflect
- [`guard.md`](guard.md), [`dodge.md`](dodge.md) â€” block/parry/dodge outcomes
- [`audio-director.md`](audio-director.md), [`accessibility.md`](accessibility.md)
- [`pixel-diorama-settings.md`](pixel-diorama-settings.md) â€” `particle_quality`
