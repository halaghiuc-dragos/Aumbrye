# Validation harness — improvement plan

## Status: FINISHED

## Current state

29 suites registered in `validation_runner.gd` (including `harness_suite.gd` first for fast harness failures). Report schema v3 with `status`, `skipped`, `exitReason`, JUnit XML, reachability metric, and bounded execution via total and per-suite watchdogs. CI writes `artifacts/mcp_validation.json` directly via `--report` with a 30-minute job timeout.

## Gaps

All items from [`../existing_codebase/validation-harness.md`](../existing_codebase/validation-harness.md) VHA-01 through VHA-19 are closed.

| ID | Status |
|----|--------|
| VHA-01 | FINISHED — total watchdog, `_finish()`, exit code 2 on harness fault; CI `timeout-minutes: 30` |
| VHA-02 | FINISHED — per-suite watchdog with `suite.timeout_*` records |
| VHA-03 | FINISHED — `--suite`, `--test`, `--report`, `--verbose`, `--fail-fast` via `runner_options.gd` |
| VHA-04 | FINISHED — `TestContext.assert_eq`, `assert_near`, `assert_true`, optional `observed` field |
| VHA-05 | FINISHED — `ValidationSuite.setup()`/`teardown()`, save backup in base class, `_isolate()` leaked-node pass |
| VHA-06 | FINISHED — `--shuffle`, `--seed`, `--repeat` with flaky detection |
| VHA-07 | FINISHED — `_print_failures()` writes `FAIL <id> [<category>] <message>` to stdout |
| VHA-08 | FINISHED — `skip()` status; `perf.frame_time_ms` skips in `perf_gate_suite.gd` |
| VHA-09 | FINISHED — JUnit XML at `--report` sibling `.xml`; CI uploads JSON + XML |
| VHA-10 | FINISHED — duplicate id records `runner.duplicate_id` |
| VHA-11 | FINISHED — `coverage` block uses `manualChecklist` + reachability; `MANUAL_REMAINING` removed from harness |
| VHA-12 | FINISHED — `fixtures.gd`, `helpers.gd`; game-rule copies removed; suites use `LocalSave.run_is_continuable`, `CastleRun.should_persist_player_state`, `DungeonSeedService.parse_run_seed` |
| VHA-13 | FINISHED — `CombatFixture.teardown()` frees arena nodes; combat pipeline uses fixture lifecycle |
| VHA-14 | FINISHED — `get_suite_name()` used in suite results; `validation_main.gd` loads `mcp_validation.tscn` |
| VHA-15 | FINISHED — `ValidationSuite.check_*` forwarders with implicit category |
| VHA-16 | FINISHED — script and scene entry points both instantiate the same `validation_runner.gd` node |
| VHA-17 | FINISHED — report `flush()`/`close()`; `runner.report_write_failed` on open failure |
| VHA-18 | FINISHED — reachability metric in report and `harness.reachability.reports_untested_scripts` |
| VHA-19 | FINISHED — `harness_suite.gd` registration parity; `docs_suite.gd`; `MIN_ASSERTIONS` coverage gates |

## Target design

The harness stays first-party. Adopting GUT or gdUnit4 would bring assertions, filtering, and reporting, but this project's suites are integration tests that drive real scenes and autoloads, and both frameworks would need the same scene-driving helpers rewritten against their lifecycle. The cost is a full rewrite of 304 call sites for machinery this plan adds in roughly 250 lines. Revisit if the suite count doubles.

### 1. Bounded execution (VHA-01, VHA-02)

Every suite and every awaited test runs under a watchdog. GDScript has no exception handling, so the guarantee has to come from a timer that can fire independently of the stuck coroutine.

Add to `validation_runner.gd`:

