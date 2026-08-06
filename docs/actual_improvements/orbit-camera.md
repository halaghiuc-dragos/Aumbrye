# Orbit camera — improvement plan

## Status: FINISHED

## Current state

`orbit_camera.gd` extends `SpringArm3D` at `Player/CameraPivot/SpringArm3D`. Camera feel is settings-driven through `AccessibilitySettings`, first-person uses blended FOV/near/pitch limits, gameplay pixel snapping is available, viewmodels render in a dedicated SubViewport pass, shake/punch/dip/framing entry points centralize combat camera feedback, and lock state round-trips through floor transitions. See [`../existing_codebase/orbit-camera.md`](../existing_codebase/orbit-camera.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| ORB-01 | P0 | Sensitivity and invert-Y compile-time constants | FINISHED |
| ORB-02 | P0 | Gameplay camera never pixel-snaps | FINISHED |
| ORB-03 | P1 | No FOV control or first-person FOV change | FINISHED |
| ORB-04 | P1 | First person has no viewmodel-safe near plane | FINISHED |
| ORB-05 | P1 | `_break_player_lock()` dead code | FINISHED |
| ORB-06 | P1 | Camera mode and zoom blocked while locked | FINISHED |
| ORB-07 | P1 | No arm smoothing or shoulder offset | FINISHED |
| ORB-08 | P2 | No shake entry point; hit_feedback wrote camera offsets | FINISHED |
| ORB-09 | P2 | Mouse captured unconditionally in `_ready` | FINISHED |
| ORB-10 | P2 | Lock state missing from camera blob | FINISHED |
| ORB-11 | P2 | Asymmetric pitch limits without first-person variant | FINISHED |

## Acceptance criteria

- [x] Setting mouse sensitivity to `0.5` halves yaw change and survives restart. (ORB-01)
- [x] Invert-Y reverses pitch in third/first person and locked pitch bias. (ORB-01)
- [x] 30% stick tilt ≈ 9% max turn rate at default curve `2.0`. (ORB-01)
- [x] Gameplay camera quantizes to whole output pixels. (ORB-02)
- [x] First person eases FOV from `70` to `82` deg over `0.22` s. (ORB-03)
- [x] Viewmodel SubViewport pass prevents arms clipping walls. (ORB-04)
- [x] Toggling camera mode while locked breaks lock and switches mode. (ORB-05, ORB-06)
- [x] Zoom works while locked. (ORB-06)
- [x] Shoulder offset `0.45` m third person; asymmetric arm pull/push rates. (ORB-07)
- [x] `hit_feedback.gd` calls orbit camera effect APIs; reduce-shake respected. (ORB-08)
- [x] Scene entry with inventory open does not capture mouse. (ORB-09)
- [x] Floor transition while locked restores lock on same enemy. (ORB-10)
- [x] First person can look `80` deg down; third person stops at `45` deg. (ORB-11)

## Related
- Existing state: [`../existing_codebase/orbit-camera.md`](../existing_codebase/orbit-camera.md)
- [`lock-on-camera.md`](lock-on-camera.md), [`lock-on.md`](lock-on.md), [`player-controls.md`](player-controls.md), [`player-combat.md`](player-combat.md), [`locomotion.md`](locomotion.md)
- [`pixel-camera-snap.md`](pixel-camera-snap.md), [`pixel-diorama-settings.md`](pixel-diorama-settings.md), [`diorama-viewmodel.md`](diorama-viewmodel.md), [`hit-feedback.md`](hit-feedback.md), [`accessibility.md`](accessibility.md), [`ui/settings.md`](ui/settings.md), [`ui/display_settings.md`](ui/display_settings.md), [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md)
