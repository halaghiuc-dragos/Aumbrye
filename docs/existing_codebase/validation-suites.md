# Validation suites

Fifty-four suites are registered in `validation_runner.gd` `SUITE_PATHS` (`validation_runner.gd:20-74`). Each suite extends `ValidationSuite`, receives a shared `TestContext`, and records pass/fail/skip rows consumed by the harness in [`validation-harness.md`](validation-harness.md). Coverage is integration-heavy: most suites instantiate scenes or call autoloads headlessly; milestone delivery files (`m5_suite.gd`, `m6_suite.gd`, `m7_suite.gd`) remain on disk but report categories `biome`, `content`, and `run` with subsystem-prefixed test ids (no `m5.`/`m6.`/`m7.` prefixes).

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/validation/validation_runner.gd` | `SUITE_PATHS`, `MIN_ASSERTIONS`, reachability, JSON v3 + JUnit |
| `apps/game/client/scripts/validation/test_context.gd` | `record`, `skip`, `assert_*`, duplicate-id guard (`test_context.gd:42-56`) |
| `apps/game/client/scripts/validation/fixtures.gd` | `SEED_A`/`SEED_B`, `REQUIRED_*`, `SAVE_PATH` |
| `apps/game/client/scripts/validation/combat_fixture.gd` | Two-body combat arena for `combat_suite.gd` |
| `apps/game/client/scripts/validation/suites/*.gd` | One file per suite (54 registered) |
| `apps/game/client/scenes/debug/mcp_validation.tscn` | Scene entry → same `validation_runner.gd` |
| `docs/validation/manual-checklist.md` | Manual-only items referenced by `checklist_ref` |

### Registered suites

| Suite file | Category | Primary focus |
|------------|----------|---------------|
| `harness_suite.gd` | `harness` | Registration parity, duplicate ids, reachability, CLI options |
| `setup_suite.gd` | `setup` | Main scene, autoload roster, input actions, MCP plugin |
| `docs_suite.gd` | `docs` | Referenced doc paths, twin-tree link resolution, checklist headings |
| `platform_suite.gd` | `platform` | Steam stub, crash logger payload/retention/scrubbing |
| `quality_bar_suite.gd` | `quality` | Quality-bar doc criteria grep guards |
| `content_suite.gd` | `content` | Enemy/item JSON, shield stats, save migration doc rows |
| `biome_kit_suite.gd` | `biome_kit` | Per-biome kit assets and registry wiring |
| `audio_suite.gd` | `content` | `AudioDirector` biome switch and bus wiring |
| `content_drift_suite.gd` | `drift` | Content-vs-code drift (combat ids, affix keys) |
| `inventory_suite.gd` | `inventory` | Grid, equip, sort, filter, affix determinism |
| `progression_suite.gd` | `progression` | XP, talents, relic buffs, progression doc path |
| `procgen_suite.gd` | `procgen` | Determinism, `procgen.determinism_seed_sweep` (30+ seeds), builder guards |
| `placements_suite.gd` | `placements` | Placement offsets, treasure path, tier seeds |
| `room_graph_suite.gd` | `room_graph` | Phase-1 graph, ASCII dump, full pipeline determinism |
| `room_kit_suite.gd` | `room_kit` | Room kit prefixes and template kinds |
| `procgen_seed_health_suite.gd` | `procgen_seed_health` | `generate_reported` parity, 50-seed sweep, CLI exit contract |
| `cross_stack_parity_suite.gd` | `cross_stack_parity` | Mix-seed, kind-spec, biome catalog, CLI v1 output |
| `affix_suite.gd` | `affix` | Affix roll determinism |
| `room_content_suite.gd` | `room_content` | Room assignment, critical path, world-state reset |
| `world_state_suite.gd` | `world_state` | Hub/world flag persistence |
| `save_suite.gd` | `save` | Migrations, continuable rules via `LocalSave.run_is_continuable` |
| `net_suite.gd` | `net` | Transport stub, auth, save round-trip, offline finalize |
| `hub_suite.gd` | `hub` | Continue/portal/seed parsing via production helpers |
| `hub_m4_suite.gd` | `hub_m4` | NPCs, dialogue, quests, blacksmith, merchant, storage |
| `arena_suite.gd` | `arena` | Training dummy, duel reset, loadout sync |
| `camera_suite.gd` | `camera` | Toggle, first-person API, preference round trip |
| `lock_on_suite.gd` | `lock_on` | Aim API, FP policy, movement/camera suites, suffixed loop ids |
| `combat_suite.gd` | `combat` | `CombatFixture` pipeline, weapons, feedback, tokens |
| `trap_suite.gd` | `traps` | Trap placement and trigger behavior |
| `dungeon_suite.gd` | `dungeon` | Build, enemies, loot, boss door, snapshot round trip |
| `floor_shell_suite.gd` | `floor_shell` | Floor shell chunk load/unload |
| `player_suite.gd` | `player` | Locomotion constants, weapon controller wiring |
| `enemy_suite.gd` | `enemy` | Enemy presentation and death guards |
| `flow_suite.gd` | `flow` | Death/escape, results UI, continue, cloud sync wiring |
| `m5_suite.gd` | `biome` | Biomes, damage types, statuses, loadout gates (legacy file) |
| `m6_suite.gd` | `content` | Catalog caps, achievements, leaderboards (legacy file) |
| `m7_suite.gd` | `run` | Endless/waves, seeds, portals, retreat (legacy file) |
| `achievements_suite.gd` | `achievements` | Achievement service and toast scene |
| `a11y_suite.gd` | `accessibility` | Settings, damage colors, subtitle line application |
| `ui_suite.gd` | `ui` | `GameUISkin` theme, main-menu focus ring via `Input.parse_input_event` |
| `debug_suite.gd` | `debug` | Debug overlay actions and API surface |
| `error_paths_suite.gd` | `save` | Corrupt/truncated save, future schema, unknown item id |
| `pixel_pipeline_suite.gd` | `pixel_pipeline` | Pipeline assets, autoload paths, shader uniforms |
| `pixel_camera_snap_suite.gd` | `graphics` | Pixel camera snap behavior |
| `pixel_settings_suite.gd` | `graphics` | `PixelDioramaSettings` presets |
| `pixel_style_suite.gd` | `graphics` | `PixelDioramaStyle` palette constants |
| `visual_lighting_suite.gd` | `graphics` | Visual lighting hooks |
| `death_visual_suite.gd` | `graphics` | Dissolve/flash roundtrip, dummy dissolve |
| `portal_shader_suite.gd` | `graphics` | Portal shader uniforms |
| `diorama_anim_suite.gd` | `diorama_anim` | Authored libraries, clips, controller markers |
| `vfx_service_suite.gd` | `graphics` | `VfxService` burst API |
| `export_suite.gd` | `tools` | Authored library load, digests, pose marker |
| `voxel_grid_suite.gd` | `graphics` | Voxel grid helpers |
| `perf_gate_suite.gd` | `performance` | VFX pool, seven headless budgets, optional frame baseline |

**Registered 54, on disk 54.** `harness.registration.every_suite_file_is_registered` enforces bidirectional parity (`harness_suite.gd:113-143`).

## How it works

### Entry and orchestration

The runner loads each `SUITE_PATHS` entry, awaits optional `setup()` / `run()` / `teardown()`, enforces per-suite (`120 s`) and total (`900 s`) watchdogs, applies `MIN_ASSERTIONS` category floors (`validation_runner.gd:77-86`), computes script reachability (`validation_runner.gd:313-324`), and quits `0`/`1`/`2` on pass/fail/harness fault.

CLI filters: `--suite=`, `--test=`, `--shuffle`, `--seed=`, `--repeat=`, `--fail-fast`, `--report=`, `--harness-fast-timeout` (`runner_options.gd:18-42`).

### Assertion styles

1. **Behavioral** — dominant in `combat_suite.gd` (`CombatFixture`), `net_suite.gd` (HTTP stub), `platform_suite.gd` (Steam/crash logger instances), `perf_gate_suite.gd` (timed builds), `export_suite.gd` (library load + digest), `ui_suite.gd` (focus ring with `Input.parse_input_event`, `ui_suite.gd:59-63`), `death_visual_suite.gd` (dissolve state roundtrip).
2. **Reflective** — reduced; some `has_method` remain in `m7_suite.gd` for run-flow surface checks.
3. **Textual** — legitimate for docs (`docs_suite.gd`), CI workflow files, and shader source uniform greps where GPU execution is unavailable headless.

### Documentation guards (`docs_suite.gd`)

| Test id | Asserts |
|---------|---------|
| `docs.referenced_paths_exist` | Every `docs/existing_codebase/`, `docs/actual_improvements/`, `docs/validation/` string in any suite resolves |
| `docs.relative_links_resolve` | Relative markdown links under twin trees resolve |
| `docs.checklist_refs_resolve` | `docs/validation/manual-checklist.md` exists |
| `docs.checklist_headings_resolve` | Every `checklist_ref` string has a heading |

Doc paths in gameplay suites point at twin-tree files, e.g. `progression_suite.gd:102` → `docs/existing_codebase/progression-service.md`, `m7_suite.gd:731` → `docs/validation/manual-checklist.md`, `m7_suite.gd:750` → `docs/existing_codebase/save-migrator.md`.

### Performance gates (`perf_gate_suite.gd`)

| Test id | Budget constant | Evidence |
|---------|-----------------|----------|
| `perf.vfx_burst_pool` | `VfxService.BURST_POOL_MAX` | Behavioral 200-burst peak + reuse (`perf_gate_suite.gd:29-52`) |
| `perf.dungeon_build_ms` | `1500` ms | `BUDGET_DUNGEON_BUILD_MS` (`perf_gate_suite.gd:6`, `:82-105`) |
| `perf.procgen_generate_ms` | `250` ms | `BUDGET_PROCGEN_MS` (`perf_gate_suite.gd:7`, `:108-121`) |
| `perf.save_write_ms` | `50` ms | `BUDGET_SAVE_WRITE_MS` (`perf_gate_suite.gd:8`, `:124-139`) |
| `perf.content_load_ms` | `750` ms | `BUDGET_CONTENT_LOAD_MS` (`perf_gate_suite.gd:9`, `:142-153`) |
| `perf.node_count_after_build` | `8000` nodes | `BUDGET_NODE_COUNT` (`perf_gate_suite.gd:10`, `:156-179`) |
| `perf.static_memory_after_build` | `512 MiB` | `BUDGET_STATIC_MEMORY_BYTES` (`perf_gate_suite.gd:11`, `:183-205`) |
| `perf.frame_budget` | `16.67` ms p95 | Skips when `user://perf_baseline.json` absent (`perf_gate_suite.gd:56-63`) |

### Determinism

- `procgen.determinism_seed_sweep` — `DETERMINISM_SEEDS` plus 25 RNG-derived seeds (30 total), layout signature match on repeat (`procgen_suite.gd:575-613`).
- `procgen_seed_health_suite.gd` — 50-seed `generate_reported` vs `generate` parity (`procgen_seed_health_suite.gd:42-63`).

### Networking and platform

`net_suite.gd` exercises version constants, base-URL priority, transport stub (`get_returns_body_key`, 429 retry, 426 mismatch), auth session round-trip, save put/get/conflict, and offline `RunFlow._cloud_finalize_run` (`net_suite.gd:47-415`).

`platform_suite.gd` covers Steam stub unavailable/sync-zero, app-id env override, crash payload fields, log write/flush, retention prune, upload opt-out, path scrubbing (`platform_suite.gd:17-312`).

### Error paths

`error_paths_suite.gd` (category `save`) rejects corrupt JSON, truncated JSON, future `schemaVersion`, and drops unknown inventory item ids (`error_paths_suite.gd:15-80`). Unwritable save directory and missing catalog file scenarios are **ABSENT** (no matching test ids under `suites/`).

### Duplicate test ids

`TestContext.record` emits `runner.duplicate_id` on collision (`test_context.gd:42-56`). Loop bodies suffix discriminators, e.g. `lock_on.auto_advance_on_death.advances` (`lock_on_suite.gd:141-198`).

### Reachability

After all suites, the runner reports `coverage.reachableScripts` / `totalScripts` by substring-matching every `res://scripts/**/*.gd` path against suite source text (`helpers.gd:64-87`, `validation_runner.gd:313-324`). This is reachability, not line coverage.

## Contracts

- **Registration:** every new `*_suite.gd` must appear in `SUITE_PATHS`; `harness.registration.every_suite_file_is_registered` fails otherwise.
- **Categories:** `get_category()` groups JUnit output; `MIN_ASSERTIONS` enforces minimum counts for `combat`, `drift`, `quality`, `docs`, `harness`, `lock_on`, `arena`, `traps` (`validation_runner.gd:77-86`).
- **Save isolation:** suites with `manage_save_file = true` (default) backup/restore `user://aumbrye_save.json` in `ValidationSuite.setup()` / `teardown()`.
- **Production helpers:** continuable rules use `LocalSave.run_is_continuable` (`save_suite.gd:115-193`); hub seed parsing uses production `DungeonSeedService` paths (see [`validation-harness.md`](validation-harness.md) VHA-12).

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Doc path guards | IMPLEMENTED | `docs_suite.gd`; old `docs/plan/**` paths removed from suites |
| Net behavioral suite | IMPLEMENTED | `net_suite.gd` registered `validation_runner.gd:42` |
| Platform / Steam / crash | IMPLEMENTED | `platform_suite.gd:17-312` |
| Export / authored libraries | IMPLEMENTED | `export_suite.gd` category `tools` |
| Combat fixture pipeline | IMPLEMENTED | `combat_fixture.gd`, `combat_suite.gd` |
| Perf headless budgets | IMPLEMENTED | `perf_gate_suite.gd:6-11`, seven timed tests |
| 30-seed procgen sweep | IMPLEMENTED | `procgen.determinism_seed_sweep` (`procgen_suite.gd:590-613`) |
| UI focus + input simulation | IMPLEMENTED | `ui_suite.gd:37-73` |
| Accessibility behavioral | PARTIAL | Settings and subtitles behavioral; `a11y.colorblind.has_consumer` still grep (`a11y_suite.gd:66-78`) |
| Error-path coverage | PARTIAL | Four save/content cases; disk-full and missing catalog **ABSENT** |
| Milestone file dissolution | PARTIAL | Categories/ids migrated; `m5_suite.gd`/`m6_suite.gd`/`m7_suite.gd` files remain |
| Graphics category split | PARTIAL | `pixel_pipeline` + `diorama_anim` distinct; six suites still `graphics` |
| Cross-stack CLI fixtures | PARTIAL | Four parity tests; no CI-generated procgen fixture compare |
| Debug release-build guard | PARTIAL | `debug_suite.gd` checks actions/API; no release-export overlay absence test |
| Full-run stability | BROKEN | Headless full run can crash during `arena_suite` isolation (`debug_overlay.gd` after `quest_tracker_ui` freed node) — observed locally Aug 2026 |

## Related

- Improvement plan: [`../actual_improvements/validation-suites.md`](../actual_improvements/validation-suites.md) — **FINISHED**
- [`validation-harness.md`](validation-harness.md) — runner, `TestContext`, reporting
- [`combat-validation.md`](combat-validation.md) — combat/lock-on/arena depth
- [`networking.md`](networking.md), [`platform-and-net.md`](platform-and-net.md), [`export-tools.md`](export-tools.md)
- [`ci-cd.md`](ci-cd.md) — CI Godot job and artifact upload
