# Dodge

`dodge.gd` owns two player actions: the dash/roll with invincibility frames, and the jump with coyote time and input buffering. It is on the live play path (`player.tscn:77`) and its `iframes_active` flag is the first mitigation gate in the damage pipeline.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/player/dodge.gd` | Dash, i-frames, jump, coyote time, jump buffer |

## How it works

### Constants

| Constant | Value |
|----------|-------|
| `JUMP_VELOCITY` | 4.8 |
| `COYOTE_TIME` | 0.12 s |
| `JUMP_BUFFER_TIME` | 0.15 s |
| `DODGE_SPEED` | 9.0 m/s |
| `DODGE_BACK_SPEED` | 6.0 m/s |
| `DODGE_DURATION` | 0.45 s |
| `DODGE_RECOVERY` | 0.25 s |
| `DODGE_STAMINA_COST` | 32.0 |
| `JUMP_STAMINA_COST` | 18.0 |
| `IFRAME_START` | 0.05 s |
| `IFRAME_END` | 0.30 s |

### Control flow

`Locomotion._physics_process` drives the dodge, not the dodge itself. At `locomotion.gd:79-88` it calls `Dodge.process_dash_physics(delta)` and, if `is_dodging` is then true, returns early — so locomotion's own gravity, acceleration, facing and `move_and_slide()` are all skipped for the duration.

`process_dodge_physics(delta)` (`dodge.gd:55`) either advances an in-flight dash or, when `dodge` is just pressed and `_can_dash()` passes, starts one.

`_can_dash()` (`:101`) refuses while `is_dodging` or `_recovery_timer > 0.0`, and refuses when `Stamina.has(DODGE_STAMINA_COST)` is false. `_start_dash()` (`:109`) then calls `_stamina.consume(...)` without a null guard — `_can_dash()` tolerates a missing `Stamina` node but `_start_dash()` would fail on it.

Direction selection in `_start_dash()`:

| Condition | Speed | Direction |
|-----------|-------|-----------|
| Lock-on active and input held | `DODGE_SPEED` | `LockOnMovement.get_move_direction(...)` |
| Lock-on active, no input | `DODGE_BACK_SPEED` | `_get_attack_backstep_direction()` |
| No lock-on, input held | `DODGE_SPEED` | `_get_camera_relative_direction(input)` |
| No lock-on, no input | `DODGE_BACK_SPEED` | `_get_attack_backstep_direction()` |

`_get_attack_backstep_direction()` (`:137`) returns `-Facing.global_transform.basis.z`, i.e. away from the direction the model faces, falling back to `get_facing_direction()` then `Vector3.BACK`.

`_process_dash(delta)` (`:163`) each physics frame:

1. Decrements `_dodge_timer`.
2. Overwrites `_body.velocity.x` and `.z` with `_dodge_direction * _dodge_speed`. `velocity.y` is never touched, so no gravity is applied during a dash.
3. Computes `elapsed = DODGE_DURATION - _dodge_timer` and sets `iframes_active = elapsed >= 0.05 and elapsed <= 0.30`, emitting `iframes_changed(active)` on transitions.
4. Calls `_body.move_and_slide()` itself.
5. Ends the dash when the timer expires.

`_end_dash()` clears `is_dodging` and `iframes_active`, emits `iframes_changed(false)`, sets `_recovery_timer = DODGE_RECOVERY`, and emits both `dash_ended` and `dodge_ended`. `locks_movement()` returns true while `_recovery_timer > 0.0`, consumed by `player_combat_reactions.gd:57-58`.

The dash therefore runs at a constant 9.0 m/s for the full 0.45 s (covering 4.05 m) with no ease-in or ease-out, and i-frames cover 0.25 s of that — from 11% to 67% of the dash.

### Signal aliasing

`_ready()` (`:37-41`) connects `dash_started` to re-emit `dodge_started` and `dash_ended` to re-emit `dodge_ended`. `_start_dash()` then emits **both** `dash_started` and `dodge_started` directly (`:133-134`), so `dodge_started` fires twice per dash. `_end_dash()` does the same for `dodge_ended` (`:183-184`).

`WeaponController` connects to `dodge_started` / `dodge_ended` (`weapon_controller.gd:84-87`); `_on_dodge_started` ends an attack in recovery and `_on_dodge_ended` sets `_post_dodge_attack_buffer = POST_DODGE_ATTACK_BUFFER := 0.1`.

### Jump

`_physics_process` (`:44`) runs independently of the dash path and handles jumping. `_update_timers` refreshes `_coyote_timer` to 0.12 s while on the floor and starts `_jump_buffer_timer` at 0.15 s on a `jump` press. `_handle_jump_buffer` (`:90`) fires when a buffered jump meets live coyote time and the player is not dodging: it spends 18 stamina through `consume()` and sets `velocity.y = 4.8`. There are no jump i-frames and no air control changes.

### Damage interaction

`Hurtbox.receive_hit` (`hurtbox.gd:37-39`) walks ancestors for a node named `Dodge`, reads its `iframes_active` property, and returns immediately when true — before parry, before block, before any feedback. Nothing is emitted: no signal, no VFX, no sound, no `damaged` emission. The dodge succeeds silently.

## Contracts

- **Node name:** must be a child of the player `CharacterBody3D` named exactly `Dodge`. Resolved by name in `hurtbox.gd:111`, `weapon_controller.gd:83,565`, `locomotion.gd:30`, `player_combat_reactions.gd:30`.
- **Sibling nodes:** `Stamina`, `Facing`, `LockOn`.
- **Methods on the parent body:** `get_camera_relative_direction(Vector2) -> Vector3` and `get_facing_direction() -> Vector3`, both implemented by `locomotion.gd:163-170`.
- **Public state:** `is_dodging` (read by `locomotion.gd:81,86` and `weapon_controller.gd:566`), `iframes_active` (read by `hurtbox.gd:38`).
- **Signals:** `dodge_started`, `dodge_ended`, `dash_started`, `dash_ended`, `iframes_changed(active)`.
- **Methods consumed by others:** `process_dash_physics(delta)`, `process_dodge_physics(delta)`, `locks_movement()`, `get_dash_progress()`, `get_dash_direction()`.
- **Input actions:** `dodge`, `jump`, `move_left`/`move_right`/`move_forward`/`move_back`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Dash with directional selection and lock-on awareness | IMPLEMENTED | `dodge.gd:109-135` |
| I-frame window | IMPLEMENTED | `dodge.gd:167-171`, consumed at `hurtbox.gd:37-39` |
| Stamina gating | IMPLEMENTED | `dodge.gd:101-110` |
| Recovery lockout | IMPLEMENTED | `dodge.gd:181`, `player_combat_reactions.gd:57-58` |
| Coyote time and jump buffer | IMPLEMENTED | `dodge.gd:77-98` |
| Dodge confirmation feedback | ABSENT | `hurtbox.gd:37-39` returns with no signal, VFX, sound or `damaged` emission |
| Gravity during a dash | ABSENT | `dodge.gd:163-172` writes only `velocity.x`/`.z`; `locomotion.gd:79-83` returns before its own gravity step |
| Dash velocity curve | PARTIAL | `dodge.gd:165-166` — a constant 9.0 m/s for the full 0.45 s, no ease |
| Dash steering or cancel | ABSENT | `_dodge_direction` is fixed at `_start_dash` and never re-read |
| Dodge tuning as data | ABSENT | `dodge.gd:5-15` are GDScript constants; no equip weight, class or talent input |
| `staminaCostReduction` on dodge and jump | ABSENT | Applied only in `weapon_controller.gd:456-457`; `dodge.gd:94,110` use raw constants |
| Jump i-frames or air control | ABSENT | `dodge.gd:90-98` sets `velocity.y` and nothing else |
| `dodge_started` / `dodge_ended` emission | BROKEN | Emitted twice per dash — once directly (`dodge.gd:133-134,183-184`) and once through the `dash_*` relays wired at `dodge.gd:40-41` |
| `_start_dash` null safety | PARTIAL | `dodge.gd:110` calls `_stamina.consume` unguarded while `_can_dash()` (`:104`) tolerates a null `Stamina` |
| Dash i-frames against area hazards | PARTIAL | `trap_damage_area.gd:33` routes through `receive_hit` so i-frames apply, but `poison_hazard.gd:35-40` calls `StatusController.apply_status` on the body directly and bypasses the hurtbox entirely |

## Related

- Improvement plan: [`../actual_improvements/dodge.md`](../actual_improvements/dodge.md)
- [`combat-core.md`](combat-core.md) — i-frames as pipeline stage 2
- [`guard.md`](guard.md) — the option dodge competes with
- [`stamina-mana.md`](stamina-mana.md) — the 32.0 cost
- [`locomotion.md`](locomotion.md) — drives `process_dash_physics`
- [`lock-on-movement.md`](lock-on-movement.md) — dash direction under lock-on
- [`weapons.md`](weapons.md) — dodge-cancel of attack recovery
- [`combat-hazards.md`](combat-hazards.md) — hazards that ignore i-frames
