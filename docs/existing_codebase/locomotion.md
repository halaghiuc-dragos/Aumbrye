# Locomotion

`locomotion.gd` is the script on the **root `Player` node** of `player.tscn`. It owns ground movement, sprint, facing rotation, the player rig, and the per-frame animation call. It is on the live play path in the hub, castle run, waves run, and the debug arenas. It does not own jump, dodge, attack, or guard input; jump and dodge live in [`dodge.md`](dodge.md).

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/player/locomotion.gd` | The `CharacterBody3D` script |
| `apps/game/client/scenes/player/player.tscn` | Node tree; `script = locomotion.gd` on the root (`:38`), `camera_yaw_path = "CameraPivot"`, `facing_path = "Facing"` (`:39-40`) |
| `apps/game/client/scripts/player/lock_on_movement.gd` | Static strafe/facing helpers, see [`lock-on-movement.md`](lock-on-movement.md) |

## Tuning constants

| Constant | Value | Meaning |
|----------|-------|---------|
| `WALK_SPEED` | `4.5` | m/s |
| `SPRINT_SPEED` | `7.0` | m/s |
| `ACCELERATION` | `12.0` | m/s^2 toward target velocity |
| `DECELERATION` | `14.0` | m/s^2 with no input |
| `SPRINT_STAMINA_DRAIN` | `18.0` | stamina/s while sprinting |
| `ROTATION_SPEED` | `10.0` | `lerp_angle` rate for `Facing` |
| `SPEED_SCALE_FORWARD` | `1.0` | full speed within 45 deg of facing |
| `SPEED_SCALE_STRAFE` | `0.82` | strafe speed scale |
| `SPEED_SCALE_BACK` | `0.65` | backpedal speed scale |
| `SPRINT_MIN_FORWARD_DOT` | `0.5` | sprint denied beyond 60 deg off facing |
| `AIR_ACCELERATION` | `4.0` | airborne horizontal acceleration |
| `AIR_CONTROL_MAX_TURN_DEG` | `55.0` | max airborne turn from takeoff heading |
| `TERMINAL_FALL_SPEED` | `22.0` | m/s downward velocity cap |
| `SPRINT_RAMP_UP` | `0.35` | s to reach full sprint |
| `SPRINT_RAMP_DOWN` | `0.5` | s to leave sprint |

All ground locomotion constants are `const` at `locomotion.gd:3-26`. `WALK_SPEED` and `SPRINT_SPEED` are duplicated as `DioramaAnimController.WALK_REFERENCE_SPEED` / `RUN_REFERENCE_SPEED` (`diorama_anim_controller.gd:34-35`) to scale clip playback.

## How it works

`_ready()` (`locomotion.gd:27`) adds the body to group `player`, caches sibling nodes by name — `Stamina`, `Dodge`, `CombatReactions`, `LockOn`, `WeaponController` — resolves `camera_yaw_path` and `facing_path`, then builds the visual rig:

1. `DioramaCharacterSkin.build_player_body(_facing)` (`locomotion.gd:39`) creates `Facing/DioramaVisual` and hides the blockout capsule via `PixelDioramaStyle.hide_legacy_meshes` (`diorama_character_skin.gd:91`).
2. A `PlayerAnimDirector` is instantiated in code, named `AnimDirector`, and added as a child of the `Player` root (`locomotion.gd:40-42`). It is not present in `player.tscn`.
3. `_anim_director.bind(visual)` compiles or loads the clip library.
4. `_sync_first_person_body_visibility()` asks `CameraPivot/SpringArm3D.is_first_person()` and applies `DioramaCharacterSkin.apply_first_person` (`locomotion.gd:60-65`).

`_physics_process(delta)` (`locomotion.gd:68`) runs in this order:

1. **Movement lock.** If `CombatReactions.is_movement_locked()` or `_landing_lock_timer > 0`, gravity still applies, horizontal velocity decays at `DECELERATION`, `move_and_slide()` runs, the animation is updated, and the frame returns (`locomotion.gd:69-77`).
2. **Dash.** `Dodge.process_dash_physics(delta)` is called; if `Dodge.is_dodging` is true the frame returns after updating animation (`locomotion.gd:79-88`). `dodge.gd` calls `move_and_slide()` itself (`dodge.gd:172`).
3. **Gravity** when not `is_on_floor()` with terminal velocity clamp (`locomotion.gd:90-91`).
4. **Direction.** `PlayerInput.move_vector()` then `_get_move_direction()`, which routes through `LockOnMovement.get_move_direction` while locked on and otherwise through `_get_camera_relative_direction` (`locomotion.gd:142-160`). Camera-relative direction is `Basis(Vector3.UP, _camera_yaw.global_rotation.y) * Vector3(input.x, 0, input.y)`, normalized.
5. **Target speed.** Sprint ramps over `SPRINT_RAMP_UP`/`SPRINT_RAMP_DOWN`. Base speed lerps walk→sprint, then multiplied by `_speed_multiplier`, weapon commit, stamina, `_direction_speed_scale(direction)`, and `StatusController.get_slow_multiplier()` (`locomotion.gd:103-106`). Sprint is denied when movement is more than 60 deg off facing (`SPRINT_MIN_FORWARD_DOT`).
6. **Sprint stamina.** `Stamina.drain(SPRINT_STAMINA_DRAIN * delta)`; on failure the sprint ramp decays toward walk (`locomotion.gd:108-110`).
7. **Velocity blend.** `horizontal.move_toward(direction * target_speed, rate * delta)` with `rate = ACCELERATION` on ground, `AIR_ACCELERATION` airborne, `DECELERATION` with no input. Airborne turns are clamped to `AIR_CONTROL_MAX_TURN_DEG` from takeoff heading.
8. **Orbit correction.** While locked on, `LockOnMovement.apply_orbit_radius_correction` nudges velocity toward the 1.75 m orbit radius (`locomotion.gd:117-120`).
9. **Facing.** While locked on, `LockOnMovement.update_facing_toward_target(_facing, target, delta, ROTATION_SPEED)`. Otherwise, if not attacking and there is input, `_facing.rotation.y` lerps toward the movement direction at `ROTATION_SPEED * rotation_cap_mult`, where `rotation_cap_mult` is `WeaponController.get_rotation_cap_multiplier()` (`0.15` during startup/active/drawing) (`locomotion.gd:125-135`).
10. `move_and_slide()`, then landing detection via `_update_floor_state()` → `_on_landed(fall_height)`, then `_update_footstep_vfx(delta)`, then `_update_character_animation(delta, fall_height)`.

`_update_footstep_vfx()` (`locomotion.gd:181`) is a procedural fallback: it returns early only when `_anim_director.has_footstep_markers()` is true. Otherwise it paces at `VfxService.FOOTSTEP_INTERVAL_WALK = 0.42` and `FOOTSTEP_INTERVAL_SPRINT = 0.28` (`vfx_service.gd:5-6`) above a `0.35` m/s speed floor. Both paths call `play_footstep_effects()`, which resolves surface from a cached downward raycast and drives `VfxService.play_footstep(pos, forward, surface)` plus `AudioDirector.play_sfx("footstep_{surface}", ...)`.

`_update_character_animation()` (`locomotion.gd:200`) forwards `is_on_floor()`, `velocity`, sprint state, and `fall_height` to `PlayerAnimDirector.update_locomotion`.

## Contracts

- Root node must be a `CharacterBody3D`; `collision_layer = 2` (`player_body`) (`player.tscn:37`).
- `floor_max_angle = deg(48)`, `floor_snap_length = 0.35`, `floor_stop_on_slope = true`, `max_slides = 6`, `wall_min_slide_angle = deg(15)` set on the root body (`player.tscn:36-42`).
- Sibling node names read by name: `Stamina`, `Dodge`, `CombatReactions`, `LockOn`, `WeaponController`, `StatusController`, `CameraPivot/SpringArm3D`.
- Child `Facing` is the yaw node for the visual, weapon pivot, and hitbox. The body itself never rotates.
- Creates and owns the `AnimDirector` child node; `player_combat_reactions.gd:81` and `hit_feedback.gd:34` look it up by that name.
- Public API: `set_speed_multiplier(float)`, `get_current_speed_breakdown() -> Dictionary`, `play_footstep_effects()`, `refresh_appearance_visual()`, `get_camera_relative_direction(Vector2) -> Vector3`, `get_facing_direction() -> Vector3`, `get_facing_yaw() -> float`.
- `get_facing_direction()` returns `+basis.z` of `Facing`, not `-basis.z` (`locomotion.gd:167-170`). `LockOnMovement.world_direction_to_local_facing_y` matches that convention (`lock_on_movement.gd:95`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Walk, sprint, acceleration, camera-relative direction | IMPLEMENTED | `locomotion.gd:93-123` |
| Facing rotation and attack rotation cap | IMPLEMENTED | `locomotion.gd:125-135` |
| Lock-on strafe and orbit correction | IMPLEMENTED (see [`lock-on-movement.md`](lock-on-movement.md) for its limits) | `locomotion.gd:117-128` |
| Footstep VFX and SFX | IMPLEMENTED | Animation method tracks via `has_footstep_markers()`; procedural fallback when absent (`locomotion.gd:198-220`, `diorama_anim_controller.gd:113-131`) |
| Equipment/talent move-speed multiplier | IMPLEMENTED | `inventory_service.gd:295-299` via `PlayerControls.resolve_locomotion` |
| Waves move-speed multiplier | IMPLEMENTED | `waves_run_service.gd:317-320` calls it on the body |
| Directional speed and sprint gating | IMPLEMENTED | `_direction_speed_scale`, `SPRINT_MIN_FORWARD_DOT` (`locomotion.gd:9-12`, `:175-195`) |
| Air control and terminal velocity | IMPLEMENTED | `AIR_ACCELERATION`, `_clamp_airborne_turn` (`locomotion.gd:13-15`, `:197-205`) |
| Landing weight (clip, lock, dip, damage) | IMPLEMENTED | `_on_landed`, `land_hard` clip, `orbit_camera.apply_landing_dip` |
| Movement input while meta UI open | IMPLEMENTED | `PlayerInput.move_vector()` (`player_input.gd:11-14`) |
| Slope/step handling | IMPLEMENTED | `player.tscn` body properties |
| Sprint ramp | IMPLEMENTED | `_sprint_blend` (`locomotion.gd:22-23`, `:119-127`) |
| Speed breakdown query | IMPLEMENTED | `get_current_speed_breakdown()`; debug overlay reads it |
| Surface-aware footsteps | IMPLEMENTED | `_resolve_footstep_surface`, floor `surface` metadata |
| Jump | Owned elsewhere | `jump` is read only by `dodge.gd:84`; `JUMP_VELOCITY = 4.8`, `COYOTE_TIME = 0.12`, `JUMP_BUFFER_TIME = 0.15`, `JUMP_STAMINA_COST = 18.0` (`dodge.gd:5-13`) |

## Related
- Improvement plan: [`../actual_improvements/locomotion.md`](../actual_improvements/locomotion.md) — **FINISHED**
- [`player-anim-director.md`](player-anim-director.md), [`lock-on-movement.md`](lock-on-movement.md), [`orbit-camera.md`](orbit-camera.md), [`dodge.md`](dodge.md), [`stamina-mana.md`](stamina-mana.md), [`player-controls.md`](player-controls.md)
