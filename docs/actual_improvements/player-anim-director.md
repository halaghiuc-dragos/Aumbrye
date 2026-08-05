# Player animation director — improvement plan

## Current state

`PlayerAnimDirector` (`apps/game/client/scripts/player/player_anim_director.gd`) subclasses `DioramaAnimController`, subscribes to `Dodge`, `Guard`, `WeaponController`, `CombatReactions`, `Health`, and `Poise`, drives the third-person rig, and mirrors a first-person viewmodel. The priority stack, the phase-stretched attack compilation, and the dash direction picker all work. See [`../existing_codebase/player-anim-director.md`](../existing_codebase/player-anim-director.md).

Every clip name the director requests exists in `DioramaAnimLibrary`. The failures are elsewhere: the whole animation-event system is dead because no library ever gets a method track, healing has no clip and borrows the hurt animation, the bow draw keys a pivot the player rig does not have, and hitstop never reaches the rig because of a `_ready` ordering bug.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PAD-01 | P0 | No animation method track is ever compiled, so `anim_footstep`, `anim_swing_vfx`, `anim_hitbox_on`, and `anim_hitbox_off` never fire for the player. Two independent causes: the exporter passes `events_path = ""`, and the runtime resolver rejects any visual that is not an ancestor of the controller | `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd:81`, `apps/game/client/scripts/art/characters/diorama_anim_library.gd:550`, `apps/game/client/scripts/art/characters/diorama_anim_controller.gd:111-121` |
| PAD-02 | P0 | Drinking a flask plays the `stagger` hurt clip. `play_heal(duration)` is a one-line alias for `play_stagger(duration)`, and `CLIPS` has no heal, drink, or quaff entry | `player_anim_director.gd:128-129`, `diorama_anim_library.gd:32-261` |
| PAD-03 | P0 | Hitstop never reaches the player rig. `hit_feedback.gd` caches `AnimDirector` in its own `_ready`, which Godot runs before the parent `_ready` that creates the node, so `set_speed_scale(0.05)` is never called | `apps/game/client/scripts/combat/hit_feedback.gd:32-34`, `apps/game/client/scripts/player/locomotion.gd:40-42` |
| PAD-04 | P1 | `attack_shoot` is the only bow clip and its bow motion keys a `Bow` pivot the player rig never builds. `PROFILES["player"]` declares no `extras`; only `"ranged"` adds `Bow` | `diorama_anim_library.gd:377`, `apps/game/client/scripts/art/characters/diorama_character_skin.gd:32-41`, `:57-59`, `:408-412` |
| PAD-05 | P1 | No directional locomotion clips. `update_locomotion` receives only a speed magnitude, so a left strafe or a backpedal plays the forward walk cycle. `CLIPS` has no `walk_b`, `walk_l`, `walk_r`, `run_b`, or `turn_*` | `player_anim_director.gd:155-161`, `diorama_anim_library.gd:48-90` |
| PAD-06 | P1 | Blocking cancels locomotion entirely: `block_hold` is a full-body looping clip at `Priority.BLOCK`, so a shielded player slides with static legs | `diorama_anim_controller.gd:181-187`, `diorama_anim_library.gd:174` |
| PAD-07 | P1 | The viewmodel palette is hardcoded to `PaletteTheme.HUB`, so first-person arms never match the biome | `player_anim_director.gd:66` |
| PAD-08 | P1 | The prebuilt `.res` libraries contain no `RESET` clip, because `_compile_reset` runs only on the compile branch that the authored load short-circuits. `revive()` falls back to `_apply_rest_pose()` writing transforms directly | `diorama_anim_library.gd:468-482`, `diorama_anim_controller.gd:231-244` |
| PAD-09 | P1 | Double reaction trigger: a hit that costs both health and poise calls `_on_health_changed` (flinch) and `_on_poise_damaged` (flinch or stagger) in an order set by signal connection, so the same hit can play two clips back to back | `player_anim_director.gd:132-136`, `:268-276` |
| PAD-10 | P2 | `request_locomotion(&"air", {"vertical_speed": ...})` passes a parameter no consumer reads; rising and falling look identical | `player_anim_director.gd:149`, `diorama_anim_controller.gd:156-162` |
| PAD-11 | P2 | Attack clips are compiled into the shared `AnimationLibrary` returned by `ResourceLoader.load`, so runtime clips are written into a cached resource shared by every rig of that profile | `diorama_anim_controller.gd:295-300`, `diorama_anim_library.gd:468-472` |
| PAD-12 | P2 | No additive layering. One `AnimationPlayer` plays one clip, so there is no upper-body-only reaction, no head look-at, and no breathing on top of movement | `diorama_anim_controller.gd:90-104` |

