# Player combat reactions — improvement plan

## Current state

`CombatReactions` (`apps/game/client/scripts/player/player_combat_reactions.gd`) owns the stagger timer, the death latch, `can_act()`, and `is_movement_locked()`. The timer, the lock-on break, the death dissolve, and the revive path all work. See [`../existing_codebase/player-combat-reactions.md`](../existing_codebase/player-combat-reactions.md).

Two defects undo most of the value. `is_movement_locked()` returns `Guard.locks_movement()` unconditionally, which short-circuits the weapon and heal checks below it, so attacks and flask drinking never lock movement. And the only hit feedback the node produces is a scale pulse on the blockout capsule, which the rig builder hides — so parries and guard breaks are silent and invisible from this node. There is also no hit direction anywhere in the reaction path.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PCR-01 | P0 | `is_movement_locked()` returns `_guard.call("locks_movement")` unconditionally whenever a `Guard` node exists, and `Guard` always exists on the player. Its return is `_stagger_timer > 0.0`, non-zero only during a guard break, so the function is effectively `false`. The `WeaponController` and `PlayerHeal` checks below are unreachable: attacks and drinking never lock movement | `player_combat_reactions.gd:59-66`, `apps/game/client/scripts/combat/guard.gd:146-147`, `apps/game/client/scenes/player/player.tscn:80-81` |
| PCR-02 | P0 | `_pulse_mesh` scales `Facing/MeshInstance3D`, which `hide_legacy_meshes` sets `visible = false` on when the rig is built. Parry success, guard break, and stagger produce no visible reaction from this node | `player_combat_reactions.gd:124-129`, `apps/game/client/scripts/art/style/pixel_diorama_style.gd:976-977`, `apps/game/client/scripts/art/characters/diorama_character_skin.gd:91` |
| PCR-03 | P1 | No hit direction reaches the reaction. `_apply_stagger(duration)` takes only a duration, and nothing forwards the incoming `DamageInfo.direction`, so every stagger looks identical regardless of where the hit came from | `player_combat_reactions.gd:86-91`, `apps/game/client/scripts/combat/hurtbox.gd:140-142` |
| PCR-04 | P1 | The stagger duration is a single constant. `POISE_STAGGER_DURATION = 0.85` applies to a dagger nick and a boss slam alike; nothing scales it by poise damage or by the attacker's weight | `player_combat_reactions.gd:6`, `:94-95` |
| PCR-05 | P1 | No stagger recovery input and no i-frames on wake-up. `_stagger_timer` cannot be shortened, and the frame it expires the player is fully hittable again | `player_combat_reactions.gd:41-47` |
| PCR-06 | P1 | No death sequence beyond a dissolve. No camera move, no slow-motion, no input lock-out window, and `player_died` is consumed only by the animation director | `player_combat_reactions.gd:111-121`, `apps/game/client/scripts/player/player_anim_director.gd:118-119` |
| PCR-07 | P2 | `reset_combat_state()` restores the hidden capsule's scale and the rig's dissolve but does not reset `Stamina`, `Poise`, `Guard`, or `StatusController`, so a revive can start with a broken guard or an active burn | `player_combat_reactions.gd:70-83` |
| PCR-08 | P2 | Guard break has no dedicated player-side state. `_on_guard_broken` only pulses the hidden mesh; the movement lock and the vulnerability window both live inside `guard.gd` | `player_combat_reactions.gd:103-104` |
| PCR-09 | P2 | No validation coverage of the gate itself. `player_suite.gd:56-65` asserts only that `CombatReactions` exists and exposes `can_act()` | `apps/game/client/scripts/validation/suites/player_suite.gd:55-65` |

## Target design

**One explicit lock aggregator.** Replace the early-return chain with an accumulating loop over named sources so a new source can never silently shadow an old one:

```gdscript
const LOCK_SOURCES := [
	["Dodge", "locks_movement"],
	["Guard", "locks_movement"],
	["WeaponController", "locks_movement"],
	["PlayerHeal", "locks_movement"],
]

func is_movement_locked() -> bool:
	if is_dead or is_staggered:
		return true
	for entry in LOCK_SOURCES:
		var node := _body.get_node_or_null(entry[0])
		if node and node.has_method(entry[1]) and node.call(entry[1]):
			return true
	return false

func get_lock_sources() -> PackedStringArray  # debug overlay and validation
```

