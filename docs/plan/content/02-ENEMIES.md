# Content: Enemies (EA ≤20)

> Roster complete for EA (M6 close). Legacy M5 ids (`crystal_slime`, etc.) remain on disk for compatibility; biomes use roster ids below.

## Roster

| # | Id | Theme | Role | Phase | Status |
|---|----|-------|------|-------|--------|
| 1 | `training_grunt` | debug | duel trainer | M1 | done |
| 2 | `castle_grunt` | forgotten_castle | melee | M2 | done |
| 3 | `castle_archer` | forgotten_castle | ranged | M2 | done |
| 4 | `castle_shield` | forgotten_castle | guard | M2 | done |
| 5 | `castle_hound` | forgotten_castle | fast melee | M5/M6 | done |
| 6 | `crystal_crawler` | crystal_caverns | melee | M5/M6 | done |
| 7 | `crystal_spitter` | crystal_caverns | ranged | M5/M6 | done |
| 8 | `crystal_golem` | crystal_caverns | heavy | M5 | done |
| 9 | `crystal_wisp` | crystal_caverns | arcane harass | M5/M6 | done |
| 10 | `swamp_slasher` | poison_swamp | melee | M5/M6 | done |
| 11 | `swamp_spitter` | poison_swamp | poison ranged | M5/M6 | done |
| 12 | `swamp_brute` | poison_swamp | heavy | M5/M6 | done |
| 13 | `swamp_swarm` | poison_swamp | pack melee | M5/M6 | done |
| 14 | `frost_raider` | frozen_fortress | melee | M6 | done |
| 15 | `frost_archer` | frozen_fortress | ranged | M6 | done |
| 16 | `frost_knight` | frozen_fortress | elite | M6 | done |
| 17 | `frost_hound` | frozen_fortress | fast | M6 | done |
| 18 | `cathedral_acolyte` | dark_cathedral | caster | M6 | done |
| 19 | `cathedral_warden` | dark_cathedral | melee | M6 | done |
| 20 | `cathedral_shade` | dark_cathedral | teleport harass | M6 | done |

## Per-enemy definition checklist

- [x] JSON def with behaviors + stats + lootTableId + telegraphProfileId
- [x] Scene/prefab
- [x] At least one readable attack telegraph
- [x] Placed in biome pool
- [ ] Manual combat sanity check — automated scene resolve (`m6.scene.*`)

Minibosses/bosses are tracked in [03-BOSSES.md](03-BOSSES.md), not here.
