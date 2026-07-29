# System: Movement and Camera

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| MOVE-1 | Soulslike locomotion | M1 |
| CAM-1 | Third-person camera + lock-on | M1 |

## Minor milestones

| ID | Title | Phase | Depends |
|----|-------|-------|---------|
| MOVE-1.1 | Locomotion base | M1 | SETUP-0.3 |
| MOVE-1.2 | Jump + dodge/roll i-frames | M1 | MOVE-1.1 |
| CAM-1.1 | Orbit + zoom + collision | M1 | SETUP-0.3 |
| CAM-1.2 | Lock-on soft/hard + switch | M1 | CAM-1.1, ENEMY-1.1 |

Full acceptance criteria: [phases/M1-COMBAT.md](../phases/M1-COMBAT.md).

## Design constraints

- Weight over snappy arcade unless talent explicitly changes it.
- Dodge recovery must be punishable.
- Lock-on must remain readable in cramped rooms (spring arm length clamps).
- All tuning via named constants or `content/player/locomotion.json`.

## Primary paths

- `apps/game/client/scripts/player/`
- `apps/game/client/scripts/camera/`
