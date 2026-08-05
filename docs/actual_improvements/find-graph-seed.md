# find_graph_seed diagnostic — improvement plan

## Current state

29 lines that test one hardcoded biome with one seed on one attempt, print a sentence, and exit 0. It cannot answer the question its name implies — "find me a seed that works" — and its verdict is misleading, because the public generator retries `max_generation_attempts` times before falling back and the tool only ever runs attempt one. There is no way to measure the fallback rate, which is the single most important health metric for the room graph generator. See [`../existing_codebase/find-graph-seed.md`](../existing_codebase/find-graph-seed.md).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| FGS-01 | P1 | The tool reports the outcome of one attempt, while the shipping generator retries and then falls back, so `FAIL` does not mean the game degrades and `OK` does not mean it does not | `find_graph_seed.gd:22` vs `room_graph_generator.gd:34-49` |
| FGS-02 | P1 | No aggregate statistics: the fallback rate over N seeds, the failure-reason histogram, and the room-count distribution are unmeasurable | single seed per process (`find_graph_seed.gd:12-22`) |
| FGS-03 | P1 | The biome is hardcoded to `forgotten_castle`, so the nine other biome configs are never exercised | `find_graph_seed.gd:18` |
| FGS-04 | P2 | Exit code is always 0, so the tool cannot gate CI | `find_graph_seed.gd:29` |
| FGS-05 | P2 | Output is unstructured `print()` text with no JSON or report file | `find_graph_seed.gd:24-28` |
| FGS-06 | P2 | Reaches into three private members of the generator (`_try_generate_once`, `_last_validate_reason`, `_count_main_slots`) | `find_graph_seed.gd:22,24,27` |
| FGS-07 | P2 | Seed parsing takes the first int-valued entry of `OS.get_cmdline_args()`, which includes engine flags | `find_graph_seed.gd:13-17` |
| FGS-08 | P2 | The documented invocation uses `--path .`, which only works from `apps/game/client` | `find_graph_seed.gd:4`; `project.godot` is at `apps/game/client/project.godot` |
| FGS-09 | P2 | `RoomGraphDebug.print_graph` is never called, so a failing seed cannot be inspected visually | no reference in `find_graph_seed.gd`; `room_graph_generator.gd:40-41` gates it on `config.debug_ascii` |
| FGS-10 | P2 | No CI step; the tool is documented in a header comment and nowhere else | no match in `.github/workflows/` |
| FGS-11 | P2 | `var seed` shadows the global `seed()` function | `find_graph_seed.gd:12` |
| FGS-12 | P2 | `seed1.json` / `seed99999.json` sit at the repo root untracked, and `seed1.json`'s name does not match its `seed` field (`2000007`) | `seed1.json:1`, `.gitignore:177` |

## Target design

Turn the diagnostic into a **procgen health report**: a headless script that sweeps a seed range across all biomes, writes a JSON report, prints a summary table, and exits non-zero when the fallback rate or any validation-failure rate exceeds a threshold. The generator gains the small public surface the tool needs so it stops poking at privates.

### 1. Public generator surface (FGS-01, FGS-06)

Add to `room_graph_generator.gd`:

```gdscript
## Result of one generation, including how it was reached.
class GenerationReport extends RefCounted:
    var ok: bool                 # a graph was produced (always true today)
    var used_fallback: bool
    var attempts: int            # 1..max_generation_attempts
    var reasons: PackedStringArray  # validation reason per failed attempt
    var graph: RoomGraph
    var main_room_count: int

static func generate_reported(config: RoomGraphConfig, run_seed: int) -> GenerationReport
```

`generate()` becomes a thin wrapper over `generate_reported()` so both paths share one implementation, and `_last_validate_reason` — a process-global static (`room_graph_generator.gd:31`) — is replaced by the per-attempt `reasons` array. That removes the stale-value hazard and the private-access coupling in one change.

### 2. Sweep tool (FGS-02, FGS-03, FGS-04, FGS-05, FGS-07, FGS-08, FGS-09, FGS-11)

Rewrite `find_graph_seed.gd` with parsed arguments taken from `OS.get_cmdline_user_args()` (everything after `--`), which excludes engine flags (FGS-07):

| Argument | Default | Meaning |
|----------|---------|---------|
| `--seed <int>` | — | test exactly this seed and print the ASCII map |
| `--from <int>` | `1` | sweep start, inclusive |
| `--count <int>` | `1000` | number of seeds to sweep |
| `--biome <id>` | all ids from `BiomeRegistry` | comma-separated biome list |
| `--max-fallback-rate <float>` | `0.01` | exit 1 when exceeded |
| `--report <path>` | `reports/procgen_seed_health.json` | JSON output path |
| `--ascii` | off | print the graph for every failing seed |