```gdscript
const SUITE_TIMEOUT_SECONDS := 120.0
const TOTAL_TIMEOUT_SECONDS := 900.0

var _finished := false

func _ready() -> void:
    _ctx = TestContextScript.new(self)
    _arm_total_watchdog()
    await _run_all_suites()
    _finish(0)

func _arm_total_watchdog() -> void:
    var timer := get_tree().create_timer(TOTAL_TIMEOUT_SECONDS, true, false, true)
    timer.timeout.connect(func():
        if _finished:
            return
        _ctx.record("runner.total_timeout", "runner", false,
            "validation exceeded %ds; report is partial" % int(TOTAL_TIMEOUT_SECONDS))
        _finish(2))

func _finish(reason_code: int) -> void:
    if _finished:
        return
    _finished = true
    _write_report()
    _print_failures()
    get_tree().quit(2 if reason_code == 2 else (1 if _ctx.failed > 0 else 0))
```

Per suite, race the suite's `run()` against a timer using a completion flag rather than `await` on the coroutine directly, so the runner can move on even when the suite never returns:

```gdscript
var done := [false]
_call_suite_async(suite, done)
var elapsed := 0.0
while not done[0] and elapsed < SUITE_TIMEOUT_SECONDS:
    await get_tree().process_frame
    elapsed += get_process_delta_time()
if not done[0]:
    _ctx.record("suite.timeout_%s" % suite_name, category, false,
        "suite exceeded %ds and was abandoned" % int(SUITE_TIMEOUT_SECONDS))
```

The abandoned coroutine keeps a reference and leaks; that is acceptable, because the alternative is a hung CI job with no report. The `runner.total_timeout` and `suite.timeout_*` entries make the abandonment visible in the report rather than silent.

Exit codes become: 0 all passed, 1 assertions failed, 2 harness fault (timeout, load failure, report write failure). CI treats 2 differently from 1 in the job summary.

Pair this with `timeout-minutes: 30` on the `godot` job, specified in [`ci-cd.md`](ci-cd.md) step 5. Both layers are needed: the watchdog produces a report, the job timeout is the backstop.

### 2. Real assertions (VHA-04, VHA-08, VHA-10, VHA-15)

Add `apps/game/client/scripts/validation/assertions.gd` and give `ValidationSuite` thin forwarding methods so call sites shrink and category is implicit:

```gdscript
# In ValidationSuite
func check(id: String, condition: bool, message: String, ref := "") -> bool
func check_eq(id: String, actual, expected, message: String, ref := "") -> bool
func check_ne(id: String, actual, unexpected: Variant, message: String, ref := "") -> bool
func check_near(id: String, actual: float, expected: float, epsilon: float, message: String, ref := "") -> bool
func check_in(id: String, needle, haystack, message: String, ref := "") -> bool
func check_has(id: String, dict: Dictionary, key: String, message: String, ref := "") -> bool
func check_not_null(id: String, value, message: String, ref := "") -> bool
func check_file_exists(id: String, path: String, message: String, ref := "") -> bool
func skip(id: String, message: String, ref := "") -> void
```

Each records the category from `get_category()`, times itself, and on failure builds the message as `"<message> (expected <expected>, got <actual>)"`. That is the entire point: a CI log line that names the value.

`TestContext.record` gains a `status` field with values `pass`, `fail`, `skip`, and separate `passed`, `failed`, `skipped` counters. `skipped` does not affect the exit code. `perf_gate_suite.gd:36-38` becomes `skip("perf.headless_budget_gate", "GPU frame time unavailable headless")` instead of asserting `true`.

`record` also rejects a duplicate id: on collision it records an extra `runner.duplicate_id` failure naming both suites.

The existing `record`/`timed_record` stay as the underlying primitive so the 304 call sites can migrate incrementally rather than in one commit.

### 3. Filtering and repeatability (VHA-03, VHA-06)

Parse `OS.get_cmdline_user_args()` (the arguments after `--`) in `validation_runner._ready`:

| Argument | Effect |
|----------|--------|
| `--suite=combat,flow` | Run only the named suites |
| `--test=combat.parry` | Run only tests whose id starts with the prefix; suites still load, non-matching records are dropped |
| `--seed=12345` | Seed the shuffle |
| `--shuffle` | Randomize suite order |
| `--repeat=3` | Run the selected set three times; a test that is not stable across runs is reported as flaky |
| `--fail-fast` | Stop at the first failure |
| `--report=<path>` | Override the report path, so CI can write into the workspace directly |

