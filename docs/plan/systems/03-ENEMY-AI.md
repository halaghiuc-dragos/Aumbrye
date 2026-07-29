# System: Enemy AI

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| ENEMY-1 | Training enemy | M1 |
| ENEMY-2 | Castle trio | M2 |
| ENEMY-5 | Theme packs A | M5 |
| ENEMY-6 | Roster fill ≤20 | M6 |

## Behavior set (every enemy)

Data must define parameters for:

`patrol | chase | investigate | attack | retreat | idle`

Optional: `stagger`, `guard`.

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| ENEMY-1.1 | Training enemy actor | M1 |
| ENEMY-1.2 | Hit reactions / poise | M1 |
| ENEMY-1.3 | Fair duel tuning | M1 |
| ENEMY-2.1 | Castle melee grunt | M2 |
| ENEMY-2.2 | Archer | M2 |
| ENEMY-2.3 | Shield enemy | M2 |
| ENEMY-6.1 | Fill roster ≤20 | M6 |

Theme-specific enemies are listed in [content/02-ENEMIES.md](../content/02-ENEMIES.md) and created under THEME-5.x / THEME-6.x.

## Fairness law

- Every attack has a telegraph ≥ readable frames before active hitbox.
- No invisible hitboxes.
- Elite/miniboss may be harder, not cheaper on telegraph.

## Primary paths

- `content/enemies/`
- `apps/game/client/scripts/enemies/`
