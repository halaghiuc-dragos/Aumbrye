# Locomotion — improvement plan

## Current state

`locomotion.gd` on the root `Player` node moves the body at `WALK_SPEED = 4.5` / `SPRINT_SPEED = 7.0` with `ACCELERATION = 12.0` and `DECELERATION = 14.0`, rotates a child `Facing` node at `ROTATION_SPEED = 10.0`, drains `SPRINT_STAMINA_DRAIN = 18.0`/s, and pushes one animation call per physics frame. See [`../existing_codebase/locomotion.md`](../existing_codebase/locomotion.md).

The core movement is solid. What is broken is everything around the edges: footsteps never play in either the animation path or the fallback path, the equipment move-speed multiplier is dropped, there is no air control or landing weight, and the speed is direction-agnostic so backpedalling is as fast as sprinting forward.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| LOC-01 | P0 | The player emits no footstep VFX or SFX at all. The procedural fallback disables itself as soon as the rig is bound, and the animation marker that is supposed to replace it never exists: the prebuilt library is exported with `events_path = ""` and the runtime path is rejected by an `is_ancestor_of` guard | `locomotion.gd:182`, `apps/game/client/scripts/tools/export_diorama_anim_libraries.gd:81`, `apps/game/client/scripts/art/characters/diorama_anim_library.gd:550`, `apps/game/client/scripts/art/characters/diorama_anim_controller.gd:116` |
| LOC-02 | P0 | Equipment and talent move-speed bonuses never reach the player outside waves mode: `set_speed_multiplier` is called on a `"Locomotion"` child node that does not exist | `apps/game/client/scripts/inventory/inventory_service.gd:206-208`, `apps/game/client/scenes/player/player.tscn:36-38` |
| LOC-03 | P1 | Speed is direction-agnostic. Backpedalling and strafing use the same `4.5` / `7.0` as running forward, and sprint is allowed in every direction | `locomotion.gd:103` |
| LOC-04 | P1 | No air control model. The same `ACCELERATION = 12.0` applies airborne, so the player can fully redirect a jump mid-flight | `locomotion.gd:112-123` |
| LOC-05 | P1 | Landing has no weight. `land` fires as a fixed clip with no fall-height input, no landing speed penalty, and no dust or camera dip | `apps/game/client/scripts/player/player_anim_director.gd:151-153` |
| LOC-06 | P1 | Movement continues while a meta UI is open because `Input.get_vector` is polled unconditionally | `locomotion.gd:93` |
| LOC-07 | P2 | `CharacterBody3D` movement properties are left at engine defaults — `floor_max_angle`, `floor_snap_length`, `max_slides`, `floor_stop_on_slope` are not set in `player.tscn`, so the player slides on shallow ramps and can pop off small steps | `apps/game/client/scenes/player/player.tscn:36-40` |
| LOC-08 | P2 | Sprint has no ramp: the target speed jumps from `4.5` to `7.0` the frame `sprint` goes down, and drops back the frame stamina fails, which reads as a stutter rather than a burst | `locomotion.gd:96`, `:103`, `:108-110` |
| LOC-09 | P2 | `_speed_multiplier` has no source of truth. It is clamped to a `0.1` floor with no ceiling, and status slow, weapon commit, and equipment bonus are multiplied in three different places with no single query for "current speed" that the HUD or validation can read | `locomotion.gd:47-48`, `:99-106` |
| LOC-10 | P2 | Footstep surface is ignored: `VfxService.play_footstep` takes only a position and a facing vector, so stone, water, and wood sound and look identical | `apps/game/client/scripts/art/vfx/vfx_service.gd:201` |

## Target design

**Footsteps come from the animation, with a working fallback.** Two fixes, both required:

1. Relax `DioramaAnimController._resolve_events_path` to accept any two nodes in the same tree — `visual.get_path_to(self)` already produces a valid `../../AnimDirector`-style path that `AnimationPlayer` resolves against `root_node`. Keep an `is_inside_tree()` guard on both nodes and return `""` only when the path is empty.
2. Re-export the authored libraries with a real events path. Change `export_diorama_anim_libraries.gd` to pass the canonical runtime path per profile (`"../../AnimDirector"` for the player rig, `"../../AnimController"` for enemies) and add that string to `REST_POSES` as an `"events_path"` key so the exporter and the runtime agree by construction.

Then keep the procedural fallback alive as a safety net instead of disabling it: `_update_footstep_vfx` returns early only when the bound library actually contains a footstep marker, queried through a new `DioramaAnimController.has_footstep_markers() -> bool`.

Footstep cadence stays at `FOOTSTEP_INTERVAL_WALK = 0.42` s and `FOOTSTEP_INTERVAL_SPRINT = 0.28` s in the fallback; in the animation path the two `FOOTSTEP` keys per cycle land at `0.18` s and `0.58` s of the `0.8` s walk and `0.10` s and `0.38` s of the `0.56` s run (`diorama_anim_library.gd:68`, `:89`), which at `speed_scale = 1.0` gives the same 0.4 s and 0.28 s spacing.

