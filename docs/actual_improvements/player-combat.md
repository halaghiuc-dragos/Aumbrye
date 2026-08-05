# Player combat (scene wiring) — improvement plan

## Current state

`player.tscn` wires 16 authored nodes plus two created at runtime (`AnimDirector`, `Facing/DioramaVisual`). Attacks, hitbox profiles per archetype, soft-lock facing, stamina costs, and the combo index all work; see [`../existing_codebase/player-combat.md`](../existing_codebase/player-combat.md).

Three wiring defects break feel rather than function. `HitFeedback.camera_path` is authored relative to the wrong node, so the player has no camera punch, no shake, and no FOV kick. `HitFeedback` caches `AnimDirector` before that node is created, so there is no hitstop. And the animation-driven hitbox hooks exist but are never called, so the strike frame and the damage frame are only coincidentally aligned. Beyond that, the scene ships a hidden blockout capsule, a stub lunge, and an unused `Mana` node.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PCB-01 | P0 | `HitFeedback` never finds the camera. `camera_path` is authored as `"CameraPivot/SpringArm3D/Camera3D"` but resolved with `get_node_or_null` from the `HitFeedback` node, so it needs `"../CameraPivot/..."`. `_camera` stays `null`, which disables camera punch, camera shake, and the FOV kick for the player | `apps/game/client/scenes/player/player.tscn:97-99`, `apps/game/client/scripts/combat/hit_feedback.gd:30-31`, `:115-153` |
| PCB-02 | P0 | No hitstop on the player. `HitFeedback._ready` caches `AnimDirector`, but Godot runs a child's `_ready` before its parent's, and the parent `_ready` is what creates that node | `hit_feedback.gd:32-34`, `apps/game/client/scripts/player/locomotion.gd:40-42` |
| PCB-03 | P0 | Hitbox windows are driven only by `_phase_timer`, never by the animation. `enable_hitbox_from_anim` and `disable_hitbox_from_anim` have no reachable caller because no method track is ever compiled | `apps/game/client/scripts/combat/weapon_controller.gd:242-248`, `:320-329`; see PAD-01 in [`player-anim-director.md`](player-anim-director.md) |
| PCB-04 | P1 | Attack lunge is a stub: `get_attack_lunge_velocity()` returns `Vector3.ZERO` and has no call site, so every swing is rooted in place apart from the animation's own root offset | `weapon_controller.gd:238-239` |
| PCB-05 | P1 | `TWO_HAND_POISE_MULT = 1.35` is declared and never read, so two-handing raises damage by 25 percent and hitbox size by 10 percent but does not raise poise damage as the constant advertises | `weapon_controller.gd:16`, `:435-437` |
| PCB-06 | P1 | The `Mana` node is instanced on the player and nothing on the player consumes it, so mana is a HUD bar with no cost attached to any player action | `player.tscn:71-72`; no `Mana` reference in `scripts/player/` or `weapon_controller.gd` |
| PCB-07 | P1 | The hitbox is a single `1.2 x 0.8 x 1.4` box on a fixed pivot at `(0, 0.75, 0.75)`. It does not sweep, so a fast swing can pass through a thin target between physics ticks, and the shape does not follow the animated weapon | `player.tscn:52-63`, `weapon_controller.gd:531-561` |
| PCB-08 | P2 | The blockout `CapsuleMesh` still ships in the scene and is hidden at runtime, so the editor view and the game view disagree | `player.tscn:26-28`, `:48-50`, `apps/game/client/scripts/art/characters/diorama_character_skin.gd:91` |
| PCB-09 | P2 | `camera_path`, `hitbox_path`, `health_path`, and `poise_path` are exported `NodePath`s with no validation. PCB-01 is exactly the failure mode this invites, and nothing warns | `player.tscn:95`, `:99`, `:124-125`, `hit_feedback.gd:30`, `weapon_controller.gd:88` |
| PCB-10 | P2 | No riposte or backstab positioning. `Guard.get_riposte_damage_multiplier` is consumed blind at the next attack with no prompt, no window display, and no positional requirement | `weapon_controller.gd:341-346` |

## Target design

**Fix the two wiring bugs and make them unrepeatable.** `camera_path` becomes `"../CameraPivot/SpringArm3D/Camera3D"` in `player.tscn`, and every exported `NodePath` on the player gains a `_ready` assertion helper:

```gdscript
# scripts/combat/node_path_guard.gd  (class_name NodePathGuard, static only)
static func require(host: Node, path: NodePath, type_hint: String) -> Node:
	var node := host.get_node_or_null(path)
	if node == null:
		push_error("%s: %s does not resolve to a %s" % [host.get_path(), path, type_hint])
	return node
```

