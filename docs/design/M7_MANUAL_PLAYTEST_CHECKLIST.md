# M7 Manual Playtest Checklist (mirror)

> **Canonical source:** [MANUAL_PLAYTEST_CHECKLIST.md § M7](MANUAL_PLAYTEST_CHECKLIST.md#m7--ea-polish--ship) — edit items there only.  
> This file is a printable/export mirror for M7 EA polish + ship feel gates.  
> Implementation record: [M7_IMPLEMENTATION_LOG.md](M7_IMPLEMENTATION_LOG.md)  
> Known issues: [KNOWN_ISSUES_M7.md](KNOWN_ISSUES_M7.md)

**Tester:** _____________  
**Date:** _____________  
**Build / commit:** _____________

---

## Before starting

1. Run `./scripts/run-all-validation.ps1` — must pass with **0 failures** (`m7_suite`: 65/65; `m6_suite`: 73/73).
2. For Steam tests: place `steam_appid.txt` locally (gitignored) and launch via Steam if GodotSteam SDK available.
3. Review [07-EA-DEFINITION-OF-DONE.md](../plan/07-EA-DEFINITION-OF-DONE.md) — M7 manual gates map to EA ship criteria.

---

## Quick roll-up (sign-off targets)

| ID | Item | Status |
|----|------|--------|
| M7.floor.ten_clear | Complete 10-floor Forgotten Castle run | [ ] |
| M7.floor.chunk_single_active | Only current floor loaded after ascend | [ ] |
| M7.floor.stair_lever_ascend | Boss → lever → next floor (no mid portal) | [ ] |
| M7.floor.final_boss_phases | Floor 10 lobby + final boss phases 1–3 | [ ] |
| M7.endless.portal | Umbral Endless hub portal (New / Continue) | [ ] |
| M7.endless.past_ten | Endless run past floor 10 with scaling | [ ] |
| M7.endless.skip_consume | Skip item consumed; correct start floor | [ ] |
| M7.waves.portal | Umbral Waves hub portal + lobby | [ ] |
| M7.waves.reward | 50-wave clear → pick 3 items to main inventory | [ ] |
| M7.steam.overlay | Steam overlay opens (if SDK) | [ ] |
| M7.gamepad.hub_castle_loop | Full hub → castle → escape gamepad-only | [ ] |
| M7.perf.1080p60 | 1080p ≥60 FPS in typical combat rooms | [ ] |
| M7.ship.external_playtest | ≥20 playtesters completed full loop | [ ] |
| M7.ship.known_issues | Known-issues list ready for store page | [ ] |

---

## Full checklist

See **[MANUAL_PLAYTEST_CHECKLIST.md § M7](MANUAL_PLAYTEST_CHECKLIST.md#m7--ea-polish--ship)** for the complete tables:

| Section | Items | IDs prefix |
|---------|-------|------------|
| Closed playtest | 3 | `M7.ship.external_playtest`, `M7.ship.crash_rate`, `M7.ship.qualitative` |
| Performance | 4 | `M7.perf.*` |
| Multi-floor + chunking | 14 | `M7.floor.*` |
| Umbral Endless | 6 | `M7.endless.*` |
| Umbral Waves | 10 | `M7.waves.*` |
| Steam (SDK) | 5 | `M7.steam.*` |
| Tutorial | 3 | `M7.polish.*` |
| Release ship | 4 | `M7.ship.store_assets`, `M7.ship.hotfix_doc`, `M7.ship.ea_branch`, `M7.ship.known_issues` |
| Controller (M1 carry-over) | 3 | `M7.gamepad.*` |
| Feel carry-over (M3–M6) | 19 | `M7.movement.*`, `M7.combat.*`, `M7.hub.*`, etc. |

**Total:** 49 checklist IDs in § M7 (+ 19 inherited feel items tagged `M7.*` elsewhere = **68 total**).

---

## Milestone mapping (for traceability)

| Plan milestone | Manual IDs |
|----------------|------------|
| FLOOR-7.x | `M7.floor.*` |
| ENDLESS-7.x | `M7.endless.*` |
| WAVES-7.x | `M7.waves.*` |
| STEAM-7.1–7.4 | `M7.steam.*` |
| POLISH-7.1 | `M7.gamepad.*` |
| POLISH-7.2 | `M7.polish.*` |
| PERF-7.1–7.2 | `M7.perf.*` |
| SHIP-7.1–7.3 | `M7.ship.*` |

Automated coverage: [M7_IMPLEMENTATION_LOG.md](M7_IMPLEMENTATION_LOG.md).

---

## Sign-off

| Area | Pass | Date | Tester |
|------|------|------|--------|
| M7 multi-floor + Umbral modes | [ ] | | |
| M7 Steam + ship (when SDK ready) | [ ] | | |
| M7 feel & UX (carry-over) | [ ] | | |
| EA DoD ready | [ ] | | |

When complete, mark rows in the canonical [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) sign-off table.
