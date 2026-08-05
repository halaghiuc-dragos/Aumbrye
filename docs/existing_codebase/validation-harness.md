# Validation harness

A hand-rolled test harness, 426 lines across four files. A `SceneTree` entry script instantiates a runner node; the runner loads 24 suite scripts from a hardcoded list, calls `run()` on each, accumulates boolean results into a shared context, writes a JSON report to `user://mcp_validation.json`, and quits with 1 if anything failed. There is no assertion library, no isolation between suites, no per-test timeout, and no way to run a subset.

## Files

| Path | Lines | Role |
|------|-------|------|
| `apps/game/client/scripts/validation/validation_main.gd` | 19 | `extends SceneTree`. Headless entry point |
| `apps/game/client/scripts/validation/validation_runner.gd` | 125 | `extends Node`. Suite list, orchestration, report writing, exit code |
| `apps/game/client/scripts/validation/test_context.gd` | 257 | `class_name TestContext`. Result recording plus shared fixtures and helpers |
| `apps/game/client/scripts/validation/validation_suite.gd` | 25 | `class_name ValidationSuite`. Base class: `run()`, `get_category()`, `get_suite_name()` |
| `apps/game/client/scenes/debug/mcp_validation.tscn` | 6 | A single `Node` with `validation_runner.gd` attached |

Suites live in `apps/game/client/scripts/validation/suites/`; see [`validation-suites.md`](validation-suites.md).

## How it works

### Entry points

Two, both documented in the file headers:

| Command | Path |
|---------|------|
| `godot --path . --headless --script res://scripts/validation/validation_main.gd` | `validation_main.gd:3` |
| `godot --path . --headless res://scenes/debug/mcp_validation.tscn` | `validation_runner.gd:6`, marked "recommended" |

CI uses the first (`.github/workflows/ci.yml:120`), while `validation_main.gd:4` says to prefer the second. Nothing verifies the two produce the same result.

`validation_main._initialize` loads `validation_runner.gd`, `quit(1)` on a load or instantiation failure, and otherwise `root.add_child(runner)` (`validation_main.gd:7-18`). It never quits on success; the runner does that.

### Orchestration

`validation_runner._ready` (`:44-49`):

```gdscript
_ctx = TestContextScript.new(self)
await _run_all_suites()
_write_report()
var exit_code := 1 if _ctx.failed > 0 else 0
get_tree().quit(exit_code)
```

`_run_all_suites` (`:52-94`) iterates `SUITE_PATHS` in declaration order. For each path it `load()`s the script, records a synthetic `suite.load_<name>` failure and continues if that returns null, `new(_ctx)`s it, records `suite.init_<name>` and continues if that returns null, snapshots `_ctx.passed` and `_ctx.failed`, `await`s `run()` if the method exists, and appends a per-suite summary of name, category, passed, failed, and duration.

Every suite shares one `TestContext` instance. There is no reset between suites.

### `SUITE_PATHS`

`validation_runner.gd:13-38` lists 24 paths, in this order:

```
setup, content, inventory, progression, procgen, room_graph,
cross_stack_parity, room_content, save, hub, hub_m4, arena,
camera, lock_on, combat, dungeon, player, flow,
m5, m6, m7, pixel_pipeline, diorama_anim, perf_gate
```

`apps/game/client/scripts/validation/suites/` contains exactly 24 `.gd` files (plus one `.uid` each). **Registered 24, on disk 24 — every suite file is registered and no path in the list is missing from disk.**

### Result recording

`TestContext.record(id, category, passed_test, message, checklist_ref = "", duration_ms = 0)` (`test_context.gd:89-110`) increments `passed` or `failed`, builds a dictionary, adds `checklist_ref` only when non-empty, and appends to `tests`. `timed_record` is the same with `duration_ms` computed from a start timestamp (`test_context.gd:113-121`).

That is the entire assertion surface. There is no `assert_eq`, `assert_true`, `assert_near`, `assert_throws`, or anything else. Suites compute a boolean inline and pass it in:

```gdscript
ctx.timed_record(
    "m7.steam.auth_ticket_deferred",
    get_category(),
    ticket == "",
    "auth ticket deferred in stub mode",
    start,
    "STEAM-7.4"
)
```

Across the 24 suites there are 304 `ctx.record`/`ctx.timed_record` call sites. Because only a boolean crosses the boundary, a failure report carries the author's prose message and never the actual value that was compared.

`category` is a parameter, but every call site passes `get_category()`, so it is redundant at all 304 sites.

There is no third state. A test either passes or fails; nothing can be skipped. `perf_gate_suite.gd:36-38` handles this by hardcoding `true`:

```gdscript
ctx.timed_record(
    "perf.headless_budget_gate", get_category(), true, BUDGET_DOC, start, "M7.perf.gate"
)
```