## Target design

**Working animation events.** The events path is a relative `NodePath` resolved against `AnimationPlayer.root_node`, which is the visual root. `visual.get_path_to(controller)` already yields a valid path such as `../../AnimDirector`; the `is_ancestor_of` guard at `diorama_anim_controller.gd:116` is simply too strict. Replace it with:

```gdscript
func _resolve_events_path(visual: Node3D) -> String:
	if not is_inside_tree() or not visual.is_inside_tree():
		return ""
	var path := visual.get_path_to(self)
	return "" if path.is_empty() else String(path)
```

Then make the exporter agree by construction: add `"events_path"` to each `REST_POSES` entry in `export_diorama_anim_libraries.gd` (`"../../AnimDirector"` for `player`, `"../../AnimController"` for the five enemy profiles, matching the node names used by `locomotion.gd:41` and `castle_enemy_base.gd:115`) and pass it to `build_library`. Add a validation assertion so a future export cannot silently drop the tracks again.

Rejected alternative: emitting the events from GDScript timers inside the controller. It would re-introduce the timing drift the marker system exists to remove, and the swing frame would no longer follow `speed_scale` during hitstop.

**A real heal animation.** New `CLIPS` entry `heal`, length `1.35` s to match `PlayerHeal.DRINK_DURATION`, looping off, with three beats:

| Time | Pose |
|------|------|
| `0.00`–`0.22` s | `ArmL` raises the flask toward the head, `Torso` leans back `0.12` rad, `Head` tilts back `0.18` rad |
| `0.22`–`0.95` s | hold, with a `0.02` rad `Torso` sway and a `0.03` m `Root` bob so it is not frozen |
| `0.95`–`1.35` s | arm returns, `Torso` and `Head` settle, `ArmR` stays free so a shield or weapon reads as still held |

Method markers: `anim_heal_gulp` at `0.30` s and `0.62` s (two audible gulps), `anim_heal_commit` at `0.95` s. `PlayerAnimDirector.play_heal(duration)` becomes `_start_action(&"heal", Priority.ATTACK)` plus `speed_scale = clip_length / duration` so a future faster flask still reads correctly, and it no longer routes through `play_stagger`. A new `heal_commit_frame` signal lets `PlayerHeal` apply the health at `0.95` s instead of at the very end. `Priority.ATTACK` rather than `STAGGER` so a real stagger interrupts the drink.

**Hitstop that lands.** Give `hit_feedback.gd` a lazy accessor instead of a `_ready` cache:

```gdscript
func _director() -> Node:
	if _anim_director == null or not is_instance_valid(_anim_director):
		var body := get_parent()
		_anim_director = body.get_node_or_null("AnimDirector") if body else null
	return _anim_director
```

Hitstop values stay at `DEFAULT_HITSTOP = 0.09` s and `speed_scale = 0.05`, weighted by `clamp(damage / 20.0, 0.85, 1.35)` (`hit_feedback.gd:51`), giving a `0.077`–`0.122` s freeze.

**Bow on the player rig.** Add `"extras": ["bow"]` handling for the player profile conditioned on the equipped archetype: `DioramaCharacterSkin.attach_weapon` already redirects a bow kit to a `Bow` pivot when one exists (`diorama_character_skin.gd:249-252`). Build the pivot lazily in `attach_weapon` when `kit_id == "bow"` and no `Bow` pivot is present, parenting it under `WeaponMount` at `Vector3.ZERO`, and re-collect the rest pose so `attack_shoot`'s `Bow` track compiles. Because the rest pose changes, `bind()` must be re-run after a weapon archetype change to or from `bow`.

**Directional locomotion.** Add six clips and change the request contract:

