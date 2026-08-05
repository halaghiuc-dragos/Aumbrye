# Tools and scripts

Everything under `tools/` and `scripts/`, plus the three root-level tool configs (`pyproject.toml`, `.gdlintrc`, `.pre-commit-config.yaml`). These are development-time generators, validators, and runners. None ship with the game; one of them, `procgen-cli`, is a runtime fallback the client shells out to.

## Files

### `tools/`

| Path | Lines | Role |
|------|-------|------|
| `tools/procgen-cli/Program.cs` | 93 | Top-level-statement CLI over `packages/procedural`, writes canonical dungeon JSON to stdout |
| `tools/procgen-cli/ProcgenCli.csproj` | 16 | `net8.0`, `OutputType Exe`, `AssemblyName procgen-cli` |
| `tools/procgen-cli/README.md` | 19 | Usage and publish instructions |
| `tools/generate_expansion_biomes.py` | 305 | Generates 5 expansion biomes: room `.tscn` files, `content/biomes/*.json`, audio profiles; then shells into the materials script |
| `tools/generate_pixel_diorama_materials.py` | 179 | Regenerates `mat_floor` / `mat_wall` / `mat_accent` `ShaderMaterial` resources for 10 biome folders |

### `scripts/`

| Path | Lines | Role |
|------|-------|------|
| `scripts/run-all-validation.ps1` | 95 | Two-layer runner; merges results into `reports/validation-summary.json` |
| `scripts/run-automated-tests.ps1` | 24 | Builds `procgen-cli`, runs both dotnet test projects, runs content validation |
| `scripts/run-mcp-validation.ps1` | 107 | Locates a Godot binary and runs the headless validation scene |
| `scripts/validate-content/validate.mjs` | 326 | Ajv-based JSON Schema validation plus catalog consistency and stat-key rules |
| `scripts/validate-content/package.json` | 17 | `validate`, `validate:strict`, `test` scripts; `ajv`, `ajv-formats`, `glob` |
| `scripts/balance/balance-cli.ps1` | 37 | Counts content JSON files; `-Export` writes `reports/balance_export.json`, `-Summary` prints |
| `scripts/balance/generate-m6-items.ps1` | 112 | Writes item JSON into `content/items/**` and `content/relics/` |
| `scripts/tools/generate-biome-audio.mjs` | 119 | Synthesizes per-biome placeholder ambience and boss WAV/OGG loops from `content/audio_profiles/` |

### Root tool configs

| Path | Role |
|------|------|
| `pyproject.toml` | Ruff: `target-version = "py311"`, `line-length = 120`, `src = ["tools"]`, `lint.select = ["E", "F", "I", "W"]` |
| `.gdlintrc` | Disables `class-definitions-order`, `max-public-methods`, `constant-name`, `max-line-length`; `gdformat.line_length: 120` |
| `.pre-commit-config.yaml` | One local hook, `validate-content`, `always_run: true`, `pass_filenames: false` |

## How it works

### `procgen-cli`

`tools/procgen-cli/Program.cs:3` gates on `args[0]` being `generate`, `-h`, or `--help`; anything else prints usage and returns `1` when `args` is empty, `0` otherwise.

`ParseGenerateArgs` (`Program.cs:36`) requires at least three arguments. `args[1]` is the biome id, `args[2]` must parse as an integer `>= 1` or it throws `"Seed must be a positive integer."`. An optional GUID at `args[3]` becomes the run id; otherwise `Guid.NewGuid()`. Remaining flags:

| Flag | Effect | Default |
|------|--------|---------|
| `--floor N` | `floorIndex = max(1, N)` | `1` |
| `--final-floor` | `isFinalFloor = true` | `false` |
| `--tier N` | `tier = max(1, N)` | `1` |
| `--player-level N` | `playerLevel = max(1, N)` | `1` |

Unknown flags throw `"Unknown argument: <arg>"`. On success the canonical JSON goes to stdout and the process returns `0`; on any exception the message goes to stderr and it returns `1` (`Program.cs:27-34`).

The Godot client resolves the executable in three steps (`apps/game/client/scripts/dungeon/local_procgen.gd:7-9`): `tools/procgen-cli/publish/procgen-cli.exe`, then `tools/procgen-cli/bin/Debug/net8.0/procgen-cli.exe`, then `dotnet` on `PATH` (`local_procgen.gd:164`). When none resolve it surfaces the hint `"dotnet build tools/procgen-cli/ProcgenCli.csproj"` (`local_procgen.gd:82`).

### `scripts/validate-content/validate.mjs`

