# System: Testing

## Layers

| Layer | Scope | Command |
|-------|-------|---------|
| **All validation** | C# + content + Godot in-engine | `./scripts/run-all-validation.ps1` |
| Unit | Procgen, loot, affixes, dialogue conditions, damage formula | `./scripts/run-automated-tests.ps1` |
| Integration | Auth → run → complete → save | Backend tests (M4+) |
| **Godot in-engine** | M1–M5 structural + scenario checks | `./scripts/run-mcp-validation.ps1` |
| Manual | EA ship gates, feel, UX, soak, gamepad, external playtest | [07-EA-DEFINITION-OF-DONE.md](../07-EA-DEFINITION-OF-DONE.md) |
| Perf | Fixed camera path benchmarks per biome | M4+ |
| Soak | 10-run (M4), 100-seed gen (M3), 50-seed smoke (EA) | |

Suites live under `apps/game/client/scripts/validation/suites/`. Godot editor verification: [MCP_AGENT_GUIDE.md](../../MCP_AGENT_GUIDE.md).

## Manual carry-over (deferred → M7)

| ID | Title | Notes |
|----|-------|-------|
| TEST-M1-GPAD | Gamepad combat arena playtest | Bindings in `project.godot`; verify before EA ship. Does not block M2–M3. |
| M2.gamepad.full_loop | Gamepad full vertical slice | Deferred from M2 — `POLISH-7.1` |
| M2.playtest.external | External friend playtest | Deferred from M2 — `SHIP-7.1` |
| M7.* | Feel/UX polish (17 items) | EA DoD + [AUDIT_2026-08.md](../../design/AUDIT_2026-08.md) |
| M4.deferred.* | Carried from M4 close | See checklist § M4 |
| M5.manual | M5 feel playtest (biomes, weapons, bosses, audio) | EA DoD |
| M5.deferred.* | Art, mythic uniques, item roster | M6 phase file; manual gates in EA DoD |

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
- Track open bugs in [AUDIT_2026-08.md](../../design/AUDIT_2026-08.md).
