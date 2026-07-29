# System: Damage and Status

## Damage types (EA)

`physical | fire | frost | poison | lightning | arcane`

## Status effects (EA)

`burn | bleed | poison | freeze | stun` (+ `curse` if time)

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| DMG-5 | Full elemental + status | M5 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| DMG-5.1 | Damage type pipeline + resists | M5 |
| DMG-5.2 | Status implementations | M5 |

## Rules

- Data-driven durations/stacks/tick rates.
- Colorblind-safe indicators (also A11Y).
- Resistances multiply; document formula in `docs/design/damage_formula.md` during DMG-5.1.
