# Content: Themes (EA)

## EA themes (exactly 5)

| # | Id | Name | Phase delivered | Status |
|---|----|------|-----------------|--------|
| 1 | `forgotten_castle` | Forgotten Castle | M2 slice, M5 art pass | done |
| 2 | `crystal_caverns` | Crystal Caverns | M5 | done |
| 3 | `poison_swamp` | Poison Swamp | M5 | done |
| 4 | `frozen_fortress` | Frozen Fortress | M6 | done |
| 5 | `dark_cathedral` | Dark Cathedral | M6 | done |

## Per-theme deliverable checklist

For each theme, all must be done before marking theme complete:

- [x] Biome JSON (`content/biomes/{id}.json`) — all 5
- [x] Room template set (≥6 templates) — all 5 (8–9 each)
- [x] Lighting profile — all 5
- [x] Audio profile (ambience, explore, combat, boss) — stubs for M6 themes
- [x] Enemy pool (4–5) — all 5
- [x] Miniboss — all 5
- [x] Boss (≥2 phases) — scripted; phase transitions vary by boss
- [x] Puzzle type (≥1) — frozen/cathedral puzzle rooms
- [x] Trap set (≥1) — frost + cathedral traps in loot tables
- [x] Loot tables + ≥2 unique items — all 5
- [x] Generator rules (secrets, budgets) — procgen wired
- [ ] Smoke: 20 seeds generate + 1 full manual clear — automated generate yes (`m6.procgen.*`); manual clear open

## Post-EA themes (do not implement before EA)

Forgotten blueprint leftovers: Ancient Temple, Haunted Village, Ancient Library, Underground Prison, Mechanical Factory, Eastern Kingdom, Lava Depths, Sky Citadel, Corrupted Garden, Dream Realm, Void Temple, Mushroom Forest, Sunken Palace, Clockwork City, Ash Wastes, …

See [99-POST-EA.md](99-POST-EA.md).
