# M-Phases Status (M0–M7)

> One-page snapshot for agents and humans. **Authoritative detail** lives in phase implementation logs under `docs/design/`.

**Last updated:** 2026-07-31  
**Current phase:** M7 automated closed — **EA ship pending manual gates**  
**Automated gate:** `./scripts/run-all-validation.ps1` — `m7_suite` + prior suites

---

## Summary table

| Phase | Name | Status | Automated validation | Manual gates | Canonical log |
|-------|------|--------|----------------------|--------------|---------------|
| M0 | Foundation / CI | **Complete** | CI + `setup_suite` green | — | [systems/00-SETUP-CI.md](systems/00-SETUP-CI.md) |
| M1 | Combat core | **Complete** | `arena_suite`, `combat_suite`, etc. | KB/M signed off; gamepad → M7 | [M1_IMPLEMENTATION_LOG.md](../design/M1_IMPLEMENTATION_LOG.md) |
| M2 | Vertical slice | **Complete** | `dungeon_suite`, `flow_suite` | Castle loop signed off | [M2_IMPLEMENTATION_LOG.md](../design/M2_IMPLEMENTATION_LOG.md) |
| M3 | Server generation | **Complete** | `procgen_suite` + C# procgen tests | Spot-checks open (seed, offline) | [M3_IMPLEMENTATION_LOG.md](../design/M3_IMPLEMENTATION_LOG.md) |
| M4 | Gameplay loop | **Complete** | `hub_m4_suite`, `progression_suite`, `inventory_suite` | TEST-4.1 soak open | [M4_IMPLEMENTATION_LOG.md](../design/M4_IMPLEMENTATION_LOG.md) |
| M5 | Content pack A | **Complete** | `m5_suite` (74 tests) | Feel gates § M5 | [MANUAL_PLAYTEST_CHECKLIST.md](../design/MANUAL_PLAYTEST_CHECKLIST.md) |
| M6 | Content pack B | **Complete** | `m6_suite` (73 tests) | Feel gates § M6 | [M6_IMPLEMENTATION_LOG.md](../design/M6_IMPLEMENTATION_LOG.md) |
| M7 | EA polish / Steam | **Automated closed** | `m7_suite` (65 tests) | Ship gates § M7 (68 IDs) | [M7_IMPLEMENTATION_LOG.md](../design/M7_IMPLEMENTATION_LOG.md) |

> M7 phase file removed after automated close (same pattern as M6). EA ship requires [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md) + manual sign-off.

---

## M7 automated close (2026-07-31)

- Multi-floor 10-floor runs + **floor chunking** (single active floor; save v3)
- **Umbral Endless** + **Umbral Waves** + skip consumables
- Steam/crash/glyph/tutorial stubs, save migrator v3, release CI workflow
- `m7_suite`: 65 tests — **446 automated total** (363 Godot + 83 C#), 0 failures
- Phase file `M7-EA-POLISH.md` deleted; canonical: [M7_IMPLEMENTATION_LOG.md](../design/M7_IMPLEMENTATION_LOG.md)

## M7 ship actions (manual — blocks EA)

1. Close [MANUAL_PLAYTEST_CHECKLIST.md § M7](../design/MANUAL_PLAYTEST_CHECKLIST.md#m7--ea-polish--ship) (mirror: [M7_MANUAL_PLAYTEST_CHECKLIST.md](../design/M7_MANUAL_PLAYTEST_CHECKLIST.md))
2. Publish [KNOWN_ISSUES_M7.md](../design/KNOWN_ISSUES_M7.md) with store page
3. Steam App ID + GodotSteam build → STEAM-7.1 manual
4. ≥20 playtesters (SHIP-7.1)
5. Meet [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md)

---

## Validation commands

```powershell
./scripts/run-all-validation.ps1
```

Report: `reports/validation-summary.json`

**Latest automated totals:** 363 Godot + 83 C# = **446** (0 failures)