Naming: the local variable becomes `seed_value` (FGS-11), and the header comment documents `--path apps/game/client` from the repo root plus `--path .` from inside the project (FGS-08).

Per seed it calls `generate_reported()` once and accumulates:

```
{
  "schemaVersion": 1,
  "generatedAtUnix": 1767225600,
  "seedFrom": 1, "seedCount": 1000,
  "biomes": {
    "forgotten_castle": {
      "seeds": 1000,
      "firstAttemptOk": 962,
      "retriedOk": 37,
      "usedFallback": 1,
      "fallbackRate": 0.001,
      "attemptHistogram": { "1": 962, "2": 31, "3": 6 },
      "failureReasons": { "Not enough dead ends": 29, "2x2 block detected": 8 },
      "mainRoomCount": { "min": 6, "max": 10, "mean": 8.1, "histogram": { "6": 41, "7": 180 } },
      "worstSeeds": [ { "seed": 771, "attempts": 3, "reasons": ["..."] } ]
    }
  },
  "totals": { "seeds": 10000, "usedFallback": 4, "fallbackRate": 0.0004 }
}
```

Failure reasons are bucketed by their format-string prefix rather than the interpolated text, so `Not enough dead ends (1 < 2)` and `(0 < 2)` land in one bucket.

Stdout gets a fixed-width summary table — one row per biome with seeds, first-attempt rate, fallback rate, and room-count min/mean/max — so a human reading CI logs sees the answer without opening the JSON (FGS-05).

Exit codes (FGS-04):

| Code | Condition |
|------|-----------|
| 0 | every biome's fallback rate is at or under `--max-fallback-rate` |
| 1 | any biome exceeds it |
| 2 | a biome JSON failed to load, or a generation returned `ok == false` |

Single-seed mode (`--seed`) prints the report for that seed plus the ASCII map via `RoomGraphDebug.print_graph`, which is what an author debugging one bad layout actually wants (FGS-09). It should also print the room-count, the boss distance, and the dead-end count next to the config thresholds, so the reason a seed missed is legible without reading `_validate_graph`.

### 3. Rename and relocate

`find_graph_seed.gd` becomes `apps/game/client/scripts/tools/procgen_seed_health.gd`. The old name describes a search that the script never performed; the new one describes what it reports. Keep the search: `--find-first-fallback` walks upward from `--from` and prints the first seed whose generation needed the fallback, which is the one genuinely useful "find a seed" behavior.

### 4. CI wiring (FGS-10)

Add a step to `.github/workflows/ci.yml` beside the existing export step at `:118`:

```yaml
- name: Procgen seed health
  run: godot --path apps/game/client --headless --script res://scripts/tools/procgen_seed_health.gd -- --from 1 --count 500 --max-fallback-rate 0.01 --report ../../../reports/procgen_seed_health.json
- uses: actions/upload-artifact@v4
  with: { name: procgen-seed-health, path: reports/procgen_seed_health.json }
```

500 seeds x 10 biomes is 5000 graph generations; the graph phase is pure integer work with no scene instantiation, so this belongs in the fast job rather than the nightly one. If it measures slower than roughly 30 seconds, drop the PR run to `--count 100` and keep 5000 on a nightly schedule.

The threshold starts at the rate the first run measures, rounded up, and ratchets down as the generator improves. A ratchet that starts loose and only tightens is the only kind that survives contact with a real codebase.

### 5. Root artifacts (FGS-12)

Delete `seed1.json` and `seed99999.json` from the working tree. Any definition worth keeping as a comparison baseline goes to `content/fixtures/` with a name stating what it is, its real seed, and which generator produced it — for example `content/fixtures/csharp_cli_forgotten_castle_seed99999.json`. `.gitignore:177` already prevents new root dumps from being committed. The CLI's `--out` default should point at `reports/` rather than the current working directory.

## Data and schema changes

- New `content/schemas/procgen-seed-health.v1.json` describing the report above: `schemaVersion`, `generatedAtUnix`, `seedFrom`, `seedCount`, `biomes` (object keyed by biome id), `totals`. `additionalProperties: false`, all rates as `number` in `[0, 1]`.
- `reports/` is already ignored (see [`repository-root.md`](../existing_codebase/repository-root.md)); the report is a CI artifact, not a committed file.
- Move `seed99999.json` to `content/fixtures/csharp_cli_forgotten_castle_seed99999.json` if it is kept as a parity baseline; delete `seed1.json`.
- No change to `content/schemas/dungeon-definition.v1.json` — the tool never constructs a definition, only a graph.

## Determinism

