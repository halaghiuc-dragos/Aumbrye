# System: Combat

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| COMBAT-1 | Core combat loop | M1 |
| COMBAT-5 | Elemental/status integration | M5 |
| COMBAT-7 | Feel polish | M7 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| COMBAT-1.1 | Health/Stamina/Poise components | M1 |
| COMBAT-1.2 | Sword moveset | M1 |
| COMBAT-1.3 | Block / guard break | M1 |
| COMBAT-1.4 | Parry window | M1 |
| COMBAT-1.5 | Hit feedback | M1 |
| WPN-1.1 | Hitbox/hurtbox pipeline | M1 |
| UI-1.1 | Minimal combat HUD | M1 |
| DBG-1.1 | Combat arena overlays | M1 |

Elemental work is owned by [17-DAMAGE-STATUS.md](17-DAMAGE-STATUS.md) and [18-WEAPONS.md](18-WEAPONS.md).

## State machine (player)

`Idle → Attack | Block | Parry | Dodge | Hitstun | Death`

Rules:

- Attacks define startup/active/recovery, stamina, hyperarmor, cancels in data.
- One hit per target per swing.
- Player skill > gear: gear widens margins, does not delete telegraphs.

## Agent rules

- Do not add complex RPG menus into combat HUD.
- Prefer AnimationPlayer markers for active frames.
- No magic numbers in swing logic.
