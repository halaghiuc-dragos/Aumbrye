# find_graph_seed diagnostic — improvement plan

## Current state

`find_graph_seed.gd` was replaced by `procgen_seed_health.gd`, a retry-aware sweep tool that calls the public `RoomGraphGenerator.generate_reported()` API, writes `procgen-seed-health.v1` JSON, gates CI on fallback rate, and runs in `.github/workflows/ci.yml`. See [`../existing_codebase/find-graph-seed.md`](../existing_codebase/find-graph-seed.md).

## Status: FINISHED

## Gaps

| ID | Sev | Gap | Evidence | Resolution |
|----|-----|-----|----------|------------|
| FGS-01 | P1 | The tool reports the outcome of one attempt, while the shipping generator retries and then falls back | was `find_graph_seed.gd:22` vs `room_graph_generator.gd:34-49` | **Done** — `generate_reported()` mirrors retry loop (`room_graph_generator.gd:42-61`); tool calls it per seed (`procgen_seed_health.gd:318`) |
| FGS-02 | P1 | No aggregate statistics | was single seed per process | **Done** — sweep accumulates histograms and rates (`procgen_seed_health.gd:133-161`, `:296-360`) |
| FGS-03 | P1 | Biome hardcoded to `forgotten_castle` | was `find_graph_seed.gd:18` | **Done** — `BIOME_IDS` lists all 10 biomes (`procgen_seed_health.gd:19-30`) |
| FGS-04 | P2 | Exit code always 0 | was `find_graph_seed.gd:29` | **Done** — `evaluate_exit_code()` returns 0/1/2 (`procgen_seed_health.gd:164-171`) |
| FGS-05 | P2 | Unstructured stdout only | was `find_graph_seed.gd:24-28` | **Done** — JSON report + summary table (`procgen_seed_health.gd:174-181`, `:218-238`); schema at `content/schemas/procgen-seed-health.v1.json` |
| FGS-06 | P2 | Reaches into private generator members | was `find_graph_seed.gd:22,24,27` | **Done** — tool uses only `generate_reported()` (`procgen_seed_health.gd:318`) |
| FGS-07 | P2 | Seed parsing from `OS.get_cmdline_args()` | was `find_graph_seed.gd:13-17` | **Done** — `parse_args(OS.get_cmdline_user_args())` (`procgen_seed_health.gd:38`, `:54`) |
| FGS-08 | P2 | `--path .` only works from client dir | was `find_graph_seed.gd:4` | **Done** — header documents both invocations (`procgen_seed_health.gd:4-7`) |
| FGS-09 | P2 | No ASCII map output | was absent | **Done** — `--seed --ascii` calls `RoomGraphDebug.print_graph` (`procgen_seed_health.gd:244-246`) |
| FGS-10 | P2 | No CI step | was absent from workflows | **Done** — `.github/workflows/ci.yml:270-276` |
| FGS-11 | P2 | `var seed` shadows global `seed()` | was `find_graph_seed.gd:12` | **Done** — renamed to `seed_value` (`procgen_seed_health.gd:223`, `:318`) |
| FGS-12 | P2 | Root `seed*.json` artifacts | was `seed1.json`, `seed99999.json` | **Done** — files absent; `content_suite.gd` `test_no_root_seed_dumps` guards regression |

## Target design

Turn the diagnostic into a **procgen health report**: a headless script that sweeps a seed range across all biomes, writes a JSON report, prints a summary table, and exits non-zero when the fallback rate or any validation-failure rate exceeds a threshold. The generator gains the small public surface the tool needs so it stops poking at privates.

### 1. Public generator surface (FGS-01, FGS-06) — implemented

`GenerationReport` and `generate_reported()` added at `room_graph_generator.gd:26-61`. `generate()` is a thin wrapper (`:64-79`). Per-attempt reasons live on the report object; `_last_validate_reason` remains for `local_procgen.gd` compatibility.

### 2. Sweep tool (FGS-02, FGS-03, FGS-04, FGS-05, FGS-07, FGS-08, FGS-09, FGS-11) — implemented

`apps/game/client/scripts/tools/procgen_seed_health.gd` replaces `find_graph_seed.gd`. Arguments parsed from `OS.get_cmdline_user_args()` per table in [`existing_codebase/find-graph-seed.md`](../existing_codebase/find-graph-seed.md).

### 3. Rename and relocate — implemented

Old script deleted. `--find-first-fallback` implemented (`procgen_seed_health.gd:251-275`).

### 4. CI wiring (FGS-10) — implemented

