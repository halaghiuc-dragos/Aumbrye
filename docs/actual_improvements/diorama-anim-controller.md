# Diorama anim controller — improvement plan

## Current state

`DioramaAnimController` builds an `AnimationPlayer` per rig, arbitrates clips through a six-level priority stack, stretches attack clips onto weapon phase timings, and mirrors every call to the first-person viewmodel controller. The stack, blends, and attack stretching work. The event layer does not: `_resolve_events_path` returns `""` for all four shipped node layouts, so no animation in the game carries a method track and the four `anim_*` handlers are dead code. See [`../existing_codebase/diorama-anim-controller.md`](../existing_codebase/diorama-anim-controller.md).

This plan fixes the event path, makes silent failures loud, and turns the mirror from private-field pokes into a real API. It does not change what a rig is made of; that is [`character-authoring.md`](character-authoring.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ANC-01 | P0 | `_resolve_events_path` requires `visual.is_ancestor_of(self)`, which is false for the player, the viewmodel, every enemy, every boss, and the dummy. `_events_path` is always `""`, and `DioramaAnimLibrary._compile` skips the method track on an empty path, so no clip in the game has a method track. | `:111-121`; `diorama_anim_library.gd:550`; layouts at `locomotion.gd:39`, `:41-42`, `castle_enemy_base.gd:115-116`, `training_grunt.gd:39-40`, `diorama_viewmodel.gd:38-40` |
| ANC-02 | P0 | `anim_footstep` never fires, and `locomotion.gd` disables its own distance-based footstep fallback whenever a rig is bound, so the player produces no footstep SFX or dust VFX at all while moving. | `:360-361`; `locomotion.gd:181-183`; `player_anim_director.gd:279-285` |
| ANC-03 | P0 | `anim_swing_vfx` never fires, so `VfxService.play_weapon_trail` has no reachable caller for the player or for enemies: every melee swing is silent visually. | `:356-357`; `player_anim_director.gd:288-292`; `castle_enemy_base.gd:135-137` |
| ANC-04 | P1 | `anim_hitbox_on`/`anim_hitbox_off` look for a `WeaponController` child of `get_parent()`. Only the player has one, so even after ANC-01 is fixed enemy hitboxes cannot be animation-driven and stay on their own state timers. | `:364-379`; `weapon_controller.gd:242`, `:247`; `castle_enemy_base.gd:68`, `:640-650` |
| ANC-05 | P1 | Every missing-clip path returns silently: `_start_action` at `:309`, `_play` at `:321-322`, `play_dash` silently rewrites any unknown dash to `dash_f`, `play_attack` returns on an empty clip list. A rig that cannot play `stagger` looks identical to one that chose not to. | `:167-171`, `:249-269`, `:304-313`, `:316-322` |
| ANC-06 | P1 | `play_flinch` returns when `_priority >= STAGGER`, and `flinch` itself sets `STAGGER`, so a second hit inside the 0.26 s flinch produces no reaction. Rapid multi-hits read as the player being hit once. | `:208-211` |
| ANC-07 | P1 | Mirror state is propagated by writing another instance's private fields (`mirror._priority`, `mirror._desired_locomotion`, `mirror._player.speed_scale`). `play_stagger`'s duration-matched `speed_scale` and `play_dash`/`play_parry`/`play_guard_break`/`play_flinch`/`play_death` reach mirrors only as a side effect of the `_play` inside `_start_action`, so a staggered player's viewmodel plays `stagger` at the wrong rate. | `:317-320`, `:382-387`, `:214-220`, `:167-228` |
| ANC-08 | P1 | Locomotion playback rate is `speed / WALK_REFERENCE_SPEED` clamped to `[0.45, 1.6]`, with no relation to the clip's actual stride, so feet skate. | `:34-35`, `:156-162`; paired with ANL-02 |
| ANC-09 | P1 | `_finish_bind` returns silently when `collect_rest_pose` comes back empty, leaving `_player` null. The host then sees `is_bound() == false` forever and the character never animates, with no warning and no retry. | `:85-87` |
| ANC-10 | P1 | `_mirrors` is never cleared and mirror validity is never checked. `_teardown` deliberately keeps it (`:407-415`), so a freed viewmodel controller stays registered and every fan-out call touches a freed object. | `:53`, `:59-61`, `:407-415` |
| ANC-11 | P2 | `_compiled_attacks` is keyed on rounded phase timings and never evicted; the library accumulates a runtime animation per distinct timing set for the life of the bind. | `:285-301` |
| ANC-12 | P2 | `revive()` resets pose, priority, and `_dead` but not `_combo_index`, so a revived character resumes mid-combo. | `:231-244` vs `:276-277` |
| ANC-13 | P2 | `LIBRARY_NAME` is `&""` and compiled attacks are added into the same namespace as authored clip names, using `"%s_%d_%d_%d"` keys. A future authored clip named like a timing key would collide silently. | `:30`, `:292`, `:298-299` |
| ANC-14 | P2 | `_on_animation_finished` special-cases block clips by string prefix (`begins_with("block_hold")`), which is a workaround for compiled attack names sharing the namespace. | `:344-352` |

## Target design

### 1. Events path resolved from the AnimationPlayer, not the visual

Method tracks store a `NodePath` resolved against the `AnimationPlayer`'s `root_node`, which `_finish_bind` sets to the visual (`:94`). The controller does not have to be a descendant of the visual — it only has to be reachable from it. Replace the ancestor test with a real path computation plus a resolve check:

```gdscript
func _resolve_events_path(visual: Node3D) -> String:
    if not is_inside_tree() or not visual.is_inside_tree():
        return ""
    var path := visual.get_path_to(self)   # yields e.g. "../../AnimDirector"
    if path.is_empty():
        return ""
    if visual.get_node_or_null(path) != self:
        push_warning("DioramaAnimController: events path %s does not resolve back to self" % path)
        return ""
    return String(path)
```

`Node.get_path_to` already emits `..` segments for a sibling or ancestor target, so this covers all four layouts: `../../AnimDirector` for the player, `../AnimController` for enemies and the dummy, and a longer relative path for the viewmodel. Rejected alternative: reparenting each controller under its visual so the current ancestor test passes. That would break `anim_hitbox_on`'s `get_parent() as CharacterBody3D` lookup and every host's `$AnimController` reference for a cosmetic reason.

Because `.res` libraries bake the path at export time, the exporter needs a matching per-profile path table (ANL-01, see [`diorama-anim-library.md`](diorama-anim-library.md)).

### 2. Hitbox and event dispatch through the host, not a hardcoded sibling name

The four `anim_*` handlers stop reaching across the tree. Add two signals and let each host wire itself:

```gdscript
signal hitbox_open_frame
signal hitbox_close_frame

func anim_hitbox_on() -> void:
    hitbox_open_frame.emit()

func anim_hitbox_off() -> void:
    hitbox_close_frame.emit()
```

`weapon_controller.gd` connects `hitbox_open_frame` to `enable_hitbox_from_anim` and `hitbox_close_frame` to `disable_hitbox_from_anim`; `castle_enemy_base.gd` connects them to its own `AttackPivot/Hitbox` enable/disable, which closes ANC-04 by giving enemies the same animation-driven windows the player gets. The existing `swing_frame` and `footstep_frame` signals stay as they are; their consumers already exist and become live the moment ANC-01 lands.

Failure behavior: if a host connects neither signal, the controller warns once per bind rather than per frame.

### 3. Silence becomes diagnostics

Add a `_missing_clips: Dictionary` set and a shared reporter:

```gdscript
func _report_missing(clip: StringName, context: String) -> void:
    if _missing_clips.has(clip):
        return
    _missing_clips[clip] = true
    push_warning("DioramaAnimController[%s]: clip '%s' missing (%s)" % [_profile, clip, context])
```

Called from `_start_action`, `_play`, `play_dash` (before falling back to `dash_f`), and `play_attack` when `_attack_clips` is empty after a refresh. Deduplicated per bind so a missing looping clip cannot spam the log. `_finish_bind` also warns when the rest pose is empty and re-arms the deferred `tree_entered` connection so a rig built later still binds, closing ANC-09.

### 4. Mirrors as an API

Replace direct field writes with an explicit fan-out that survives freed nodes:

```gdscript
func _live_mirrors() -> Array[DioramaAnimController]:
    var out: Array[DioramaAnimController] = []
    for m in _mirrors:
        if m != null and is_instance_valid(m):
            out.append(m)
    if out.size() != _mirrors.size():
        _mirrors = out
    return out

func mirror_apply(priority: int, locomotion: StringName, clip: StringName, blend: float, scale: float) -> void:
    _priority = priority
    _desired_locomotion = locomotion
    if _player:
        _player.speed_scale = scale
    _play_local(clip, blend)
```

`_play` splits into `_play` (fan out via `mirror_apply`, then `_play_local`) and `_play_local` (the current body minus the mirror loop). `play_stagger`, `play_dash`, `play_parry`, `play_guard_break`, `play_flinch`, and `play_death` then propagate their full state including the stretched `speed_scale`, closing ANC-07. `remove_mirror(other)` is added and called by `PlayerAnimDirector` when it rebuilds the viewmodel, closing ANC-10.

### 5. Flinch re-triggering

`play_flinch` allows re-entry when the currently playing clip is itself `flinch`, so consecutive hits re-strike the reaction while a `stagger` or `death` still wins:

```gdscript
func play_flinch(direction: StringName = &"") -> void:
    if _priority > Priority.STAGGER:
        return
    if _priority == Priority.STAGGER and _player.current_animation != "flinch" \
            and not _player.current_animation.begins_with("flinch_"):
        return
    var clip := direction if direction != &"" and has_clip(direction) else &"flinch"
    _start_action(clip, Priority.STAGGER)
```

The `direction` argument consumes the `flinch_f`/`flinch_b`/`flinch_l`/`flinch_r` clips from [`diorama-anim-library.md`](diorama-anim-library.md) section 3, selected by the caller from the damage direction. Closes ANC-06.

### 6. Stride-driven locomotion rate

`request_locomotion` reads the clip's `stride_m` and `length` from the library instead of a fixed reference speed:

```gdscript
var meta := AnimLibrary.clip_meta(state)   # {length, loop, stride_m, contacts}
if meta.get("stride_m", 0.0) > 0.0:
    var travel := float(params.get("speed", 0.0))
    var scale := travel * float(meta["length"]) / float(meta["stride_m"])
    if scale < SPEED_SCALE_MIN or scale > SPEED_SCALE_MAX:
        _report_clamp(state, scale)
    _player.speed_scale = clampf(scale, SPEED_SCALE_MIN, SPEED_SCALE_MAX)
```

`SPEED_SCALE_MIN = 0.5`, `SPEED_SCALE_MAX = 2.2`. `WALK_REFERENCE_SPEED` and `RUN_REFERENCE_SPEED` are deleted. Clip selection moves into a helper the caller uses, so the walk/jog/run thresholds live in one place: `select_locomotion_clip(speed)` returns `idle` below 0.15, `walk` below 2.4, `jog` below 5.0, `run` above. Closes ANC-08.

### 7. Bounded attack cache and a private namespace

Compiled attacks go into a second library named `&"runtime"` so their names can never shadow authored clips, and are addressed as `runtime/<key>`. `_compiled_attacks` gains an LRU cap of 24 entries; on overflow the least recently used key is removed from both the dictionary and the library. `_on_animation_finished` then tests membership in `AnimLibrary.ATTACKS` and a `block_` prefix set rather than string prefixes on compiled names, closing ANC-11, ANC-13, and ANC-14. `revive()` calls `reset_combo()`, closing ANC-12.

## Work plan

1. **Fix `_resolve_events_path`** — replace the ancestor test with `get_path_to` plus a resolve check and warning. This alone makes `FOOTSTEP`, `SWING_VFX`, `HITBOX_ON`, and `HITBOX_OFF` fire for every runtime-compiled rig, so the player regains footsteps and swing trails. Closes ANC-01 for the runtime path, and ANC-02 and ANC-03 for the player. Authored `.res` profiles still lack markers until the exporter change in [`diorama-anim-library.md`](diorama-anim-library.md) step 2 lands.
2. **Add `hitbox_open_frame` / `hitbox_close_frame` signals and rewire hosts** — `weapon_controller.gd` connects to its existing `enable_hitbox_from_anim` / `disable_hitbox_from_anim`; `castle_enemy_base.gd` connects to its `AttackPivot/Hitbox`. Closes ANC-04.
3. **Add `_report_missing` and the empty-rest-pose warning with bind retry** — closes ANC-05 and ANC-09.
4. **Split `_play` into `_play` / `_play_local`, add `mirror_apply`, `_live_mirrors`, and `remove_mirror`; propagate stagger `speed_scale`** — closes ANC-07 and ANC-10.
5. **Add directional flinch and flinch re-entry** — closes ANC-06. Depends on the `flinch_*` clips existing; degrades to plain `flinch` until then.
6. **Replace reference-speed scaling with stride-driven scaling and add `select_locomotion_clip`** — closes ANC-08. Depends on `stride_m` metadata from `diorama-anim-library.md` step 5.
7. **Move compiled attacks into a `runtime` library, add the LRU cap, rewrite `_on_animation_finished` to use clip sets, call `reset_combo()` from `revive()`** — closes ANC-11, ANC-12, ANC-13, ANC-14.

Steps 1-4 are independent of the library work and each leaves the game runnable. Steps 5 and 6 tolerate the clip metadata being absent by falling back to current behavior.

## Data and schema changes

No JSON content, schema, or save changes. `stride_m` and `contacts` are added to the GDScript clip tables, not to `content/`, and are exposed to the controller through a new `AnimLibrary.clip_meta(clip)` accessor.

## Acceptance criteria

- [ ] `_events_path` is a non-empty relative path for the player, the player viewmodel, every enemy, every boss, and the training dummy.
- [ ] Walking the player emits `footstep_frame` at each of the clip's declared contact times, and a footstep sound plus dust VFX are produced.
- [ ] Every melee swing emits `swing_frame` once and produces a weapon trail, for the player and for enemies.
- [ ] An enemy's hitbox opens and closes on animation frames, verified by an enemy whose `AttackPivot/Hitbox` enable is triggered only by `hitbox_open_frame`.
- [ ] Requesting a clip the rig cannot play logs exactly one warning naming the clip and the profile, and does not log again for that clip during the same bind.
- [ ] Binding a visual with no recognized pivots logs a warning and does not leave `is_bound()` permanently false once the rig is populated.
- [ ] Freeing the viewmodel controller and then calling `request_locomotion` on the body controller does not error and drops the dead mirror.
- [ ] A staggered player's viewmodel plays `stagger` at the same `speed_scale` as the body.
- [ ] Two hits 0.1 s apart produce two visible flinch reactions.
- [ ] `speed_scale` stays inside `[0.5, 2.2]` without hitting either bound at any reachable movement speed, and hitting a bound logs a warning.
- [ ] `_compiled_attacks` never exceeds 24 entries, and evicted names are removed from the library.
- [ ] Compiled attack animations live under the `runtime` library and no authored clip name can collide with a timing key.
- [ ] Reviving a character resets its combo index to 0.

## Validation

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd` (category `graphics`) with controller-level assertions, all runnable headless by building a rig and a controller in a detached tree:

- `diorama_anim.events_path_resolves` — for each of the four host layouts, construct the layout, bind, and assert `_events_path != ""` and that the path resolves from the visual back to the controller. Fails today for all four.
- `diorama_anim.method_signals_fire` — bind a player rig, play `walk` for one full cycle with `speed_scale = 1.0`, and assert `footstep_frame` fired exactly twice; play `attack_light_1` and assert `swing_frame` fired once and `hitbox_open_frame`/`hitbox_close_frame` fired once each.
- `diorama_anim.missing_clip_warns` — request a clip name that does not exist and assert exactly one warning is recorded, and a second identical request records none.
- `diorama_anim.empty_rest_pose_warns` — bind a bare `Node3D` with no pivots and assert a warning is recorded and `is_bound()` is false.
- `diorama_anim.mirror_survives_free` — register a mirror, free it, call `request_locomotion`, `set_blocking`, `play_attack`, and `set_speed_scale`, and assert no error and `_mirrors` is empty.
- `diorama_anim.mirror_speed_scale_matches` — `play_stagger(0.4)` on the body and assert the mirror's `speed_scale` equals the body's.
- `diorama_anim.flinch_retriggers` — `play_flinch()` twice 0.1 s apart and assert the animation restarts from time 0 the second time.
- `diorama_anim.locomotion_scale_in_range` — for each profile and each of `walk`, `jog`, `run`, sweep travel speed across the clip's selection band and assert `speed_scale` stays strictly inside `[0.5, 2.2]`.
- `diorama_anim.attack_cache_bounded` — call `play_attack` with 40 distinct timing triples and assert `_compiled_attacks.size() <= 24` and that the library holds exactly that many `runtime/` animations.
- `diorama_anim.revive_resets_combo` — advance the combo, `play_death()`, `revive()`, and assert the next attack uses `_attack_clips[0]`.
- `diorama_anim.hitbox_signal_wired` — assert `weapon_controller.gd` and `castle_enemy_base.gd` each connect both hitbox signals after setup.

Manual checklist:
- Footstep timing lands on the visual foot contact rather than ahead of or behind it, at all three locomotion speeds.

## Related
- Current behavior: [`../existing_codebase/diorama-anim-controller.md`](../existing_codebase/diorama-anim-controller.md)
- Rig and authoring-format decision: [`character-authoring.md`](character-authoring.md)
- [`diorama-anim-library.md`](diorama-anim-library.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`diorama-viewmodel.md`](diorama-viewmodel.md)
- [`player-anim-director.md`](player-anim-director.md), [`combat-core.md`](combat-core.md), [`hit-hurtboxes.md`](hit-hurtboxes.md), [`vfx-service.md`](vfx-service.md), [`enemies.md`](enemies.md), [`validation-suites.md`](validation-suites.md)