1. `collectJsonFiles(content/)` walks recursively, skipping the `schemas` directory (`validate.mjs:59`).
2. `resolveSchemaForFile` maps each file to a schema by path prefix — 24 rules covering `fixtures/`, `enemies/`, `weapons/`, `items/`, `bosses/`, `biomes/`, `affixes/`, `progression/`, `talents/`, `npcs/`, `quests/`, `dialogue/`, `relics/`, `recipes/`, `merchant/`, `classes/`, `audio_profiles/`, `achievements/`, `statuses/`, `loot/` (`validate.mjs:68-143`). Unmatched files print `SKIP (no schema)` and do **not** fail.
3. Ajv is constructed with `{ allErrors: true, strict: false }` plus `ajv-formats` (`validate.mjs:145-146`).
4. `validateItemCatalogConsistency` (`validate.mjs:209`) cross-checks `content/items/catalog.json` against the files in `equipment/`, `consumables/`, `materials/` in both directions and flags duplicate ids. `itemType` mismatches are a `WARN`, not a failure (`validate.mjs:265-269`).
5. `validateContentRules` (`validate.mjs:286`) enforces a 28-entry `ALLOWED_ITEM_STAT_KEYS` allowlist (`validate.mjs:14-42`), that a `weapon`-type item in the `weapon` slot has a `weaponId`, and that every `weaponId` has a matching `content/weapons/<id>.json`. Only under `--strict-content` does it also reject descriptions matching `/^M6 content item\.?$/i` (`validate.mjs:12,295`).
6. Exit code 1 if any failure counted.

### PowerShell runners

`scripts/run-all-validation.ps1` runs two layers. Layer 1 invokes `run-automated-tests.ps1`; layer 2 invokes `run-mcp-validation.ps1` and then reads `%APPDATA%/Godot/app_userdata/Aumbrye/mcp_validation.json` (`run-all-validation.ps1:54`). Both are wrapped in `try`/`catch` so a thrown layer records `ok = false` rather than aborting. The merged summary is written to `reports/validation-summary.json` with `schemaVersion = 1` and the script exits `1` if any layer failed (`run-all-validation.ps1:68-94`).

`scripts/run-mcp-validation.ps1` resolves Godot in order: `$env:GODOT_BIN` (accepting a directory and preferring `*_console.exe`), `godot` on `PATH`, then four glob candidates under `%LOCALAPPDATA%\Programs\Godot`, `%ProgramFiles%\Godot`, and `%USERPROFILE%\Downloads` (`run-mcp-validation.ps1:33-62`). It runs the **scene** (`res://scenes/debug/mcp_validation.tscn`), not the script entry CI uses, then prints per-suite and per-test lines and exits `1` when `report.failed > 0`.

### Python generators

`tools/generate_expansion_biomes.py` declares 5 biomes as dictionaries with `id`, `folder`, `prefix`, floor/wall/accent colors, a `lighting` block, an `enemy_pool` list of `(enemyId, threatCost)` pairs, `boss`, `miniboss`, `trap`, and four loot tuples. `main()` writes room scenes per `ROOM_SPECS`, the biome JSON, and an audio profile for each, then `subprocess.run([sys.executable, tools/generate_pixel_diorama_materials.py], check=True)`.

`tools/generate_pixel_diorama_materials.py` maps 10 biome folders to base and shadow colors and an `ACCENT_HIGHLIGHTS` emissive per biome, writing `ShaderMaterial` resources bound to `res://assets/shared/pixel_diorama_surface.gdshader` with `ACCENT_SURFACE_KIND = 3` kept in sync with `PixelDioramaStyle.SurfaceKind.ACCENT`.

Both resolve paths from `Path(__file__).resolve().parents[1]`, so they must live exactly one directory below the repo root.

### Content generators in `scripts/`

`scripts/balance/generate-m6-items.ps1` writes one JSON file per `Write-Item` call into `content/items/equipment`, `content/items/consumables`, or `content/relics`. Every generated item gets `description = "M6 content item."` and `value = 20` (`generate-m6-items.ps1:21-22`).

`scripts/tools/generate-biome-audio.mjs` reads `content/audio_profiles/`, synthesizes 8-second ambience and 6-second boss loops at 44100 Hz mono 16-bit (`generate-biome-audio.mjs:16-18`), writes RIFF WAV by hand, and shells out via `execFileSync` for encoding.

### Lint configs

`pyproject.toml` selects only `E` (pycodestyle errors), `F` (pyflakes), `I` (isort), `W` (pycodestyle warnings). CI runs `ruff check tools/` (`.github/workflows/ci.yml:59`) — `scripts/` contains no Python, so the scope matches.

