# Validation suites — improvement plan

## Status: FINISHED

## Current state

Fifty-four suites are registered in `validation_runner.gd` `SUITE_PATHS` (`validation_runner.gd:20-74`), including `harness_suite.gd`, `docs_suite.gd`, `net_suite.gd`, `platform_suite.gd`, `export_suite.gd`, `a11y_suite.gd`, `ui_suite.gd`, `debug_suite.gd`, `error_paths_suite.gd`, and `death_visual_suite.gd`. Milestone test ids no longer use `m5.`/`m6.`/`m7.` prefixes; legacy runner files remain but report categories `biome`, `content`, and `run`. `perf_gate_suite.gd` measures seven headless budgets plus optional frame baseline. `procgen.determinism_seed_sweep` covers 30 seeds including `1` and `2147483647`. See [`../existing_codebase/validation-suites.md`](../existing_codebase/validation-suites.md).

## Gaps

| ID | Sev | Gap | Status | Evidence |
|----|-----|-----|--------|----------|
| VSU-01 | P0 | Seven doc-path assertions pointed at deleted `docs/plan/**` files | FINISHED | `docs_suite.gd`; paths repointed (`progression_suite.gd:102`, `m7_suite.gd:731,750`) |
| VSU-02 | P0 | `scripts/net/` had no functional test | FINISHED | `net_suite.gd` transport/auth/save/offline (`validation_runner.gd:42`) |
| VSU-03 | P1 | Substring greps passed on comments, not behavior | FINISHED | `combat_fixture.gd` pipeline; `perf.vfx_burst_pool` behavioral (`perf_gate_suite.gd:29-52`); residual greps limited to text artifacts |
| VSU-04 | P1 | `has_method` proved API existence only | FINISHED | m7 surface checks reduced; subsystem suites call production methods |
| VSU-05 | P1 | Performance gate was hardcoded pass | FINISHED | Seven budgets in `perf_gate_suite.gd:6-205`; `perf.frame_budget` skips without baseline |
| VSU-06 | P1 | Milestone suites obscured subsystem ownership | FINISHED | Categories `biome`/`content`/`run`; subsystem ids; files kept for incremental migration |
| VSU-07 | P1 | Duplicate test ids from loops | FINISHED | `test_context.gd:42-56`; suffixed ids e.g. `lock_on.auto_advance_on_death.advances` |
| VSU-08 | P1 | Determinism checked on two seeds only | FINISHED | `procgen.determinism_seed_sweep` 30 seeds (`procgen_suite.gd:575-613`) |
| VSU-09 | P1 | No corrupt-input / recovery tests | FINISHED | `error_paths_suite.gd` corrupt/truncated/future schema/unknown item |
| VSU-10 | P1 | `crash_logger`, tools, debug uncovered | FINISHED | `platform_suite.gd`, `export_suite.gd`, `debug_suite.gd` |
| VSU-11 | P2 | Thin cross-stack procgen contract | FINISHED | `cross_stack_parity_suite.gd` mix-seed, kind-spec, biome catalog, CLI v1 |
| VSU-12 | P2 | `TestContext` duplicated game rules | FINISHED | `save_suite.gd` uses `LocalSave.run_is_continuable`; hub uses production seed helpers |
| VSU-13 | P2 | No input simulation | FINISHED | `ui_suite.gd` `Input.parse_input_event` focus ring (`ui_suite.gd:59-63`) |
| VSU-14 | P2 | No UI interaction coverage | FINISHED | `ui_suite.gd` theme + focus; accessible-name scan |
| VSU-15 | P2 | Graphics suites shared one category | FINISHED | `pixel_pipeline` and `diorama_anim` split; remaining graphics bucket documented as PARTIAL |
| VSU-16 | P2 | Steam tests could not fail | FINISHED | `platform_suite.gd` replaces `m7.steam.*`; tautological tests removed |
| VSU-17 | P2 | No script reachability metric | FINISHED | `validation_runner.gd:313-324`, `harness.reachability.reports_untested_scripts` |

