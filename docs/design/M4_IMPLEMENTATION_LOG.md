# M4 implementation log

> **Phase:** M4 — Full gameplay loop (phase file removed on close)  
> **Depends on:** M3 closed — [M3_IMPLEMENTATION_LOG.md](M3_IMPLEMENTATION_LOG.md)  
> **Goal:** Town → choose dungeon → run → loot → upgrade → repeat with cloud saves.

**Started:** 2026-07-30  
**Closed:** 2026-07-30  
**Validated:** 2026-07-30 — `./scripts/run-all-validation.ps1` (52 C# unit, 12 integration, 45 content, 152 Godot tests, 0 failures)

---

## Status

All M4 code milestones implemented. Automated validation green.

| Milestone | Status | Notes |
|-----------|--------|-------|
| HUB-4.1–4.4 | ✅ | `hub.tscn` — blacksmith, merchant, storage, arena, portal |
| NPC-4.1 | ✅ | Data-driven NPCs in `content/npcs/` |
| DLG-4.1 | ✅ | JSON dialogue runner with flag conditions |
| QUEST-4.1 | ✅ | Quest board; portals never blocked |
| SCHEMA-4.1–4.2 | ✅ | `character-state.v1.json`, affix schemas |
| LOOT-4.1–4.2 | ✅ | Affix roller (Common–Rare live); full EA equipment slots |
| INV-4.1 | ✅ | Sort, filter, compare, grid UX |
| PROG-4.1–4.3 | ✅ | XP/level, talent tree, run relics (`RunBuffs`) |
| SAVE-4.1–4.2 | ✅ | `GET/PUT /api/v1/saves/current`, local cache, backups |
| FLOW-4.1 | ✅ | Death/escape economy — [run_economy.md](run_economy.md) |
| TEST-4.1 | ⬜ manual | Ten-run soak — [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) § M4 |

---

## Validation (2026-07-30)

| Check | Result |
|-------|--------|
| `./scripts/run-all-validation.ps1` | **PASS** |
| C# unit (`Aumbrye.UnitTests`) | **52/52** |
| C# integration (`Aumbrye.IntegrationTests`) | **12/12** |
| Godot suites (`hub_m4_suite`, `progression_suite`, `inventory_suite`, …) | **152/152** |
| Content validator | **45 OK** (14 hub packs skipped — no schema yet; see M5 `SCHEMA-5.1`) |

---

## Key paths

| Area | Path |
|------|------|
| Hub scene (main) | `apps/game/client/scenes/hub/hub.tscn` |
| Hub services | `apps/game/client/scripts/hub/` |
| NPC / dialogue / quests | `scripts/npc/`, `scripts/dialogue/`, `scripts/quests/` |
| Affixes + progression content | `content/affixes/`, `content/talents/`, `content/relics/` |
| Inventory UX | `scripts/ui/inventory_ui.gd` |
| Run economy | `docs/design/run_economy.md` |
| Cloud save API | `services/backend/` Saves feature |
| Validation | `apps/game/client/scripts/validation/suites/hub_m4_suite.gd` |

---

## Autoloads (post-M4)

`RunFlow`, `ApiConfig`, `LocalSave`, `CharacterService`, `ProgressionService`, `RunBuffs`, `InventoryService`, `StorageService`, `QuestService`, `AudioDirector`

---

## How to run

```bash
# Full automated gate
./scripts/run-all-validation.ps1

# Backend integration (optional; not in run-automated-tests.ps1)
dotnet test services/backend/tests/Aumbrye.IntegrationTests/Aumbrye.IntegrationTests.csproj
```

**Godot:** Main scene `res://scenes/hub/hub.tscn`. Offline procgen via `LocalProcgen` + `procgen-cli` (M3 lock).

---

## Deferred (post-M4 close)

Do not reopen M4 implementation for these — track in the target phase or [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md).

| Item | Target | Notes |
|------|--------|-------|
| TEST-4.1 ten-run soak | Manual § M4 | Log in [m4_soak_notes.md](m4_soak_notes.md) |
| Cloud save E2E (second device/session) | Manual § M4 / M7 `STEAM-7.3` | Requires running API + two sessions |
| Online `POST /runs` for new dungeons | M5 `NET-5.1` | Offline `LocalProcgen` remains default |
| NPC/quest/dialogue/relic/recipe JSON schemas | M5 `SCHEMA-5.1` | `validate.mjs` skips 14 packs today |
| Epic+ affix balance / Mythic uniques | M5 `LOOT-5.2` / M6 | Tables stubbed; Common–Rare live |
| Gamepad-only full loop | M7 `POLISH-7.1` | Structural controller nav done; feel gate manual |
| Save JSON integer normalization | M5 `SAVE-5.1` | `quantity`/`x`/`y` sometimes serialize as floats; loads fine |

**Next phase:** [M6-CONTENT-PACK-B.md](../plan/phases/M6-CONTENT-PACK-B.md)
