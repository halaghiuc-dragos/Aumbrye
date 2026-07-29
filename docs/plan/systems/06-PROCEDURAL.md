# System: Procedural Generation

## Pipeline (strict order)

1. Seeded RNG  
2. Layout graph  
3. Connectivity validation  
4. Room type assignment  
5. Enemy placement  
6. Loot placement  
7. Puzzle placement  
8. Boss + exit placement  
9. Decoration hints  
10. Final validation  
11. Canonical serialization  

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| PROC-3 | Full pipeline for Forgotten Castle | M3 |
| PROC-5 | Multi-biome rules | M5 |
| PROC-6 | Five-biome production hardening | M6 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| PROC-3.1 | Seeded RNG + layout | M3 |
| PROC-3.2 | Connectivity validation | M3 |
| PROC-3.3 | Room types | M3 |
| PROC-3.4 | Enemy budgets | M3 |
| PROC-3.5 | Loot/puzzle/boss/exit | M3 |
| PROC-3.6 | Deco + serialize | M3 |
| TEST-3.1 | Unit battery + 100 seeds | M3 |

## Handcrafted feel rules

- Assemble **hand-authored room prefabs**, do not noise-sculpt caves for EA.
- Reject graphs that are too linear, lack secrets, or place boss adjacent to entrance.
- Determinism is mandatory: same inputs → same JSON.

## Primary paths

- `packages/procedural/`
- `content/biomes/`
