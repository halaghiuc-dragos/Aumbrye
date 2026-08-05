# Lock-on — improvement plan

## Current state

`LockOn` (`apps/game/client/scripts/camera/lock_on.gd`) acquires a target inside an `18.0` m range and a `75` deg cone, retains it through a `0.75` s line-of-sight grace, advances to the next enemy when the current one dies, and switches horizontally and vertically on stick flicks and the mouse wheel. The acquisition ordering, the AABB-based aim point, and the defeated-enemy raycast exclusions are all well built. See [`../existing_codebase/lock-on.md`](../existing_codebase/lock-on.md).

The main structural problem is that the node runs with `PROCESS_MODE_ALWAYS` and only guards `get_tree().paused` in `_unhandled_input`, not in `_physics_process`. So while the game is paused, the lock still tracks, still switches target on stick input read straight from `Input`, and still drives the camera. Beyond that, acquisition ignores enemy threat entirely, break has no hysteresis, and nothing on screen marks the locked target.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| LKO-01 | P0 | Lock-on keeps running while paused. `process_mode` is `PROCESS_MODE_ALWAYS` and `_physics_process` has no `paused` guard, so `_handle_target_switch` polls `Input.get_vector("look_left", ...)` and `_update_lock_camera` moves the camera behind an open pause or settings menu | `lock_on.gd:33`, `:59-69`, `:194` |
| LKO-02 | P0 | No on-screen lock indicator. `lock_changed` is consumed to gate camera and movement behaviour, but nothing draws a reticle at the target aim point, so the player cannot tell which enemy is locked when two overlap | grep of `lock_changed` finds `lock_on.gd:15`, `:107`, `:118`, `apps/game/client/scripts/camera/orbit_camera.gd` connection and `apps/game/client/scripts/player/locomotion.gd`; no UI listener |
| LKO-03 | P1 | Break is a hard threshold with no hysteresis. The lock drops the frame `distance > 18.0` and re-acquisition requires a fresh button press, so hovering at the range edge flickers between locked and free | `lock_on.gd:149-152` |
| LKO-04 | P1 | Acquisition ignores threat. `_find_best_target` scores by planar distance and then cone angle only, so a distant boss winding up an attack loses to a nearer idle rat | `lock_on.gd:290-293` |
| LKO-05 | P1 | Mouse-wheel target switching steals the wheel from camera zoom whenever a lock is held, and `zoom_in`/`zoom_out` are wheel-bound. Locked players cannot zoom at all | `lock_on.gd:50-56`, `apps/game/client/project.godot` zoom bindings, `orbit_camera.gd` zoom gate |
| LKO-06 | P1 | Two different range measurements. Acquisition uses planar distance with `offset.y = 0.0` (`:277-279`) while retention uses full 3D `distance_to` (`:149`), so a target 6 m above at 17 m planar is acquirable and then instantly dropped | `lock_on.gd:277-280`, `:149-152` |
| LKO-07 | P2 | `_switch_target_vertical` picks the nearest target in the vertical direction with no horizontal or distance weighting, so a flick up can select an enemy behind the player | `lock_on.gd:204-224` |
| LKO-08 | P2 | Line of sight is a single ray from `player + 1.0 m` to the aim point on mask `1`, so a thin pillar or a railing at chest height breaks the lock even though the target is plainly visible | `lock_on.gd:303-306` |
| LKO-09 | P2 | Membership in the `lockable` group is the only filter. A friendly NPC or a destructible added to that group becomes lockable, and there is no per-target opt-out | `lock_on.gd:323-330` |
| LKO-10 | P2 | Switch cooldown `0.15` s is shared by stick, wheel, and vertical switching, so a fast mouse-wheel flick through five enemies takes `0.75` s | `lock_on.gd:7`, `:223`, `:252` |

## Target design

**Pause correctness.** Keep `PROCESS_MODE_ALWAYS` (needed so the node can still receive the unpause frame cleanly) and add one guard at the top of `_physics_process`:

```gdscript
if get_tree().paused or PlayerInput.is_gameplay_blocked():
	return
```

`PlayerInput.is_gameplay_blocked()` is the shared helper introduced in [`player-controls.md`](player-controls.md), so lock-on, locomotion, and dodge answer the question the same way. The stick poll in `_handle_target_switch` also moves behind it.

