# Player heal

`PlayerHeal` is the bound-charge heal ("estus flask"): a fixed number of charges per rest, a timed drink, then a percentage heal. It is on the live play path â€” the node ships in `player.tscn` and polls the `heal` action every physics frame â€” but it has no HUD, no dedicated animation, no sound, and no save persistence.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/player/player_heal.gd` | The node script, `extends Node` |
| `apps/game/client/scenes/player/player.tscn:86-87` | Node `PlayerHeal` under `Player` |

## Tuning constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `DEFAULT_MAX_CHARGES` | `3` | charges after a rest |
| `HEAL_AMOUNT` | `0.45` | fraction of `Health.max_health` restored |
| `DRINK_DURATION` | `1.35` | seconds of committed drink |
| `HEAL_STAMINA_COST` | `0.0` | stamina cost â€” free |

All four are `const` at `player_heal.gd:5-8`.

## How it works

`_ready()` (`:25`) caches `Health`, `Stamina`, `CombatReactions` from the parent body and emits `charges_changed(3, 3)`.

`_physics_process(delta)` (`:33`) has two branches. When not drinking it polls `Input.is_action_just_pressed("heal")` and calls `_try_drink()`. When drinking it counts `_drink_timer` down and calls `_finish_drink()` at zero.

`_try_drink()` (`:52`) refuses if already drinking, if `current_charges <= 0`, if `CombatReactions.can_act()` is false, or if `Health.is_dead()`. The two stamina checks at `:59-62` are both guarded by `HEAL_STAMINA_COST > 0.0` and are dead while that constant is `0.0`. On success it sets `is_drinking`, arms `_drink_timer = DRINK_DURATION`, emits `heal_started`, and calls `AnimDirector.play_heal(DRINK_DURATION)`.

`_finish_drink()` (`:71`) clears `is_drinking`, decrements the charge, emits `charges_changed`, applies `Health.heal(Health.max_health * HEAL_AMOUNT)`, and emits `heal_ended`. The heal lands at the **end** of the 1.35 s window, so an interruption before then costs nothing but also heals nothing.

`refill_charges()` (`:43`) resets to `max_charges`. Its only caller is `RunFlow.rest_at_bonfire` (`apps/game/client/scripts/app/run_flow.gd:456-458`), alongside `Health.reset_health()` and `Stamina.reset_stamina()`.

`locks_movement()` (`:48`) returns `is_drinking`.

## Contracts

- Node name `PlayerHeal` under the player body. Looked up by `player_combat_reactions.gd:64` and `run_flow.gd:456`.
- Signals emitted: `charges_changed(current, max_value)`, `heal_started`, `heal_ended`.
- Public API: `refill_charges()`, `locks_movement()`. Fields `max_charges`, `current_charges`, `is_drinking` are public.
- Requires `AnimDirector` to expose `play_heal(float)` (`player_anim_director.gd:128`).
- Reads the `heal` input action (`project.godot:283-288`): `H` on keyboard, joypad `button_index: 7`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Charge count, drink timer, percentage heal | IMPLEMENTED | `player_heal.gd:33-77` |
| Bonfire refill | IMPLEMENTED | `run_flow.gd:456-458` |
| Drink animation | PLACEHOLDER | `player_anim_director.gd:128-129` maps `play_heal(duration)` onto `play_stagger(duration)`, so the player plays the `stagger` hurt clip (`diorama_anim_library.gd:230`) time-warped by `speed_scale = 0.85 / 1.35 = 0.63` (`diorama_anim_controller.gd:217-220`). There is no `heal`, `drink`, or `quaff` clip in `CLIPS` |
| Drink SFX | ABSENT | No `AudioDirector` call anywhere in `player_heal.gd`; `SFX_PROFILES` has no `heal` entry and `play_sfx` silently falls back to the `hit` profile for unknown keys (`audio_director.gd:34-43`, `:221-226`) |
| Drink VFX | ABSENT | No `VfxService` call in `player_heal.gd` |
| Charge HUD | ABSENT | `charges_changed` has no listener. `combat_hud.gd` contains no flask or charge widget; its bars are health, stamina, mana, and attack phase only |
| Movement lock while drinking | BROKEN | `locks_movement()` is correct, but its only caller sits behind an unconditional `return` in `player_combat_reactions.gd:59-60`, so the player walks and sprints at full speed while drinking |
| Interrupt on damage | ABSENT | Nothing clears `is_drinking` on `Health.health_changed`, `Poise.poise_broken`, or `CombatReactions.stagger_started`; a stagger mid-drink leaves the drink running and it still completes |
| Charge persistence | ABSENT | No `LocalSave` key; `current_charges` resets to `DEFAULT_MAX_CHARGES` on every scene load because it is a plain field initializer (`player_heal.gd:15`) |
| Upgradeable charges or heal amount | ABSENT | `max_charges` is writable but nothing writes it; `HEAL_AMOUNT` is `const`. No `content/` JSON key feeds either |
| Stamina cost | STUB | `HEAL_STAMINA_COST = 0.0` makes both checks at `:59-62` unreachable |

## Related
- Improvement plan: [`../actual_improvements/player-heal.md`](../actual_improvements/player-heal.md) - **FINISHED**
- [`player-combat-reactions.md`](player-combat-reactions.md), [`player-anim-director.md`](player-anim-director.md), [`player-controls.md`](player-controls.md)
- [`stamina-mana.md`](stamina-mana.md), [`combat-core.md`](combat-core.md), [`ui/combat_hud.md`](ui/combat_hud.md), [`run-flow.md`](run-flow.md), [`local-save.md`](local-save.md)