Usage: `godot --path . --headless --script res://scripts/validation/validation_main.gd -- --suite=combat --test=combat.parry`.

`--report` matters for CI: it removes the need for the fragile `~/.local/share/godot/app_userdata/...` copy step described in [`ci-cd.md`](ci-cd.md).

### 4. Isolation and lifecycle (VHA-05, VHA-13)

`ValidationSuite` gains `setup()` and `teardown()`, both `await`-able and both defaulting to empty. The runner calls `setup()`, `run()`, `teardown()` in order, each under the watchdog, and calls `teardown()` even when `run()` timed out.

The runner adds a between-suite hygiene pass:

```gdscript
func _isolate() -> void:
    for child in get_tree().root.get_children():
        if child == self or child.name in _AUTOLOAD_NAMES:
            continue
        _ctx.record("suite.leaked_node_%s" % child.name, "runner", false,
            "suite left %s in the tree" % child.get_path())
        child.queue_free()
    await get_tree().process_frame
```

Leaked nodes become a reported failure rather than a silent contaminant of the next suite. Save-file backup and restore move into the base class `setup`/`teardown` so no suite has to remember, with an opt-out flag for suites that intentionally test persistence across the boundary.

### 5. Diagnosable output (VHA-07, VHA-09, VHA-11, VHA-17)

- `_print_failures()` writes every failing test to stdout as `FAIL <id> [<category>] <message>`, followed by the counts. Passing tests stay quiet unless `--verbose`.
- `_write_report()` calls `flush()` then `close()`, and records `runner.report_write_failed` plus exit code 2 when `FileAccess.open` returns null.
- Add `_write_junit()` producing `user://mcp_validation.xml` (or the `--report` sibling path) in JUnit format: one `<testsuite>` per suite, one `<testcase>` per test with `classname` set to the category, `<failure message="...">` for failures, and `<skipped/>` for skips. GitHub Actions test reporters consume this directly and annotate the pull request.
- Replace the meaningless `coverage` block. `manual_remaining` moves out of `test_context.gd` into `docs/validation/manual-checklist.md` with one heading per id, and the report carries `{"automated": <count>, "manualChecklist": "docs/validation/manual-checklist.md"}`. A `docs-links`-style check asserts every id in the report's `checklist_ref` fields resolves to a heading in that file (VHA-16 from the existing doc).

### 6. Framework and game logic separated (VHA-12, VHA-14, VHA-19)

Split `test_context.gd` into three files:

| File | Contents |
|------|----------|
| `validation/test_context.gd` | Recording, counters, `await_frame`, `await_physics`, report state. Roughly 110 lines |
| `validation/fixtures.gd` | `SEED_A`, `SEED_B`, `FIXTURE_BOSS`, `REQUIRED_*`, `KEY_SCENES`, `ROOM_TEMPLATE_SCENES`, `matches_m2_fixture`, `layout_signature` |
| `validation/helpers.gd` | `file_contains`, `count_nodes_by_script`, `count_loot_chests`, save backup and restore |

Delete `eval_continuable`, `player_snapshot_allowed`, and `parse_castle_seed` from the harness and call the production functions instead — `LocalSave.has_continuable_run()`, the castle-run snapshot guard, and the real seed parser. A test that asserts against a private copy of the rule is not testing anything. Where the production function is not reachable from a test, that is the bug to fix.

Delete the unused `get_suite_name()` or make the runner use it; do not keep two implementations.

Add `harness_suite.gd` testing the harness itself, listed under Validation below.

### 7. Coverage signal (VHA-18)

