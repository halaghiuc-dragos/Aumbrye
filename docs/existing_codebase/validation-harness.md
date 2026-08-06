# Validation harness

Hand-rolled Godot validation harness: **29 suites** in `validation_runner.gd`, schema v3 JSON + JUnit XML, CLI filtering (`runner_options.gd`), total and per-suite watchdogs, suite `setup()`/`teardown()` with save backup, leak detection, `assert_eq`/`assert_near`/`skip`, and `harness_suite.gd` registered first for fast harness regressions.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/validation/validation_main.gd` | Headless `SceneTree` entry â€” loads `mcp_validation.tscn` |
| `apps/game/client/scripts/validation/validation_runner.gd` | Orchestration, watchdogs, reporting, `SUITE_PATHS` |
| `apps/game/client/scripts/validation/runner_options.gd` | CLI: `--suite`, `--test`, `--shuffle`, `--seed`, `--repeat`, `--fail-fast`, `--verbose`, `--report` |
| `apps/game/client/scripts/validation/test_context.gd` | Recording, assertions, `skip`, duplicate-id detection |
| `apps/game/client/scripts/validation/assertions.gd` | Shared assertion helpers |
| `apps/game/client/scripts/validation/fixtures.gd` | Fixture utilities |
| `apps/game/client/scripts/validation/helpers.gd` | Harness helpers (no duplicated game rules) |
| `apps/game/client/scripts/validation/validation_suite.gd` | Base class with `setup()`/`teardown()` |
| `apps/game/client/scripts/validation/combat_fixture.gd` | Two-body combat arena fixture |
| `apps/game/client/scripts/validation/suites/harness_suite.gd` | Meta-tests for runner registration and reachability |
| `apps/game/client/scenes/debug/mcp_validation.tscn` | Scene entry (same runner as script entry) |
| `docs/validation/manual-checklist.md` | Manual-only checklist referenced by reports |

Suites live in `apps/game/client/scripts/validation/suites/`; see [`validation-suites.md`](validation-suites.md).

## How it works

### Entry points

- **Script:** `godot --path apps/game/client --headless --script res://scripts/validation/validation_main.gd`
- **Scene:** `mcp_validation.tscn` (same `validation_runner.gd` node)
- **CI:** `godot ... -- --report=artifacts/mcp_validation.json` (uploads JSON + JUnit XML; `timeout-minutes: 30`)

### Execution

1. Parse CLI options (`runner_options.gd`).
2. Start total watchdog (900s default).
3. For each suite in `SUITE_PATHS`: `setup()`, `run()` with per-suite watchdog (120s), `teardown()`, leak check.
4. Enforce `MIN_ASSERTIONS` per category where configured.
5. Write schema v3 report + sibling `.xml`; print `FAIL <id> [category] message` lines for failures.
6. Quit: 0 pass, 1 assertion fail, 2 harness fault (timeout/crash).

Game-rule assertions call production APIs (`LocalSave.run_is_continuable()`, `CastleRun.should_persist_player_state()`, `DungeonSeedService.parse_run_seed()`, etc.) â€” not copies in `TestContext`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Suite runner + exit codes | IMPLEMENTED | `validation_runner.gd` |
| Total + per-suite watchdogs | IMPLEMENTED | VHA-01, VHA-02 |
| CLI filtering / shuffle / repeat | IMPLEMENTED | `runner_options.gd` |
| Assertion vocabulary + diffs | IMPLEMENTED | `test_context.gd`, `assertions.gd` |
| Setup/teardown + save backup | IMPLEMENTED | `validation_suite.gd` base |
| Leaked-node detection | IMPLEMENTED | `_isolate()` in runner |
| JUnit XML + CI report path | IMPLEMENTED | `--report`; `ci.yml` |
| Skip status | IMPLEMENTED | `perf_gate_suite.gd` and others |
| Harness self-tests | IMPLEMENTED | `harness_suite.gd` |
| Reachability metric | IMPLEMENTED | Report + `harness.reachability.*` |
| Production-rule copies in context | REMOVED | `fixtures.gd` / `helpers.gd`; suites use autoloads |

All VHA-01â€“VHA-19 gaps from the improvement plan are closed. See [`../actual_improvements/validation-harness.md`](../actual_improvements/validation-harness.md).

## Related

- Improvement plan: [`../actual_improvements/validation-harness.md`](../actual_improvements/validation-harness.md) - **FINISHED**
- [`validation-suites.md`](validation-suites.md), [`combat-validation.md`](combat-validation.md)
- [`ci-cd.md`](ci-cd.md)