### The base class

`ValidationSuite` (`validation_suite.gd`) provides `_init(context)` storing `ctx`, `get_category()` returning `"unknown"`, `get_suite_name()` derived from the script path, and an empty `run()`. There are no `setup()`, `teardown()`, `before_each()`, or `after_each()` hooks.

`get_suite_name()` has no callers; the runner recomputes the name from the path at `validation_runner.gd:82`.

Suites extend by path (`extends "res://scripts/validation/validation_suite.gd"`), not by the registered `class_name`.

### `TestContext` fixtures and helpers

Beyond recording, `test_context.gd` holds shared test data and game-logic helpers:

| Member | Kind | Lines |
|--------|------|-------|
| `REPORT_PATH`, `SAVE_PATH` | Paths | `:6-7` |
| `SEED_A` = 42001, `SEED_B` = 99999 | Seeds | `:9-10` |
| `FIXTURE_BOSS` = `Vector3(38, 0, 58)` | Layout fixture | `:11` |
| `REQUIRED_INPUT_ACTIONS` | 13 action names | `:13-17` |
| `REQUIRED_ENEMIES` | 4 ids | `:19-21` |
| `REQUIRED_ITEMS` | 4 ids | `:23-25` |
| `KEY_SCENES` | 5 scene paths | `:27-33` |
| `ROOM_TEMPLATE_SCENES` | 8 template id to scene path | `:35-44` |
| `MANUAL_REMAINING` | 30 manual-test ids | `:46-77` |
| `file_contains` | Helper | `:124-127` |
| `backup_save_file` / `restore_save_file` / `_local_save` | Save fixture management | `:130-160` |
| `eval_continuable` | Re-implements the continue-run rule | `:163-174` |
| `player_snapshot_allowed` | Re-implements the snapshot rule | `:177-182` |
| `layout_signature` | Canonical layout string for parity checks | `:185-208` |
| `matches_m2_fixture` | Hardcoded 8-room boss-position check | `:211-222` |
| `parse_castle_seed` | Re-implements seed input parsing | `:225-232` |
| `count_nodes_by_script` / `count_loot_chests` | Tree walkers | `:235-246` |
| `await_physics` / `await_frame` | Frame helpers | `:249-256` |

`eval_continuable`, `player_snapshot_allowed`, and `parse_castle_seed` are second implementations of rules that also exist in production code. A suite asserting against them verifies the copy, not the shipped behavior.

`backup_save_file` and `restore_save_file` are the only teardown mechanism in the harness, and suites must call them explicitly.

### The report

`_write_report` (`validation_runner.gd:97-124`) writes `user://mcp_validation.json`:

```json
{
  "schemaVersion": 2,
  "generatedAt": "2026-08-05T14:00:00",
  "passed": 0,
  "failed": 0,
  "suites": [ { "name": "...", "category": "...", "passed": 0, "failed": 0, "duration_ms": 0 } ],
  "tests":  [ { "id": "...", "category": "...", "pass": true, "message": "...", "duration_ms": 0, "checklist_ref": "..." } ],
  "coverage": { "automated": 0, "manual_remaining": [ "M3.seed.spot_check", "..." ] },
  "reportPath": "<absolute user data dir>/mcp_validation.json"
}
```

The file is opened `WRITE` and written; there is no `flush()`, no `close()`, and no branch for a null handle.

Stdout gets exactly one line (`validation_runner.gd:115-124`):

```
[ValidationRunner] 231 passed, 4 failed -> user://mcp_validation.json
```

No failing test id and no message reaches stdout. In CI the report is not uploaded either (`.github/workflows/ci.yml:119-120`), so a failed run is diagnosable only by reproducing it locally. See [`ci-cd.md`](ci-cd.md) gap CID-06.

The `coverage` block divides nothing by nothing: `automated` is the raw test count and `manual_remaining` is a 30-entry string list maintained by hand at `test_context.gd:46-77`, with no link to any suite, document, or checklist.

## Absent