Full line coverage of GDScript needs engine support that does not exist. A useful proxy: `harness_suite.gd` walks `res://scripts/` recursively, collects every `.gd` file, and reports the fraction referenced by at least one suite (by `preload`, `load`, or path string). That is a reachability metric, not coverage, and the report labels it as such. It answers the question that matters — which subsystems have no test at all — which is the real gap surfaced in [`validation-suites.md`](validation-suites.md).

### 8. Entry points (VHA-16)

Keep both, make them equivalent: `validation_main.gd` becomes a three-line shim that instantiates the same node the scene does, and `harness_suite.gd` asserts the scene's script path equals `validation_runner.gd`. Update both file headers to state that CI uses the script entry point and the scene is for in-editor runs.

## Work plan

1. **Add the total watchdog and `_finish`** — guarantees a report and an exit code. Land with `timeout-minutes: 30` on the `godot` job. (VHA-01)
2. **Add the per-suite watchdog** and the `suite.timeout_*` record. (VHA-02)
3. **Print failures to stdout and flush the report file.** Two small changes that make every future CI failure readable. (VHA-07, VHA-17)
4. **Emit JUnit XML and add `--report`**; wire the CI reporter and drop the user-data-dir copy step. (VHA-09)
5. **Add `assertions.gd` and the `check_*` forwarders**, plus `skip` and the `status` field. Migrate `perf_gate_suite` first as the proof. (VHA-04, VHA-08)
6. **Add duplicate-id detection.** (VHA-10)
7. **Add cmdline parsing** for `--suite`, `--test`, `--shuffle`, `--seed`, `--repeat`, `--fail-fast`, `--verbose`. (VHA-03, VHA-06)
8. **Add `setup`/`teardown` and the leaked-node pass**; move save backup and restore into the base class. (VHA-05, VHA-13)
9. **Split `test_context.gd`** into context, fixtures, and helpers; delete the three duplicated game-logic functions and repoint their suites at production code. (VHA-12)
10. **Move `MANUAL_REMAINING` to `docs/validation/manual-checklist.md`** and replace the `coverage` block. (VHA-11)
11. **Add `harness_suite.gd`** including the reachability metric. (VHA-18, VHA-19)
12. **Migrate the remaining 300-odd call sites to `check_*`**, suite by suite, mechanically. (VHA-04, VHA-15)
13. **Unify the two entry points** and fix both file headers. (VHA-14, VHA-16)

Steps 1-4 are independent, small, and immediately valuable; land them before anything else. Step 12 is the long tail and can proceed one suite per pull request.

## Data and schema changes

`mcp_validation.json` goes to `schemaVersion: 3`:

| Change | Detail |
|--------|--------|
| `tests[].status` | New. `"pass"`, `"fail"`, or `"skip"`. `tests[].pass` is retained for one release for any external reader, then removed |
| `skipped` | New top-level counter |
| `suites[].skipped` | New |
| `suites[].timedOut` | New boolean |
| `coverage` | Replaced by `{"automated": int, "reachableScripts": int, "totalScripts": int, "manualChecklist": "docs/validation/manual-checklist.md"}` |
| `exitReason` | New. `"complete"`, `"total_timeout"`, or `"report_error"` |

`reports/validation-summary.json` at the repository root is a stale artifact of a previous run and is untracked; see [`repository-root.md`](repository-root.md). Nothing in this plan writes it.

New tracked files: `apps/game/client/scripts/validation/assertions.gd`, `fixtures.gd`, `helpers.gd`, `suites/harness_suite.gd`, `docs/validation/manual-checklist.md`.

No save-format change, so **no `save_migrator.gd` version bump**. No `content/schemas/` change.

## Acceptance criteria

