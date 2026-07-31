# M-Phases Status (M0–M7)

> One-page snapshot for agents and humans. **Authoritative detail** lives in phase implementation logs under `docs/design/` and phase files under `docs/plan/phases/`.

**Last updated:** 2026-07-31  
**Current phase:** M7 EA polish  
**Automated gate:** `./scripts/run-all-validation.ps1` — **283 Godot + 79 backend tests, 0 failures**

---

## Summary table

| Phase | Name | Status | Automated validation | Manual gates | Canonical log |
|-------|------|--------|----------------------|--------------|---------------|
| M0 | Foundation / CI | **Complete** | CI + `setup_suite` green | — | [systems/00-SETUP-CI.md](systems/00-SETUP-CI.md) |
| M1 | Combat core | **Complete** | `arena_suite`, `combat_suite`, etc. | KB/M signed off; gamepad → M7 | [M1_IMPLEMENTATION_LOG.md](../design/M1_IMPLEMENTATION_LOG.md) |
| M2 | Vertical slice | **Complete** | `dungeon_suite`, `flow_suite` | Castle loop signed off | [M2_IMPLEMENTATION_LOG.md](../design/M2_IMPLEMENTATION_LOG.md) |
| M3 | Server generation | **Complete** | `procgen_suite` + C# procgen tests | Spot-checks open (seed, offline) | [M3_IMPLEMENTATION_LOG.md](../design/M3_IMPLEMENTATION_LOG.md) |
| M4 | Gameplay loop | **Complete** | `hub_m4_suite`, `progression_suite`, `inventory_suite` | TEST-4.1 soak open | [M4_IMPLEMENTATION_LOG.md](../design/M4_IMPLEMENTATION_LOG.md) |
| M5 | Content pack A | **Complete** | `m5_suite` (70 tests) | Feel gates § M5 | [MANUAL_PLAYTEST_CHECKLIST.md](../design/MANUAL_PLAYTEST_CHECKLIST.md) |
| M6 | Content pack B | **Complete** | `m6_suite` (57 tests) | Feel gates [MANUAL_PLAYTEST_CHECKLIST.md § M6](../design/MANUAL_PLAYTEST_CHECKLIST.md#m6--content-pack-b) (mirror: [M6_MANUAL_PLAYTEST_CHECKLIST.md](../design/M6_MANUAL_PLAYTEST_CHECKLIST.md)) | [M6_IMPLEMENTATION_LOG.md](../design/M6_IMPLEMENTATION_LOG.md) |
| M7 | EA polish / Steam | **Not started** | Partial (existing suites) | All § M7 items open | [M7-EA-POLISH.md](phases/M7-EA-POLISH.md) |

---

## M6 close criteria (automated ✅)

- 5 EA biomes registered; frozen + cathedral procgen + dungeon build
- 20 enemies + 8 bosses in catalog with scenes
- 79 items (≤80 cap), 25 achievements
- Leaderboards API + web pages + a11y baseline
- `m6_suite`: biomes, procgen, dungeon build, enemy/boss scenes, room preloads, items, achievements, audio, balance doc

**Deferred to M7 / post-EA:** OAuth, input remapping UI, mythic unique rules, status HUD icon art, OGG audio, final room art. **Manual feel playtest:** [MANUAL_PLAYTEST_CHECKLIST.md § M6](../design/MANUAL_PLAYTEST_CHECKLIST.md#m6--content-pack-b) (100 checklist IDs; mirror: [M6_MANUAL_PLAYTEST_CHECKLIST.md](../design/M6_MANUAL_PLAYTEST_CHECKLIST.md)).

---

## M7 next actions

1. Open [M7-EA-POLISH.md](phases/M7-EA-POLISH.md)
2. STEAM-7.1 → Steamworks init
3. Close manual gates in [MANUAL_PLAYTEST_CHECKLIST.md](../design/MANUAL_PLAYTEST_CHECKLIST.md) (M3–M7 sections)
4. Meet [07-EA-DEFINITION-OF-DONE.md](07-EA-DEFINITION-OF-DONE.md)

---

## Validation commands

```powershell
./scripts/run-all-validation.ps1
```

Report: `reports/validation-summary.json`
