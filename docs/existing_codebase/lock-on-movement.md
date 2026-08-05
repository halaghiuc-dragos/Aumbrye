# Lock-on movement

`LockOnMovement` is a static-only helper class (no node, no instance) holding the locked-on strafe, orbit-radius correction, and facing math. It is on the live play path: `locomotion.gd` calls it three times per physics frame and `dodge.gd` uses it to pick a dash direction.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/player/lock_on_movement.gd` | `class_name LockOnMovement`, all `static func` |
| `apps/game/client/scripts/player/locomotion.gd` | Caller: `:117-120`, `:126-128`, `:143-149` |
| `apps/game/client/scripts/player/dodge.gd` | Caller: `:114-118` |
| `apps/game/client/scripts/combat/weapon_controller.gd` | Caller: `:496` |

The file has no `extends`; it is a bare `class_name` script used purely as a namespace. The header comment cites decision `DEC-G08`.

## Tuning constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `DEFAULT_ORBIT_RADIUS` | `1.75` | m; used only when the lock-on node has no `get_orbit_radius()` |
| `FACING_SPEED` | `10.0` | default `lerp_angle` rate; `locomotion.gd:128` overrides it with its own `ROTATION_SPEED = 10.0` |

## API

| Function | Behaviour |
|----------|-----------|
| `is_active(lock_on)` | `lock_on is LockOn and lock_on.is_locked` (`:9-10`) |
| `get_target(lock_on)` | `current_target` when active, else `null` |
| `get_orbit_radius(lock_on)` | Duck-typed `get_orbit_radius()` call, else `DEFAULT_ORBIT_RADIUS` |
| `get_move_direction(player, lock_on, input_dir, camera_relative_fn)` | Splits the stick: forward/back stays camera-relative through the callable, left/right becomes a tangent orbit vector. Sums and normalizes (`:25-51`) |
| `get_orbit_strafe_direction(player, stick_x, enemy)` | `Vector3.UP.cross(radial).normalized() * signf(stick_x)`, where `radial` is the flattened player-minus-enemy offset (`:54-61`) |
| `apply_orbit_radius_correction(player, lock_on, input_dir, horizontal_velocity, delta)` | Only when `abs(input_dir.x) >= 0.01`. Adds `-radial * clamp((dist - radius) * 6.0, -3.0, 3.0) * delta` to the velocity (`:64-85`) |
| `world_direction_to_local_facing_y(body, world_direction)` | `atan2(dir.x, dir.z) - body.rotation.y`. The `+basis.z` forward convention is documented in the comment at `:94` and matches `locomotion.get_facing_direction` (`locomotion.gd:169`) |
| `update_facing_toward_target(facing, target, delta, speed)` | `lerp_angle` of `facing.rotation.y` toward `LockOn.get_target_aim_point(target)` flattened (`:100-115`) |

## Behaviour while locked on

1. `locomotion.gd:143-149` replaces the camera-relative direction with `get_move_direction`, so `A`/`D` orbit the target instead of moving relative to the camera.
2. `locomotion.gd:117-120` adds the radius correction, pulling the player toward a 1.75 m ring while strafing. Proportional gain `6.0`, clamped to `+/-3.0` m/s.
3. `locomotion.gd:126-128` replaces movement-driven facing with target-driven facing, so the player always faces the target regardless of the stick.

## Contracts

- Consumers must be `Node3D`s; `get_orbit_strafe_direction` and `apply_orbit_radius_correction` read `global_position` on both player and target.
- `world_direction_to_local_facing_y` assumes the visual forward is `+basis.z` and that the yaw is applied to a child node while the body's own `rotation.y` stays at whatever the caller has. Anything that rotates the body itself must keep `body.rotation.y` consistent.
- `update_facing_toward_target` depends on `LockOn.get_target_aim_point` being static (`lock_on.gd:340`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Tangential strafe on the horizontal axis | IMPLEMENTED | `lock_on_movement.gd:54-61` |
| Orbit radius correction | IMPLEMENTED | `lock_on_movement.gd:64-85` |
| Target-facing rotation | IMPLEMENTED | `lock_on_movement.gd:100-115` |
| Locked dash direction | IMPLEMENTED | `dodge.gd:114-122`, including the backstep fallback with no stick input |
| Speed parity between strafe and forward run | BROKEN | `locomotion.gd:103` uses the same `WALK_SPEED`/`SPRINT_SPEED` for every direction. A locked-on player strafes and backpedals at 4.5 m/s walking and 7.0 m/s sprinting, identical to running forward |
| Sprint while locked on | PARTIAL | `sprint` is not gated by lock-on, so the player can orbit a boss at 7.0 m/s (`locomotion.gd:96`, `:103`) |
| Orbit correction while moving forward or back | ABSENT | `apply_orbit_radius_correction` returns unchanged when `abs(input_dir.x) < 0.01` (`:71-72`), so approach and retreat have no radius influence at all |
| Diagonal normalization bias | PARTIAL | Forward/back and strafe are summed then normalized (`:51`), so a diagonal input yields a direction that is neither purely tangential nor purely radial and the orbit ring is only held on pure strafe |
| Strafe animation | ABSENT | `PlayerAnimDirector.update_locomotion` receives only speed magnitude and picks `walk`/`run` (`player_anim_director.gd:155-161`); there are no `walk_l`/`walk_r`/`walk_b` clips in `diorama_anim_library.gd`, so a left strafe plays a forward walk cycle |
| Facing during attacks while locked on | PARTIAL | `locomotion.gd:126-128` runs the lock-on facing branch before the `attacking` check at `:129`, so the rig keeps turning toward the target during an attack's startup and active frames, bypassing the `ATTACK_ROT_CAP_MULT = 0.15` cap that applies when unlocked (`weapon_controller.gd:232-235`) |
| Dedicated validation coverage | ABSENT | No suite under `apps/game/client/scripts/validation/suites/` references `LockOnMovement`; `lock_on_suite.gd` covers acquisition only |

## Related
- Improvement plan: [`../actual_improvements/lock-on-movement.md`](../actual_improvements/lock-on-movement.md)
- [`lock-on.md`](lock-on.md), [`lock-on-camera.md`](lock-on-camera.md), [`locomotion.md`](locomotion.md), [`dodge.md`](dodge.md), [`player-anim-director.md`](player-anim-director.md)