Called from `hit_feedback.gd`, `weapon_controller.gd`, `hurtbox.gd`, and `status_controller.gd`. A broken path then fails loudly in the editor and in CI instead of silently disabling a feature.

**Node creation order.** Two changes so runtime nodes are never raced:

1. `locomotion.gd` emits a new `rig_ready(director: Node)` signal after `add_child(_anim_director)`.
2. Any consumer resolves `AnimDirector` lazily (`hit_feedback.gd`, `player_combat_reactions.gd:81`, `player_heal.gd:66` already does it lazily) rather than caching it in `_ready`.

**Animation-driven hitboxes.** Once PAD-01 lands, the `HITBOX_ON` / `HITBOX_OFF` markers injected at `startup_end` and `active_end` (`diorama_anim_library.gd:499-500`) become live. `WeaponController` then treats the marker as authoritative and the timer as a backstop: `_process_attack_phase` still advances the phase, but `_enable_hitbox_for_attack` is idempotent and `enable_hitbox_from_anim` becomes the normal entry point. Add `_hitbox_opened_this_swing: bool` reset by `reset_swing()` so a doubled call cannot re-enable a hitbox that already resolved.

**Swept hitboxes.** Replace the single-tick `Area3D` overlap test with a two-point sweep. Each physics tick while `current_phase == ACTIVE`, `hitbox.gd` records the previous global transform of its `CollisionShape3D` and issues a `PhysicsShapeQueryParameters3D` motion query between the previous and current transform on mask 8. Keeps the same `BoxShape3D` sizes per archetype (`weapon_controller.gd:537-555`), so no content retuning.

**Attack lunge.** Implement `get_attack_lunge_velocity()` with per-attack JSON data:

| JSON key | Default | Meaning |
|----------|---------|---------|
| `lunge_distance` | `0.0` m | forward travel across the startup and active phases |
| `lunge_curve` | `"ease_out"` | `ease_out`, `linear`, or `spike` |
| `lunge_start_ratio` | `0.6` | fraction of startup elapsed before the lunge begins |

`locomotion.gd` adds the lunge velocity in the movement-locked branch it already runs during attacks (`locomotion.gd:69-77`), so the lunge works even while movement is locked. Defaults of `0.0` keep existing weapons unchanged until authored: sword light 1-3 get `0.35` / `0.35` / `0.7` m, greatsword heavy `1.1` m, spear thrusts `0.9` m.

**Two-hand parity.** Apply `TWO_HAND_POISE_MULT` in `_enable_hitbox_for_attack` alongside the damage multiplier, and surface the stance in the HUD.

**Player mana.** Give the weapon-art path a mana cost so the `Mana` node has a purpose: `art.mana_cost` in weapon JSON, defaulting to `0.0`, checked and consumed in `_try_weapon_art` exactly like stamina (`weapon_controller.gd:288-292`). Staff and catalyst archetypes get non-zero values.

**Riposte and backstab.** Add `scripts/combat/critical_attack.gd` with two static checks against a candidate target:

| Check | Condition |
|-------|-----------|
| riposte | target is in `poise_broken` or `guard_broken` state, within `1.8` m, and the attacker faces within `50` deg of the target centre |
| backstab | attacker is within `1.4` m, behind the target's forward by more than `120` deg, and the target is not staggered |

Either grants `RIPOSTE_DAMAGE_MULT = 2.0` (reuse the existing constant) and plays a dedicated clip. A prompt appears on the HUD while the check passes so the window is legible.

## Work plan

1. **Fix `camera_path`** to `"../CameraPivot/SpringArm3D/Camera3D"` in `player.tscn`. Closes PCB-01.
2. **Add `NodePathGuard`** and call it from the four exported-path consumers. Closes PCB-09.
3. **Lazy `AnimDirector` resolution** in `hit_feedback.gd`, plus `rig_ready` on `locomotion.gd`. Closes PCB-02.
4. **Land PAD-01** from [`player-anim-director.md`](player-anim-director.md), then make `enable_hitbox_from_anim` the primary opener with the phase timer as backstop and add `_hitbox_opened_this_swing`. Closes PCB-03.
5. **Add the swept hitbox query** in `hitbox.gd`. Closes PCB-07.
6. **Implement the lunge**: three JSON keys, `get_attack_lunge_velocity()`, and the addition in `locomotion.gd`'s locked branch. Author values for sword, greatsword, spear, axe. Closes PCB-04.
7. **Apply `TWO_HAND_POISE_MULT`** and add a stance indicator to `combat_hud.gd`. Closes PCB-05.
8. **Add `art.mana_cost`** and consume `Mana` in `_try_weapon_art`. Closes PCB-06.
9. **Remove the blockout capsule** `MeshInstance3D` and its `CapsuleMesh` sub-resource from `player.tscn`, and replace the two `_pulse_mesh` uses in `player_combat_reactions.gd` with rig-based feedback (see [`player-combat-reactions.md`](player-combat-reactions.md)). Closes PCB-08.
10. **Add `critical_attack.gd`**, the two clips, and the HUD prompt. Closes PCB-10.