Chosen over reordering the existing `if` chain: the bug was caused by a `return` in the middle of a chain, and an aggregating loop makes that class of mistake structurally impossible while also giving the debug overlay a readable answer.

**Rig-based hit feedback.** Delete `_pulse_mesh` and replace its three call sites with real feedback:

| Event | Feedback |
|-------|----------|
| parry success | `MaterialFlash.flash(visual, Color(1.0, 0.88, 0.2), 0.10 s)`, `AudioDirector.play_sfx("parry")`, `VfxService.play_parry_spark` at the weapon anchor |
| guard break | `MaterialFlash.flash(visual, Color(0.45, 0.78, 1.0), 0.16 s)`, `guard_break` clip (already played by the director), `0.35` s camera dip |
| stagger start | `MaterialFlash.flash(visual, Color(1.0, 0.35, 0.3), 0.12 s)` plus the directional stagger clip |

`MaterialFlashScript` is already imported at `player_combat_reactions.gd:4` and used only in `reset_combat_state`, so this needs no new dependency.

**Directional, weight-scaled reactions.** `Hurtbox` gains `damaged(amount: float, poise_damage: float, direction: Vector3)` and `CombatReactions` consumes it. Direction is converted into `Facing`-local space and quantized to four octants. Stagger duration becomes a function of poise damage rather than a constant:

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `STAGGER_DURATION_MIN` | `0.45` s | poise damage at or below `STAGGER_POISE_LOW` |
| `STAGGER_DURATION_MAX` | `1.25` s | poise damage at or above `STAGGER_POISE_HIGH` |
| `STAGGER_POISE_LOW` | `10.0` | |
| `STAGGER_POISE_HIGH` | `45.0` | |
| `STAGGER_WAKEUP_IFRAMES` | `0.14` s | invulnerability at the end of a stagger |
| `STAGGER_ROLLOUT_WINDOW` | `0.22` s | trailing window where `dodge` cancels the remaining stagger |
| `STAGGER_ROLLOUT_COST` | `1.5x` | stamina multiplier on a roll-out dodge |

Duration is a linear interpolation between the two poise anchors, so a 10-poise nick gives `0.45` s and a 45-poise slam gives `1.25` s. The existing `0.85` s sits at 27.7 poise, which keeps current enemy tuning roughly where it is today.

**Roll-out.** During the final `STAGGER_ROLLOUT_WINDOW` of a stagger, a `dodge` press cancels the stagger, charges `DODGE_STAMINA_COST * STAGGER_ROLLOUT_COST` (48 stamina), and starts a normal dash. This gives the player something to do during a punish instead of watching.

**Death sequence.** `_on_died` becomes a coroutine with named beats:

| Beat | Time | Effect |
|------|------|--------|
| impact | `0.00` s | `Engine.time_scale = 0.35`, `death` clip, dissolve start |
| settle | `0.60` s | `Engine.time_scale = 1.0`, camera unparents to a fixed point 3 m back and 2 m up, framing the body |
| hold | `1.40` s | input fully locked, screen desaturates via the pixel finish material |
| hand-off | `2.20` s | `player_died` reaches `RunFlow` for the run-outcome screen |

The camera move goes through a new `orbit_camera.enter_death_framing()` so the spring arm stops following.

**Revive completeness.** `reset_combat_state()` also calls `Stamina.reset_stamina()`, `Poise.reset_poise()`, `Guard.reset_after_revive()` (new, clearing `GUARD_BROKEN` and the stagger timer), `StatusController.clear_all()`, `Engine.time_scale = 1.0`, and `orbit_camera.exit_death_framing()`.

## Work plan

