# Content: Bosses (EA ≤8)

| # | Id | Theme | Phases | Phase delivered | Status |
|---|----|-------|--------|-----------------|--------|
| 1 | `boss_castle_knight` | forgotten_castle | 2 | M2 | done |
| 2 | `miniboss_castle_captain` | forgotten_castle | 1–2 | M5 | done |
| 3 | `boss_crystal_sovereign` | crystal_caverns | 2+ | M5 | done |
| 4 | `miniboss_crystal_guardian` | crystal_caverns | 1–2 | M5 | done |
| 5 | `boss_swamp_devourer` | poison_swamp | 2+ | M5 | done |
| 6 | `boss_frost_warlord` | frozen_fortress | 2+ | M6 | done |
| 7 | `boss_cathedral_hollow` | dark_cathedral | 2+ | M6 | done |
| 8 | `miniboss_cathedral_bell` | dark_cathedral | 1–2 | M6 | done |

## Per-boss checklist

- [x] Data/scripted attacks defined
- [x] Arena scene + mechanic
- [x] Phase transition readable (varies by boss)
- [x] No softlock / unavoidable instant kill (automated smoke — `m6.dungeon.*`)
- [x] Boss music hooked (stub tones)
- [ ] Manual clear by skilled player
- [x] Listed in biome `bossPool`

Note: Roster ids may alias to legacy scene names (e.g. `boss_castle_knight` → `castle_knight` scene).