| Clip | Length | Notes |
|------|--------|-------|
| `walk_b` | `0.9` s | shorter stride, torso upright, arms lower |
| `walk_l` / `walk_r` | `0.85` s | crossover step, hips rotated `0.18` rad into the direction of travel |
| `run_b` | `0.62` s | |
| `turn_l` / `turn_r` | `0.34` s | one-shot pivot step, played when the facing error exceeds `1.4` rad while `horizontal_speed <= 0.2` |

`update_locomotion(on_floor, velocity, sprinting, fall_height)` computes the movement direction in `Facing`-local space and requests `walk`/`walk_b`/`walk_l`/`walk_r` on the same 45/135 deg boundaries the movement speed scale uses (see [`locomotion.md`](locomotion.md)), with a `0.12` s blend so a circling input crossfades rather than snaps.

**Blocking locomotion.** Add `block_walk` (`0.9` s, loop) and make `_resume_locomotion` pick `block_walk` over `block_hold` when the desired locomotion state is not `idle`. Guard state stays `Priority.BLOCK`.

**Reaction arbitration.** Route both damage paths through one handler. `_on_health_changed` no longer plays anything; `Hurtbox` gains a `damaged(amount, poise_damage, direction)` signal that the director consumes to pick exactly one reaction per hit:

| Condition | Clip |
|-----------|------|
| blocking and the hit is frontal | `block_hit` |
| `poise_damage >= 20.0` or poise broken | `stagger`, `0.85` s |
| `poise_damage >= 8.0` | `flinch_f`/`flinch_l`/`flinch_r`/`flinch_b` chosen from the hit direction in `Facing`-local space |
| otherwise | `flinch_f` |

Add the three new directional flinch clips (`0.26` s each, mirroring the existing `flinch`).

**Viewmodel theme.** Take the theme from `CharacterService.appearance_theme` at build time, and add `PlayerAnimDirector.set_viewmodel_theme(theme: int)` called from the biome setup in `castle_run.gd` and `hub.gd` so the arms retint on floor change. Rebuild only the materials, not the node tree.

**Per-instance attack library.** In `_finish_bind`, wrap the authored library: `_library = loaded.duplicate(true)` when it came from `ResourceLoader`, so `_ensure_attack_clip` writes into a private copy. Also add `RESET` to the exported libraries by calling `_compile_reset` before the authored early-return, so `revive()` can blend rather than snap.

## Work plan

1. **Fix `_resolve_events_path`** and add `has_footstep_markers()` / `has_marker_tracks()` to `DioramaAnimController`. Closes half of PAD-01.
2. **Fix the exporter**: `events_path` per profile, `RESET` in the authored output, regenerate the six `.res` files. Closes PAD-01 and PAD-08.
3. **Duplicate the authored library on bind.** Closes PAD-11.
4. **Lazy `AnimDirector` lookup in `hit_feedback.gd`.** Closes PAD-03.
5. **Author the `heal` clip**, add `anim_heal_gulp` / `anim_heal_commit` markers and the `heal_commit_frame` signal, rewrite `play_heal`, and move the health application in `player_heal.gd` onto the marker. Closes PAD-02. Pairs with [`player-heal.md`](player-heal.md).
6. **Add directional flinch clips and the single-reaction arbiter**, including the `Hurtbox.damaged` direction argument. Closes PAD-09.
7. **Add the six directional locomotion clips and `block_walk`**, extend `update_locomotion`, and add turn-in-place. Closes PAD-05 and PAD-06.
8. **Build the `Bow` pivot on demand** in `attach_weapon` and re-bind on archetype change. Closes PAD-04.
9. **Thread the viewmodel theme** through `set_viewmodel_theme`. Closes PAD-07.
10. **Use `vertical_speed`**: split `air` into `air_rise` (`velocity.y > 1.0`) and `air_fall`, each `0.9` s and looping. Closes PAD-10.
11. **Add an additive layer.** Introduce a second `AnimationPlayer` named `DioramaAdditivePlayer` on the visual root, blend-mode additive, owning `breathe` (`3.4` s, loop, `Torso` and `Head` only) and `head_look` driven from the lock-on target. It plays on top of whatever the primary player is doing. Closes PAD-12.

## Data and schema changes

