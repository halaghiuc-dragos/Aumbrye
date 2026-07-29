# Content: Enemies (EA ≤20)

> Mark status as planned → in_progress → done.
> Do not exceed 20 definitions without ADR.

## Roster

| # | Id | Theme | Role | Phase | Status |
|---|----|-------|------|-------|--------|
| 1 | `training_grunt` | debug | duel trainer | M1 | planned |
| 2 | `castle_grunt` | forgotten_castle | melee | M2 | planned |
| 3 | `castle_archer` | forgotten_castle | ranged | M2 | planned |
| 4 | `castle_shield` | forgotten_castle | guard | M2 | planned |
| 5 | `castle_hound` | forgotten_castle | fast melee | M5 | planned |
| 6 | `crystal_crawler` | crystal_caverns | melee | M5 | planned |
| 7 | `crystal_spitter` | crystal_caverns | ranged | M5 | planned |
| 8 | `crystal_golem` | crystal_caverns | heavy | M5 | planned |
| 9 | `crystal_wisp` | crystal_caverns | arcane harass | M5 | planned |
| 10 | `swamp_slasher` | poison_swamp | melee | M5 | planned |
| 11 | `swamp_spitter` | poison_swamp | poison ranged | M5 | planned |
| 12 | `swamp_brute` | poison_swamp | heavy | M5 | planned |
| 13 | `swamp_swarm` | poison_swamp | pack melee | M5 | planned |
| 14 | `frost_raider` | frozen_fortress | melee | M6 | planned |
| 15 | `frost_archer` | frozen_fortress | ranged | M6 | planned |
| 16 | `frost_knight` | frozen_fortress | elite | M6 | planned |
| 17 | `frost_hound` | frozen_fortress | fast | M6 | planned |
| 18 | `cathedral_acolyte` | dark_cathedral | caster | M6 | planned |
| 19 | `cathedral_warden` | dark_cathedral | melee | M6 | planned |
| 20 | `cathedral_shade` | dark_cathedral | teleport harass | M6 | planned |

## Per-enemy definition checklist

- [ ] JSON def with behaviors + stats + lootTableId + telegraphProfileId
- [ ] Scene/prefab
- [ ] At least one readable attack telegraph
- [ ] Placed in biome pool
- [ ] Manual combat sanity check

Minibosses/bosses are tracked in [03-BOSSES.md](03-BOSSES.md), not here (unless a miniboss also uses an enemy def — then dual-list carefully without double-counting toward 20 if counted as boss-only).
