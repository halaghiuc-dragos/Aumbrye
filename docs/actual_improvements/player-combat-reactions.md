# Player combat reactions — improvement plan

## Status: FINISHED

All PCR-01 through PCR-09 gaps are implemented in `player_combat_reactions.gd` and supporting scripts. Validation lives in `player_suite.gd`.

| ID | Sev | Status | Summary |
|----|-----|--------|---------|
| PCR-01 | P0 | FINISHED | `LOCK_SOURCES` aggregator + `get_lock_sources()`; weapon/heal locks no longer shadowed by guard |
| PCR-02 | P0 | FINISHED | `_pulse_mesh` removed; parry/guard-break/stagger use `MaterialFlash`, audio, and VFX on the diorama rig |
| PCR-03 | P1 | FINISHED | `Hurtbox.hurt_received` forwards direction; directional `stagger_f/b/l/r` clips |
| PCR-04 | P1 | FINISHED | Poise-scaled stagger duration (`0.45`–`1.25` s) |
| PCR-05 | P1 | FINISHED | Wake-up i-frames (`0.14` s) and roll-out dodge (`0.22` s window, `48` stamina) |
| PCR-06 | P1 | FINISHED | Death coroutine: slow-mo, camera framing, desaturation, delayed `player_died` at `2.20` s |
| PCR-07 | P2 | FINISHED | `reset_combat_state()` resets health, stamina, poise, guard, statuses, time scale, camera |
| PCR-08 | P2 | FINISHED | `is_guard_broken` mirrors `Guard.guard_broken_state` |
| PCR-09 | P2 | FINISHED | Eight validation cases in `player_suite.gd` |

## Current state

`CombatReactions` (`apps/game/client/scripts/player/player_combat_reactions.gd`) owns the stagger timer, the death latch, `can_act()`, and `is_movement_locked()`. See [`../existing_codebase/player-combat-reactions.md`](../existing_codebase/player-combat-reactions.md).

## Acceptance criteria

- [x] `is_movement_locked()` returns `true` while an attack is in startup, active, or non-cancellable recovery, and while a flask is being drunk. (PCR-01)
- [x] `get_lock_sources()` names the node responsible for the current lock. (PCR-01)
- [x] A successful parry flashes the rig yellow for `0.10` s and plays the `parry` SFX; nothing depends on the blockout capsule. (PCR-02)
- [x] A hit from behind plays a rearward stagger; a hit from the left plays a leftward one. (PCR-03)
- [x] A 10-poise hit staggers for `0.45` s and a 45-poise hit for `1.25` s. (PCR-04)
- [x] The last `0.14` s of a stagger cannot be hit; a `dodge` press in the last `0.22` s cancels it for 48 stamina. (PCR-05)
- [x] Death slows time to `0.35` for `0.60` s, reframes the camera, and hands off to `RunFlow` at `2.20` s. (PCR-06)
- [x] After a revive, stamina, poise, guard state, statuses, and `Engine.time_scale` are all at their defaults. (PCR-07)
- [x] `CombatReactions.is_guard_broken` mirrors `Guard`'s state within one physics frame. (PCR-08)

## Validation

Implemented in `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `player.movement_lock_during_attack`
- `player.movement_lock_during_heal`
- `player.movement_lock_not_shadowed_by_guard`
- `player.stagger_duration_scales_with_poise`
- `player.stagger_wakeup_iframes`
- `player.stagger_rollout_cancels`
- `player.revive_resets_all_subsystems`
- `player.reaction_direction_quadrant`

## Related
- Existing state: [`../existing_codebase/player-combat-reactions.md`](../existing_codebase/player-combat-reactions.md)
- [`player-combat.md`](player-combat.md), [`player-anim-director.md`](player-anim-director.md), [`player-heal.md`](player-heal.md), [`locomotion.md`](locomotion.md), [`orbit-camera.md`](orbit-camera.md)
- [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`hit-feedback.md`](hit-feedback.md), [`statuses-and-buffs.md`](statuses-and-buffs.md), [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md)