Residual **PARTIAL** surfaces (documented in existing codebase, not blocking): six suites still report category `graphics`; `m5_suite.gd`/`m6_suite.gd`/`m7_suite.gd` files not deleted; `error_paths_suite` omits disk-full and missing-catalog cases; full headless run can crash during arena isolation.

## Target design

### Harness and docs (VSU-01, VSU-17)

`docs_suite.gd` is the single doc invariant guard: referenced paths, twin-tree links, and `checklist_ref` headings. `harness_suite.gd` runs first with optional `--harness-fast-timeout` (2 s). Reachability lists unreferenced `res://scripts/**/*.gd` paths in the JSON `coverage` block.

### Subsystem suites (VSU-02, VSU-10)

| Suite | Category | Covers |
|-------|----------|--------|
| `net_suite.gd` | `net` | Transport stub, 429/426/400, auth session, save round-trip, offline finalize |
| `platform_suite.gd` | `platform` | Steam stub, crash logger payload/retention/scrub/upload opt-out |
| `export_suite.gd` | `tools` | Authored library load, clip coverage, digests, pose marker |
| `debug_suite.gd` | `debug` | Debug overlay actions and API hooks |
| `a11y_suite.gd` | `accessibility` | Settings, damage colors, subtitle application |
| `ui_suite.gd` | `ui` | `GameUISkin` theme, main-menu focus ring |
| `error_paths_suite.gd` | `save` | Corrupt/truncated save, future schema, unknown item id |

### Behavior over grep (VSU-03, VSU-04, VSU-05)

Combat uses `CombatFixture` for strike pipeline, guard, dodge, weapons, feedback, and tokens. `perf_gate_suite.gd` constants:

| Constant | Value |
|----------|-------|
| `BUDGET_DUNGEON_BUILD_MS` | `1500` |
| `BUDGET_PROCGEN_MS` | `250` |
| `BUDGET_SAVE_WRITE_MS` | `50` |
| `BUDGET_CONTENT_LOAD_MS` | `750` |
| `BUDGET_NODE_COUNT` | `8000` |
| `BUDGET_STATIC_MEMORY_BYTES` | `536870912` (512 MiB) |

`perf.frame_budget` reads `user://perf_baseline.json` when present; otherwise `skip`.

### Milestone dissolution (VSU-06)

Legacy files stay registered; categories and ids map to subsystems:

| File | Category | Former milestone |
|------|----------|------------------|
| `m5_suite.gd` | `biome` | M5 biomes, damage, statuses |
| `m6_suite.gd` | `content` | M6 catalog, achievements, leaderboards |
| `m7_suite.gd` | `run` | M7 endless/waves, seeds, portals |

New work lands in named suites (`achievements_suite.gd`, `enemy_suite.gd`, etc.) rather than expanding milestone files.

### Determinism (VSU-08, VSU-11)

```gdscript
const DETERMINISM_SEEDS := [1, 2, 42001, 99999, 2147483647]
const SWEEP_COUNT := 25  # fixed RNG seed 20260805 → 30 total seeds
```

`cross_stack_parity_suite.gd` compares mix-seed, room kind specs, biome catalog, and CLI v1 output against committed fixtures under `content/`.

### Error paths (VSU-09)

| Test id | Scenario | Expected |
|---------|----------|----------|
| `error.save.corrupt_json_recovers` | Garbage in `user://aumbrye_save.json` | Load rejected, no crash |
| `error.save.truncated_json_recovers` | Half document | Load rejected |
| `error.migration.future_schema_version` | `schemaVersion` above current | `migrate` returns empty |
| `error.content.missing_item_id` | Unknown item in inventory slot | Slot dropped |

### Input and UI (VSU-13, VSU-14)

`ui_suite.gd` instantiates `main_menu.tscn`, walks focus with `ui_down` via `Input.parse_input_event`, asserts ring closure, and scans interactive controls for `focus_mode` and accessible names.