**Lock reticle.** New `apps/game/client/scenes/ui/lock_on_reticle.tscn` plus `scripts/ui/lock_on_reticle.gd` on the existing HUD `CanvasLayer`:

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `RETICLE_SIZE` | `18` px | base diameter, unscaled pixels |
| `RETICLE_ACQUIRE_SCALE` | `2.2` | starting scale of the acquire pop |
| `RETICLE_ACQUIRE_TIME` | `0.14` s | pop settle to `1.0` |
| `RETICLE_COLOR` | `Color(0.94, 0.86, 0.55)` | idle |
| `RETICLE_COLOR_DANGER` | `Color(0.95, 0.36, 0.30)` | while the target's telegraph is active |
| `RETICLE_OFFSCREEN_MARGIN` | `24` px | clamp distance when the target is behind the camera |
| `RETICLE_LOS_ALPHA` | `0.35` | alpha while inside the `0.75` s line-of-sight grace |

Position comes from `camera.unproject_position(LockOn.get_target_aim_point(target))` each frame, snapped to whole pixels so it does not shimmer against the pixel pipeline. It shows a small left and right chevron when more than one lockable target is in range, which teaches the switch input without a tutorial.

**Hysteresis and unified range.** One planar measurement everywhere, with separate acquire and break radii:

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `LOCK_ACQUIRE_RANGE` | `18.0` m | planar distance for `_find_best_target` |
| `LOCK_BREAK_RANGE` | `22.0` m | planar distance before the lock drops |
| `LOCK_BREAK_GRACE` | `0.4` s | time beyond `LOCK_BREAK_RANGE` before dropping, so a dash out and back keeps the lock |
| `LOCK_VERTICAL_LIMIT` | `8.0` m | absolute vertical difference that disqualifies a target in both paths |

`_update_lock` uses the same `offset.y = 0.0` planar form as `_find_best_target`, plus the explicit vertical limit, so the two can no longer disagree.

**Threat-weighted acquisition.** Replace the two-key comparison with a single score, lowest wins:

```
score = distance_weight * (distance / LOCK_ACQUIRE_RANGE)
      + angle_weight    * (angle_deg / LOCK_PICK_CONE_DEG)
      - threat_weight   * threat
```

| Named constant | Default |
|----------------|---------|
| `SCORE_DISTANCE_WEIGHT` | `1.0` |
| `SCORE_ANGLE_WEIGHT` | `0.75` |
| `SCORE_THREAT_WEIGHT` | `0.5` |

`threat` is `0.0` to `1.0` from a new optional `get_lock_threat() -> float` on the target: `1.0` while a telegraph is active, `0.6` while attacking, `0.3` while aggroed, `0.0` idle. Targets without the method return `0.0`, so nothing regresses before enemies implement it. Angle weighting stays because a screen-centre bias is what makes acquisition feel deliberate.

**Wheel versus zoom.** The mouse wheel keeps switching targets while locked, but zoom stops being wheel-only: add `zoom_in` on `Page Up` / `zoom_out` on `Page Down` (see the input map in [`player-controls.md`](player-controls.md)) and, more importantly, do not consume the wheel when only one lockable target is in range. `_switch_target` already early-returns on `candidates.size() < 2`; the `set_input_as_handled()` call must move inside the branch that actually switched.

**Switch quality.** `_switch_target_vertical` gains the same score form, weighting the vertical delta at `1.0` and the horizontal delta at `0.4` so an upward flick prefers something roughly ahead. Separate cooldowns: `SWITCH_COOLDOWN_STICK = 0.15` s (debounces an analog stick) and `SWITCH_COOLDOWN_WHEEL = 0.05` s (a wheel click is already discrete).

**Better line of sight.** Three rays instead of one, from `player + 1.0 m` to the aim point, the aim point plus `Vector3.UP * 0.4`, and the aim point minus `Vector3.UP * 0.4`. Visible if any ray is clear. Same mask, same exclusions, negligible cost at one target.

**Explicit lockable contract.** A target is lockable when it is in the `lockable` group, is not defeated, and either has no `get_lock_priority()` method or returns a non-negative value from it. Returning `-1.0` opts a node out permanently, which gives friendly NPCs and destructibles a way to share the group without becoming targets.

## Work plan

1. **Add the pause and UI guard** to `_physics_process` and `_handle_target_switch`. Closes LKO-01. Depends on `PlayerInput` from [`player-controls.md`](player-controls.md).
2. **Unify the range measurement** and add `LOCK_ACQUIRE_RANGE`, `LOCK_BREAK_RANGE`, `LOCK_BREAK_GRACE`, `LOCK_VERTICAL_LIMIT`. Closes LKO-03 and LKO-06.
3. **Add the scored acquisition** with the three weights and the optional `get_lock_threat()`; implement the method on `castle_enemy_base.gd` and the boss base. Closes LKO-04.
4. **Build the reticle** scene and script, connect it to `lock_changed`, and add the multi-target chevrons. Closes LKO-02.
5. **Fix wheel consumption** so it is only marked handled when a switch happened, and add the keyboard zoom bindings. Closes LKO-05.
6. **Rework vertical switching** with the weighted score and split the cooldowns. Closes LKO-07 and LKO-10.
7. **Add the three-ray line-of-sight test.** Closes LKO-08.
8. **Add the `get_lock_priority()` opt-out** to `_get_lockable_targets`. Closes LKO-09.

