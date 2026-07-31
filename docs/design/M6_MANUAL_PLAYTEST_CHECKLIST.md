# M6 Manual Playtest Checklist (mirror)

> **Canonical source:** [MANUAL_PLAYTEST_CHECKLIST.md § M6](MANUAL_PLAYTEST_CHECKLIST.md#m6--content-pack-b) — edit items there only.  
> This file is a printable/export mirror for M6 Content Pack B feel gates.  
> Implementation record: [M6_IMPLEMENTATION_LOG.md](M6_IMPLEMENTATION_LOG.md)

**Tester:** _____________  
**Date:** _____________  
**Build / commit:** _____________

---

## Before starting

1. Run `./scripts/run-all-validation.ps1` — must pass with **0 failures** (`m6_suite` 73/73).
2. Start backend API (account + leaderboards) and web dev server if testing website/meta flows.

---

## Quick roll-up (sign-off targets)

| ID | Item | Status |
|----|------|--------|
| M6.theme.frozen | Frozen Fortress — generate + clear | [ ] |
| M6.theme.cathedral | Dark Cathedral — generate + clear | [ ] |
| M6.enemy.roster | 20-enemy roster combat sanity | [ ] |
| M6.boss.all_eight | All 8 bosses readable + clearable | [ ] |
| M6.meta.achievements | Achievement unlock + toast on escape | [ ] |
| M6.meta.leaderboards | Web leaderboards match API | [ ] |
| M6.web.account | Register/login against local API | [ ] |
| M6.a11y.settings | UI scale + reduce shake in settings | [ ] |
| M6.perf.smoke | 1080p combat room frame time spot-check | [ ] |

---

## Full checklist

See **[MANUAL_PLAYTEST_CHECKLIST.md § M6](MANUAL_PLAYTEST_CHECKLIST.md#m6--content-pack-b)** for the complete tables:

| Section | Items | IDs prefix |
|---------|-------|------------|
| Prerequisites | 4 | `M6.automated`, `M6.prereq.*` |
| Frozen Fortress | 10 | `M6.theme.frozen_*` |
| Dark Cathedral | 9 | `M6.theme.cathedral_*` |
| Boss spot-check | 8 | `M6.boss.*` |
| Enemy roster | 15 | `M6.enemy.*` |
| Items / loot | 9 | `M6.items.*` |
| Achievements | 6 | `M6.meta.achievement_*` |
| Leaderboards | 5 | `M6.meta.leaderboard_*`, `M6.web.leaderboards_page` |
| Website | 7 | `M6.web.*` |
| Accessibility | 6 | `M6.a11y.*` |
| Audio | 4 | `M6.audio.*` |
| Performance | 4 | `M6.perf.*` |
| Integration | 5 | `M6.integration.*` |
| M7 carry-over (optional) | 7 | `M6.deferred.*` |

**Total:** 100 checklist IDs (1 automated done, 99 manual open, 7 optional deferred).

---

## Sign-off

| Area | Pass | Date | Tester |
|------|------|------|--------|
| M6 manual playtest (feel) | [ ] | | |

When complete, mark rows in the canonical [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) sign-off table.
