# M6 Implementation Log

**Phase:** M6 — Content Pack B + Meta  
**Closed:** 2026-07-31 (automated gates green; manual feel gates open)  
**Next phase:** EA ship (manual) — [M7_IMPLEMENTATION_LOG.md](M7_IMPLEMENTATION_LOG.md)  
**Phase snapshot:** [M-PHASES-STATUS.md](../plan/M-PHASES-STATUS.md)

---

## Summary

M6 delivered EA content volume (5 themes, 20 enemies, 8 bosses, 79 catalog items), meta features (achievements + leaderboards), website pages, accessibility baseline, balance/perf tooling, and automated validation (`m6_suite`, 73 tests). Phase file `docs/plan/phases/M6-CONTENT-PACK-B.md` was removed after close; this log is the canonical record.

---

## Fully implemented

| Milestone | Summary |
|-----------|---------|
| **THEME-6.1** | `frozen_fortress` biome JSON, 9 room templates (`scenes/rooms/frozen/`), materials, audio profile, frost hazards, procgen prefix `frozen_` |
| **THEME-6.2** | `dark_cathedral` biome JSON, 9 room templates (`scenes/rooms/cathedral/`), materials, audio profile, procgen prefix `cathedral_` |
| **ENEMY-6.1** | 20-enemy EA roster; M5 gap fills (`castle_hound`, `crystal_crawler/spitter/wisp`, `swamp_slasher/spitter/brute/swarm`) + M6 frost/cathedral enemies |
| **BOSS-6.1** | 8 boss JSON defs; scenes for `boss_frost_warlord`, `boss_cathedral_hollow`, `miniboss_cathedral_bell`; roster aliases for M2/M5 bosses |
| **ITEM-6.1** | Catalog: 79 items (≤80 cap); theme uniques for frozen/cathedral; expanded affix pool |
| **META-6.1** | `content/achievements/catalog.json` (25), `AchievementService` autoload, toast UI, unlock on escape |
| **META-6.2** | `ILeaderboardService` (Redis + in-memory), `GET/POST /api/v1/leaderboards`, client opt-in submit via `ApiClient.submit_leaderboard` |
| **WEB-6.1** | Brand-first React landing (`apps/web/src/pages/Landing.tsx`) |
| **WEB-6.2** | Account page + auth flow against local API |
| **WEB-6.3** | Patch notes (JSON) + wiki stubs |
| **WEB-6.4** | Leaderboards page wired to API |
| **A11Y-6.1** | `AccessibilitySettings` — UI scale, reduce camera shake, colorblind damage colors, subtitle scale |
| **BAL-6.1** | `scripts/balance/balance-cli.ps1`, `docs/design/balance_m6.md` |
| **PERF-6.1** | `EnemyPool`, `docs/design/performance_m6.md` (1080p60 target documented) |
| **Validation** | `m6_suite.gd` registered in `validation_runner.gd` |

---

## Partial / deferred

| Item | Status | Notes |
|------|--------|-------|
| **AUTH-6.1 OAuth** | Deferred | Google/Discord not implemented; email/password works |
| **Input remapping UI** | Deferred | Settings cover UI scale/shake/colorblind; full rebind UI → M7 |
| **Mythic unique rules** | Partial | Epic+ affix min counts; per-item unique behavior stubbed |
| **Status HUD icons** | Partial | Colored squares (M5 carry-over → M7) |
| **OGG audio** | Partial | Generator-tone stubs for new biomes |
| **Room art** | Partial | Blockout + theme materials; no final diorama meshes |
| **Manual playtest** | Open | [MANUAL_PLAYTEST_CHECKLIST.md § M6](MANUAL_PLAYTEST_CHECKLIST.md#m6--content-pack-b) (100 IDs); mirror: [M6_MANUAL_PLAYTEST_CHECKLIST.md](M6_MANUAL_PLAYTEST_CHECKLIST.md) |

---

## Post-close fixes

### UTF-8 BOM (2026-07-31)

Batch-generated `.tscn` and `.gd` files had UTF-8 BOM prefixes, causing `Parse Error: Expected '['` at line 1. Fixed by stripping BOM from 54 files. **Prevention:** write Godot assets with UTF-8 no BOM.

### m6_suite extended (2026-07-31)

Added dungeon build, enemy/boss scene resolution, and room preload tests (25 → 57 → **73** tests). Covers frozen/cathedral procgen → `DungeonBuilder` → boss door wiring, web, leaderboards, a11y.

---

## Wiring

- `BiomeRegistry` — 5 EA biomes
- `RoomTemplateCatalog.cs` / `RoomTypeAssigner.cs` — frozen/cathedral prefixes
- `ThemeLootTables.cs` — frozen/cathedral loot + traps
- Biome JSON enemy/boss pools — roster IDs
- `RunFlow._handle_escape_meta` — achievements + opt-in leaderboard submit
- `LeaderboardSettings` + settings UI toggle
- `project.godot` — `AchievementService` autoload

---

## EA content counts

| Asset | Count | Cap |
|-------|-------|-----|
| Themes | 5 | 5 |
| Enemies (roster) | 20 | 20 |
| Bosses | 8 | 8 |
| Catalog items | 79 | 80 |
| Achievements | 25 | ~25 |

---

## Validation (final — 2026-07-31)

| Suite | Result |
|-------|--------|
| `./scripts/run-all-validation.ps1` | **PASS** |
| Godot headless (`m6_suite` + all suites) | **363 passed, 0 failed** (`m6_suite`: 73/73) |
| Backend `dotnet test` | **79 passed** (67 unit + 12 integration) |
| Web `npm run build` | **PASS** (via content/CI layer) |
| M6 scene load | **PASS** (BOM fix; scene + room preload tests) |

### Godot MCP verification (2026-07-31)

| MCP server | Status | Notes |
|------------|--------|-------|
| `project-0-Aumbrye-godot-mcp` | **Ready** | `project_info`, `filesystem_file`, `debug_log` work |
| `project-0-Aumbrye-godot-mcp-docs` | **Ready** | `get_documentation_tree` / `get_documentation_file` available |
| Editor-interface tools | **Unavailable** | `editor_status`, `scene_management`, `scene_hierarchy`, `scene_run` return "Editor interface not available" when Godot editor GUI is not connected to MCP plugin |

**MCP probes performed:**

- `project_info` → Godot 4.7.1, main scene `res://scenes/hub/hub.tscn`
- `filesystem_file` exists checks → `frozen_boss.tscn`, `boss_frost_warlord.tscn`, `cathedral_boss.tscn` ✅
- `filesystem_file` read → `frozen_boss.tscn` parses cleanly (no BOM)
- `debug_log` print → success

**Note:** Headless validation (`run-all-validation.ps1`) is the authoritative automated gate. MCP editor tools require the Godot editor open with the MCP plugin active.

---

## Key paths

| Area | Path |
|------|------|
| Frozen rooms | `apps/game/client/scenes/rooms/frozen/` |
| Cathedral rooms | `apps/game/client/scenes/rooms/cathedral/` |
| M6 enemies | `apps/game/client/scenes/enemies/frost_*`, `cathedral_*`, gap fills |
| Achievements | `content/achievements/catalog.json` |
| Leaderboards API | `services/backend/src/Aumbrye.Api/Endpoints/LeaderboardsEndpoints.cs` |
| Web app | `apps/web/src/` |
| Known issues | [KNOWN_ISSUES_M6.md](KNOWN_ISSUES_M6.md) |
