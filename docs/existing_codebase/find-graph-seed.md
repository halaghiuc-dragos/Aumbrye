# find_graph_seed diagnostic

A 29-line headless script that reports whether one seed produces a valid `forgotten_castle` room graph on its first attempt, or the validation reason it failed. It is the only diagnostic tooling that exists for the room graph generator.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/tools/find_graph_seed.gd` | `SceneTree` script: load biome, build config, run one generation attempt, print the result |

## How it works

```
godot --path . --headless --script res://scripts/tools/find_graph_seed.gd [seed]
```

That invocation line is copied from the file header (`find_graph_seed.gd:4`). `--path .` only resolves when the working directory is `apps/game/client`, since that is where `project.godot` lives — from the repo root the command needs `--path apps/game/client`.

`_initialize()` (`:11-29`) does five things:

1. Defaults `seed` to `42001` and scans `OS.get_cmdline_args()` for the first argument that satisfies `is_valid_int()` (`:12-17`). Engine flags are included in that array, so any numeric-looking engine argument that appears before the intended seed wins.
2. Loads the biome with `ProcgenBiomeLoader.load("forgotten_castle")` (`:18`), which reads `content/biomes/forgotten_castle.json` through the `ContentLoader` autoload (`procgen_biome_loader.gd:5-6`). The biome id is hardcoded; the other nine biomes cannot be tested.
3. Builds a `RoomGraphConfig` with `from_biome` (`:19`).
4. Seeds a fresh `RandomNumberGenerator` and calls `RoomGraphGeneratorScript._try_generate_once(config, rng)` (`:20-22`) — the private single-attempt function, not the public `generate()`.
5. Prints either `seed %d FAIL: %s` with `RoomGraphGeneratorScript._last_validate_reason` (`:24`) or `seed %d OK main=%d` with `_count_main_slots(graph)` (`:26-28`), then `quit()` with the default exit code 0 (`:29`).

### What "FAIL" does and does not mean

The public generator retries. `RoomGraphGenerator.generate()` (`room_graph_generator.gd:34-49`) loops `config.max_generation_attempts` times, reseeding with `run_seed + (attempt + 1) * 1_000_003` after each miss, and only then builds a fallback graph with `run_seed ^ 0xFA11BAC`. The tool runs attempt one only. A `FAIL` line therefore says "this seed missed on its first attempt", not "the game falls back on this seed", and an `OK` line says nothing about the retry path.

The tool also never reports the thing an operator actually wants to know: whether `generate()` returned `used_fallback` (`:49`). Reading that flag would require calling the public function.

### Validation reasons it can print

`_last_validate_reason` is a static var (`room_graph_generator.gd:31`) set by `_validate_graph` (`:486-522`), so the tool can print any of:

| Reason | Line |
|--------|------|
| `Room count %d below minimum %d` | `:486` |
| `Unreachable room '%s' from start` | `:496` |
| `Boss room not assigned` | `:499` |
| `Boss too close to start (%d < %d)` | `:502` |
| `Not enough dead ends (%d < %d)` | `:512` |
| `2x2 block detected at %s` | `:520` |

The var is cleared to `""` on success (`:522`) and is process-global, so a stale value from an earlier attempt in the same process would be printed as-is. In this one-attempt tool that cannot happen, but nothing in the design prevents it.

### Root JSON artifacts

`seed1.json` and `seed99999.json` at the repo root are **not** output of this tool. It prints one text line and writes no files. Both artifacts are canonical-JSON `DungeonDefinition` dumps from the C# `tools/procgen-cli`: alphabetically ordered keys, a `checksum` field, a GUID `runId`, `position` keys inside placements, and no `roomContent` / `locks` / `landmarks` / `branchPreviews` — all C# CLI markers, none of which the GDScript generator produces.

| File | `seed` field | Rooms | `checksum` |
|------|-------------|-------|-----------|
| `seed1.json:1` | `2000007` | 9 | `7cfec53d...` |
| `seed99999.json:1` | `99999` | 10 | `1564465e...` |

Note that `seed1.json` contains seed `2000007`, so the filename does not match its contents. Both files are untracked and covered by `.gitignore:177` (`/seed*.json`). They are treated as stray root artifacts by [`repository-root.md`](repository-root.md).

### Comparison with the other tool script

`apps/game/client/scripts/tools/` contains exactly two scripts (`find_graph_seed.gd`, `export_diorama_anim_libraries.gd`). The export tool runs in CI (`.github/workflows/ci.yml:118`); `find_graph_seed.gd` has no CI step, no wrapper in `tools/`, and no mention in any workflow or `package.json` script.

## Contracts

- Invocation: `godot --path <project> --headless --script res://scripts/tools/find_graph_seed.gd [seed]`; a `SceneTree` script, so no scene is loaded.
- Depends on the `ContentLoader` autoload through `ProcgenBiomeLoader`.
- Depends on three private members of `room_graph_generator.gd`: `_try_generate_once`, `_last_validate_reason`, `_count_main_slots`. Renaming any of them breaks the tool silently at parse or call time.
- Output is unstructured stdout text; the exit code is always 0.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Single-seed pass/fail report with reason | IMPLEMENTED | `find_graph_seed.gd:22-28` |
| Seed override from the command line | PARTIAL | first int-valued arg of `OS.get_cmdline_args()` wins, engine flags included (`:13-17`) |
| Documented invocation | PARTIAL | `--path .` is wrong from the repo root (`:4`); `project.godot` is at `apps/game/client` |
| Range scan despite the name "find seed" | ABSENT | one seed per process, no loop (`:12-22`) |
| Retry-aware verdict / `used_fallback` reporting | ABSENT | calls `_try_generate_once`, not `generate()` (`:22` vs `room_graph_generator.gd:34-49`) |
| Biome selection | ABSENT | `"forgotten_castle"` hardcoded (`:18`) |
| Tier / floor / player-level inputs | ABSENT | graph config only; no `DungeonProcgen` call |
| ASCII map output | ABSENT | `RoomGraphDebug.print_graph` exists but is not called; `config.debug_ascii` is never set |
| Machine-readable output | ABSENT | `print()` only, no JSON, no file write |
| Non-zero exit on failure | ABSENT | plain `quit()` (`:29`) |
| CI usage | ABSENT | no reference in `.github/workflows/` |
| Statistics across seeds (fallback rate, room-count distribution) | ABSENT | no aggregation anywhere in the repo |
| Uses private API of the generator | PARTIAL | `_try_generate_once`, `_last_validate_reason`, `_count_main_slots` (`:22,24,27`) |
| `var seed` shadows the global `seed()` function | PARTIAL | `:12` |
| `seed1.json` / `seed99999.json` provenance | ABSENT from this tool | C# CLI dumps; see the table above |

## Related

- Improvement plan: [`../actual_improvements/find-graph-seed.md`](../actual_improvements/find-graph-seed.md)
- [`room-graph-procgen.md`](room-graph-procgen.md) — the generator, its validation rules, retry and fallback
- [`local-procgen.md`](local-procgen.md) — the seed derivation the tool bypasses
- [`biome-registry.md`](biome-registry.md) — the biome JSON the tool loads
- [`tools-scripts.md`](tools-scripts.md) — the wider tool inventory
- [`export-tools.md`](export-tools.md) — the sibling tool script that does run in CI
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md) — where seed coverage belongs long term
- [`repository-root.md`](repository-root.md) — the stray root artifacts