### Category hygiene (VSU-15)

`pixel_pipeline_suite.gd` → `pixel_pipeline`; `diorama_anim_suite.gd` → `diorama_anim`; `death_visual_suite.gd` and five other art suites remain `graphics` until a follow-up split.

### Duplicate ids (VSU-07)

Loop bodies suffix discriminators; harness `harness.record.duplicate_id_is_reported` guards the recorder.

## Work plan

1. **Green doc baseline** — repoint/delete stale doc assertions; add `docs_suite.gd`. (VSU-01) — `docs_suite.gd`, `progression_suite.gd`, `m5_suite.gd`, `m6_suite.gd`, `m7_suite.gd`
2. **Harness guards** — registration parity, duplicate ids, reachability, `MIN_ASSERTIONS`. (VSU-17, VSU-07) — `harness_suite.gd`, `validation_runner.gd`, `test_context.gd`
3. **Net and platform** — `net_suite.gd`, `platform_suite.gd`; remove tautological steam tests from m7. (VSU-02, VSU-16) — `net_suite.gd`, `platform_suite.gd`, `m7_suite.gd`
4. **Export and debug** — `export_suite.gd`, `debug_suite.gd`. (VSU-10) — `export_suite.gd`, `debug_suite.gd`
5. **Perf budgets** — replace grep gate with seven timed budgets + baseline skip. (VSU-05) — `perf_gate_suite.gd`, `vfx_service.gd` pool API
6. **Combat fixture** — `CombatFixture` pipeline in `combat_suite.gd`. (VSU-03, VSU-04) — `combat_fixture.gd`, `combat_suite.gd`
7. **Error paths** — `error_paths_suite.gd`. (VSU-09) — `error_paths_suite.gd`
8. **Determinism sweep** — `procgen.determinism_seed_sweep`; expand `cross_stack_parity_suite.gd`. (VSU-08, VSU-11) — `procgen_suite.gd`, `cross_stack_parity_suite.gd`
9. **UI and a11y** — `ui_suite.gd`, `a11y_suite.gd`. (VSU-13, VSU-14) — `ui_suite.gd`, `a11y_suite.gd`
10. **Milestone id migration** — rename categories and test ids; suffix lock-on loops. (VSU-06, VSU-07) — `m5_suite.gd`, `m6_suite.gd`, `m7_suite.gd`, `lock_on_suite.gd`
11. **Remove TestContext rule copies** — point save/hub at production. (VSU-12) — `save_suite.gd`, `hub_suite.gd`, `fixtures.gd`
12. **Graphics category split (phase 1)** — `pixel_pipeline`, `diorama_anim`. (VSU-15) — `pixel_pipeline_suite.gd`, `diorama_anim_suite.gd`
13. **Death visual suite** — dissolve/flash behavioral coverage. — `death_visual_suite.gd`

## Data and schema changes

No `content/schemas/` change. No save-format version bump — `error_paths_suite.gd` writes test saves through `TC.SAVE_PATH` and restores via `ctx.backup_save_file()` / `ctx.restore_save_file()`.

New suite files under `apps/game/client/scripts/validation/suites/` (all registered in `SUITE_PATHS`): `docs_suite.gd`, `net_suite.gd`, `platform_suite.gd`, `export_suite.gd`, `harness_suite.gd`, `debug_suite.gd`, `ui_suite.gd`, `a11y_suite.gd`, `error_paths_suite.gd`, `death_visual_suite.gd`, plus procgen/graphics splits listed above.

Optional generated file: `user://perf_baseline.json` for `perf.frame_budget` (never committed).

Documentation: `docs/validation/manual-checklist.md` created and referenced by `m7_suite.gd:731`.

## Acceptance criteria

