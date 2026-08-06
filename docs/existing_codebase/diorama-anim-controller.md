# Diorama anim controller

## Status: FINISHED

Owns the `AnimationPlayer` for one diorama rig and arbitrates which clip plays through a six-level priority stack. It is on the live play path for every animated character: `PlayerAnimDirector` extends it (`player_anim_director.gd:2`), `castle_enemy_base.gd:174-183` instantiates one per enemy and boss, `training_grunt.gd:38-43` one for the dummy, and `player_anim_director.gd:145-175` a second one for the first-person viewmodel registered as a mirror.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/art/characters/diorama_anim_controller.gd` | Binding, priority stack, runtime attack cache, mirror API, method-track handlers |
| `apps/game/client/scripts/art/characters/diorama_anim_library.gd` | Clip tables, `clip_meta`, `select_locomotion_clip`, `events_path_for_profile`, library build/supplement |
| `apps/game/client/scripts/player/player_anim_director.gd` | Player subclass; maps gameplay signals to controller calls and builds the viewmodel mirror |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | Enemy/boss host; connects `hitbox_open_frame` / `hitbox_close_frame` |
| `apps/game/client/scripts/combat/weapon_controller.gd` | Player hitbox signal consumer |
| `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` | Headless controller-level behavioural tests |

## How it works

### Binding

`bind(visual)` (`diorama_anim_controller.gd:81-90`) tears down any previous player, stores the visual, and defers to `tree_entered` (one-shot) if the visual is not yet in the tree. `_finish_bind` (`:98-138`):

1. `_rest_pose = CharacterSkin.collect_rest_pose(visual)`; warns and re-arms deferred bind when empty (`:103-110`).
2. `_events_path = _resolve_events_path(visual)` via `visual.get_path_to(self)` plus a resolve check (`:145-156`).
3. `_library = AnimLibrary.build_library(_rest_pose, _events_path, _profile)`; authored `.res` libraries are supplemented when footstep markers are missing (`diorama_anim_library.gd:_supplement_authored_library`).
4. Creates `_runtime_library` for compiled attacks (`RUNTIME_LIBRARY_NAME = &"runtime"`, `ATTACK_CACHE_LIMIT = 24`).
5. Creates `DioramaAnimPlayer` as a child of the visual with `root_node = NodePath("..")`.
6. Adds both `""` and `runtime` animation libraries, connects `animation_finished`, plays `idle`.

`_resolve_events_path` yields non-empty paths for all shipped layouts:

| Host | Resolved path |
|------|---------------|
| Player | `../../AnimDirector` |
| Player viewmodel | relative path up to `ViewmodelAnim` |
| Enemy / boss / dummy | `../AnimController` |

### Priority stack

`Priority` enum (`:20-27`): `LOCOMOTION`, `DASH`, `BLOCK`, `ATTACK`, `STAGGER`, `DEATH`.

`_begin_action(clip, priority, scale)` (`:511-523`) refuses when `priority < _priority`, reports missing clips once per bind, fans out full state via `mirror_apply`, and plays locally.

`_play` / `_play_local` (`:526-547`) fan out through `mirror_apply`; `_play_local` restarts non-looping clips from time 0 when the same clip is already playing.

`_on_animation_finished` (`:596-606`) ignores `block_*` clips and compiled runtime attacks (namespaced under `runtime/`), then resumes locomotion.

### Public API

| Method | Effect |
|--------|--------|
| `bind(visual)` | Build library, create `AnimationPlayer`, play `idle` |
| `is_bound()` | `_player != null and is_instance_valid(_player)` |
| `set_profile(profile)` | Store profile and refresh attack clip list |
| `set_weapon(weapon_id, archetype)` | Fan out to mirrors, refresh attack clips, re-attach kit |
| `has_clip(clip)` | Checks default and `runtime/` libraries |
| `select_locomotion_clip(speed)` | Delegates to `AnimLibrary.select_locomotion_clip` with jog/walk fallback |
| `request_locomotion(state, params)` | Stride-driven `speed_scale` via `_locomotion_speed_scale`, clamped `[0.5, 2.2]` |
| `play_dash(direction)` | Reports missing clips; falls back to `dash_f` |
| `play_flinch(direction)` | Re-enters while a `flinch`/`flinch_*` clip is playing; directional clips from world hit vector |
| `play_stagger(duration, direction)` | Duration-matched `speed_scale`; directional `stagger_*` when present |
| `play_attack(...)` | Compiles/caches into `runtime/<timing_key>` with LRU eviction |
| `revive()` | Clears death/blocking, calls `reset_combo()`, restores idle |
| `add_mirror(other)` / `remove_mirror(other)` | Register or drop a mirrored controller |
| `mirror_apply(...)` | Public fan-out entry used by bodyâ†’viewmodel sync |

### Locomotion speed scaling

`request_locomotion` reads `AnimLibrary.clip_meta(state)` and scales by `travel * length / stride_m`, clamped to `SPEED_SCALE_MIN` (0.5) and `SPEED_SCALE_MAX` (2.2). `WALK_REFERENCE_SPEED` / `RUN_REFERENCE_SPEED` are removed.

### Method-track handlers

`anim_swing_vfx`, `anim_footstep`, `anim_hitbox_on`, `anim_hitbox_off`, `anim_heal_gulp`, `anim_heal_commit` emit signals (`swing_frame`, `footstep_frame`, `hitbox_open_frame`, `hitbox_close_frame`, `heal_gulp_frame`, `heal_commit_frame`). Hosts wire hitbox signals: `weapon_controller.gd:333-336`, `castle_enemy_base.gd:182-183`.

`locomotion.gd:403-406` suppresses distance-based footstep fallback when `has_footstep_markers()` is true.

### Mirrors

`_live_mirrors()` prunes freed instances. `_teardown` preserves live mirrors (`:686-687`). `PlayerAnimDirector._build_viewmodel` calls `remove_mirror` before freeing the old viewmodel controller (`player_anim_director.gd:155`).

## Contracts

- **Signals emitted** â€” `swing_frame`, `footstep_frame`, `hitbox_open_frame`, `hitbox_close_frame`, `heal_gulp_frame`, `heal_commit_frame`.
- **Animation libraries** â€” authored clips in `&""`; compiled attacks in `&"runtime"`.
- **Depends on** â€” `DioramaCharacterSkin`, `DioramaAnimLibrary.build_library`, `.build_attack`, `.clip_meta`, `.select_locomotion_clip`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Events path resolves for all host layouts | IMPLEMENTED | `diorama_anim_controller.gd:_resolve_events_path`; `diorama_anim_suite.gd:_test_events_path_resolves` |
| Footstep / swing method tracks fire signals | IMPLEMENTED | `anim_footstep`, `anim_swing_vfx`; `locomotion.gd:403-406` |
| Enemy hitbox driven by animation frames | IMPLEMENTED | `castle_enemy_base.gd:182-193` |
| Missing-clip diagnostics (deduplicated) | IMPLEMENTED | `_report_missing`, `_missing_clips` |
| Flinch re-entry during stagger window | IMPLEMENTED | `play_flinch`; `_play_local` seek restart |
| Mirror API with speed_scale propagation | IMPLEMENTED | `mirror_apply`, `_live_mirrors`, `remove_mirror` |
| Stride-driven locomotion rate | IMPLEMENTED | `_locomotion_speed_scale`, `AnimLibrary.clip_meta` |
| Empty rest-pose bind retry | IMPLEMENTED | `_finish_bind:103-110` |
| Bounded runtime attack cache | IMPLEMENTED | `ATTACK_CACHE_LIMIT = 24`, `_attack_cache_order` LRU |
| `revive()` resets combo | IMPLEMENTED | `revive:426` calls `reset_combo()` |
| Priority stack, blends, attack stretching | IMPLEMENTED | `_begin_action`, `AnimLibrary.build_attack` |
| Controller validation suite | IMPLEMENTED | `diorama_anim_suite.gd` (20 tests) |

## Related
- Improvement plan: [`../actual_improvements/diorama-anim-controller.md`](../actual_improvements/diorama-anim-controller.md) - **FINISHED**
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`player-anim-director.md`](player-anim-director.md), [`enemies.md`](enemies.md), [`combat-core.md`](combat-core.md), [`vfx-service.md`](vfx-service.md)
