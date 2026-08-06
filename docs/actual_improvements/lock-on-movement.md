# Lock-on movement — improvement plan

## Status: FINISHED

## Current state

`LockOnMovement` (`apps/game/client/scripts/player/lock_on_movement.gd`) is a static-only helper: it converts stick input into a tangential strafe around the target, applies a spring correction toward `ORBIT_RADIUS = 1.75` m, converts world directions into `Facing`-local yaw, and rotates `Facing` toward the aim point at `FACING_SPEED = 10.0`. See [`../existing_codebase/lock-on-movement.md`](../existing_codebase/lock-on-movement.md).

The maths is correct and cleanly separated. What is missing is that locked movement is not actually different from free movement in any way the player can see or feel: the same speed in every direction, the same forward-run animation while strafing, and the radius spring pulls the player toward the enemy whenever they try to back off diagonally.

## Gaps

| ID | Sev | Gap | Evidence | Resolution |
|----|-----|-----|----------|------------|
| LKM-01 | P0 | The radius spring fights deliberate retreat. `apply_orbit_radius_correction` runs on any input with `absf(input_dir.x) >= 0.01`, so a back-and-left retreat is pulled inward at up to `3.0` m/s toward the `1.75` m radius while the player is trying to disengage | `lock_on_movement.gd:71-85` | **FINISHED** — correction gated on strafe dominance, deadband, and outward scale (`lock_on_movement.gd`) |
| LKM-02 | P0 | Locked strafing plays the forward run cycle. The helper produces a world direction and `locomotion.gd` passes only a speed magnitude to the animation director, so a circling player moon-walks | `apps/game/client/scripts/player/locomotion.gd:135-141`, `apps/game/client/scripts/player/player_anim_director.gd:155-161` | **FINISHED** — `locomotion.gd` passes `Facing`-local direction; `player_anim_director.gd` selects `walk_l`/`walk_r`/`walk_b` |
| LKM-03 | P1 | No speed differentiation while locked. Strafe and backpedal use `WALK_SPEED = 4.5` / `SPRINT_SPEED = 7.0` exactly as forward running, so orbiting a boss is as fast as charging it | `locomotion.gd:96-110` | **FINISHED** — locked speed table (`LOCKED_SPEED_*`) and sprint breaks lock |
| LKM-04 | P1 | `ORBIT_RADIUS` is one global constant shared by every enemy size. A `1.75` m orbit around a boss whose collision radius is larger than that puts the player inside the target | `lock_on_movement.gd:5`, `apps/game/client/scripts/camera/lock_on.gd:5`, `:72-73` | **FINISHED** — `get_lock_orbit_radius()` on `castle_enemy_base.gd`, threaded through `get_orbit_radius(lock_on, target)` |
| LKM-05 | P1 | The strafe direction is quantized by `signf(stick_x)`, discarding analog magnitude, so a 20 percent stick tilt orbits at full speed | `lock_on_movement.gd:61` | **FINISHED** — raw axis with `ORBIT_INPUT_DEADZONE` |
| LKM-06 | P1 | Diagonal input is normalized after combining, so pure forward and forward-plus-strafe both move at full speed but along different arcs; there is no explicit orbit-versus-approach blend and no dead zone between them | `lock_on_movement.gd:45-51` | **FINISHED** — analog blend with radial-forward approach |
| LKM-07 | P2 | `FACING_SPEED = 10.0` is a fixed lerp rate, so facing snap is frame-rate-shaped and identical for a 5 deg correction and a 170 deg turn; there is no maximum turn rate in degrees per second | `lock_on_movement.gd:6`, `:115` | **FINISHED** — `FACING_TURN_RATE_DEG` / `FACING_SNAP_DEG` clamped turn rate |
| LKM-08 | P2 | The correction gain `6.0` and clamp `3.0` are inline literals with no names, so the orbit spring cannot be tuned or documented | `lock_on_movement.gd:84` | **FINISHED** — `ORBIT_CORRECTION_GAIN` / `ORBIT_CORRECTION_CLAMP` named constants |
| LKM-09 | P2 | No dodge integration. A locked dodge uses the same direction pipeline, so there is no dedicated sidestep or backstep flavour and the orbit correction still applies mid-dash | `apps/game/client/scripts/player/dodge.gd` dash direction path | **FINISHED** — `get_locked_dodge_direction()` in `dodge.gd`; orbit correction skipped while dashing |

## Target design