**Surface-aware footsteps.** `VfxService.play_footstep(pos, forward, surface: StringName = &"stone")`. Surface is resolved once per footstep by `locomotion.gd` from a downward `PhysicsRayQueryParameters3D` of length `0.4` on mask `1`, reading `collider.get_meta("surface", "stone")`. New `AudioDirector.SFX_PROFILES` entries: `footstep_stone` `{freq 80.0, duration 0.05}`, `footstep_wood` `{freq 120.0, duration 0.05}`, `footstep_water` `{freq 200.0, duration 0.09}`, `footstep_snow` `{freq 60.0, duration 0.07}`. The raycast runs at most once every `0.25` s and caches its result.

**Directional speed.** Replace the single `target_speed` with a per-direction cap applied after the camera-relative direction is known:

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `SPEED_SCALE_FORWARD` | `1.0` | full speed within 45 deg of the facing forward |
| `SPEED_SCALE_STRAFE` | `0.82` | 45-135 deg |
| `SPEED_SCALE_BACK` | `0.65` | beyond 135 deg |
| `SPRINT_MIN_FORWARD_DOT` | `0.5` | sprint is denied when the movement direction is more than 60 deg off the facing forward |

The scale is a `smoothstep` blend across the two boundaries, not a hard switch, so a circling input does not step. Backpedal walk becomes `2.93` m/s and strafe walk `3.69` m/s.

**Air control.** New constants: `AIR_ACCELERATION = 4.0` (one third of ground), `AIR_CONTROL_MAX_TURN_DEG = 55.0` measured against the horizontal velocity at takeoff, `TERMINAL_FALL_SPEED = 22.0` m/s clamp on `velocity.y`. Airborne input can trim the trajectory but not reverse it.

**Landing.** Track `_fall_start_y` on the frame the body leaves the floor and compute `fall_height` on the frame it lands:

| Named constant | Default | Effect at landing |
|----------------|---------|-------------------|
| `LAND_SOFT_HEIGHT` | `1.2` m | below this: no clip, no penalty, one footstep burst |
| `LAND_HARD_HEIGHT` | `3.5` m | above this: `land` clip, `LAND_HARD_LOCK = 0.18` s movement lock, camera dip |
| `LAND_DAMAGE_HEIGHT` | `7.0` m | above this: `Health.take_damage` of `4.0` per metre past the threshold |
| `LAND_SPEED_PENALTY` | `0.45` | horizontal velocity multiplier applied for `0.18` s on a hard landing |
| `LAND_CAMERA_DIP` | `0.12` m over `0.16` s | applied by `orbit_camera` through a new `apply_landing_dip(strength)` |

`PlayerAnimDirector.update_locomotion` gains a `fall_height: float` argument so it can pick between a 0.26 s `land` and a new 0.42 s `land_hard` clip.

**Single speed query.** Add `locomotion.get_current_speed_breakdown() -> Dictionary` returning `{"base": float, "equipment": float, "status": float, "weapon": float, "direction": float, "final": float}`. The HUD and the validation suite read it instead of recomputing.

## Work plan

1. **Fix the events path.** Relax `diorama_anim_controller.gd:111-121`; add `"events_path"` to each `REST_POSES` entry and pass it at `export_diorama_anim_libraries.gd:81`; re-run the exporter and commit the six `.res` files. Add `has_footstep_markers()` and gate `locomotion.gd:182` on it. Closes LOC-01.
2. **Fix the move-speed multiplier.** Use `PlayerControls.resolve_locomotion(player)` at `inventory_service.gd:206`. Closes LOC-02. Depends on step 1 of [`player-controls.md`](player-controls.md).
3. **Add surface-aware footsteps.** Extend `VfxService.play_footstep` and `AudioDirector.SFX_PROFILES`; add the cached downward probe to `locomotion.gd`; tag floor meshes with `surface` metadata in `floor_shell_builder.gd` and `hub_diorama.gd`. Closes LOC-10.
4. **Add directional speed scaling** with the four constants above and a new `_direction_speed_scale(direction) -> float`. Closes LOC-03.
5. **Add the air model.** `AIR_ACCELERATION`, turn clamp, terminal velocity. Closes LOC-04.
6. **Add landing weight.** Fall-height tracking, the five constants, `land_hard` clip in `diorama_anim_library.gd`, `apply_landing_dip` in `orbit_camera.gd`, and the `fall_height` argument on `update_locomotion`. Closes LOC-05.
7. **Route input through `PlayerInput`** as described in [`player-controls.md`](player-controls.md). Closes LOC-06.
8. **Set the body properties** in `player.tscn`: `floor_max_angle = deg_to_rad(48)`, `floor_snap_length = 0.35`, `floor_stop_on_slope = true`, `max_slides = 6`, `wall_min_slide_angle = deg_to_rad(15)`. Closes LOC-07.
9. **Add the sprint ramp.** `SPRINT_RAMP_UP = 0.35` s and `SPRINT_RAMP_DOWN = 0.5` s applied as a lerp on the sprint contribution rather than a step. Closes LOC-08.
10. **Add `get_current_speed_breakdown()`** and use it in the debug overlay. Closes LOC-09.

