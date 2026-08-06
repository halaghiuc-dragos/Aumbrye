# Player combat reactions

`CombatReactions` is the player's reaction and action-gate node. It owns the stagger timer, the death latch, the `is_movement_locked()` gate every other player system defers to, rig-based hit feedback, and the death sequence coroutine. It is on the live play path; `locomotion.gd` and `weapon_controller.gd` both hold a reference to it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/player/player_combat_reactions.gd` | The node script, `extends Node` |
| `apps/game/client/scenes/player/player.tscn:83-84` | Node `CombatReactions` under `Player` |

## How it works

`_ready()` caches `Health`, `Poise`, `Guard`, `Dodge`, `Stamina`, `StatusController`, `orbit_camera`, and connects:

| Signal | Handler | Effect |
|--------|---------|--------|
| `Health.died` | `_on_died` | starts the death sequence coroutine |
| `Poise.poise_broken` | `_on_poise_broken` | poise-scaled stagger with last hit direction |
| `Poise.poise_damaged` | `_on_poise_damaged` | tracks last poise damage for duration scaling |
| `Hurtbox.hurt_received` | `_on_hurt_received` | tracks hit direction and poise damage |
| `Guard.parry_success` | `_on_parry_success` | yellow `MaterialFlash`, `parry` SFX, `VfxService.play_parry_spark` |
| `Guard.guard_broken` | `_on_guard_broken` | blue flash, `0.35` s camera dip |

### Movement lock aggregator

`is_movement_locked()` loops `LOCK_SOURCES` (`Dodge`, `Guard`, `WeaponController`, `PlayerHeal`) and returns true on the first active lock. Death and stagger short-circuit first. `get_lock_sources()` returns a `PackedStringArray` naming every active source for debug overlays and validation.

### Stagger

`_apply_stagger(duration, direction)` breaks lock-on, sets `is_staggered`, starts `_stagger_timer`, stores `stagger_direction` / `stagger_duration`, emits `stagger_started`, and flashes the diorama rig red.

Duration scales linearly between `STAGGER_POISE_LOW` (`10.0` → `0.45` s) and `STAGGER_POISE_HIGH` (`45.0` → `1.25` s). The last `STAGGER_WAKEUP_IFRAMES` (`0.14` s) grant i-frames through `Dodge.grant_external_iframes`. The last `STAGGER_ROLLOUT_WINDOW` (`0.22` s) allows a dodge press to cancel for `DODGE_STAMINA_COST * STAGGER_ROLLOUT_COST` (`48` stamina).

Direction is quantized to four octants in `Facing`-local space; `get_stagger_clip_for_direction()` returns `stagger_f` / `stagger_b` / `stagger_l` / `stagger_r`.

### Death sequence

`_on_died()` runs a coroutine:

| Beat | Time | Effect |
|------|------|--------|
| impact | `0.00` s | `Engine.time_scale = 0.35`, `AnimDirector.play_death`, dissolve, death SFX/VFX |
| settle | `0.60` s | `Engine.time_scale = 1.0`, `orbit_camera.enter_death_framing()` |
| hold | `1.40` s | screen desaturates via `PixelDioramaSettings.screen_saturation` |
| hand-off | `2.20` s | `player_died` emitted for `RunFlow` |

### Revive

`reset_combat_state()` clears death/stagger latches, restores the diorama visual, resets `Health`, `Stamina`, `Poise`, `Guard` (`reset_after_revive`), `StatusController` (`clear_all`), `Engine.time_scale`, screen saturation, death camera framing, and calls `AnimDirector.revive()`.

### Guard-break mirror

`is_guard_broken` mirrors `Guard.guard_broken_state` each physics frame.

## Contracts

- Node name `CombatReactions` under the player body.
- Signals: `stagger_started`, `stagger_ended`, `player_died` (delayed to `2.20` s on death).
- Public API: `can_act()`, `is_movement_locked()`, `get_lock_sources()`, `reset_combat_state()`, `stagger_duration_for_poise()`, `get_stagger_clip_for_direction()`, `apply_stagger_from_poise()`.
- Fields read by other scripts: `is_staggered`, `is_dead`, `is_guard_broken`, `stagger_direction`, `stagger_duration`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Stagger timer, death latch, `can_act()` | IMPLEMENTED | `player_combat_reactions.gd` |
| `LOCK_SOURCES` movement lock aggregator | IMPLEMENTED | `is_movement_locked()`, `get_lock_sources()` |
| Rig-based parry / guard-break / stagger feedback | IMPLEMENTED | `MaterialFlash`, audio, VFX; no blockout mesh dependency |
| Directional stagger clips | IMPLEMENTED | `stagger_f/b/l/r` in `diorama_anim_library.gd`; `get_stagger_clip_for_direction()` |
| Poise-scaled stagger duration | IMPLEMENTED | `stagger_duration_for_poise()` |
| Wake-up i-frames and roll-out dodge | IMPLEMENTED | `STAGGER_WAKEUP_IFRAMES`, `STAGGER_ROLLOUT_WINDOW` |
| Death sequence with camera framing | IMPLEMENTED | `_run_death_sequence()`, `orbit_camera.enter_death_framing()` |
| Full revive reset | IMPLEMENTED | `reset_combat_state()` |
| `is_guard_broken` mirror | IMPLEMENTED | `_sync_guard_broken_mirror()` |
| Validation coverage | IMPLEMENTED | `player_suite.gd` PCR-01–PCR-09 cases |

## Related
- Improvement plan: [`../actual_improvements/player-combat-reactions.md`](../actual_improvements/player-combat-reactions.md) — **FINISHED**
- [`player-combat.md`](player-combat.md), [`player-anim-director.md`](player-anim-director.md), [`player-heal.md`](player-heal.md), [`locomotion.md`](locomotion.md)
- [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`hit-feedback.md`](hit-feedback.md), [`material-dissolve.md`](material-dissolve.md), [`material-flash.md`](material-flash.md), [`orbit-camera.md`](orbit-camera.md)