**Retreat must win.** Gate the radius correction on intent rather than on the presence of any horizontal input:

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `ORBIT_CORRECTION_GAIN` | `6.0` | spring stiffness, unchanged, now named |
| `ORBIT_CORRECTION_CLAMP` | `3.0` m/s | maximum correction speed, unchanged, now named |
| `ORBIT_CORRECTION_DEADBAND` | `0.35` m | radius error below which no correction is applied |
| `ORBIT_STRAFE_DOMINANCE` | `0.7` | correction runs only when `absf(input_dir.x)` exceeds this fraction of the input magnitude |
| `ORBIT_CORRECTION_OUTWARD_SCALE` | `0.25` | outward correction is quartered, so being pushed away from the target is gentle and being pulled in is firm |

Together: the spring only engages during a genuine sideways orbit, never during a retreat or an approach, and never inside a `0.35` m band where it would jitter.

**Per-target orbit radius.** `get_orbit_radius(lock_on, target)` gains a target argument and reads an optional `get_lock_orbit_radius() -> float` on the target, falling back to `DEFAULT_ORBIT_RADIUS`. Enemy bases derive it from their collision radius:

| Enemy scale | Orbit radius |
|-------------|--------------|
| small (rat, imp) | `1.4` m |
| standard humanoid | `1.75` m |
| large (ogre, knight) | `2.6` m |
| boss | `collision_radius + 1.8` m, minimum `3.5` m |

**Analog orbit with an explicit blend.** Replace `signf(stick_x)` with the raw axis value and blend approach against orbit by input angle rather than by vector addition:

```
orbit_weight   = clamp(absf(input_dir.x), 0.0, 1.0)
approach_weight = clamp(absf(input_dir.y), 0.0, 1.0)
direction = (tangent * input_dir.x + radial_forward * -input_dir.y).normalized()
```

with a `ORBIT_INPUT_DEADZONE = 0.15` below which an axis contributes nothing. `radial_forward` is `-radial`, that is, straight at the target, which makes locked forward motion track the enemy as it moves instead of following the camera. This is the behaviour difference that makes lock-on feel like lock-on.

**Locked movement speed.** Locked movement gets its own scale table, distinct from the free-movement table in [`locomotion.md`](locomotion.md) because the intent differs:

| Named constant | Default | Applies to |
|----------------|---------|------------|
| `LOCKED_SPEED_APPROACH` | `1.0` | moving toward the target |
| `LOCKED_SPEED_ORBIT` | `0.78` | pure strafe |
| `LOCKED_SPEED_RETREAT` | `0.62` | moving away |
| `LOCKED_SPRINT_ALLOWED` | `false` | sprinting breaks the lock instead of speeding up the orbit |

Sprinting while locked calls `LockOn.break_lock()`, which gives the player one clear input to disengage and removes the current oddity of a 7 m/s orbit.

**Directional animation.** `locomotion.gd` passes the `Facing`-local movement direction to `PlayerAnimDirector.update_locomotion`, which selects among `walk`/`walk_b`/`walk_l`/`walk_r` and the `run_*` set (added in [`player-anim-director.md`](player-anim-director.md)) with a `0.12` s crossfade.

**Facing as a turn rate.** Replace the raw lerp with a clamped angular velocity so a large correction takes a predictable time:

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `FACING_TURN_RATE_DEG` | `540.0` deg/s | maximum yaw rate toward the target |
| `FACING_SNAP_DEG` | `1.5` deg | error below which the yaw is set exactly, ending the lerp tail |

A 170 deg correction then completes in `0.31` s regardless of frame rate.

**Locked dodge.** With no directional input while locked, `dodge` becomes a backstep away from the target; with horizontal input it becomes a sidestep along the tangent. The orbit correction is skipped entirely while `Dodge.is_dashing`, so the spring cannot bend a dash.

## Work plan

