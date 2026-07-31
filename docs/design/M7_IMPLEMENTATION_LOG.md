# M7 Implementation Log

**Phase:** M7 — EA polish + multi-floor dungeons + Umbral modes + Steam ship prep  
**Closed (automated):** 2026-07-31  
**EA ship:** pending manual gates — [07-EA-DEFINITION-OF-DONE.md](../plan/07-EA-DEFINITION-OF-DONE.md)  
**Phase snapshot:** [M-PHASES-STATUS.md](../plan/M-PHASES-STATUS.md)  
**Manual gates:** [M7_MANUAL_PLAYTEST_CHECKLIST.md](M7_MANUAL_PLAYTEST_CHECKLIST.md) · [MANUAL_PLAYTEST_CHECKLIST.md § M7](MANUAL_PLAYTEST_CHECKLIST.md#m7--ea-polish--ship)

---

## Summary

M7 delivered 10-floor multi-floor dungeon runs with **floor chunking** (single active floor), **Umbral Endless** (infinite floors + skip consumables), **Umbral Waves** (lobby + milestone waves + isolated inventory), Steam/crash/glyph/tutorial stubs, save migrator v3, release CI workflow, and `m7_suite` (**65 tests**). Phase file `docs/plan/phases/M7-EA-POLISH.md` was removed after automated close; **this log is the canonical record**.

---

## Fully implemented (automated / structural)

| Milestone | Summary | Verification |
|-----------|---------|--------------|
| **FLOOR-7.x** | 10-floor main mode; per-floor seed mix; stair lever; floor 10 lobby + Forgotten Castle final boss; max 2 secrets/floor | `m7.floor.*`, `m7.procgen.*`, `m7.boss.*` |
| **FLOOR-7.x chunking** | Only current floor in scene tree; unload on ascend; v3 save without `floorDefinitions` | `m7.floor.chunking_api`, `m7.floor.builder_unload` |
| **ENDLESS-7.x** | Hub portal + menu; infinite floors; tier scaling after F10; skip items; save/continue | `m7.endless.*`, `m7.skip.*` |
| **WAVES-7.x** | Hub portal; 10-chest lobby; milestones 5/10/20/50; prep walls; isolated inventory; `wavesActiveRun` save | `m7.waves.*` |
| **SKIP-7.x** | 4 skip consumables in catalog + global drop table | `m7.skip.items_catalog`, `m7.skip.loot_table` |
| **STEAM-7.1** | `SteamService` stub init path | `m7.steam.stub_init` |
| **STEAM-7.2** | Achievement sync stub | `m7.steam.achievement_sync_stub` |
| **STEAM-7.3** | Cloud policy documented | `docs/SAVE_MIGRATIONS.md` |
| **STEAM-7.4** | Auth ticket deferred; email auth unaffected | `m7.steam.auth_ticket_deferred` |
| **POLISH-7.1** | `InputGlyphService` + controller glyph labels | `m7.polish.controller_glyphs` |
| **POLISH-7.2** | `HubTutorialService` skippable hub tips | `m7.polish.hub_tutorial` |
| **PERF-7.2** | `CrashLogger` autoload + hooks | `m7.perf.crash_logger` |
| **PERF-7.1 (partial auto)** | Enemy pool module present | `m7.perf.enemy_pool` |
| **SCHEMA-7.1** | `SaveMigrator` v1→v2→v3; `SAVE_MIGRATIONS.md` | `m7.save.migration_floor_fields`, `m7.schema.migration_doc` |
| **CI-7.1** | `.github/workflows/release.yml` stub | `m7.ci.release_workflow` |
| **SHIP-7.x (structural)** | Manual checklist + known issues docs exist | `m7.ship.manual_checklist` |

---

## Partial / deferred (code)

| Item | Milestone | Status | Notes |
|------|-----------|--------|-------|
| GodotSteam binary / Steam launch | STEAM-7.1 | Stub | Needs Steam App ID + SDK in repo/CI |
| Steam overlay / achievements in client | STEAM-7.1–7.2 | Manual | Stub sync only until SDK build |
| Steam Cloud file I/O bridge | STEAM-7.3 | Documented | Backend cloud remains source of truth |
| 1080p60 GPU profiling pass | PERF-7.1 | Manual | Pool module exists; no CI perf gate |
| Final boss other 4 biomes | FLOOR-7.x | Stub | Forgotten Castle fully implemented |
| Waves full equip UI | WAVES-7.x | Partial | `waves_inventory` exists; no equip panel |
| Endless retreat-to-hub lever | ENDLESS-7.x | Not implemented | Die-only exit |
| Umbral dedicated art palette | ENDLESS/WAVES | Stub | Reuses `dark_cathedral` materials |
| Steam depot upload / public branch | SHIP-7.3 | Manual | CI export stub only |
| Store page / trailer | SHIP-7.2 | Manual | Not started |
| ≥20 external playtesters | SHIP-7.1 | Manual | Checklist open |
| Hotfix process doc | SHIP-7.3 | Manual | Checklist open |

See also [KNOWN_ISSUES_M7.md](KNOWN_ISSUES_M7.md).

---

## Manual-only gates

Tracked in [MANUAL_PLAYTEST_CHECKLIST.md § M7](MANUAL_PLAYTEST_CHECKLIST.md#m7--ea-polish--ship) (**49 § M7 IDs** + **19 carry-over** `M7.*` elsewhere = **68 total**).

| Area | Milestone | Key IDs |
|------|-----------|---------|
| Multi-floor feel | FLOOR-7.x | `M7.floor.ten_clear`, `M7.floor.stair_lever_*`, `M7.floor.chunk_*` |
| Umbral Endless | ENDLESS-7.x | `M7.endless.portal`, `M7.endless.past_ten`, `M7.endless.skip_*` |
| Umbral Waves | WAVES-7.x | `M7.waves.portal`, `M7.waves.reward`, `M7.waves.equip_feel` |
| Steam (SDK required) | STEAM-7.x | `M7.steam.launch`, `M7.steam.overlay`, `M7.steam.cloud` |
| Controller | POLISH-7.1 | `M7.gamepad.*` (M1 carry-over) |
| Tutorial feel | POLISH-7.2 | `M7.polish.hub_tips`, `M7.polish.arena_roll` |
| Performance | PERF-7.x | `M7.perf.1080p60`, `M7.perf.crash_reports` |
| Ship / EA DoD | SHIP-7.x | `M7.ship.external_playtest`, `M7.ship.ea_branch`, `M7.ship.known_issues` |
| Inherited feel | M3–M6 | `M7.movement.*`, `M7.combat.*`, etc. |

**EA Definition of Done:** [07-EA-DEFINITION-OF-DONE.md](../plan/07-EA-DEFINITION-OF-DONE.md) — all product/perf/playtest boxes remain **open** until manual sign-off.

---

## Inherited deferred (from M4–M6, tracked during M7)

| Item | Milestone | Notes |
|------|-----------|-------|
| Gamepad-only full loop feel | POLISH-7.1 | Structural nav done in M4 |
| Cloud save E2E (second device) | STEAM-7.3 | `M7.steam.cloud` + M4 `M4.cloud_e2e` |
| TEST-4.1 ten-run soak | M4 manual | [m4_soak_notes.md](m4_soak_notes.md) |
| M5.theme.blind (all 5 biomes) | M5 manual | Extends `M5.theme.blind` |
| M5 manual feel gates | M5 manual | Weapons, statuses, bosses, audio |
| Online procgen default-on | NET-5.1 carry | Path exists; off by default |

---

## Design decisions (defaults used)

| Question | Decision |
|----------|----------|
| Umbral visual theme | Reuse `dark_cathedral` materials in waves arena (stub palette) |
| Waves chest policy | Open anytime in lobby; **Ready** blocked until all 10 opened |
| Endless retreat | No explicit retreat lever — death ends run |
| Waves equip UI | Minimal — items in waves inventory; full equip panel deferred |
| Waves early exit | No item transfer to main inventory before wave 50 clear |

---

## Validation

- Suite: `m7_suite.gd` — **65 tests**
- Full gate: `./scripts/run-all-validation.ps1` — **363 Godot** + **83 C#** = **446 automated** (0 failures)
- Content: `content/schemas/global-drops.v1.json` for `content/loot/global_drops.json`

---

## Key paths

| Area | Path |
|------|------|
| Run modes | `apps/game/client/scripts/app/run_mode_config.gd` |
| Floor config / chunking | `apps/game/client/scripts/dungeon/run_floor_config.gd`, `run_flow.gd`, `dungeon_builder.gd` |
| Endless | `endless_difficulty.gd`, `umbral_endless_menu.gd` |
| Waves | `waves_run_service.gd`, `waves_run.tscn`, `umbral_waves_menu.gd` |
| Skip items | `skip_floor_service.gd`, `content/loot/global_drops.json` |
| Steam stub | `apps/game/client/scripts/platform/steam_service.gd` |
| Save v3 | `save_migrator.gd`, `docs/SAVE_MIGRATIONS.md` |
| Multi-floor design | [multi_floor_dungeons.md](multi_floor_dungeons.md) |

---

## User input still needed

1. **Steam App ID** for `steam_appid.txt` and depot config
2. **GodotSteam** plugin path or CI build step
3. **Crash report upload** destination (PERF-7.2 playtest verification)
4. **Waves early-exit policy** copy for store/known issues
5. **Umbral art pass** — dedicated palette vs `dark_cathedral` stub
