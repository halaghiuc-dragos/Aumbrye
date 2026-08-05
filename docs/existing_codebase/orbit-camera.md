# Orbit camera

`orbit_camera.gd` is the script on `Player/CameraPivot/SpringArm3D`. It owns mouse and stick look, pitch clamping, zoom, the first-person toggle and its persistence, and the lock-on framing entry points. It is the only gameplay camera in the repo and is on the live play path in every scene that instances `player.tscn`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/camera/orbit_camera.gd` | `extends SpringArm3D` |
| `apps/game/client/scenes/player/player.tscn:106-116` | `CameraPivot` at `(0, 1.6, 0)`, `SpringArm3D` with `spring_length = 4.0`, `collision_mask = 1`, `yaw_pivot_path = ".."`, and a `Camera3D` with `current = true` |
| `apps/game/client/scripts/save/local_save.gd` | `is_first_person_camera()` / `set_first_person_camera()` (`:76-84`) |

## Tuning constants

| Constant | Value |
|----------|-------|
| `MOUSE_SENSITIVITY` | `0.003` rad per pixel |
| `STICK_SENSITIVITY` | `2.5` rad/s |
| `MIN_PITCH` / `MAX_PITCH` | `deg_to_rad(-45.0)` / `deg_to_rad(60.0)` |
| `MIN_ZOOM` / `MAX_ZOOM` | `2.5` / `7.0` m |
| `ZOOM_STEP` | `0.5` m per wheel notch |
| `ZOOM_SPEED` | `8.0` (lerp rate toward `_target_zoom`) |
| `FIRST_PERSON_LENGTH` | `0.0` |
| `INVERT_Y` | `false` |

`orbit_camera.gd:3-12`. All are `const`; none is settings-driven.

## How it works

`_ready()` (`:35`) seeds `_target_zoom` and `_saved_third_person_zoom` from the authored `spring_length` (4.0), forces `collision_mask = 1`, resolves `yaw_pivot_path` (`CameraPivot`) and `facing_path` (default `"../../Facing"`, which is `Player/Facing`), applies the saved first-person preference from `LocalSave.is_first_person_camera()`, and calls `Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)` unconditionally.

`_unhandled_input()` (`:50`):
- Mouse motion is consumed only while `Input.get_mouse_mode() == MOUSE_MODE_CAPTURED`. While locked on, only the pitch component is used, through `_apply_lock_pitch_look`, and the event is marked handled. Otherwise `_apply_look(-relative.x * MOUSE_SENSITIVITY, -relative.y * MOUSE_SENSITIVITY)`.
- Everything below returns early while locked on (`:57-58`): `toggle_camera`, `zoom_in`, `zoom_out`.
- Zoom is additionally suppressed in first person (`:61`).

`_physics_process()` (`:68`) returns early while locked on. Otherwise it applies right-stick look at `STICK_SENSITIVITY * delta` and lerps `spring_length` toward `_target_zoom` at `ZOOM_SPEED * delta`.

`_apply_look(yaw_delta, pitch_delta)` (`:77`) rotates the **yaw pivot** in Y and clamps the arm's own `rotation.x` to the pitch range. Yaw and pitch therefore live on different nodes: `CameraPivot.rotation.y` and `SpringArm3D.rotation.x`.

**First person.** `_toggle_camera_mode()` (`:233`) flips the mode and persists it via `LocalSave.set_first_person_camera`. `_apply_first_person(enabled)` (`:238`) saves the third-person zoom, sets `spring_length` to `FIRST_PERSON_LENGTH = 0.0`, then calls `_update_body_visibility()` and `_update_spring_collision()`. Collision is disabled entirely in first person (`collision_mask = 0`) because the spring's wall pull fights the eye position (`:253-255`). `_update_body_visibility()` calls `DioramaCharacterSkin.apply_first_person(_facing, _first_person)` and then `AnimDirector.sync_camera_mode()`, found by walking up to the nearest `CharacterBody3D` (`:258-272`).

What first person hides: `FIRST_PERSON_HIDDEN_PARTS = ["Torso"]` (`diorama_character_skin.gd:23`). The `Torso` pivot subtree — head, both arms, weapon, and shield — is switched to `SHADOW_CASTING_SETTING_SHADOWS_ONLY`, so it still casts a shadow but is not drawn. The legs stay fully visible below the camera. Weapon, shield, and bow mounts additionally get `cast_shadow = OFF` (`diorama_character_skin.gd:296-302`).

**State capture.** `capture_state()` / `apply_state()` (`:209-230`) round-trip `yaw`, `pitch`, `zoom`, and `firstPerson` as a `Dictionary`.

**Look helpers.** `snap_look_direction`, `blend_look_direction`, and `snap_camera_forward` all convert a flat world direction to a yaw with `atan2(-dir.x, -dir.z)` and add `PI` in first person (`:179-184`, `:196-200`).

## Camera pixel snapping

`orbit_camera.gd` does not snap. The snap happens on a mirror camera inside the low-resolution pipeline: `PixelDioramaViewport._mirrored_transform()` calls `PixelCameraSnap.snap_transform(source.global_transform, fov, SNAP_FOCUS_DISTANCE = 5.0)` (`pixel_diorama_viewport.gd:104-111`). The comment there records why the gameplay pivot is not snapped: it would decouple yaw from player movement and break spring-arm follow.

`PixelCameraSnap.snap_transform` returns the source transform unchanged unless `PixelDioramaSettings.camera_snap_enabled` is true (`pixel_camera_snap.gd:8-9`). The default is `DEFAULT_CAMERA_SNAP := false` (`pixel_diorama_settings.gd:34`), and `reset_to_defaults` also sets it to `false` (`:215`). The only way to enable it is the Settings toggle "Snap camera to pixel grid" (`settings_ui.gd:246-250`). **Out of the box the camera does not snap.** When enabled, the step is one rendered pixel at 5 m: `2 * 5 * tan(fov/2) / active_render_height` (`pixel_diorama_settings.gd:283-286`).

## Contracts

- Must be a `SpringArm3D` at `Player/CameraPivot/SpringArm3D` with a `Camera3D` child named `Camera3D`. That literal path is used by `player.tscn:99`, `hit_feedback.gd`, `player_anim_director.gd:12-13`, `lock_on.gd:41`, `pixel_diorama_viewport.gd:287`, `camera_suite.gd:26`.
- `yaw_pivot_path` must resolve to a `Node3D` that is a direct child of the player body.
- Public API: `get_yaw_basis()`, `snap_look_direction()`, `blend_look_direction()`, `snap_camera_forward()`, `set_lock_on_active()`, `update_lock_on_frame()`, `is_first_person()`, `capture_state()`, `apply_state()`.
- `locomotion.gd:158` reads `_camera_yaw.global_rotation.y` directly from `CameraPivot` rather than calling `get_yaw_basis()`.
- Sets the mouse mode globally in `_ready`; UI scripts that need a cursor set it back themselves (for example `talents_ui.gd:60`).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Mouse and stick look, pitch clamp, split yaw/pitch nodes | IMPLEMENTED | `orbit_camera.gd:50-82` |
| Zoom with smoothing | IMPLEMENTED | `orbit_camera.gd:62-65`, `:74` |
| First-person toggle, persistence, body hiding | IMPLEMENTED | `orbit_camera.gd:233-263`; covered by `scripts/validation/suites/camera_suite.gd:13-77` |
| State capture and restore | IMPLEMENTED | `orbit_camera.gd:209-230` |
| Camera pixel snapping | PARTIAL, off by default | `pixel_diorama_settings.gd:34`, `:215`; applied only to the mirror camera at `pixel_diorama_viewport.gd:106-111` |
| First-person yaw convention | BROKEN under lock-on | `_yaw_for_look_direction` is called with `apply_fp_offset = false` only while locked on (`:116`), so the `yaw += PI` at `:182-183` is skipped there and applied everywhere else (`:198-199`) |
| `_break_player_lock()` | STUB | Defined at `:275-283` with no call site anywhere in the repo |
| Mouse sensitivity, stick sensitivity, invert-Y | ABSENT as options | All three are `const` (`:3-4`, `:12`); `accessibility_settings.gd` exposes only `ui_scale`, `reduce_camera_shake`, `colorblind_mode`, `subtitle_scale`, `vibration_intensity` |
| Collision-aware framing in third person | PARTIAL | `collision_mask = 1` gives the stock `SpringArm3D` pull-in with no smoothing; no occlusion fade, no minimum-distance easing, and the lock-on pivot offset can push the boom into geometry |
| FOV control | ABSENT | `Camera3D.fov` is never set by this script; the only writer is the transient `hit_feedback.gd:126-129` kick, which is inert on the player because `_camera` is `null` |
| Camera collision recovery in first person | PARTIAL | `collision_mask = 0` in first person means the eye can be pushed inside geometry with no correction (`:253-255`) |
| Camera shake ownership | Split | Shake is applied as `h_offset`/`v_offset` from `hit_feedback.gd:132-153`, not by this script |

## Related
- Improvement plan: [`../actual_improvements/orbit-camera.md`](../actual_improvements/orbit-camera.md)
- [`lock-on-camera.md`](lock-on-camera.md), [`lock-on.md`](lock-on.md), [`locomotion.md`](locomotion.md)
- [`pixel-camera-snap.md`](pixel-camera-snap.md), [`pixel-diorama-pipeline.md`](pixel-diorama-pipeline.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`diorama-character-skin.md`](diorama-character-skin.md), [`hit-feedback.md`](hit-feedback.md), [`accessibility.md`](accessibility.md)