The report is only useful if it is reproducible: the same `--from`, `--count`, and biome list must produce a byte-identical JSON body apart from `generatedAtUnix`.

- Each seed is generated in isolation with a fresh `RandomNumberGenerator`, exactly as `generate()` does at `room_graph_generator.gd:35-36`, so no state leaks between seeds. Removing the `_last_validate_reason` static is part of this.
- Biomes are iterated in sorted id order and seeds in ascending order.
- `worstSeeds` is sorted by `(attempts desc, seed asc)` and truncated to 10, so ties never reorder.
- Floats in the report are written with a fixed 6-decimal format so the JSON is diffable.
- The assertion lives in the validation suite: run the sweep twice in-process over a small range and compare the serialized reports minus the timestamp.

## Acceptance criteria

- [ ] The report distinguishes first-attempt success, retried success, and fallback, and its `usedFallback` count matches the number of seeds for which `generate()` returns `used_fallback` (FGS-01).
- [ ] A sweep of 500 seeds across all 10 biomes produces per-biome fallback rates, an attempt histogram, and a failure-reason histogram (FGS-02, FGS-03).
- [ ] The process exits 1 when a biome exceeds `--max-fallback-rate` and 0 when none does (FGS-04).
- [ ] The report validates against `content/schemas/procgen-seed-health.v1.json` (FGS-05).
- [ ] The tool references no identifier beginning with `_` from `room_graph_generator.gd` (FGS-06).
- [ ] `--seed 42001 --ascii` prints the graph and the measured room count, boss distance, and dead-end count next to their thresholds (FGS-09).
- [ ] Arguments are read from `OS.get_cmdline_user_args()`, and passing an engine flag such as `--fixed-fps 60` does not change the seed (FGS-07).
- [ ] The header comment's invocation works verbatim from the repo root (FGS-08).
- [ ] CI runs the sweep and uploads the report as an artifact (FGS-10).
- [ ] No `seed*.json` file exists at the repo root (FGS-12).

## Validation

Add `apps/game/client/scripts/validation/suites/procgen_seed_health_suite.gd` (registered in the harness per [`validation-harness.md`](validation-harness.md)):

- `test_generate_reported_matches_generate` — for 50 seeds, assert `generate_reported(config, s).used_fallback` equals the `used_fallback` flag from `generate(config, s)` and that the returned graphs are structurally identical (same slot ids, types, and door masks).
- `test_attempt_accounting` — construct a config guaranteed to fail validation on the first attempt (`min_dead_ends` above what the grid allows) and assert `attempts == config.max_generation_attempts`, `used_fallback == true`, and `reasons.size() == attempts`.
- `test_no_static_reason_leak` — run a failing generation then a succeeding one and assert the second report's `reasons` is empty, proving the removal of the process-global static.
- `test_sweep_deterministic` — run the sweep twice over `--from 1 --count 50` for two biomes and assert the reports are byte-identical after removing `generatedAtUnix` (determinism).
- `test_report_schema_valid` — validate a generated report against `content/schemas/procgen-seed-health.v1.json`.
- `test_fallback_rate_threshold` — assert the measured fallback rate over 200 seeds of `forgotten_castle` is at or below 0.01, and record the value in the suite output so regressions are visible in the report history.
- `test_all_biomes_generate` — for each of the 10 biome ids, assert `generate_reported` returns `ok == true` and a graph with at least `config.min_rooms` main slots (FGS-03).
- `test_exit_code_contract` — call the tool's argument parser and threshold evaluator directly (extracted as static functions so they are testable without spawning a process) and assert the 0 / 1 / 2 mapping.

Extend `apps/game/client/scripts/validation/suites/content_suite.gd`:

- `test_no_root_seed_dumps` — assert no `res://../../../seed*.json` exists, so the artifacts do not creep back (FGS-12).

Manual checklist: run `--find-first-fallback --from 1` for each biome and confirm the reported seed reproduces the fallback when passed to `--seed`, and that the ASCII map of that seed visibly violates the reported validation rule.

## Related

- [`../existing_codebase/find-graph-seed.md`](../existing_codebase/find-graph-seed.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — the generator, `generate_reported`, validation rules the report buckets
- [`local-procgen.md`](local-procgen.md) — seed derivation, the C# CLI fallback
- [`biome-registry.md`](biome-registry.md) — the biome list the sweep iterates
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md) — suite registration
- [`ci-cd.md`](ci-cd.md) — where the sweep step and artifact upload land
- [`tools-scripts.md`](tools-scripts.md), [`export-tools.md`](export-tools.md) — the tool inventory and the CI-wired sibling
- [`repository-root.md`](repository-root.md) — root artifact cleanup
