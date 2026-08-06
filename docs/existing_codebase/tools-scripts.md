# Tools and scripts

Everything under `tools/` and `scripts/`, plus the three root-level tool configs (`pyproject.toml`, `.gdlintrc`, `.pre-commit-config.yaml`). These are development-time generators, validators, and runners. None ship with the game; one of them, `procgen-cli`, is a runtime fallback the client shells out to.

## Files

### `tools/`

| Path | Lines | Role |
|------|-------|------|
| `tools/procgen-cli/Program.cs` | 40 | Top-level-statement CLI entry; delegates to `ProcgenCliArgs.ParseGenerateArgs` |
| `tools/procgen-cli/ProcgenCliArgs.cs` | 65 | Testable argument parser for `generate` subcommand |
| `tools/procgen-cli/ProcgenCli.csproj` | 16 | `net8.0`, `OutputType Exe`, `AssemblyName procgen-cli` |
| `tools/procgen-cli/README.md` | 19 | Usage and publish instructions |
| `tools/generate_expansion_biomes.py` | 350+ | Generates 5 expansion biomes; supports `--dry-run`, `--only`, `--force` |
| `tools/generate_pixel_diorama_materials.py` | 200+ | Regenerates biome `ShaderMaterial` resources; idempotent via manifest |
| `tools/generated_manifest.py` | 45 | SHA-256 sidecar helpers for generator idempotency |
| `tools/.generated-manifest.json` | 1 | Maps generated path → SHA-256 at generation time |

### `scripts/`

| Path | Lines | Role |
|------|-------|------|
| `scripts/validate.mjs` | 250+ | Cross-platform four-layer runner (dotnet, content, python, godot) |
| `scripts/validate.ps1` | 4 | Thin PowerShell wrapper around `validate.mjs` |
| `scripts/validate.sh` | 4 | Thin bash wrapper around `validate.mjs` |
| `scripts/validate-content/validate.mjs` | 490+ | Ajv-based JSON Schema validation plus catalog and authorship rules |
| `scripts/validate-content/package.json` | 17 | `validate`, `validate:strict`, `test` scripts |
| `scripts/balance/balance-cli.mjs` | 280+ | Balance export CLI; writes `reports/balance_export.json` |
| `scripts/balance/generate-m6-items.ps1` | 115 | Scaffolding generator; emits `authored: false`, empty description, null value |
| `scripts/tools/generate-biome-audio.mjs` | 119 | Synthesizes per-biome placeholder ambience and boss loops |

### Root tool configs

| Path | Role |
|------|------|
| `package.json` | Root `npm run validate` / `validate:strict` delegating to `validate.mjs` |
| `pyproject.toml` | Ruff: `target-version = py311`, `line-length = 120`, `src = ["tools"]` |
| `.gdlintrc` | `max-line-length: 120`; `gdformat.line_length: 120` |
| `.pre-commit-config.yaml` | Four hooks: content validation, ruff, gdformat, eslint |

## How it works

### `procgen-cli`

`Program.cs` gates on `args[0]` being `generate`, `-h`, or `--help`. `ProcgenCliArgs.ParseGenerateArgs` requires biome id, positive integer seed, optional run GUID, and flags `--floor`, `--final-floor`, `--tier`, `--player-level`. Unknown flags throw `"Unknown argument: <arg>"`. Canonical JSON goes to stdout on success.

### `scripts/validate-content/validate.mjs`

1. `collectJsonFiles(content/)` walks recursively, skipping `schemas/`.
2. `resolveSchemaForFile` maps each file to a schema by path prefix. Unmapped files **fail** with attempted prefix list unless listed in `UNSCHEMA_ALLOWLIST`.
3. Ajv validates each mapped file.
4. `validateItemCatalogConsistency` cross-checks `catalog.json` against equipment/consumables/materials; `itemType` folder mismatches are **failures**.
5. `validateContentRules` enforces stat-key allowlist, weaponId rules, and **always** rejects `authored: false`, empty `description`, null `value`, and placeholder descriptions under `content/items/` and `content/relics/`.

