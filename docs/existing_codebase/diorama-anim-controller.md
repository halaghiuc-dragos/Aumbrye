# Diorama anim controller

Owns the `AnimationPlayer` for one diorama rig and arbitrates which clip plays through a six-level priority stack. It is on the live play path for every animated character: `PlayerAnimDirector` extends it (`player_anim_director.gd:2`), `castle_enemy_base.gd:114-121` instantiates one per enemy and boss, `training_grunt.gd:38-43` one for the dummy, and `player_anim_director.gd:73-81` a second one for the first-person viewmodel registered as a mirror.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_anim_controller.gd` | 416 lines: binding, priority stack, attack compilation cache, mirror fan-out, method-track handlers |
| `apps/game/client/scripts/player/player_anim_director.gd` | Player subclass; maps gameplay signals to controller calls and builds the viewmodel mirror |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | Enemy/boss host |
| `apps/game/client/scripts/enemies/training_grunt.gd` | Training dummy host |

## How it works

### Binding

`bind(visual)` (`:64-73`) tears down any previous player, stores the visual, and defers to `tree_entered` (one-shot) if the visual is not yet in the tree. `_finish_bind` (`:81-104`):

1. `_rest_pose = CharacterSkin.collect_rest_pose(visual)`; returns if empty.
2. `_events_path = _resolve_events_path(visual)`.
3. `_library = AnimLibrary.build_library(_rest_pose, _events_path, _profile)`.
4. Creates an `AnimationPlayer` named `DioramaAnimPlayer` as a child of the visual, with `root_node = NodePath("..")` so track paths resolve relative to the visual itself (`:90-94`).
5. `add_animation_library(LIBRARY_NAME, _library)` where `LIBRARY_NAME = &""` (`:30`), so clips are addressed by bare name.
6. Connects `animation_finished`, sets `playback_default_blend_time = LOCOMOTION_BLEND` (0.12).
7. Applies a deferred `set_weapon` if one arrived before the rig existed (`:102-103`).
8. Plays `idle`.

`_resolve_events_path(visual)` (`:111-121`) returns `""` unless `visual.is_ancestor_of(self)`, i.e. unless the controller node is a **descendant of the visual**. In every shipped configuration it is not:

| Host | Visual node path | Controller node path | `visual.is_ancestor_of(controller)` |
|------|-----------------|---------------------|-------------------------------------|
| Player | `Player/Facing/DioramaVisual` (`locomotion.gd:39`) | `Player/AnimDirector` (`locomotion.gd:41-42`) | false |
| Player viewmodel | `.../Camera3D/Viewmodel/ViewRoot` (`diorama_viewmodel.gd:38-40`) | `Player/AnimDirector/ViewmodelAnim` (`player_anim_director.gd:74-75`) | false |
| Enemy / boss | `<Enemy>/DioramaVisual` (`diorama_character_skin.gd:477-481`, parent is the body) | `<Enemy>/AnimController` (`castle_enemy_base.gd:115-116`) | false |
| Training dummy | `<Dummy>/DioramaVisual` | `<Dummy>/AnimController` (`training_grunt.gd:39-40`) | false |

`_events_path` is therefore `""` for every character in the game, and `DioramaAnimLibrary._compile` skips the method track whenever `events_path == ""` (`diorama_anim_library.gd:550`). No clip anywhere carries a method track, so `anim_footstep`, `anim_swing_vfx`, `anim_hitbox_on`, and `anim_hitbox_off` are never called by an animation.

### Priority stack

`Priority` (`:16-23`), lowest to highest: `LOCOMOTION`, `DASH`, `BLOCK`, `ATTACK`, `STAGGER`, `DEATH`.

`_start_action(clip, priority)` (`:304-313`) refuses only when `priority < _priority` — an equal priority is allowed to interrupt. It then requires `has_clip(clip)` and returns silently if the clip is absent.

`_play(clip, blend)` (`:316-329`) fans out to mirrors first (copying `_priority` and `_desired_locomotion` by direct field write, `:317-320`), returns silently on a missing clip, and refuses to restart a looping clip that is already playing so `idle` does not stutter (`:325-328`).

`_resume_locomotion()` (`:332-341`) resets `speed_scale` to 1.0, returns to `block_hold` if still blocking, else replays `_desired_locomotion`.

`_on_animation_finished` (`:344-352`) ignores `block_start`, `block_hit`, and anything starting with `block_hold`, and does nothing while `_dead`; otherwise it unwinds to locomotion.

### Public API

| Method | Effect |
|--------|--------|
| `bind(visual)` | Build library, create `AnimationPlayer`, play `idle` |
| `is_bound()` | `_player != null and is_instance_valid(_player)` (`:107-108`) |
| `set_profile(profile)` | Store profile and refresh the attack clip list (`:124-126`) |
| `set_theme(theme)` | Store theme used by `attach_weapon` (`:129-130`) |
| `set_weapon(weapon_id, archetype = "")` | Fan out to mirrors, store both, refresh attack clips, re-attach the kit (`:133-140`) |
| `has_clip(clip)` | `_library.has_animation(clip)` (`:143-144`) |
| `request_locomotion(state, params)` | Records `_desired_locomotion`, returns early if a higher priority owns the stack, sets `speed_scale`, plays the clip if not already current (`:148-164`) |
| `play_dash(direction)` | Falls back to `dash_f` when the directional clip is missing; `DASH` priority (`:167-171`) |
| `set_blocking(holding)` | On: `block_start` then queues `block_hold` at `BLOCK`. Off: drops to `LOCOMOTION` and resumes (`:174-187`) |
| `play_block_impact()` | `block_hit` with a 0.03 s blend, requeues `block_hold`; no-op unless already blocking (`:190-195`) |
| `play_parry()` | `parry_success` at `ATTACK` (`:198-200`) |
| `play_guard_break()` | `guard_break` at `STAGGER` (`:203-205`) |
| `play_flinch()` | `flinch` at `STAGGER`, but returns early when `_priority >= STAGGER` (`:208-211`) |
| `play_stagger(duration)` | `stagger` at `STAGGER`; when `duration > 0.05` scales playback by `clip_length / duration` clamped to 0.4-2.5 (`:214-220`) |
| `play_death()` | `death` at `DEATH`, latched by `_dead` (`:223-228`) |
| `revive()` | Clears `_dead`/`_blocking`, resets priority and `_desired_locomotion`, applies the rest pose, plays `idle` with zero blend (`:231-244`) |
| `play_attack(startup, active, recovery, clip_override)` | Resolves the clip, fans out to mirrors, compiles/caches, plays at `ATTACK` (`:249-269`) |
| `play_heavy_attack(...)` | `play_attack` with `AnimLibrary.heavy_clip_for(_weapon_archetype)` (`:272-273`) |
| `reset_combo()` | `_combo_index = 0` (`:276-277`) |
| `add_mirror(other)` | Registers a second controller to receive the same calls (`:59-61`) |
| `set_speed_scale(scale)` | Floors at 0.01, applies to self and mirrors (`:382-387`) |
| `get_weapon_mount()` | `CharacterSkin.find_part(_visual, "WeaponMount")` (`:390-393`) |

### Locomotion speed scaling

`WALK_REFERENCE_SPEED = 4.5`, `RUN_REFERENCE_SPEED = 7.0` (`:34-35`). `request_locomotion` divides the reported horizontal speed by the reference and clamps: `walk` to `[0.45, 1.6]`, `run` to `[0.6, 1.5]` (`:157-161`). Blend times are `LOCOMOTION_BLEND = 0.12` and `ACTION_BLEND = 0.06` (`:28-29`).

### Attack compilation cache

`play_attack` (`:249-269`) picks `clip_override` when it names a real `ATTACKS` entry, else cycles `_attack_clips[_combo_index % size]` and increments (`:253-259`). Mirrors receive the **resolved** clip so both rigs swing identically (`:261-262`).

`_ensure_attack_clip` (`:285-301`) keys the cache on `"%s_%d_%d_%d"` with each phase rounded to centiseconds, compiles through `AnimLibrary.build_attack`, adds the result to `_library` under that key as the runtime animation name, and stores it in `_compiled_attacks`. Entries are never evicted; `_teardown` clears the dictionary but the library is discarded with it (`:407-415`).

### Method-track handlers

`anim_swing_vfx()` emits `swing_frame` (`:356-357`); `anim_footstep()` emits `footstep_frame` (`:360-361`). `anim_hitbox_on`/`anim_hitbox_off` (`:364-379`) cast `get_parent()` to `CharacterBody3D`, look for a `WeaponController` child, and call `enable_hitbox_from_anim` / `disable_hitbox_from_anim`. Those two methods exist only on `weapon_controller.gd:242` and `:247`, which is a player-only node — enemies drive their hitboxes from their own state timers (`castle_enemy_base.gd:640-650`). None of the four handlers is reachable from an animation because `_events_path` is always `""`.

### Mirrors

`_mirrors: Array[DioramaAnimController]` (`:53`). `request_locomotion`, `set_blocking`, `set_weapon`, `play_attack`, `revive`, `set_speed_scale`, and `_play` all fan out. `_start_action` and `play_dash`/`play_parry`/`play_guard_break`/`play_flinch`/`play_stagger`/`play_death` reach mirrors only indirectly, through the `_play` call inside `_start_action`. `_mirrors` is not cleared by `_teardown` (`:407-415`), so re-binding the host rig preserves the viewmodel link.

## Contracts

- **Signals emitted** — `swing_frame`, `footstep_frame` (`:13-14`). Consumed by `player_anim_director.gd:54-55` and `castle_enemy_base.gd:121`.
- **Methods the host may call** — the public API table above. `castle_enemy_base` guards every call with `_animator.is_bound()`.
- **Node created** — `DioramaAnimPlayer` as a child of the bound visual, `root_node = ".."`.
- **Animation library name** — `&""` (the default library), so clips are addressed unqualified.
- **Depends on** — `DioramaCharacterSkin.collect_rest_pose`, `.attach_weapon`, `.find_part`, `.WEAPON_MOUNT`; `DioramaAnimLibrary.build_library`, `.build_attack`, `.ATTACKS`, `.attack_clips_for`, `.heavy_clip_for`.
- **No autoloads** are referenced from this file.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `_events_path` is `""` for every character, so no clip carries a method track | BROKEN | `:116` requires `visual.is_ancestor_of(self)`; the four shipped node layouts in the table above all fail it |
| `anim_footstep` never fires; `locomotion.gd` suppresses its own timer-based footsteps whenever the rig is bound, so the player has no footstep VFX or SFX | BROKEN | `:360-361`, `locomotion.gd:181-183`, `player_anim_director.gd:279-285` |
| `anim_swing_vfx` never fires, so `VfxService.play_weapon_trail` is unreachable | BROKEN | `:356-357`, `player_anim_director.gd:288-292`, `castle_enemy_base.gd:135-137` (the only two call sites) |
| `anim_hitbox_on`/`anim_hitbox_off` never fire | BROKEN | `:364-379`; `weapon_controller.gd:242`, `:247` are the only implementations |
| `anim_hitbox_on`/`off` would be no-ops for enemies even if fired: enemies have no `WeaponController` child | PARTIAL | `:368`, `castle_enemy_base.gd:68` uses `AttackPivot/Hitbox` |
| Missing clips are swallowed with no warning | PARTIAL | `:309`, `:321-322` |
| `play_flinch` is rejected while a `flinch` is already playing, so a second hit during the 0.26 s flinch gives no reaction | PARTIAL | `:209-210` (`_priority >= STAGGER` covers `flinch` itself, which sets `STAGGER` at `:211`) |
| `_compiled_attacks` grows unbounded for the life of a bind | PARTIAL | `:285-301`; no eviction |
| Mirror state is propagated by writing another instance's private fields | PARTIAL | `:318-319`, `:386-387` |
| `revive()` does not reset `_combo_index` or clear `_compiled_attacks` | PARTIAL | `:231-244` vs `:276-277` |
| `LIBRARY_NAME` is `&""`, so runtime attack animations share the namespace with authored clip names | PARTIAL | `:30`, `:298-299` |
| Priority stack, blend times, and one-shot unwinding | IMPLEMENTED | `:304-352` |
| Attack phase stretching so the visual swing matches weapon JSON timings | IMPLEMENTED | `:263`, `diorama_anim_library.gd:486-512` |
| `play_stagger` duration matching | IMPLEMENTED | `:214-220` |
| Deferred bind for visuals not yet in the tree | IMPLEMENTED | `:69-79` |

## Related
- Improvement plan: [`../actual_improvements/diorama-anim-controller.md`](../actual_improvements/diorama-anim-controller.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`player-anim-director.md`](player-anim-director.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md), [`combat-core.md`](combat-core.md), [`vfx-service.md`](vfx-service.md)
- Cross-cutting decision on authored characters and rigs: [`character-authoring.md`](character-authoring.md)