1. **Name the two literals** and add `ORBIT_CORRECTION_DEADBAND`, `ORBIT_STRAFE_DOMINANCE`, `ORBIT_CORRECTION_OUTWARD_SCALE`; gate the correction accordingly and skip it while dashing. Closes LKM-01, LKM-08, and part of LKM-09.
2. **Add the analog orbit blend** with `ORBIT_INPUT_DEADZONE` and radial-forward approach. Closes LKM-05 and LKM-06.
3. **Add the per-target orbit radius** through `get_lock_orbit_radius()`, implemented on `castle_enemy_base.gd` and the boss base; thread the target argument through `LockOn.get_orbit_radius`. Closes LKM-04.
4. **Add the locked speed table** and make sprint break the lock. Closes LKM-03.
5. **Pass the local movement direction** to the animation director and select the directional clips. Closes LKM-02. Depends on PAD-05 in [`player-anim-director.md`](player-anim-director.md).
6. **Convert facing to a clamped turn rate** with `FACING_TURN_RATE_DEG` and `FACING_SNAP_DEG`. Closes LKM-07.
7. **Add locked backstep and sidestep dodges** in `dodge.gd`, selecting `dash_b`, `dash_l`, `dash_r` from the locked input. Closes LKM-09.

## Data and schema changes

- No JSON or schema change. `get_lock_orbit_radius()` is an optional method on target nodes; absent implementations keep `1.75` m.
- `diorama_anim_library.gd` needs the directional walk and run clips from [`player-anim-director.md`](player-anim-director.md); the six `.res` files are regenerated there.
- No save format change, so no `save_migrator.gd` bump.

## Acceptance criteria

- [x] Holding back-and-left while locked at `1.75` m increases the distance to the target monotonically for 1 s. (LKM-01)
- [x] Strafing left while locked plays a left strafe clip, not the forward run. (LKM-02)
- [x] Orbiting speed is `3.51` m/s against `4.5` m/s approaching, and retreat is `2.79` m/s. (LKM-03)
- [x] Pressing `sprint` while locked breaks the lock instead of raising the orbit speed. (LKM-03)
- [x] Locking a boss with a `3.0` m collision radius orbits at `4.8` m, not `1.75` m. (LKM-04)
- [x] A 20 percent stick tilt orbits at roughly 20 percent of the orbit speed; a 10 percent tilt produces no movement. (LKM-05)
- [x] Locked forward input moves straight at the target even when the camera is 40 deg off axis. (LKM-06)
- [x] A 170 deg facing correction completes in `0.31` s +/- 0.03 s at both 60 and 144 FPS. (LKM-07)
- [x] A locked dodge with no input backsteps away from the target; with left input it sidesteps along the tangent; neither is bent by the orbit spring. (LKM-09)

## Validation

Extend `apps/game/client/scripts/validation/suites/lock_on_suite.gd`:

- `lock_on_movement.retreat_not_corrected` — call `apply_orbit_radius_correction` with `input_dir = Vector2(-0.7, 0.7)` at `1.75` m and assert the returned velocity equals the input velocity exactly.
- `lock_on_movement.orbit_correction_deadband` — at `1.9` m radius error `0.15` m, assert no correction; at `2.4` m, assert an inward correction.
- `lock_on_movement.orbit_correction_outward_scaled` — at `1.2` m, assert the outward correction magnitude is a quarter of the inward correction at the mirrored error.
- `lock_on_movement.analog_orbit_magnitude` — `stick_x = 0.2` yields a direction whose orbit component is `0.2` +/- 0.01; `stick_x = 0.1` yields zero.
- `lock_on_movement.approach_is_radial` — with the camera 40 deg off axis, assert the returned direction dot the radial-toward-target is greater than `0.99`.
- `lock_on_movement.orbit_radius_per_target` — a stub returning `4.8` from `get_lock_orbit_radius()` is respected; a stub without the method yields `1.75`.
- `lock_on_movement.locked_speed_scales` — table-drive approach, orbit, and retreat and assert `1.0`, `0.78`, `0.62`.
- `lock_on_movement.sprint_breaks_lock` — press `sprint` while locked and assert `is_locked` became `false`.
- `lock_on_movement.facing_turn_rate` — set a 170 deg error, step at a fixed 1/60 s for 19 frames, and assert the error is under `FACING_SNAP_DEG`.
- `lock_on_movement.world_direction_to_local_facing_y` — keep the existing round-trip assertion and add a case with the body yawed by `PI / 3`.

## Related
- Existing state: [`../existing_codebase/lock-on-movement.md`](../existing_codebase/lock-on-movement.md)
- [`lock-on.md`](lock-on.md), [`lock-on-camera.md`](lock-on-camera.md), [`locomotion.md`](locomotion.md), [`player-anim-director.md`](player-anim-director.md)
- [`dodge.md`](dodge.md), [`enemies.md`](enemies.md), [`bosses.md`](bosses.md), [`stamina-mana.md`](stamina-mana.md)