## Data and schema changes

- `content/weapons/*.json`: each light attack and the heavy attack gain optional `lunge_distance`, `lunge_curve`, `lunge_start_ratio`; the `art` block gains optional `mana_cost`. `content/schemas/weapon.schema.json` must add all four as optional numbers/strings with the defaults above.
- `diorama_anim_library.gd` gains `attack_riposte` and `attack_backstab` clips; the six `.res` files are regenerated.
- No save format change, so no `save_migrator.gd` bump.

## Acceptance criteria

- [ ] Landing a hit shakes the camera and kicks the FOV; `HitFeedback._camera` is non-null on an instanced `player.tscn`. (PCB-01)
- [ ] Landing a hit freezes the attacker's rig for `0.077`–`0.122` s. (PCB-02)
- [ ] The hitbox enables on the animation's `HITBOX_ON` marker frame, and a swing whose marker is missing still enables on the phase timer. (PCB-03)
- [ ] A single swing cannot register two enable calls for the same target. (PCB-03)
- [ ] A sword light 3 moves the player `0.7` m forward across startup and active even while movement is locked. (PCB-04)
- [ ] Two-handing raises poise damage by 35 percent as well as damage by 25 percent. (PCB-05)
- [ ] A weapon art with `mana_cost: 20` is refused at 19 mana and consumes 20 at 20. (PCB-06)
- [ ] A dagger swing past a 0.2 m thick target at maximum swing speed registers a hit. (PCB-07)
- [ ] `player.tscn` contains no `CapsuleMesh`. (PCB-08)
- [ ] Every exported `NodePath` on `player.tscn` resolves; a deliberately broken one produces a `push_error` and fails the validation suite. (PCB-09)
- [ ] Attacking a guard-broken enemy from the front within `1.8` m deals `2.0x` damage and plays `attack_riposte`; attacking from more than `120` deg behind within `1.4` m plays `attack_backstab`. (PCB-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/combat_suite.gd`:

- `combat.player_node_paths_resolve` — instance `player.tscn`, walk every exported `NodePath` on `HitFeedback`, `WeaponController`, `Hurtbox`, and `StatusController`, and assert each resolves to a node of the expected class.
- `combat.hit_feedback_camera_bound` — assert `HitFeedback` holds a `Camera3D` after two physics frames.
- `combat.hitstop_applies_to_rig` — call `on_hit` and assert the rig `speed_scale` drops to `0.05` and restores within `0.13` s.
- `combat.anim_marker_opens_hitbox` — start an attack, call `enable_hitbox_from_anim` during `ACTIVE`, and assert the hitbox is monitoring; call it during `STARTUP` and assert it is not.
- `combat.swept_hitbox_catches_thin_target` — place a 0.2 m box target, teleport the hitbox across it in one tick, and assert one hit.
- `combat.lunge_distance_applied` — drive a sword light 3 and assert the body travelled `0.7` m +/- 0.1 m.
- `combat.two_hand_poise_multiplier` — compare the poise value passed to `set_attack_values` one-handed versus two-handed and assert the `1.35` ratio.
- `combat.weapon_art_mana_cost` — assert the refusal and the consumption at the boundary.
- `combat.critical_attack_checks` — table-drive `critical_attack.gd` for riposte and backstab geometry, including the negative cases just outside each threshold.

## Related
- Existing state: [`../existing_codebase/player-combat.md`](../existing_codebase/player-combat.md)
- [`combat-core.md`](combat-core.md), [`weapons.md`](weapons.md), [`guard.md`](guard.md), [`dodge.md`](dodge.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`hit-feedback.md`](hit-feedback.md), [`stamina-mana.md`](stamina-mana.md)
- [`player-anim-director.md`](player-anim-director.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`locomotion.md`](locomotion.md), [`lock-on.md`](lock-on.md), [`content-data.md`](content-data.md)
