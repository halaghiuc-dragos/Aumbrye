# Aumbrye — M1 combat tuning notes

## Training Grunt duel (M1 target)

Skilled play should win via **spacing**, **roll i-frames**, or **parry punish** — not button mashing.

| Attack phase | Duration (s) | Player counter |
|--------------|--------------|----------------|
| Windup | 0.70 | Roll away, parry, or close for punish after |
| Active | 0.15 | i-frames (0.05–0.30 into roll) |
| Recovery | 0.90 | Light combo punish window |

## Punish windows

- **Parry success:** 1.2s enemy stagger — heavy attack recommended.
- **Roll through active:** enemy recovery (0.9s) allows 2-hit light combo.
- **Spacing:** walk/sprint out during windup, re-enter during recovery.

## Tuning constants (source: `content/enemies/training_grunt.json`)

- HP 80, poise 40 — heavy attack breaks poise in 2 hits.
- Attack damage 14 — ~7 hits to kill player at 100 HP (encourages defense).
- Dodge stamina 22, block drain 12/hit — stamina management required.

## Playtest status

- [ ] Agent playtest in Godot 4.7 combat arena (manual)
- [ ] Win via roll demonstrated
- [ ] Win via parry demonstrated
- [ ] Win via spacing demonstrated
