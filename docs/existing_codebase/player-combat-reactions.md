# Player combat reactions

`CombatReactions` is the player's reaction and action-gate node. It owns the stagger timer, the death latch, the `is_movement_locked()` gate every other player system defers to, and the placeholder mesh-pulse feedback. It is on the live play path; `locomotion.gd:31` and `weapon_controller.gd:80` both hold a reference to it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/player/player_combat_reactions.gd` | The node script, `extends Node` |
| `apps/game/client/scenes/player/player.tscn:83-84` | Node `CombatReactions` under `Player` |

## How it works

`_ready()` (`player_combat_reactions.gd:24`) caches `Facing/MeshInstance3D`, `Health`, `Poise`, `Guard`, `Dodge` and connects:

| Signal | Handler | Effect |
|--------|---------|--------|
| `Health.died` | `_on_died` | breaks lock-on, sets `is_dead`, emits `player_died`, plays `VfxService.play_death` with `Color(0.72, 0.28, 0.22)`, dissolves `Facing/DioramaVisual` |
| `Poise.poise_broken` | `_on_poise_broken` | `_apply_stagger(POISE_STAGGER_DURATION)` = `0.85` s |
| `Guard.parry_success` | `_on_parry_success` | `_pulse_mesh(1.14)` |
| `Guard.guard_broken` | `_on_guard_broken` | `_pulse_mesh()` |

`_apply_stagger(duration)` (`:86`) breaks lock-on, sets `is_staggered`, starts `_stagger_timer`, emits `stagger_started`, and pulses the mesh. `_physics_process` (`:41`) counts the timer down, clears `is_staggered`, emits `stagger_ended`, and calls `Poise.reset_poise()`.

`reset_combat_state()` (`:70`) clears both latches, restores the blockout mesh scale, makes `Facing/DioramaVisual` visible again, calls `MaterialDissolveScript.restore` and `MaterialFlashScript.restore_all`, and calls `revive()` on `AnimDirector`.

### The action gates

```gdscript
func can_act() -> bool:
	return not is_dead and not is_staggered
```

`can_act()` (`:50`) is read by `weapon_controller.gd:570-572` and `player_heal.gd:55`.

`is_movement_locked()` (`:54`) is read once per physics frame by `locomotion.gd:70`. Its intended sources are, in order: death/stagger, `Dodge.locks_movement()`, `Guard.locks_movement()`, `WeaponController.locks_movement()`, `PlayerHeal.locks_movement()`.

## Contracts

- Node name `CombatReactions` under the player body.
- Signals emitted: `stagger_started`, `stagger_ended`, `player_died`. Consumers: `player_anim_director.gd:117-119` (stagger clip, death clip).
- Public API: `can_act()`, `is_movement_locked()`, `reset_combat_state()`. Fields `is_staggered`, `is_dead` are read directly by other scripts.
- Requires `Facing/MeshInstance3D` to exist for `_pulse_mesh`, and `Facing/DioramaVisual` for dissolve/restore.
- `POISE_STAGGER_DURATION = 0.85` intentionally matches `PlayerAnimDirector.DEFAULT_STAGGER = 0.85` (`player_anim_director.gd:11`) so the timer and the clip end together.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Stagger timer, death latch, `can_act()` | IMPLEMENTED | `player_combat_reactions.gd:41-51` |
| Lock-on break on stagger and death | IMPLEMENTED | `player_combat_reactions.gd:132-135` |
| Death dissolve and revive path | IMPLEMENTED | `player_combat_reactions.gd:111-121`, `:70-83` |
| `is_movement_locked()` | BROKEN | `player_combat_reactions.gd:59-60` returns `_guard.call("locks_movement")` unconditionally whenever a `Guard` node exists. `Guard` always exists on `player.tscn:80-81`, and its `locks_movement()` returns `_stagger_timer > 0.0`, which is only non-zero during a guard break (`guard.gd:146-147`). The `WeaponController` and `PlayerHeal` checks at `:61-66` are therefore unreachable, so attacks and flask drinking never lock movement |
| Hit reaction feedback | PLACEHOLDER and invisible | `_pulse_mesh` scales `Facing/MeshInstance3D` (`:124-129`), which `hide_legacy_meshes` sets `visible = false` on when the rig is built (`pixel_diorama_style.gd:976-977`, called from `diorama_character_skin.gd:91`). The parry and guard-break pulses produce no visible change |
| Directional hit reactions | ABSENT | `_apply_stagger` takes only a duration; no hit direction is passed in from `Hurtbox`, and there are no `flinch_l`/`flinch_r`/`flinch_b` clips (`diorama_anim_library.gd:220`) |
| Hyperarmor during stagger | ABSENT | No poise-armor interaction here; `WeaponController._hyperarmor_active` is checked only inside `weapon_controller.gd:571` |
| Stagger cancel / recovery input | ABSENT | `_stagger_timer` cannot be shortened; no roll-out or wake-up window |
| Death camera or ragdoll | ABSENT | Only a dissolve and, without a rig, a 0.35 s scale tween on the blockout capsule (`:119-121`) |
| Guard-break state feedback | PARTIAL | `_on_guard_broken` only pulses the hidden mesh; the `guard_break` clip is played from `player_anim_director.gd:241-242` instead |

## Related
- Improvement plan: [`../actual_improvements/player-combat-reactions.md`](../actual_improvements/player-combat-reactions.md)
- [`player-combat.md`](player-combat.md), [`player-anim-director.md`](player-anim-director.md), [`player-heal.md`](player-heal.md), [`locomotion.md`](locomotion.md)
- [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`hit-feedback.md`](hit-feedback.md), [`material-dissolve.md`](material-dissolve.md), [`material-flash.md`](material-flash.md)