### `scripts/validate.mjs`

Four layers with `--layer <name>` (repeatable):

| Layer | Command | Failure mode |
|-------|---------|--------------|
| `dotnet` | `dotnet build tools/procgen-cli/ProcgenCli.csproj` then `dotnet test services/backend/Aumbrye.sln` | non-zero exit |
| `content` | `node scripts/validate-content/validate.mjs --strict-content` | non-zero exit |
| `python` | `ruff check tools/` | non-zero exit |
| `godot` | `<godot> --path apps/game/client --headless --script res://scripts/validation/validation_main.gd` | non-zero exit or `failed > 0` |

Godot binary resolution: `--godot`, `GODOT_BIN`, `godot` on PATH, then platform defaults. Report path: `%APPDATA%/Godot/app_userdata/Aumbrye/mcp_validation.json` (Windows), `~/.local/share/godot/app_userdata/Aumbrye/` (Linux), `~/Library/Application Support/Godot/app_userdata/Aumbrye/` (macOS).

Writes `reports/validation-summary.json` with `schemaVersion: 1`.

### `scripts/balance/balance-cli.mjs`

Reads `content/` enemies, biomes, items, weapons, and `progression/xp_curve.json`. Emits `reports/balance_export.json` conforming to `content/schemas/balance-export.v1.json`. `--summary` prints per-rarity stat-total medians and outliers; `--fail-on-outliers <ratio>` exits non-zero when any item exceeds the threshold.

### Python generators

Both `generate_expansion_biomes.py` and `generate_pixel_diorama_materials.py` accept `--dry-run`, `--only` (repeatable), and `--force`. Writes consult `tools/.generated-manifest.json`; manual edits without `--force` are refused.

### Content generators in `scripts/`

`generate-m6-items.ps1` writes scaffolding with `description = ""`, `value = null`, `authored = false`.

## Contracts

- **`procgen-cli` stdout is a machine contract** — only canonical dungeon JSON.
- **`reports/`** is the shared output directory for `validate.mjs` and `balance-cli.mjs` (gitignored).
- **`ALLOWED_ITEM_STAT_KEYS`** in `validate.mjs` is the authoritative stat-key list.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| `procgen-cli generate` | IMPLEMENTED | `tools/procgen-cli/Program.cs`, `ProcgenCliArgs.cs` |
| Content schema validation | IMPLEMENTED | `scripts/validate-content/validate.mjs` |
| Cross-platform validation runner | IMPLEMENTED | `scripts/validate.mjs` |
| Godot binary resolver | IMPLEMENTED | `scripts/godot-bin.ps1`; documented in `docs/MCP_AGENT_GUIDE.md` |
| `generate-m6-items.ps1` output | PLACEHOLDER (intentional scaffolding) | `authored: false`, empty description — fails validation until authored |
| Strict content in CI | IMPLEMENTED | `.github/workflows/ci.yml` `npm run validate:strict` |
| `balance-cli.mjs` | IMPLEMENTED | Stat totals, DPS, progression, outliers |
| Unmapped content | IMPLEMENTED | Hard failure with prefix list |
| `itemType` folder mismatch | IMPLEMENTED | Failure, not warning |
| Pre-commit (ruff/gdformat/eslint/content) | IMPLEMENTED | `.pre-commit-config.yaml` |
| Python generator idempotency | IMPLEMENTED | `tools/generated_manifest.py`, `--force` |
| gdlint/gdformat line length | IMPLEMENTED | Both 120 columns |

## Related

- Improvement plan: [`../actual_improvements/tools-scripts.md`](../actual_improvements/tools-scripts.md)
- [`ci-cd.md`](ci-cd.md)
- [`packages.md`](packages.md)
- [`validation-harness.md`](validation-harness.md)
- [`content-catalog.md`](content-catalog.md)
- [`local-procgen.md`](local-procgen.md)
