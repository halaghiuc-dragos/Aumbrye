# Validation Platform

> Automated validation for Aumbrye M1–M3. Human gates live in [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md).

## Architecture

```
apps/game/client/scripts/validation/
  validation_runner.gd    # orchestrator: runs suites, writes JSON report, quits
  test_context.gd         # shared helpers: record, save backup/restore, fixtures
  validation_suite.gd     # base class for suites
  suites/
    setup_suite.gd        # project config, autoloads, scenes, input, MCP plugin
    content_suite.gd      # enemies, items, catalogs, room templates, audio
    inventory_suite.gd    # grid inventory placement and equip
    procgen_suite.gd      # seed gen, determinism, offline RunFlow, builder guards
    save_suite.gd         # continuable rules, camera pref, snapshot guards
    hub_suite.gd          # menu buttons, portal/arena, continue button states, seed UI
    arena_suite.gd        # training arena, training grunt, reset API
    camera_suite.gd       # toggle action, FP API, persistence, debug overlay
    lock_on_suite.gd      # aim point, reticle center, auto-advance on death
    combat_suite.gd       # health/stamina/poise/guard, enemy death guards
    dungeon_suite.gd      # build pipeline, rooms/enemies/loot, snapshot round-trip
    player_suite.gd       # locomotion API, sprint, weapon controller
    flow_suite.gd         # RunFlow scene paths, offline procgen, results, debug seed
    m5_suite.gd           # M5 themes, weapons, statuses, schemas
    m6_suite.gd           # M6 content pack B: biomes, meta, web, a11y, leaderboards
    m7_suite.gd           # M7 multi-floor, Umbral modes, Steam/save/CI stubs
```

Entry scene: `res://scenes/debug/mcp_validation.tscn` → `validation_runner.gd`

Legacy alias: `scripts/debug/mcp_validation.gd` extends the runner.

## How to run

### All layers (recommended)

```powershell
# Godot not on PATH:
$env:GODOT_BIN = "C:\path\to\Godot_v4.7.1-stable_win64_console.exe"
./scripts/run-all-validation.ps1
```

Runs:
1. `./scripts/run-automated-tests.ps1` — C# unit tests + content JSON schemas
2. `./scripts/run-mcp-validation.ps1` — Godot in-engine suites
3. Merges into `reports/validation-summary.json`
4. Exit code 1 if any layer fails

### Godot only

```powershell
./scripts/run-mcp-validation.ps1
```

Report: `%APPDATA%\Godot\app_userdata\Aumbrye\mcp_validation.json`

### From Cursor (Godot editor open)

1. Godot MCP plugin on `http://127.0.0.1:3000/mcp`
2. `scene_run` → `res://scenes/debug/mcp_validation.tscn`
3. Read report via `reportPath` in JSON output

## Report schema v2

```json
{
  "schemaVersion": 2,
  "generatedAt": "...",
  "passed": 0,
  "failed": 0,
  "suites": [
    { "name": "setup_suite", "category": "setup", "passed": 0, "failed": 0, "duration_ms": 0 }
  ],
  "tests": [
    {
      "id": "flow.continue.midrun_restores_hp",
      "category": "flow",
      "checklist_ref": "M3.hub.continue_enabled",
      "pass": true,
      "message": "...",
      "duration_ms": 1
    }
  ],
  "coverage": {
    "automated": 0,
    "manual_remaining": ["M7.movement.feel", "..."]
  },
  "reportPath": "..."
}
```

## Test ID conventions

| Pattern | Example | Meaning |
|---------|---------|---------|
| `{category}.{feature}` | `procgen.seed_generates` | Stable test identifier |
| `{category}.{entity}_{detail}` | `content.enemy_json_scene_castle_grunt` | Per-entity checks |
| `setup.scene_{basename}` | `setup.scene_hub` | Scene existence |

`checklist_ref` links to manual checklist or milestone when applicable (e.g. `M3.hub.continue_enabled`).

## Adding a test