- [x] A suite that awaits a signal that never fires is abandoned after 120 seconds; the report is written and the process exits.
- [x] A suite whose `run()` raises a script error does not prevent the report from being written or the process from exiting.
- [x] The total run cannot exceed 900 seconds; exceeding it writes a partial report and exits 2.
- [x] Exit code is 0 on all-pass, 1 on assertion failure, 2 on harness fault.
- [x] Every failing test prints `FAIL <id> [<category>] <message>` to stdout.
- [x] A `check_eq` failure message contains both the expected and the actual value.
- [x] `--report=artifacts/mcp_validation.json` writes there, and CI uploads it with no copy step from the user data directory.
- [x] `mcp_validation.xml` is valid JUnit and GitHub annotates the pull request with failing tests.
- [x] `-- --suite=combat` runs only `combat_suite.gd`.
- [x] `-- --test=combat.parry` runs only tests whose id starts with that prefix.
- [x] `-- --shuffle --seed=7` reproduces the same order twice, and the full run passes under three different seeds.
- [x] `-- --repeat=3` reports any test whose result varies across runs as flaky.
- [x] A suite that leaves a node under `/root` produces a `suite.leaked_node_*` failure.
- [x] `skip()` produces a `skip` status and does not affect the exit code.
- [x] Two suites registering the same test id produce a `runner.duplicate_id` failure.
- [x] `test_context.gd` contains no game-logic reimplementation; `eval_continuable`, `player_snapshot_allowed`, and `parse_castle_seed` are gone.
- [x] Every `checklist_ref` in the report resolves to a heading in `docs/validation/manual-checklist.md`.
- [x] The scene entry point and the script entry point produce byte-identical reports apart from timestamps.

## Validation

New suite `apps/game/client/scripts/validation/suites/harness_suite.gd`, registered first in `SUITE_PATHS` so a broken harness fails fast. It exercises the harness through a second, nested `TestContext` so its own assertions do not pollute the real counters.

| Test id | Asserts |
|---------|---------|
| `harness.record.counts_pass_and_fail` | A nested context's `passed` and `failed` track correctly |
| `harness.record.skip_does_not_fail` | `skip()` increments `skipped` and leaves `failed` at zero |
| `harness.record.duplicate_id_is_reported` | Recording the same id twice produces `runner.duplicate_id` |
| `harness.assert.eq_failure_message_has_values` | The message contains both operands |
| `harness.assert.near_respects_epsilon` | Just inside and just outside the epsilon behave correctly |
| `harness.timeout.suite_is_abandoned` | A synthetic suite awaiting a never-emitted signal produces `suite.timeout_*` within the budget |
| `harness.timeout.teardown_runs_after_timeout` | `teardown()` still executes |
| `harness.isolation.leaked_node_is_reported` | A synthetic suite adding a node to `/root` produces `suite.leaked_node_*` and the node is freed |
| `harness.filter.suite_selection` | `--suite=x` restricts the loaded set |
| `harness.filter.test_prefix` | `--test=` drops non-matching records |
| `harness.report.schema_version_is_3` | The written JSON has `schemaVersion: 3` and the new fields |
| `harness.report.junit_is_wellformed` | The XML parses and the testcase count equals the test count |
| `harness.report.write_failure_sets_exit_reason` | An unwritable path yields `exitReason: "report_error"` |
| `harness.entrypoints.scene_matches_script` | `mcp_validation.tscn` references `validation_runner.gd` |
| `harness.registration.every_suite_file_is_registered` | Every `.gd` under `suites/` appears in `SUITE_PATHS` and every path in `SUITE_PATHS` exists — the standing regression test for the count parity currently held by hand |
| `harness.checklist.refs_resolve` | Every `checklist_ref` used by any suite has a heading in `docs/validation/manual-checklist.md` |
| `harness.reachability.reports_untested_scripts` | The reachability metric is computed and names at least the known-untested files |

Manual verification once, not automated: run the scene entry point in the editor and confirm the report matches the headless script run.

## Related

- Existing behavior: [`../existing_codebase/validation-harness.md`](../existing_codebase/validation-harness.md)
- [`validation-suites.md`](validation-suites.md) — the suites this harness runs and the coverage holes
- [`ci-cd.md`](ci-cd.md) — job timeout, report upload, failure summary
- [`repository-root.md`](repository-root.md) — the stale `reports/` artifact
- [`combat-validation.md`](combat-validation.md) — combat-specific assertions