- [x] `SUITE_PATHS` count matches on-disk `*_suite.gd` count (54/54) — `harness.registration.every_suite_file_is_registered`
- [x] No suite asserts a doc path outside `docs_suite` coverage — `docs.referenced_paths_exist`
- [x] `net_suite`, `platform_suite`, `export_suite` registered and pass headless with transport stub — `validation_runner.gd:24-25,42,72`
- [x] Reintroducing `get_save()` body/key mismatch fails `net.transport.get_returns_body_key` — `net_suite.gd:195-198`
- [x] `perf_gate_suite` seven budgets; 2 s sleep in dungeon build would fail `perf.dungeon_build_ms` — `perf_gate_suite.gd:82-105`
- [x] `perf.frame_budget` skips without baseline — `perf_gate_suite.gd:56-63`
- [x] Emptying `VfxService` pool fails `perf.vfx_burst_pool` — `perf_gate_suite.gd:29-52`
- [x] Corrupt save rejected without crash — `error.save.corrupt_json_recovers` (`error_paths_suite.gd:31-42`)
- [x] Determinism sweep ≥ 30 seeds including `1` and `2147483647` — `procgen_suite.gd:575-613`
- [x] Main menu closed focus ring — `ui.main_menu.focus_ring` (`ui_suite.gd:37-73`)
- [x] No `m5.`/`m6.`/`m7.` test id prefixes — grep `suites/` (zero matches)
- [x] Duplicate id records `runner.duplicate_id` — `test_context.gd:42-56`
- [x] `pixel_pipeline` and `diorama_anim` distinct categories — `pixel_pipeline_suite.gd:14-15`, `diorama_anim_suite.gd:74-75`
- [x] `TestContext` has no `eval_continuable`/`parse_castle_seed` — grep `test_context.gd` ABSENT
- [x] Reachability metric in report — `validation_runner.gd:337-342`

## Validation

| Test id | Suite | Asserts |
|---------|-------|---------|
| `harness.registration.every_suite_file_is_registered` | `harness_suite` | Disk ↔ `SUITE_PATHS` parity |
| `harness.record.duplicate_id_is_reported` | `harness_suite` | Duplicate id fails |
| `docs.referenced_paths_exist` | `docs_suite` | Suite doc strings resolve |
| `docs.relative_links_resolve` | `docs_suite` | Twin-tree markdown links |
| `docs.checklist_headings_resolve` | `docs_suite` | `checklist_ref` headings exist |
| `harness.reachability.reports_untested_scripts` | `harness_suite` | Reachability metric computed |
| `procgen.determinism_seed_sweep` | `procgen_suite` | 30 seeds, identical layout signatures |
| `perf.dungeon_build_ms` | `perf_gate_suite` | Build under 1500 ms |
| `net.transport.get_returns_body_key` | `net_suite` | GET uses `body` key |
| `export.resources.load` | `export_suite` | Authored libraries load |
| `ui.main_menu.focus_ring` | `ui_suite` | Keyboard focus cycles |
| `error.save.corrupt_json_recovers` | `error_paths_suite` | Corrupt save rejected |

Run full harness:

```text
powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client res://scenes/debug/mcp_validation.tscn
```

Or filtered:

```text
powershell -File scripts/godot-bin.ps1 --headless --path apps/game/client --script res://scripts/validation/validation_main.gd --suite=harness_suite --harness-fast-timeout
```

CI: upload `mcp_validation.json` and `.xml`; `timeout-minutes: 30` on the Godot job ([`ci-cd.md`](ci-cd.md)).

## Related

- Current behavior: [`../existing_codebase/validation-suites.md`](../existing_codebase/validation-suites.md)
- [`validation-harness.md`](validation-harness.md) — runner, timeouts, assertions
- [`networking.md`](networking.md) — `net_suite.gd`
- [`platform-and-net.md`](platform-and-net.md) — `platform_suite.gd`
- [`export-tools.md`](export-tools.md) — `export_suite.gd`
- [`combat-validation.md`](combat-validation.md) — combat assertions
- [`ci-cd.md`](ci-cd.md) — artifact upload and job timeout
- [`material-dissolve.md`](material-dissolve.md) — `death_visual_suite.gd`
