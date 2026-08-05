# Orbit camera — improvement plan

## Current state

`orbit_camera.gd` extends `SpringArm3D` at `Player/CameraPivot/SpringArm3D`. It rotates a yaw pivot, clamps pitch to `-45`/`+60` deg, lerps `spring_length` between `2.5` and `7.0` m, toggles first person by collapsing the arm to `0.0` and hiding the torso subtree, and persists the mode through `LocalSave`. See [`../existing_codebase/orbit-camera.md`](../existing_codebase/orbit-camera.md).

The mechanism is sound. The problems are all player-facing controls that do not exist: sensitivity, invert-Y, and field of view are compile-time constants, so a player cannot adjust the camera at all. First person has no field-of-view change and no viewmodel-safe near plane. The gameplay camera never pixel-snaps even though the project ships a snapping helper. And `_break_player_lock` is dead code.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| ORB-01 | P0 | Sensitivity and invert-Y are compile-time constants with no settings UI and no save key. `MOUSE_SENSITIVITY = 0.003`, `STICK_SENSITIVITY = 2.5`, `INVERT_Y = false`; `accessibility_settings.gd` has no camera keys | `orbit_camera.gd:3-4`, `:12`, `apps/game/client/scripts/app/accessibility_settings.gd` |
| ORB-02 | P0 | The gameplay camera never pixel-snaps. `PixelCameraSnap` is applied only to the pixel viewport's render camera, and `PixelDioramaSettings.DEFAULT_CAMERA_SNAP` is `false`, so the third-person camera slides sub-pixel against a pixel-art presentation | `apps/game/client/scripts/art/pipeline/pixel_diorama_viewport.gd` snap wiring, `apps/game/client/scripts/art/pipeline/pixel_diorama_settings.gd` `DEFAULT_CAMERA_SNAP` |
| ORB-03 | P1 | No field-of-view control and no first-person FOV change. `Camera3D.fov` is never written by this script, so first person uses the third-person FOV authored in `player.tscn` | absence of `fov` in `orbit_camera.gd:1-284`, `apps/game/client/scenes/player/player.tscn` camera node |
| ORB-04 | P1 | First person has no viewmodel-safe near plane. `near` is never set, so at the default `0.05` the arms can still clip against world geometry, and there is no separate viewmodel render pass | absence of `near` in `orbit_camera.gd`, `apps/game/client/scripts/art/characters/diorama_viewmodel.gd` |
| ORB-05 | P1 | `_break_player_lock()` is dead code with no caller, so the intent of breaking the lock from a camera action is unimplemented | `orbit_camera.gd:275-283`; grep finds no call site |
| ORB-06 | P1 | Camera mode cannot be toggled while locked on. `_unhandled_input` returns early on `_lock_on_active` before the `toggle_camera` check, and the same early return blocks zoom | `orbit_camera.gd:57-65` |
| ORB-07 | P1 | The spring arm has no smoothing or lateral offset. Wall pull is instantaneous through the engine's own arm behaviour, and there is no shoulder offset, so the player's body sits dead centre and occludes the target | `orbit_camera.gd:38`, `:253-255` |
| ORB-08 | P2 | No camera shake or recoil entry point on this node. `hit_feedback.gd` writes camera offsets directly, which is why a wrong `NodePath` silently disabled all of it | `apps/game/client/scripts/combat/hit_feedback.gd:115-153`; see PCB-01 in [`player-combat.md`](player-combat.md) |
| ORB-09 | P2 | `Input.set_mouse_mode(MOUSE_MODE_CAPTURED)` is called unconditionally in `_ready`, so the camera claims the mouse even if a menu is already open on scene entry | `orbit_camera.gd:47` |
| ORB-10 | P2 | `capture_state` and `apply_state` carry `yaw`, `pitch`, `zoom`, and `firstPerson` but not the lock state, so a floor transition while locked restores the camera angle without the lock | `orbit_camera.gd:209-230` |
| ORB-11 | P2 | Pitch limits are asymmetric constants (`-45` / `+60` deg) with no first-person variant, so looking down in first person stops `45` deg above straight down | `orbit_camera.gd:5-6` |

## Target design

**Player-controlled camera feel.** Move the three constants into `AccessibilitySettings` with save keys and a settings panel section:

| Setting key | Default | Range | Applied as |
|-------------|---------|-------|------------|
| `cameraMouseSensitivity` | `1.0` | `0.2`–`3.0` | multiplier on `MOUSE_SENSITIVITY_BASE = 0.003` |
| `cameraStickSensitivity` | `1.0` | `0.2`–`3.0` | multiplier on `STICK_SENSITIVITY_BASE = 2.5` |
| `cameraInvertY` | `false` | bool | replaces the `INVERT_Y` constant |
| `cameraFov` | `70.0` deg | `60.0`–`100.0` | written to `Camera3D.fov` in third person |
| `cameraStickCurve` | `2.0` | `1.0`–`3.0` | exponent on the stick magnitude before scaling |
| `cameraStickDeadzone` | `0.15` | `0.05`–`0.35` | radial deadzone before the curve |

