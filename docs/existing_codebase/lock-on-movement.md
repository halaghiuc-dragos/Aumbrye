# Lock-on movement

`LockOnMovement` is a static-only helper class (no node, no instance) holding the locked-on strafe, orbit-radius correction, and facing math. It is on the live play path: `locomotion.gd` calls it three times per physics frame and `dodge.gd` uses it to pick a dash direction.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/player/lock_on_movement.gd` | `class_name LockOnMovement`, all `static func` |
| `apps/game/client/scripts/player/locomotion.gd` | Caller: locked speed, correction, facing, animation local dir |
| `apps/game/client/scripts/player/dodge.gd` | Caller: `get_locked_dodge_direction` |
| `apps/game/client/scripts/player/player_anim_director.gd` | Directional `walk_*` / `run_*` clip selection |
| `apps/game/client/scripts/enemies/castle_enemy_base.gd` | `get_lock_orbit_radius()` per enemy scale |
| `apps/game/client/scripts/camera/lock_on.gd` | Delegates `get_orbit_radius()` to target |
| `apps/game/client/scripts/combat/weapon_controller.gd` | Caller: `world_direction_to_local_facing_y` |

The file has no `extends`; it is a bare `class_name` script used purely as a namespace. The header comment cites decision `DEC-G08`.

## Tuning constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `DEFAULT_ORBIT_RADIUS` | `1.75` | m; fallback when target has no `get_lock_orbit_radius()` |
| `ORBIT_RADIUS_SMALL` / `STANDARD` / `LARGE` | `1.4` / `1.75` / `2.6` | per-enemy orbit radii from collision size |
| `ORBIT_RADIUS_BOSS_PAD` / `BOSS_MIN` | `1.8` / `3.5` | boss orbit = `collision_radius + pad`, minimum `3.5` m |
| `ORBIT_CORRECTION_GAIN` / `CLAMP` | `6.0` / `3.0` | spring stiffness and max correction m/s |
| `ORBIT_CORRECTION_DEADBAND` | `0.35` | m; no correction inside this radius error |
| `ORBIT_STRAFE_DOMINANCE` | `0.7` | correction only when strafe exceeds this fraction of input magnitude |
| `ORBIT_CORRECTION_OUTWARD_SCALE` | `0.25` | outward correction is quarter strength |
| `ORBIT_INPUT_DEADZONE` | `0.15` | stick axis below this contributes nothing |
| `LOCKED_SPEED_APPROACH` / `ORBIT` / `RETREAT` | `1.0` / `0.78` / `0.62` | locked movement speed multipliers |
| `LOCKED_SPRINT_ALLOWED` | `false` | sprint breaks lock instead of speeding orbit |
| `FACING_TURN_RATE_DEG` / `FACING_SNAP_DEG` | `540.0` / `1.5` | clamped yaw rate toward target |

## API

| Function | Behaviour |
|----------|-----------|
| `is_active(lock_on)` | `lock_on is LockOn and lock_on.is_locked` |
| `get_target(lock_on)` | `current_target` when active, else `null` |
| `get_orbit_radius(lock_on, target)` | Duck-typed `get_lock_orbit_radius()` on target, else `DEFAULT_ORBIT_RADIUS` |
| `get_move_direction(player, lock_on, input_dir, camera_relative_fn)` | Analog tangent + radial-forward blend with input deadzone |
| `get_orbit_strafe_direction(player, stick_x, enemy)` | Tangent orbit vector scaled by raw stick axis |
| `get_locked_dodge_direction(player, lock_on, input_dir)` | Radial backstep or tangent sidestep while locked |
| `get_locked_speed_scale(input_dir)` | Blended approach / orbit / retreat multiplier |
| `break_lock_on_sprint(lock_on, sprint_requested)` | Breaks lock when sprint pressed; returns effective sprint state |
| `apply_orbit_radius_correction(..., skip_correction)` | Strafe-gated spring with deadband and outward scale |
| `world_direction_to_local_facing_y(body, world_direction)` | `atan2(dir.x, dir.z) - body.rotation.y` |
| `world_velocity_to_local_facing(body, velocity)` | Facing-local movement direction for animation |
| `update_facing_toward_target(facing, target, delta)` | Clamped turn rate toward `LockOn.get_target_aim_point` |

## Behaviour while locked on

1. `locomotion.gd` replaces camera-relative direction with `get_move_direction`, so `A`/`D` orbit the target and `W`/`S` approach/retreat radially.
2. `locomotion.gd` applies strafe-gated radius correction toward the per-target orbit ring.
3. `locomotion.gd` uses `get_locked_speed_scale` instead of free-movement directional speed.
4. Sprint while locked calls `LockOn.break_lock()`.
5. `locomotion.gd` drives target-facing via clamped turn rate.
6. `locomotion.gd` passes `Facing`-local velocity to `PlayerAnimDirector` for `walk_l`/`walk_r`/`walk_b` clips.
7. `dodge.gd` uses `get_locked_dodge_direction`; orbit correction is skipped while dashing.

## Contracts

- Consumers must be `Node3D`s; strafe and correction read `global_position` on both player and target.
- `world_direction_to_local_facing_y` assumes the visual forward is `+basis.z` and that yaw is applied to a child `Facing` node.
- `update_facing_toward_target` depends on `LockOn.get_target_aim_point` being static.
- Targets may implement `get_lock_orbit_radius() -> float`; `castle_enemy_base.gd` derives it from collision radius and enemy scale.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Tangential strafe on the horizontal axis | IMPLEMENTED | `lock_on_movement.gd` analog tangent blend |
| Orbit radius correction | IMPLEMENTED | Strafe-gated spring with deadband and outward scale |
| Per-target orbit radius | IMPLEMENTED | `castle_enemy_base.gd:get_lock_orbit_radius` |
| Locked speed differentiation | IMPLEMENTED | `LOCKED_SPEED_*` table in `locomotion.gd` |
| Sprint breaks lock | IMPLEMENTED | `break_lock_on_sprint` in `locomotion.gd` |
| Directional strafe animation | IMPLEMENTED | `player_anim_director.gd:_locomotion_clip_for` |
| Clamped facing turn rate | IMPLEMENTED | `FACING_TURN_RATE_DEG` in `update_facing_toward_target` |
| Locked dodge backstep / sidestep | IMPLEMENTED | `get_locked_dodge_direction` in `dodge.gd` |
| Dedicated validation coverage | IMPLEMENTED | `lock_on_suite.gd` movement tests |

## Related
- Improvement plan: [`../actual_improvements/lock-on-movement.md`](../actual_improvements/lock-on-movement.md) — **FINISHED**
- [`lock-on.md`](lock-on.md), [`lock-on-camera.md`](lock-on-camera.md), [`locomotion.md`](locomotion.md), [`dodge.md`](dodge.md), [`player-anim-director.md`](player-anim-director.md)
