# M-Phases Status (M0–M7)

> One-page snapshot for agents and humans. **Current implementation work:** [AUDIT_2026-08.md](../design/AUDIT_2026-08.md).

**Last updated:** 2026-08-03  
**Current phase:** M7 automated closed — **EA ship pending manual gates**  
**Automated gate:** `./scripts/run-all-validation.ps1` — `m7_suite` + prior suites

---

## Summary table

| Phase | Name | Status | Automated validation | Manual gates | Reference |
|-------|------|--------|----------------------|--------------|-----------|
| M0 | Foundation / CI | **Complete** | CI + `setup_suite` green | — | [systems/00-SETUP-CI.md](systems/00-SETUP-CI.md) |
| M1 | Combat core | **Complete** | `arena_suite`, `combat_suite`, etc. | KB/M signed off; gamepad → M7 | [systems/02-COMBAT.md](systems/02-COMBAT.md) |
| M2 | Vertical slice | **Complete** | `dungeon_suite`, `flow_suite` | Castle loop signed off | [phases/M2-VERTICAL-SLICE.md](phases/M2-VERTICAL-SLICE.md) |
| M3 | Server generation | **Complete** | `procgen_suite` + C# procgen tests | Spot-checks open (seed, offline) | [phases/M3-SERVER-GENERATION.md](phases/M3-SERVER-GENERATION.md) |
| M4 | Gameplay loop | **Complete** | `hub_m4_suite`, `progression_suite`, `inventory_suite` | TEST-4.1 soak open | [checklists/01-MASTER-MILESTONE-INDEX.md](checklists/01-MASTER-MILESTONE-INDEX.md) § M4 |
| M5 | Content pack A | **Complete** | `m5_suite` (74 tests) | Feel gates | [content/01-THEMES.md](content/01-THEMES.md) |
| M6 | Content pack B | **Complete** | `m6_suite` (73 tests) | Feel gates | [phases/M6-CONTENT-PACK-B.md](phases/M6-CONTENT-PACK-B.md) |
| M7 | EA polish / Steam | **Automated closed** | `m7_suite` (65 tests) | Ship gates | [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md) |

> EA ship requires [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md) + manual sign-off. Open bugs and polish: [AUDIT_2026-08.md](../design/AUDIT_2026-08.md).

---

## M7 automated close (2026-07-31)

- Multi-floor 10-floor runs + **floor chunking** (single active floor; save v3)
- **Umbral Endless** + **Umbral Waves** + skip consumables
- Steam/crash/glyph/tutorial stubs, save migrator v3, release CI workflow
- `m7_suite`: 65 tests — **446 automated total** (363 Godot + 83 C#), 0 failures

## M7 ship actions (manual — blocks EA)

1. Meet [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md)
2. Resolve or publish known issues from [AUDIT_2026-08.md](../design/AUDIT_2026-08.md) §9
3. Steam App ID + GodotSteam build → STEAM-7.1 manual
4. ≥20 playtesters (SHIP-7.1)

---

## Validation commands

```powershell
./scripts/run-all-validation.ps1
```

Report: `reports/validation-summary.json`

**Latest automated totals:** 363 Godot + 83 C# = **446** (0 failures)

Godot editor work: [MCP_AGENT_GUIDE.md](../MCP_AGENT_GUIDE.md)