`.github/workflows/ci.yml:270-276`: 500 seeds × 10 biomes, artifact upload.

### 5. Root artifacts (FGS-12) — implemented

No `seed*.json` at repo root. Default report path `reports/procgen_seed_health.json`.

## Data and schema changes

- `content/schemas/procgen-seed-health.v1.json` — added.
- `reports/` remains gitignored.
- No change to `dungeon-definition.v1.json` / `v2`.

## Determinism

- Seeds generated in isolation via fresh `RandomNumberGenerator` per call (`room_graph_generator.gd:44-45`).
- Biomes sorted, seeds ascending (`procgen_seed_health.gd:133-161`).
- `worstSeeds` sorted `(attempts desc, seed asc)`, truncated to 10.
- Floats formatted to 6 decimals (`procgen_seed_health.gd:404-411`).
- `procgen_seed_health_suite.gd` `test_sweep_deterministic` asserts byte-identical serialization.

## Acceptance criteria

- [x] The report distinguishes first-attempt success, retried success, and fallback, and its `usedFallback` count matches the number of seeds for which `generate()` returns `used_fallback` (FGS-01). Evidence: `procgen_seed_health_suite.gd` `test_generate_reported_matches_generate`.
- [x] A sweep of 500 seeds across all 10 biomes produces per-biome fallback rates, an attempt histogram, and a failure-reason histogram (FGS-02, FGS-03). Evidence: `procgen_seed_health.gd:296-360`, CI step at `.github/workflows/ci.yml:270-272`.
- [x] The process exits 1 when a biome exceeds `--max-fallback-rate` and 0 when none does (FGS-04). Evidence: `procgen_seed_health_suite.gd` `test_exit_code_contract`.
- [x] The report validates against `content/schemas/procgen-seed-health.v1.json` (FGS-05). Evidence: `procgen_seed_health_suite.gd` `test_report_schema_valid`.
- [x] The tool references no identifier beginning with `_` from `room_graph_generator.gd` (FGS-06). Evidence: `procgen_seed_health.gd` uses only `generate_reported`.
- [x] `--seed 42001 --ascii` prints the graph and measured room count, boss distance, and dead-end count next to their thresholds (FGS-09). Evidence: `procgen_seed_health.gd:223-246`.
- [x] Arguments are read from `OS.get_cmdline_user_args()`, and passing an engine flag such as `--fixed-fps 60` does not change the seed (FGS-07). Evidence: `procgen_seed_health_suite.gd` `test_user_args_ignore_engine_flags`.
- [x] The header comment's invocation works verbatim from the repo root (FGS-08). Evidence: `procgen_seed_health.gd:4-7`; Godot validation run from repo root succeeded.
- [x] CI runs the sweep and uploads the report as an artifact (FGS-10). Evidence: `.github/workflows/ci.yml:270-276`.
- [x] No `seed*.json` file exists at the repo root (FGS-12). Evidence: `content_suite.gd` `test_no_root_seed_dumps`.

## Validation

`apps/game/client/scripts/validation/suites/procgen_seed_health_suite.gd` registered at `validation_runner.gd:33`:

- `test_generate_reported_matches_generate` — 50 seeds: `used_fallback` and graph parity (FGS-01).
- `test_attempt_accounting` — forced failures record one reason per attempt.
- `test_no_static_reason_leak` — successful report has empty `reasons`.
- `test_sweep_deterministic` — two sweeps serialize identically.
- `test_report_schema_valid` — structural schema contract.
- `test_fallback_rate_threshold` — 200 seeds of `forgotten_castle` at ≤ 0.01.
- `test_all_biomes_generate` — all 10 biomes (FGS-03).
- `test_exit_code_contract` — 0 / 1 / 2 mapping (FGS-04).
- `test_user_args_ignore_engine_flags` — FGS-07.

`content_suite.gd` `test_no_root_seed_dumps` — FGS-12.

Godot headless validation (2026-08-06): `procgen_seed_health.gd --from 1 --count 5 --biome forgotten_castle` exited 0; `--seed 42001 --ascii` printed metrics and ASCII map.

## Related

- [`../existing_codebase/find-graph-seed.md`](../existing_codebase/find-graph-seed.md)
- [`room-graph-procgen.md`](room-graph-procgen.md)
- [`local-procgen.md`](local-procgen.md)
- [`biome-registry.md`](biome-registry.md)
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md)
- [`ci-cd.md`](ci-cd.md)
- [`tools-scripts.md`](tools-scripts.md), [`export-tools.md`](export-tools.md)
- [`repository-root.md`](repository-root.md)