1. **Rewrite `is_movement_locked()`** as the `LOCK_SOURCES` loop and add `get_lock_sources()`. Closes PCR-01.
2. **Replace `_pulse_mesh`** with the three `MaterialFlash` and audio/VFX reactions listed above; remove the blockout mesh dependency. Closes PCR-02. Pairs with PCB-08 in [`player-combat.md`](player-combat.md).
3. **Add the `damaged` direction signal** on `Hurtbox` and consume it here and in the animation director. Closes PCR-03. Pairs with PAD-09 in [`player-anim-director.md`](player-anim-director.md).
4. **Add poise-scaled stagger duration** with the four constants. Closes PCR-04.
5. **Add wake-up i-frames and the roll-out window.** Wire the i-frames through the existing `Dodge.iframes_changed` consumer path so `Hurtbox` needs no new concept. Closes PCR-05.
6. **Add the death sequence** and `enter_death_framing` / `exit_death_framing` on `orbit_camera.gd`. Closes PCR-06.
7. **Complete `reset_combat_state()`** and add `Guard.reset_after_revive()` and `StatusController.clear_all()`. Closes PCR-07.
8. **Add an explicit `is_guard_broken` mirror** on `CombatReactions` fed by `Guard.guard_broken` / recovery, so the HUD and the animation director have one place to ask. Closes PCR-08.
9. **Add the validation cases** below. Closes PCR-09.

## Data and schema changes

- No JSON and no schema change: every value above is a named GDScript constant on `player_combat_reactions.gd`.
- `diorama_anim_library.gd` needs the directional flinch clips listed in [`player-anim-director.md`](player-anim-director.md); the six `.res` files are regenerated there.
- No save format change, so no `save_migrator.gd` bump.

## Acceptance criteria

- [ ] `is_movement_locked()` returns `true` while an attack is in startup, active, or non-cancellable recovery, and while a flask is being drunk. (PCR-01)
- [ ] `get_lock_sources()` names the node responsible for the current lock. (PCR-01)
- [ ] A successful parry flashes the rig yellow for `0.10` s and plays the `parry` SFX; nothing depends on the blockout capsule. (PCR-02)
- [ ] A hit from behind plays a rearward stagger; a hit from the left plays a leftward one. (PCR-03)
- [ ] A 10-poise hit staggers for `0.45` s and a 45-poise hit for `1.25` s. (PCR-04)
- [ ] The last `0.14` s of a stagger cannot be hit; a `dodge` press in the last `0.22` s cancels it for 48 stamina. (PCR-05)
- [ ] Death slows time to `0.35` for `0.60` s, reframes the camera, and hands off to `RunFlow` at `2.20` s. (PCR-06)
- [ ] After a revive, stamina, poise, guard state, statuses, and `Engine.time_scale` are all at their defaults. (PCR-07)
- [ ] `CombatReactions.is_guard_broken` mirrors `Guard`'s state within one physics frame. (PCR-08)

## Validation

Extend `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `player.movement_lock_during_attack` — start a light attack, assert `is_movement_locked()` is `true` in `STARTUP` and `ACTIVE`, and that `get_lock_sources()` contains `"WeaponController"`.
- `player.movement_lock_during_heal` — begin a drink and assert the lock plus `"PlayerHeal"` in the sources.
- `player.movement_lock_not_shadowed_by_guard` — with `Guard` present and idle, assert the weapon and heal locks still register. This is the direct regression guard for PCR-01.
- `player.stagger_duration_scales_with_poise` — table-drive `_apply_stagger` through the poise-damage path for `10.0`, `27.7`, `45.0` and assert `0.45`, `0.85`, `1.25` within 0.02 s.
- `player.stagger_wakeup_iframes` — apply a stagger, advance to `duration - 0.10` s, deal damage, and assert health is unchanged.
- `player.stagger_rollout_cancels` — apply a stagger, press `dodge` inside the window, and assert `is_staggered` is `false` and 48 stamina was consumed.
- `player.revive_resets_all_subsystems` — kill, revive, and assert health, stamina, poise, guard state, status list, and `Engine.time_scale`.
- `player.reaction_direction_quadrant` — feed four hit directions and assert the four clip names.

## Related
- Existing state: [`../existing_codebase/player-combat-reactions.md`](../existing_codebase/player-combat-reactions.md)
- [`player-combat.md`](player-combat.md), [`player-anim-director.md`](player-anim-director.md), [`player-heal.md`](player-heal.md), [`locomotion.md`](locomotion.md), [`orbit-camera.md`](orbit-camera.md)
- [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`hit-feedback.md`](hit-feedback.md), [`statuses-and-buffs.md`](statuses-and-buffs.md), [`material-flash.md`](material-flash.md), [`material-dissolve.md`](material-dissolve.md)