## Data and schema changes

- Floor and prop meshes gain an optional `surface` node metadata string (`stone`, `wood`, `water`, `snow`). Default when absent is `stone`, so no content is required up front.
- `content/schemas/` needs no change: the surface tag is authored in scene-building code, not JSON.
- `diorama_anim_library.gd` gains a `land_hard` entry in `CLIPS`; the six `.res` files under `apps/game/client/assets/animations/diorama/` must be regenerated in the same commit.
- No save format change, so no `save_migrator.gd` bump.

## Acceptance criteria

- [ ] Walking in a straight line for 4 s produces at least 9 footstep bursts and 9 footstep SFX, and both land on the same frames as the animation's foot contacts. (LOC-01)
- [ ] `DioramaAnimController.has_footstep_markers()` returns `true` for a bound player rig; with markers forced off, the procedural fallback produces footsteps instead. (LOC-01)
- [ ] An item granting `moveSpeedPercent: 20` raises steady-state walk speed from `4.5` to `5.4` m/s in the hub. (LOC-02)
- [ ] Holding `S` while facing a locked target yields `2.93` m/s walking; `sprint` while doing so does not raise it. (LOC-03)
- [ ] A jump taken at `7.0` m/s forward cannot be reversed: the horizontal velocity direction at landing is within 55 deg of the direction at takeoff. (LOC-04)
- [ ] A 1.0 m drop plays no `land` clip and applies no penalty; a 4.0 m drop plays `land`, dips the camera by `0.12` m, and locks movement for `0.18` s; a 9.0 m drop additionally deals `8.0` damage. (LOC-05)
- [ ] With the inventory open, held movement keys produce zero velocity. (LOC-06)
- [ ] The player walks up a 45 deg ramp without sliding back and does not leave the floor crossing a 0.3 m step. (LOC-07)
- [ ] Pressing `sprint` reaches `7.0` m/s in `0.35` s +/- 0.05 s rather than on the next frame. (LOC-08)
- [ ] `get_current_speed_breakdown()["final"]` equals the measured horizontal speed within 0.05 m/s in steady state. (LOC-09)
- [ ] Walking onto a mesh tagged `surface = "water"` changes both the footstep SFX profile and the particle colour. (LOC-10)

## Validation

Extend `apps/game/client/scripts/validation/suites/player_suite.gd`:

- `player.footstep_markers_present` — bind a player rig, assert `has_footstep_markers()` and that the `walk` animation has one `TYPE_METHOD` track with two keys.
- `player.footstep_fallback_active_without_markers` — bind, force markers off, simulate 2 s of walking, assert the fallback timer fired.
- `player.directional_speed_scale` — table-drive `_direction_speed_scale` for forward, 90 deg, and 180 deg inputs and assert `1.0`, `0.82`, `0.65` within 0.01.
- `player.sprint_denied_backward` — assert sprint does not raise the target speed when the movement direction is 180 deg from the facing forward.
- `player.air_control_turn_clamp` — set an airborne velocity, feed a reversed input for 30 physics frames, assert the final direction is within 55 deg of the initial.
- `player.landing_thresholds` — drive `_on_landed` with fall heights `1.0`, `4.0`, `9.0` and assert clip name, lock duration, and damage.
- `player.body_movement_properties` — assert `floor_max_angle`, `floor_snap_length`, `max_slides` on an instanced `player.tscn`.
- `player.speed_breakdown_matches_velocity` — run 60 physics frames of forward input and compare `get_current_speed_breakdown()["final"]` with `Vector2(velocity.x, velocity.z).length()`.

Extend `apps/game/client/scripts/validation/suites/diorama_anim_suite.gd`:

- `diorama_anim.authored_libraries_have_method_tracks` — for every path in `AUTHORED_LIBRARY_PATHS`, load the library and assert `walk` and `run` each contain a `TYPE_METHOD` track. This is the regression guard for the exporter bug behind LOC-01.

## Related
- Existing state: [`../existing_codebase/locomotion.md`](../existing_codebase/locomotion.md)
- [`player-anim-director.md`](player-anim-director.md), [`lock-on-movement.md`](lock-on-movement.md), [`player-controls.md`](player-controls.md), [`orbit-camera.md`](orbit-camera.md)
- [`dodge.md`](dodge.md), [`stamina-mana.md`](stamina-mana.md), [`vfx-service.md`](vfx-service.md), [`audio-director.md`](audio-director.md), [`diorama-anim-library.md`](diorama-anim-library.md), [`export-tools.md`](export-tools.md)