The stick curve matters: today a stick input is linear, so precise aiming and fast turning cannot coexist. `magnitude_curved = pow(clamp((magnitude - deadzone) / (1.0 - deadzone), 0.0, 1.0), cameraStickCurve)` gives a slow centre and a fast edge at the default exponent of `2.0`.

`orbit_camera.gd` reads the values on `_ready` and on an `AccessibilitySettings.settings_changed` signal, so a change in the pause menu applies without a reload.

**First-person camera parameters.**

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `FIRST_PERSON_FOV` | `82.0` deg | wider than third person, standard for a first-person view |
| `FIRST_PERSON_NEAR` | `0.02` m | tighter near plane so the viewmodel does not clip |
| `FIRST_PERSON_MIN_PITCH` | `deg_to_rad(-80.0)` | look further down than third person allows |
| `FIRST_PERSON_MAX_PITCH` | `deg_to_rad(80.0)` | |
| `CAMERA_MODE_BLEND_TIME` | `0.22` s | arm length, FOV, and pitch limits ease between modes rather than snapping |

`cameraFov` scales the first-person value proportionally so a player who widens the FOV gets it in both modes.

The viewmodel should render in a dedicated pass rather than relying on the near plane alone: give `DioramaViewmodel` its own `SubViewport` with a `Camera3D` that shares the gameplay camera's rotation, `near = 0.01`, `fov = 60.0`, composited over the main view. That removes viewmodel clipping entirely and lets the arms use a fixed FOV while the world FOV is player-controlled.

**Pixel snapping on the gameplay camera.** Enable snapping by default (`DEFAULT_CAMERA_SNAP = true`) and apply `PixelCameraSnap` to the gameplay camera as well, quantizing the camera position to the world size of one output pixel:

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `SNAP_ENABLED_DEFAULT` | `true` | |
| `SNAP_SUBPIXEL_STEPS` | `1` | `1` snaps to whole output pixels; `2` allows half-pixel steps for smoother motion at the cost of some shimmer |
| `SNAP_DISABLE_WHILE_LOCKED` | `false` | snapping stays on while locked so framing does not change character mid-fight |

This is a visible quality change on a pixel-art game and should ship behind a display setting (`Display Settings` already owns the pixel pipeline toggles) so it can be turned off if a player prefers smooth motion.

**Shoulder offset and arm smoothing.**

| Named constant | Default | Meaning |
|----------------|---------|---------|
| `SHOULDER_OFFSET_X` | `0.45` m | lateral camera offset in third person, so the body does not occlude the centre of the screen |
| `SHOULDER_OFFSET_BLEND` | `8.0` | rate at which the offset eases when it flips side |
| `ARM_PULL_IN_RATE` | `24.0` | fast pull-in when geometry intrudes |
| `ARM_PUSH_OUT_RATE` | `6.0` | slow push-out when it clears, so a doorway does not pump the camera |

Asymmetric rates are the standard fix for spring-arm pumping: intruding geometry must be respected immediately, but recovering can be lazy.

**Centralized shake.** Add `apply_shake(strength: float, duration: float)`, `apply_punch(direction: Vector3, strength: float)`, `apply_landing_dip(strength: float)`, `enter_death_framing()`, and `exit_death_framing()` to this node, and have `hit_feedback.gd`, `locomotion.gd`, and `player_combat_reactions.gd` call them instead of writing camera transforms. All shake is scaled by the existing `AccessibilitySettings` reduce-shake setting in one place. `_break_player_lock()` becomes reachable as the implementation of a new `break_lock` action triggered when the player toggles camera mode while locked, or is deleted; keeping it and calling it from `_toggle_camera_mode` is the better option because switching perspective mid-lock is a deliberate disengage.

**Mouse capture.** `_ready` captures the mouse only when no meta UI is open, asking `PlayerInput.is_gameplay_blocked()`, and `PlayerControls` takes ownership of releasing and recapturing it around menus.