## Data and schema changes

- No JSON or schema change. Threat and priority are optional GDScript methods on target nodes, so absent implementations behave exactly as today.
- New UI scene `apps/game/client/scenes/ui/lock_on_reticle.tscn` and script `apps/game/client/scripts/ui/lock_on_reticle.gd`, registered on the existing combat HUD `CanvasLayer`.
- No save format change, so no `save_migrator.gd` bump.

## Acceptance criteria

- [ ] With the pause menu open, stick input does not change the locked target and the camera does not move. (LKO-01)
- [ ] A reticle appears on the locked enemy within `0.14` s of acquiring, follows the aim point, fades to `0.35` alpha during the line-of-sight grace, and shows chevrons when a second target is in range. (LKO-02)
- [ ] Standing at `19.0` m from a locked target keeps the lock; crossing `22.0` m for more than `0.4` s drops it. (LKO-03)
- [ ] Given a telegraphing enemy at `12` m and an idle enemy at `6` m, both inside the cone, the telegraphing one is acquired. (LKO-04)
- [ ] While locked with only one target in range, the mouse wheel still zooms. (LKO-05)
- [ ] A target at `17` m planar and `6` m above is not acquired at all rather than being acquired and dropped on the next frame. (LKO-06)
- [ ] An upward flick with one candidate above and ahead and one above and behind selects the one ahead. (LKO-07)
- [ ] A locked target standing behind a `0.2` m railing at chest height stays locked. (LKO-08)
- [ ] A node in the `lockable` group returning `-1.0` from `get_lock_priority()` is never acquired. (LKO-09)
- [ ] Five wheel clicks cycle five targets in under `0.30` s. (LKO-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/lock_on_suite.gd`:

- `lock_on.paused_does_not_track` — lock a target, set `get_tree().paused = true`, run 10 physics frames with a synthetic stick vector, and assert `current_target` and the camera yaw are unchanged.
- `lock_on.range_hysteresis` — place a target at `19.0` m and assert the lock holds; move to `22.5` m, advance `0.5` s, and assert it broke.
- `lock_on.acquire_and_break_use_planar_distance` — place a target at `17.0` m planar and `6.0` m above and assert `_find_best_target` returns `null`.
- `lock_on.threat_weighted_acquisition` — two stubs with `get_lock_threat()` returning `1.0` at `12` m and `0.0` at `6` m; assert the threatening one wins.
- `lock_on.threat_absent_is_backward_compatible` — two stubs without the method; assert the nearer one wins.
- `lock_on.wheel_not_consumed_with_single_target` — one lockable target, feed a wheel event, and assert the viewport input was not marked handled.
- `lock_on.vertical_switch_prefers_forward` — three stubs and assert the forward one is chosen.
- `lock_on.line_of_sight_multi_ray` — place a thin occluder at the centre ray height and assert visibility still returns `true`.
- `lock_on.lock_priority_opt_out` — a `lockable` stub returning `-1.0` is excluded from `_get_lockable_targets`.
- `lock_on.reticle_follows_target` — instance the reticle, lock a target, and assert its position equals `camera.unproject_position(aim)` rounded to whole pixels.

Remove or implement the stale assertion: `lock_on_suite.gd` currently asserts `orbit_camera.gd` has a `_update_lock_on_frame_fp` method that does not exist. See LKC-02 in [`lock-on-camera.md`](lock-on-camera.md).

## Related
- Existing state: [`../existing_codebase/lock-on.md`](../existing_codebase/lock-on.md)
- [`lock-on-camera.md`](lock-on-camera.md), [`lock-on-movement.md`](lock-on-movement.md), [`orbit-camera.md`](orbit-camera.md), [`player-controls.md`](player-controls.md), [`locomotion.md`](locomotion.md)
- [`enemies.md`](enemies.md), [`bosses.md`](bosses.md), [`ui/combat_hud.md`](ui/combat_hud.md), [`ui/enemy_health_bar.md`](ui/enemy_health_bar.md), [`validation-suites.md`](validation-suites.md)
