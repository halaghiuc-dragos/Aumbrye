# System: Testing

## Layers

| Layer | Scope |
|-------|-------|
| Unit | Procgen, loot, affixes, dialogue conditions, damage formula |
| Integration | Auth → run → complete → save |
| Godot | GdUnit/GUT for inventory grid, damage, input buffer (introduce by M2/M3) |
| Manual | Combat weekly; boss checklist; controller full loop |
| Perf | Fixed camera path benchmarks per biome |
| Soak | 10-run (M4), 100-seed gen (M3), 50-seed smoke (EA) |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| CI-0.2 | Backend tests in CI | M0 |
| TEST-3.1 | Procgen battery | M3 |
| TEST-4.1 | Ten-run soak | M4 |
| SHIP-7.1 | Closed playtest ≥20 | M7 |

## Agent rules

- Prefer tests that lock determinism and budgets.
- Combat feel remains manual gate; do not claim combat “done” from unit tests alone.