**Lock state in the camera blob.** `capture_state` adds `"lockTargetPath"` (the target's `NodePath` when locked, empty otherwise) and `apply_state` re-acquires it if the node still exists, so a floor transition preserves the lock.

## Work plan

1. **Add the six camera settings** to `accessibility_settings.gd` with save keys, defaults, and a Settings panel section; read them in `orbit_camera.gd` and react to `settings_changed`. Closes ORB-01.
2. **Add the stick curve and deadzone** to `_physics_process`. Part of ORB-01.
3. **Add first-person camera parameters** and the `CAMERA_MODE_BLEND_TIME` easing for arm length, FOV, and pitch limits. Closes ORB-03 and ORB-11.
4. **Give the viewmodel its own `SubViewport` camera** and set `FIRST_PERSON_NEAR` on the gameplay camera. Closes ORB-04.
5. **Enable gameplay-camera pixel snapping** with the three snap constants and a display setting. Closes ORB-02.
6. **Add the shoulder offset and asymmetric arm rates.** Closes ORB-07.
7. **Add the five camera-effect entry points** and migrate `hit_feedback.gd` onto them. Closes ORB-08. Pairs with PCB-01 in [`player-combat.md`](player-combat.md).
8. **Allow toggling and zooming while locked**, and call `_break_player_lock()` from `_toggle_camera_mode`. Closes ORB-05 and ORB-06.
9. **Gate the mouse capture** on `PlayerInput.is_gameplay_blocked()`. Closes ORB-09. Depends on [`player-controls.md`](player-controls.md).
10. **Add `lockTargetPath`** to the camera state blob. Closes ORB-10.

## Data and schema changes

- `AccessibilitySettings` gains six keys: `cameraMouseSensitivity`, `cameraStickSensitivity`, `cameraInvertY`, `cameraFov`, `cameraStickCurve`, `cameraStickDeadzone`. These live in the settings section of the save, so a **`save_migrator.gd` version bump** is required to insert the defaults for existing saves; without it a returning player would read `0.0` sensitivity and the camera would not move.
- `PixelDioramaSettings.DEFAULT_CAMERA_SNAP` flips to `true` and a `gameplayCameraSnap` display setting is added.
- The camera state blob gains `lockTargetPath`, which is transient run state and needs no migration because an absent key means "not locked".
- No content JSON change.

## Acceptance criteria

- [ ] Setting mouse sensitivity to `0.5` halves the yaw change for the same mouse delta, and the value survives a restart. (ORB-01)
- [ ] Enabling invert-Y reverses pitch in both third and first person and in locked pitch bias. (ORB-01)
- [ ] A 30 percent stick tilt produces roughly 9 percent of the maximum turn rate at the default curve of `2.0`. (ORB-01)
- [ ] The gameplay camera position quantizes to whole output pixels and a slow pan shows no sub-pixel crawl. (ORB-02)
- [ ] Entering first person eases the FOV from `70` to `82` deg over `0.22` s. (ORB-03)
- [ ] First-person arms never clip into a wall pressed against the player. (ORB-04)
- [ ] Toggling camera mode while locked breaks the lock and switches mode. (ORB-05, ORB-06)
- [ ] Zoom works while locked. (ORB-06)
- [ ] The player body sits `0.45` m off centre in third person; walking into a doorway pulls the camera in within `0.05` s and pushes out over roughly `0.17` s. (ORB-07)
- [ ] `hit_feedback.gd` contains no direct camera transform writes; all shake respects the reduce-shake setting. (ORB-08)
- [ ] Loading into a scene with the inventory already open does not capture the mouse. (ORB-09)
- [ ] A floor transition taken while locked restores the lock on the same enemy if it still exists. (ORB-10)
- [ ] First person can look `80` deg down; third person still stops at `45` deg. (ORB-11)

## Validation

Extend `apps/game/client/scripts/validation/suites/camera_suite.gd`:

- `camera.sensitivity_setting_applied` — set `cameraMouseSensitivity` to `0.5`, feed a fixed mouse delta, and assert half the yaw change of the `1.0` case.
- `camera.invert_y_applied` — assert the pitch sign flips with the setting, including in `_apply_lock_pitch_look`.
- `camera.stick_curve_and_deadzone` — table-drive magnitudes `0.10`, `0.30`, `1.00` and assert `0.0`, `0.09` +/- 0.01, and `1.0`.
- `camera.settings_defaults_present` — assert all six keys exist with the documented defaults on a fresh settings dictionary.
- `camera.first_person_parameters` — toggle to first person, advance `0.25` s, and assert `fov == 82.0`, `near == 0.02`, and the pitch clamp at `80` deg.
- `camera.mode_blend_duration` — assert `spring_length` and `fov` both settle within `0.22` s +/- 0.03 s.
- `camera.gameplay_camera_snaps` — enable snapping, move the player by a third of a pixel, and assert the camera global position is unchanged.
- `camera.shoulder_offset_applied` — assert the camera's local x offset is `0.45` in third person and `0.0` in first person.
- `camera.arm_rates_asymmetric` — introduce and remove an occluder and assert the pull-in is at least three times faster than the push-out.
- `camera.effect_entry_points_exist` — assert `apply_shake`, `apply_punch`, `apply_landing_dip`, `enter_death_framing`, and `exit_death_framing` all exist and that `hit_feedback.gd` calls them.
- `camera.toggle_breaks_lock` — lock a target, toggle camera mode, and assert `is_locked` is `false` and the mode changed.
- `camera.state_round_trip_with_lock` — lock, `capture_state`, break, `apply_state`, and assert the lock was restored.

Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

- `save.camera_settings_migration` — load a pre-bump settings fixture and assert the six camera keys are populated with defaults rather than zeros.

## Related
- Existing state: [`../existing_codebase/orbit-camera.md`](../existing_codebase/orbit-camera.md)
- [`lock-on-camera.md`](lock-on-camera.md), [`lock-on.md`](lock-on.md), [`player-controls.md`](player-controls.md), [`player-combat.md`](player-combat.md), [`locomotion.md`](locomotion.md)
- [`pixel-camera-snap.md`](pixel-camera-snap.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`hit-feedback.md`](hit-feedback.md), [`accessibility.md`](accessibility.md), [`ui/settings.md`](ui/settings.md), [`ui/display_settings.md`](ui/display_settings.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md)