- `diorama_anim_library.gd` `CLIPS` gains: `heal`, `walk_b`, `walk_l`, `walk_r`, `run_b`, `run_l`, `run_r`, `turn_l`, `turn_r`, `block_walk`, `flinch_l`, `flinch_r`, `flinch_b`, `air_rise`, `air_fall`, `land_hard`, `breathe`.
- New marker constants `HEAL_GULP := &"anim_heal_gulp"` and `HEAL_COMMIT := &"anim_heal_commit"`.
- `export_diorama_anim_libraries.gd` `REST_POSES` gains an `events_path` string per profile; all six files under `apps/game/client/assets/animations/diorama/` are regenerated in the same commit.
- `AudioDirector.SFX_PROFILES` gains `heal_gulp` `{freq 300.0, duration 0.12, bus SFX}`.
- No JSON schema and no save format change, so no `save_migrator.gd` bump.

## Acceptance criteria

- [ ] `walk`, `run`, and every attack clip in a bound player library contain a `TYPE_METHOD` track, and `swing_frame` and `footstep_frame` both fire during normal play. (PAD-01)
- [ ] Drinking plays the `heal` clip, not `stagger`, and the health is applied at `0.95` s of the `1.35` s window. (PAD-02)
- [ ] Landing a hit visibly freezes the attacker's rig for `0.077`–`0.122` s depending on damage. (PAD-03)
- [ ] With a bow equipped, the `Bow` pivot exists on the player rig and rotates during `attack_shoot`. (PAD-04)
- [ ] Strafing left plays `walk_l`; backpedalling plays `walk_b`; turning 180 deg in place plays `turn_l` or `turn_r`. (PAD-05)
- [ ] Walking while blocking plays `block_walk` with moving legs and a raised guard. (PAD-06)
- [ ] The first-person arms use the current biome palette in the castle run, not the hub palette. (PAD-07)
- [ ] `player_locomotion.res` contains a `RESET` animation and `revive()` blends to it over `0.1` s. (PAD-08)
- [ ] A single hit that deals both health and poise damage plays exactly one reaction clip. (PAD-09)
- [ ] Rising and falling play different clips. (PAD-10)
- [ ] Two `melee` enemies attacking with different weapon phase timings do not share compiled attack clips. (PAD-11)
- [ ] The idle breathing layer remains visible while walking and while blocking. (PAD-12)

## Validation

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd`:

- `diorama_anim.authored_libraries_have_method_tracks` — every path in `AUTHORED_LIBRARY_PATHS` loads and its `walk` and `run` animations each have one `TYPE_METHOD` track with two keys.
- `diorama_anim.authored_libraries_have_reset` — every authored library has a `RESET` animation.
- `diorama_anim.required_clips` — extend the existing `required` list with `heal`, `walk_b`, `walk_l`, `walk_r`, `block_walk`, `flinch_l`, `flinch_r`, `flinch_b`, `turn_l`, `turn_r`, `air_rise`, `air_fall`, `land_hard`.
- `diorama_anim.events_path_resolves` — build a player rig, bind, and assert `_resolve_events_path` returns a non-empty path and that `visual.get_node_or_null(path)` is the controller.
- `diorama_anim.library_not_shared` — bind two rigs of profile `melee`, compile an attack on each with different timings, and assert the two `AnimationLibrary` instances are different objects.

Extend `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `player.heal_uses_heal_clip` — call `play_heal(1.35)` and assert `AnimationPlayer.current_animation == "heal"`.
- `player.hitstop_reaches_rig` — instance `player.tscn`, wait two physics frames, call `HitFeedback.on_hit(dummy, 20.0)`, and assert the rig's `speed_scale` is `0.05`.
- `player.reaction_arbitration` — feed one `damaged` event with both health and poise damage and assert exactly one action-priority clip started.
- `player.directional_locomotion_clips` — drive `update_locomotion` with four directions and assert the requested clip names.

## Related
- Existing state: [`../existing_codebase/player-anim-director.md`](../existing_codebase/player-anim-director.md)
- [`locomotion.md`](locomotion.md), [`player-heal.md`](player-heal.md), [`player-combat.md`](player-combat.md), [`player-combat-reactions.md`](player-combat-reactions.md), [`lock-on-movement.md`](lock-on-movement.md)
- [`diorama-anim-controller.md`](diorama-anim-controller.md), [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`hit-feedback.md`](hit-feedback.md), [`export-tools.md`](export-tools.md)
