# System: Testing

## Layers

| Layer | Scope | Command |
|-------|-------|---------|
| **All validation** | C# + content + Godot in-engine | `./scripts/run-all-validation.ps1` |
| Unit | Procgen, loot, affixes, dialogue conditions, damage formula | `./scripts/run-automated-tests.ps1` |
| Integration | Auth → run → complete → save | Backend tests (M4+) |
| **Godot in-engine** | M1–M3 structural + scenario checks | `./scripts/run-mcp-validation.ps1` |
| Manual | All phases — feel, UX, soak, gamepad, external playtest | [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) |
| Perf | Fixed camera path benchmarks per biome | M4+ |
| Soak | 10-run (M4), 100-seed gen (M3), 50-seed smoke (EA) | |

See [VALIDATION_PLATFORM.md](../../design/VALIDATION_PLATFORM.md) for architecture, test ID conventions, and suite layout.

## Manual carry-over (deferred → M7)

| ID | Title | Notes |
|----|-------|-------|
| TEST-M1-GPAD | Gamepad combat arena playtest | Bindings in `project.godot`; verify in [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) § M1 / M7. Does not block M2–M3. |
| M2.gamepad.full_loop | Gamepad full vertical slice | Deferred from M2 — `POLISH-7.1` |
| M2.playtest.external | External friend playtest | Deferred from M2 — `SHIP-7.1` |
| M7.* | Feel/UX polish (17 items) | Former M3 manual list — [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) § M7 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| CI-0.2 | Backend tests in CI | M0 |
| TEST-3.1 | Procgen battery | M3 — covered by `procgen_suite` + C# tests |
| TEST-4.1 | Ten-run soak | M4 |
| SHIP-7.1 | Closed playtest ≥20 | M7 |

## GdUnit

GdUnit/GUT deferred. The validation platform (`apps/game/client/scripts/validation/`) provides headless in-engine coverage for inventory grid, combat APIs, procgen, save rules, and dungeon build without adding GdUnit yet. Revisit for M4+ if input simulation needs a richer framework.

## Agent rules

- Prefer tests that lock determinism and budgets.
- Combat **feel** remains manual gate (M7); structural combat invariants are automated in `combat_suite` and `lock_on_suite`.
- Run `./scripts/run-all-validation.ps1` before claiming any phase sign-off.
- Update [MANUAL_PLAYTEST_CHECKLIST.md](../../design/MANUAL_PLAYTEST_CHECKLIST.md) when adding human gates — do not create per-phase playtest files.
