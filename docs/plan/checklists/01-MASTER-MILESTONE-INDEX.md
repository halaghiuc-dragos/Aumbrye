# Checklist: Master Milestone Index

> Flat index for agents. Prefer phase files for acceptance criteria.
> Status columns are informational; authoritative checkboxes live in `phases/`.

## M0 Foundation ✅

All milestones complete. Inventory and deferred items: [systems/00-SETUP-CI.md](../systems/00-SETUP-CI.md).

| ID | Title | Status |
|----|-------|--------|
| SETUP-0.1 | Monorepo root | done |
| SETUP-0.2 | Docker Postgres/Redis | done |
| SETUP-0.3 | Godot skeleton | done |
| SETUP-0.4 | ASP.NET solution | done |
| SETUP-0.5 | Web stub | done |
| API-0.1 | Health | done |
| SCHEMA-0.1 | Schemas + validator | done |
| SCHEMA-0.2 | Dungeon fixture | done |
| CI-0.1 | Workflow skeleton | done |
| CI-0.2 | Backend CI | done |
| CI-0.3 | Web CI | done |
| CI-0.4 | Content CI | done |
| DOC-0.1 | Standards + ADR-0001 | done |

## M1 Combat ✅

All milestones complete (KB/M signed off 2026-07-29). Archive: [M1_IMPLEMENTATION_LOG.md](../design/M1_IMPLEMENTATION_LOG.md). Gamepad playtest deferred.

| ID | Title | Status |
|----|-------|--------|
| MOVE-1.1 | Locomotion | done |
| MOVE-1.2 | Jump/dodge | done |
| CAM-1.1 | Orbit/zoom | done |
| CAM-1.2 | Lock-on | done |
| COMBAT-1.1 | Resources | done |
| COMBAT-1.2 | Sword | done |
| COMBAT-1.3 | Block | done |
| COMBAT-1.4 | Parry | done |
| COMBAT-1.5 | Feedback | done |
| WPN-1.1 | Hitboxes | done |
| ENEMY-1.1 | Training enemy | done |
| ENEMY-1.2 | Hit reactions | done |
| ENEMY-1.3 | Duel tuning | done |
| UI-1.1 | Combat HUD | done |
| DBG-1.1 | Arena | done |

## M2 Vertical slice

| ID | Title |
|----|-------|
| ART-2.1 | Castle kit |
| DUNGEON-2.1 | Layout |
| DUNGEON-2.2 | Fixture |
| BUILDER-2.1 | Builder |
| ENEMY-2.1–2.3 | Castle enemies |
| TRAP-2.1 | Traps |
| SCHEMA-2.1 | Item/inventory schema |
| INV-2.1 | Inventory MVP |
| LOOT-2.1 | Static chests |
| BOSS-2.1–2.2 | Castle knight |
| FLOW-2.1 | Escape/results |
| SAVE-2.1 | Local save |
| AUDIO-2.1 | Audio stubs |
| HUB-2.1 | Hub stub |

## M3 Server generation

| ID | Title |
|----|-------|
| AUTH-3.1 | JWT auth |
| PROC-3.1–3.6 | Generator pipeline |
| API-3.1–3.3 | Runs API |
| NET-3.1 | Godot API client |
| FLOW-3.1 | Generated E2E |
| SCHEMA-3.1–3.2 | OpenAPI + versions |
| TEST-3.1 | Procgen tests |

## M4 Gameplay loop

| ID | Title |
|----|-------|
| HUB-4.1–4.4 | Hub services |
| NPC-4.1 | NPCs |
| DLG-4.1 | Dialogue |
| QUEST-4.1 | Quests |
| SCHEMA-4.1–4.2 | Character + affix |
| LOOT-4.1–4.2 | Affixes + slots |
| INV-4.1 | Inventory UX |
| PROG-4.1–4.3 | Level/talents/relics |
| SAVE-4.1–4.2 | Cloud + backups |
| FLOW-4.1 | Economy |
| TEST-4.1 | 10-run soak |

## M5 Content A

| ID | Title |
|----|-------|
| THEME-5.1–5.3 | Castle pass, Caverns, Swamp |
| DMG-5.1–5.2 | Damage + status |
| WPN-5.1–5.5 | 4 weapons + swap |
| AUDIO-5.1 | Audio profiles |
| BOSS-5.1–5.2 | Theme bosses |
| ITEM-5.1 | Items batch A |
| BAL-5.1 | Balance pass |

## M6 Content B

| ID | Title |
|----|-------|
| THEME-6.1–6.2 | Fortress, Cathedral |
| ENEMY-6.1 | Roster ≤20 |
| BOSS-6.1 | Bosses ≤8 |
| ITEM-6.1 | Items ≤80 |
| META-6.1–6.2 | Achievements, boards |
| WEB-6.1–6.4 | Website |
| A11Y-6.1 | Accessibility |
| AUTH-6.1 | OAuth optional |
| BAL-6.1 | Tools + balance |
| PERF-6.1 | Perf pass |

## M7 EA ship

| ID | Title |
|----|-------|
| STEAM-7.1–7.4 | Steam integration |
| POLISH-7.1–7.2 | Controller + tutorial |
| PERF-7.1–7.2 | Optimize + crashes |
| SCHEMA-7.1 | Save migrations |
| CI-7.1 | Release workflow |
| SHIP-7.1–7.3 | Playtest, store, launch |
