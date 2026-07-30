# Aumbrye — M1 combat tuning notes

> M1 closed 2026-07-29. See [M1_IMPLEMENTATION_LOG.md](M1_IMPLEMENTATION_LOG.md).

## Training Grunt duel (M1 target)

Skilled play should win via **spacing**, **roll i-frames**, or **parry punish** — not button mashing.

| Attack phase | Duration (s) | Player counter |
|--------------|--------------|----------------|
| Windup | 0.70 | Roll away, parry, or close for punish after |
| Active | 0.15 | i-frames (0.05–0.30 into roll) |
| Recovery | 0.90 | Light combo punish window |

## Punish windows

- **Parry (tap Q / LT):** 0.18s window at guard start, then 0.65s block — tap only, do not hold.
- **Roll through active:** enemy recovery (0.9s) allows 2-hit light combo.
- **Spacing:** walk/sprint out during windup, re-enter during recovery.
- **Backstep dodge (Space alone):** opposite weapon/hitbox facing, not camera-relative.

## Controls

**Authoritative bindings (permanently locked):** [M1_CONTROLS.md](M1_CONTROLS.md)

- Roll/dodge: **Space** (KB/M) / **B** (gamepad)
- Jump: **F** / **A**
- Block + parry: **tap Q** / **tap LT** — not hold
- Lock-on: **middle mouse** / **RB** — camera unchanged; A/D orbit ~1.75m

## Tuning constants (source: `content/enemies/training_grunt.json`)

- HP 80, poise 40 — heavy attack breaks poise in 2 hits.
- Attack damage 14 — ~7 hits to kill player at 100 HP (encourages defense).
- Dodge stamina 32, block drain 18/hit — stamina management required.
- Lock orbit radius: **1.75m** (`lock_on.gd` → `ORBIT_RADIUS`).

## Playtest status

| Test | Status |
|------|--------|
| KB/M combat arena | ✅ Signed off 2026-07-29 |
| Lock-on orbit strafe + unchanged camera | ✅ Signed off |
| Weapon-facing backstep dodge | ✅ Signed off |
| PARRIED / BLOCKED damage text (F3) | ✅ Signed off |
| FPS > 60 | ✅ User >120 |
| Gamepad full loop | ⬜ Deferred — no controller at M1 close |
| Win via roll / parry / spacing | ✅ Signed off |

Full record: [M1_PLAYTEST_CHECKLIST.md](M1_PLAYTEST_CHECKLIST.md)
