# procgen seed health tool

Headless procgen health reporter that sweeps seed ranges across all ten EA biomes, writes `procgen-seed-health.v1` JSON, prints a summary table, and exits non-zero when fallback or generation-error thresholds are exceeded. Replaces the deleted `find_graph_seed.gd` single-attempt diagnostic.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/tools/procgen_seed_health.gd` | `SceneTree` entry: argument parsing, sweep, JSON report, exit codes |
| `apps/game/client/scripts/dungeon/procgen/room_graph_generator.gd` | `GenerationReport` + `generate_reported()` public API used by the tool |
| `content/schemas/procgen-seed-health.v1.json` | JSON Schema for the report artifact |
| `apps/game/client/scripts/validation/suites/procgen_seed_health_suite.gd` | Validation suite (registered in `validation_runner.gd:33`) |
| `.github/workflows/ci.yml:270-276` | CI sweep step + artifact upload |

## How it works

### Invocation

From repo root (`apps/game/client/project.godot`):

```
godot --path apps/game/client --headless --script res://scripts/tools/procgen_seed_health.gd -- --from 1 --count 500
```

From `apps/game/client`:

```
godot --path . --headless --script res://scripts/tools/procgen_seed_health.gd -- --from 1 --count 500
```

User arguments are read from `OS.get_cmdline_user_args()` (`procgen_seed_health.gd:54`), so engine flags such as `--fixed-fps 60` do not affect parsing (FGS-07).

| Argument | Default | Meaning |
|----------|---------|---------|
| `--seed <int>` | â€” | single-seed mode: print metrics + optional ASCII |
| `--from <int>` | `1` | sweep start, inclusive |
| `--count <int>` | `1000` | seeds per biome |
| `--biome <id>` | all 10 ids in `BIOME_IDS` | comma-separated biome filter |
| `--max-fallback-rate <float>` | `0.01` | exit `1` when any biome exceeds this |
| `--report <path>` | `reports/procgen_seed_health.json` | JSON output (repo-root relative) |
| `--ascii` | off | print ASCII graph in single-seed mode |
| `--find-first-fallback` | off | walk upward from `--from` for first retry seed |

### Per-seed generation

Each seed calls `RoomGraphGenerator.generate_reported(config, seed_value)` (`room_graph_generator.gd:42-61`), which mirrors the shipping retry loop in `generate()` (`:64-79`): up to `config.max_generation_attempts` attempts with reseed `run_seed + (attempt + 1) * 1_000_003`. There is no fallback graph today (`used_fallback` is always `false`; see [`room-graph-procgen.md`](room-graph-procgen.md)).

The tool never calls private generator members (`_try_generate_once`, `_last_validate_reason`, `_count_main_slots`).

### Sweep output

`build_sweep_report()` (`procgen_seed_health.gd:133-161`) iterates biomes in sorted id order and seeds ascending. Per biome it accumulates `firstAttemptOk`, `retriedOk`, `usedFallback`, `attemptHistogram`, bucketed `failureReasons`, `mainRoomCount` stats, and `worstSeeds` (top 10 by attempts desc, seed asc).

Stdout prints a fixed-width table via `print_summary_table()` (`:218-238`). JSON is written to `reports/` (gitignored per `.gitignore:175`).

### Exit codes

`evaluate_exit_code()` (`procgen_seed_health.gd:164-171`):

| Code | Condition |
|------|-----------|
| `0` | every biome `fallbackRate` â‰¤ `--max-fallback-rate` |
| `1` | any biome exceeds the threshold |
| `2` | biome JSON load failure or `generate_reported().ok == false` |

### Single-seed mode

`--seed 42001 --ascii` prints room count, boss distance, dead-end count against config thresholds and calls `RoomGraphDebug.print_graph()` (`procgen_seed_health.gd:244-246`).

### Headless biome loading

The tool reads biome JSON directly via `_fetch_biome()` (`:468-478`) using `_content_root()` â€” no `ContentLoader` autoload required, matching the `export_diorama_anim_libraries.gd` pattern.

## Contracts

- Depends on `RoomGraphGenerator.generate_reported()` only (public API).
- Report schema: `content/schemas/procgen-seed-health.v1.json`; `schemaVersion: 1`.
- CI artifact: `reports/procgen_seed_health.json` uploaded as `procgen-seed-health` (`.github/workflows/ci.yml:273-276`).
- `ProcgenBiomeLoader.load()` is an alias for `fetch()` (`procgen_biome_loader.gd:21-22`) for validation-suite compatibility.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Retry-aware sweep across 10 biomes | IMPLEMENTED | `procgen_seed_health.gd:133-161`, `BIOME_IDS:19-30` |
| `generate_reported()` public API | IMPLEMENTED | `room_graph_generator.gd:26-61` |
| JSON report + schema | IMPLEMENTED | `procgen_seed_health.gd:174-181`, `content/schemas/procgen-seed-health.v1.json` |
| Exit codes 0 / 1 / 2 | IMPLEMENTED | `procgen_seed_health.gd:164-171` |
| User-args parsing (no engine-flag collision) | IMPLEMENTED | `procgen_seed_health.gd:54-108` |
| Single-seed ASCII + metrics | IMPLEMENTED | `procgen_seed_health.gd:207-247` |
| CI sweep + artifact | IMPLEMENTED | `.github/workflows/ci.yml:270-276` |
| Validation suite | IMPLEMENTED | `procgen_seed_health_suite.gd`, `validation_runner.gd:33` |
| Root `seed*.json` artifacts | ABSENT | `content_suite.gd` `test_no_root_seed_dumps`; no files at repo root |
| Fallback graph generation | ABSENT | `used_fallback` always `false`; no `0xFA11BAC` path in generator |

## Related

- Improvement plan: [`../actual_improvements/find-graph-seed.md`](../actual_improvements/find-graph-seed.md) - **FINISHED**
- [`room-graph-procgen.md`](room-graph-procgen.md) â€” generator, validation rules, retry loop
- [`local-procgen.md`](local-procgen.md) â€” seed derivation the tool bypasses
- [`biome-registry.md`](biome-registry.md) â€” biome ids (tool uses hardcoded `BIOME_IDS` for headless independence)
- [`tools-scripts.md`](tools-scripts.md), [`export-tools.md`](export-tools.md) â€” tool inventory
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md)
- [`ci-cd.md`](ci-cd.md) â€” CI wiring
- [`repository-root.md`](repository-root.md) â€” root artifact policy