`.gdlintrc` disables four checks. `max-line-length` is disabled entirely while `gdformat.line_length` is 120, so gdformat rewraps at 120 but gdlint never complains about length.

`.pre-commit-config.yaml` runs `bash -c "cd scripts/validate-content && npm ci && npm run validate"` on every commit regardless of which files changed.

## Contracts

- **`procgen-cli` stdout is a machine contract.** `local_procgen.gd:113-130` rejects non-zero exit, empty output, invalid JSON, an empty definition object, and a definition without `rooms`. Anything printed to stdout besides the JSON breaks the client fallback. `PrintUsage` correctly writes to stderr (`Program.cs:88-90`).
- **`AssemblyName procgen-cli`** (`ProcgenCli.csproj:9`) is what makes the two hardcoded `.exe` paths in `local_procgen.gd:8-9` resolve.
- **Repo-relative path assumptions**: the Python tools use `parents[1]`, `balance-cli.ps1:7` uses `Split-Path (Split-Path $PSScriptRoot)`, `generate-m6-items.ps1:3` does `Set-Location` to the repo root, and `validate.mjs:8` uses `resolve(__dirname, "../..")`.
- **`reports/` is the shared output directory** for `run-all-validation.ps1` and `balance-cli.ps1 -Export`. It is gitignored (`.gitignore:173`).
- **`ALLOWED_ITEM_STAT_KEYS`** (`validate.mjs:14-42`) is the authoritative list of legal item stat keys for all authored content.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `procgen-cli generate` | IMPLEMENTED | `tools/procgen-cli/Program.cs:15-34` |
| Content schema validation | IMPLEMENTED | `scripts/validate-content/validate.mjs:166-207` |
| Three PowerShell runners | IMPLEMENTED | `scripts/run-all-validation.ps1`, `run-automated-tests.ps1`, `run-mcp-validation.ps1` |
| `generate-m6-items.ps1` output | PLACEHOLDER | Every item is written with `description = "M6 content item."` and `value = 20` (`scripts/balance/generate-m6-items.ps1:21-22`), which is exactly the string `validate.mjs:12` `PLACEHOLDER_DESC` flags |
| Strict placeholder rule in CI | BROKEN | `.github/workflows/ci.yml:78-80` runs `npm run validate:strict` with `continue-on-error: true`, so the placeholder rule never fails a build |
| `scripts/tools/generate-biome-audio.mjs` output | PLACEHOLDER | Synthesized sine loops, described in its own header as "procedural placeholder OGG loops" (`generate-biome-audio.mjs:3`) |
| `balance-cli.ps1` | STUB | Reports only file counts per content directory; no stat, curve, or DPS analysis (`scripts/balance/balance-cli.ps1:20-26`) |
| Files with no schema mapping | PARTIAL | `validate.mjs:171-174` prints `SKIP (no schema)` and continues; an unmapped content domain is silently unvalidated |
| `itemType` folder mismatch | PARTIAL | Warning only, never a failure (`validate.mjs:265-269`) |
| Python tools in `run-all-validation.ps1` | ABSENT | Neither `run-all-validation.ps1` nor `run-automated-tests.ps1` invokes `ruff` or either Python generator; Ruff runs only in CI (`.github/workflows/ci.yml:59`) |
| Pre-commit coverage of ruff / gdformat / eslint | ABSENT | `.pre-commit-config.yaml:1-9` declares exactly one hook |
| Tests for `procgen-cli` argument parsing | PARTIAL | `services/backend/tests/Aumbrye.UnitTests/ProcgenCliTests.cs` exists; the CLI itself is a top-level-statement program with no exposed parser type |
| `run-mcp-validation.ps1` Godot discovery on Linux/macOS | ABSENT | All four fallback globs are Windows paths (`run-mcp-validation.ps1:46-51`); only `$env:GODOT_BIN` and `godot` on `PATH` work elsewhere |

## Related

- Improvement plan: [`../actual_improvements/tools-scripts.md`](../actual_improvements/tools-scripts.md)
- [`ci-cd.md`](ci-cd.md) — which of these run in CI
- [`packages.md`](packages.md) — the library `procgen-cli` wraps
- [`validation-harness.md`](validation-harness.md) — what `run-mcp-validation.ps1` drives
- [`content-catalog.md`](content-catalog.md) — the content the validator checks
- [`local-procgen.md`](local-procgen.md) — the client-side CLI fallback
