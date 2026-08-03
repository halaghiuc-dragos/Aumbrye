# System: Movement and Camera

> M1 milestones **done** (2026-07-29). Controls locked: [M1_CONTROLS.md](../../design/M1_CONTROLS.md). Archive: [M1_IMPLEMENTATION_LOG.md](../../design/M1_IMPLEMENTATION_LOG.md).

## Major milestones

| Major | Title | Phase | Status |
|-------|-------|-------|--------|
| MOVE-1 | Soulslike locomotion | M1 | ✅ |
| CAM-1 | Third-person camera + lock-on | M1 | ✅ |

## Minor milestones

| ID | Title | Phase | Depends |
|----|-------|-------|---------|
| MOVE-1.1 | Locomotion base | M1 | SETUP-0.3 |
| MOVE-1.2 | Jump + dodge/roll i-frames | M1 | MOVE-1.1 |
| CAM-1.1 | Orbit + zoom + collision | M1 | SETUP-0.3 |
| CAM-1.2 | Lock-on toggle + orbit strafe | M1 | CAM-1.1, ENEMY-1.1 |

## Design constraints

- Weight over snappy arcade unless talent explicitly changes it.
- Dodge recovery must be punishable.
- **Lock-on does not change camera or mouse look.** While locked: W/S camera-relative; A/D orbit strafe at ~1.75m (`ORBIT_RADIUS` in `lock_on.gd`).
- Space alone: backstep opposite weapon/hitbox facing (`dodge.gd`).
- Lock-on target switch: right stick when locked (gamepad — verify under `TEST-M1-GPAD`).
- Tuning via named constants in scripts (future: `content/player/locomotion.json`).

## Primary paths

- `apps/game/client/scripts/player/`
- `apps/game/client/scripts/camera/`

## Pixel diorama viewport

When low-res upscale is enabled, the root viewport disables 3D rendering; a SubViewport mirror camera draws the world. **Billboards and HUD** must use `PixelDioramaViewport.get_gameplay_camera()` instead of `get_viewport().get_camera_3d()`.

Orbit camera no longer snaps pivot position (was breaking follow with SpringArm). See [PIXEL_DIORAMA_PIPELINE.md](../../design/PIXEL_DIORAMA_PIPELINE.md).