1. Pick the suite matching the system (or create a new suite extending `ValidationSuite`).
2. In `run()`, call `ctx.timed_record(id, category, passed, message, start_ms, checklist_ref)`.
3. Use `await ctx.await_physics()` / `await ctx.await_frame()` instead of timers.
4. Mutating save tests: `ctx.backup_save_file()` / `ctx.restore_save_file()`.
5. Register new suite in `validation_runner.gd` → `SUITE_SCRIPTS`.

## Automated vs manual (M7)

| Automated | Manual (M7 polish) |
|-----------|-------------------|
| Project setup, autoloads, input map | Movement feel, room traversal feel |
| Catalogs, scenes, scripts exist | HP bar visuals, shield block feel |
| Procgen determinism, seed rules | Loot/trap/boss interaction feel (E key) |
| Save continuable rules, snapshot API | Full continue playthrough scenarios |
| Hub menu wiring, continue button states | Hub Esc/Back interaction feel |
| Dungeon build pipeline, boss door/exit wiring | Camera toggle feel, relaunch persistence |
| Combat component APIs, enemy death guards | Lock-on readability in first person |
| Lock-on aim point, auto-advance | Training arena combat feel |
| Camera preference API round-trip | Cross-machine seed parity |
| RunFlow offline paths | Procgen-cli missing UX, offline hang |

See [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) § M7 for the canonical manual list. `TestContext.MANUAL_REMAINING` mirrors IDs written into each report.

## M6 / M7 test ID map (2026-07-31)

### M6 (`m6_suite.gd`)

| Area | Test IDs | Milestone |
|------|----------|-----------|
| Themes (frozen, cathedral) | `m6.biome.*`, `m6.procgen.*`, `m6.dungeon.*`, `m6.rooms.*` | THEME-6.1/6.2 |
| Enemies / bosses | `m6.enemies.roster`, `m6.bosses.roster`, `m6.scene.*` | ENEMY/BOSS-6.1 |
| Items | `m6.items.catalog_cap`, `m6.items.unique_*` | ITEM-6.1 |
| Achievements | `m6.achievements.*` | META-6.1 |
| Leaderboards | `m6.leaderboard.*` | META-6.2 |
| Web pages | `m6.web.*` | WEB-6.1–6.4 |
| Accessibility | `m6.a11y.*` | A11Y-6.1 |
| Balance / perf | `m6.balance.*`, `m6.perf.*` | BAL/PERF-6.1 |
| Escape meta | `m6.meta.escape_achievements` | META-6.1 |

### M7 (`m7_suite.gd`)

| Area | Test IDs | Milestone |
|------|----------|-----------|
| Multi-floor | `m7.floor.*`, `m7.procgen.*`, `m7.run_mode.*` | FLOOR-7.x |
| Final boss | `m7.boss.*` | FLOOR-7.5 |
| Umbral Endless | `m7.endless.*` | ENDLESS-7.x |
| Umbral Waves | `m7.waves.*`, `m7.hub.*_portal` | WAVES-7.x |
| Skip items | `m7.skip.*`, `m7.global_drops.*` | SKIP-7.x |
| Steam stub | `m7.steam.*` | STEAM-7.x |
| Polish | `m7.polish.*` | POLISH-7.x |
| Save / schema | `m7.save.*`, `m7.schema.*` | SCHEMA-7.1 |
| Perf / CI / ship | `m7.perf.*`, `m7.ci.*`, `m7.ship.*` | PERF/CI/SHIP-7.x |

### C# (backend / procgen)

| Area | Test class | Notes |
|------|------------|-------|
| Leaderboards | `LeaderboardServiceTests` | In-memory submit + filter |
| Final floor procgen | `FinalFloorGeneratorTests` | `isFinalFloor`, floor seed mix, biome prefixes |

## GdUnit

GdUnit/GUT deferred. This platform provides headless in-engine coverage without additional test framework dependencies. Revisit GdUnit for M4+ if input simulation or scene transition tests need richer harnessing.