- **Assertion helpers.** No `assert_*` function exists in any of the four files.
- **Suite or test filtering.** `SUITE_PATHS` is a `const`; there is no command-line argument, environment variable, or tag parsing. `OS.get_cmdline_args()` and `OS.get_cmdline_user_args()` do not appear in the harness.
- **Per-test or per-suite timeout.** No `SceneTreeTimer`, no watchdog. A suite awaiting a signal that never fires blocks the process indefinitely.
- **Error containment.** `await suite.call("run")` at `validation_runner.gd:76` is not guarded. There is no equivalent of a try/catch in GDScript, and no separate process per suite.
- **Setup and teardown hooks.** `ValidationSuite` defines only `run()` and `get_category()`.
- **A skip or pending status.** `record` takes a `bool`.
- **Duplicate-id detection.** `record` appends unconditionally.
- **JUnit XML or any CI-native format.** Only the custom JSON.
- **Randomized or repeated execution order.** Order is the literal order of `SUITE_PATHS`.
- **Code coverage of production scripts.** No instrumentation of any kind.
- **Parallel execution.** Suites run sequentially in one process.
- **Any test of the harness itself.** No suite asserts anything about `TestContext` or the runner.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| VHA-01 | P0 | A GDScript runtime error inside a suite's `run()` breaks the awaited coroutine chain, so `_write_report()` and `get_tree().quit()` never execute and the headless process hangs with no report and no exit code. CI sets no `timeout-minutes`, so it burns the runner's 6-hour default. | `validation_runner.gd:46-49,76`; no `timeout-minutes` in `.github/workflows/ci.yml` |
| VHA-02 | P0 | No per-test or per-suite timeout. Any `await` on a signal that never fires produces the same indefinite hang. | No timer in `validation_runner.gd` or `test_context.gd` |
| VHA-03 | P1 | No way to run one suite or one test. Iterating on a single failure means editing `SUITE_PATHS` or running all 24 suites. | `validation_runner.gd:13-38` is a `const`; no cmdline parsing in the harness |
| VHA-04 | P1 | Only a boolean crosses the assertion boundary, so a failure report never contains the actual value. Debugging requires reading the suite source and re-running locally. | `test_context.gd:89-110`; 304 call sites across `suites/` |
| VHA-05 | P1 | One shared `TestContext` with no reset. Suites mutate global state — autoload services, the save file, nodes added to the tree — and later suites inherit it. Only `backup_save_file`/`restore_save_file` exist, and only when a suite remembers to call them. | `validation_runner.gd:45`; `test_context.gd:130-153` |
| VHA-06 | P1 | Fixed execution order with no shuffle or repeat option, so order dependencies between suites are invisible. | `validation_runner.gd:53` |
| VHA-07 | P1 | Stdout carries only a pass/fail count. Combined with the report never being uploaded, a CI failure is undiagnosable from the log. | `validation_runner.gd:115-124`; `.github/workflows/ci.yml:119-120` |
| VHA-08 | P1 | No skip status, so headless-impossible checks either fail or pass vacuously. `perf.headless_budget_gate` passes a literal `true`. | `test_context.gd:89`; `perf_gate_suite.gd:36-38` |
| VHA-09 | P1 | No JUnit XML, so GitHub cannot annotate the pull request with failing tests. | `validation_runner.gd:97-114` writes only the custom JSON |
| VHA-10 | P2 | Duplicate test ids are silently accepted; the report can contain two entries with the same `id`. | `test_context.gd:110` |
| VHA-11 | P2 | The `coverage` block compares a test count against a hand-maintained 30-item manual list with no link to anything, producing a number that measures nothing. | `validation_runner.gd:105-109`, `test_context.gd:46-77` |
| VHA-12 | P2 | `TestContext` mixes harness plumbing with game-logic reimplementations (`eval_continuable`, `player_snapshot_allowed`, `parse_castle_seed`). Suites assert against the copy, so production can diverge while every test passes. | `test_context.gd:163-182,225-232` |
| VHA-13 | P2 | `ValidationSuite` has no setup or teardown hooks, so every suite hand-rolls its own fixture management. | `validation_suite.gd:11-24` |
| VHA-14 | P2 | `get_suite_name()` is defined and never called; the runner recomputes the same value from the path. | `validation_suite.gd:19-20` vs `validation_runner.gd:82` |
| VHA-15 | P2 | `category` is passed explicitly at all 304 call sites even though it is always `get_category()`. | `test_context.gd:89-91` |
| VHA-16 | P2 | Two entry points with different documented recommendations, and no test that they behave identically. CI uses the one the comments advise against. | `validation_main.gd:4` vs `validation_runner.gd:5-6`; `.github/workflows/ci.yml:120` |
| VHA-17 | P2 | `_write_report` never flushes or closes and silently does nothing when `FileAccess.open` returns null. | `validation_runner.gd:112-114` |
| VHA-18 | P2 | No coverage measurement over `apps/game/client/scripts/`, so there is no signal about which of the 271 GDScript files are exercised. | No instrumentation in the harness |
| VHA-19 | P2 | The harness itself is untested. | No suite references `TestContext` or `validation_runner` |

## Related

- Improvement plan: [`../actual_improvements/validation-harness.md`](../actual_improvements/validation-harness.md)
- [`validation-suites.md`](validation-suites.md) — the 24 suites and what each asserts
- [`ci-cd.md`](ci-cd.md) — the `godot` job, the missing artifact upload, the missing timeout
- [`combat-validation.md`](combat-validation.md) — combat-specific assertions
