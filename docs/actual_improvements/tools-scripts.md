# Tools and scripts — improvement plan

**Status: FINISHED** — TLS-01 through TLS-11 implemented.

## Current state

The tooling covers real ground: `procgen-cli` is a working CLI over `packages/procedural`, `validate.mjs` runs schema mappings plus catalog-consistency and stat-key rules, and `scripts/validate.mjs` is the cross-platform four-layer runner (see [`../existing_codebase/tools-scripts.md`](../existing_codebase/tools-scripts.md)). Generated scaffolding is visibly unfinished (`authored: false`, empty description, null value), unmapped content fails validation, and CI enforces strict content rules without `continue-on-error`.

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| TLS-01 | P0 | `generate-m6-items.ps1` wrote placeholder descriptions contradicting `validate.mjs` | **FINISHED** — generator emits `authored: false`, empty description, null value; validator always rejects |
| TLS-02 | P0 | Strict placeholder rule never failed CI (`continue-on-error: true`) | **FINISHED** — single `npm run validate:strict` step, no `continue-on-error` |
| TLS-03 | P1 | Unmapped content printed `SKIP (no schema)` and passed | **FINISHED** — hard failure with prefix list; `UNSCHEMA_ALLOWLIST` opt-out |
| TLS-04 | P1 | Validation runners were Windows-only PowerShell | **FINISHED** — `scripts/validate.mjs` + `.ps1`/`.sh` wrappers; old runners deleted |
| TLS-05 | P1 | `balance-cli.ps1` only counted JSON files | **FINISHED** — `scripts/balance/balance-cli.mjs` + `balance-export.v1.json` schema |
| TLS-06 | P1 | Two Godot validation entry points (scene vs script) | **FINISHED** — all runners invoke `validation_main.gd` |
| TLS-07 | P2 | `itemType`-versus-folder mismatches were `WARN` only | **FINISHED** — promoted to `FAIL` |
| TLS-08 | P2 | Local runners did not invoke `ruff` | **FINISHED** — `python` layer in `scripts/validate.mjs` |
| TLS-09 | P2 | Pre-commit had one slow hook | **FINISHED** — ruff, gdformat, eslint, content validation hooks |
| TLS-10 | P2 | Python generators overwrote hand-edits silently | **FINISHED** — `--dry-run`, `--only`, `--force`, `tools/.generated-manifest.json` |
| TLS-11 | P2 | `.gdlintrc` disabled `max-line-length` while gdformat used 120 | **FINISHED** — gdlint max 120 matches gdformat |

## Target design

Implemented as specified in the original plan: cross-platform `scripts/validate.mjs` (dotnet, content, python, godot layers), unified Godot entry via `validation_main.gd`, balance export CLI, idempotent generators, and aligned lint/format line length.

## Work plan

All twelve steps completed (TLS-01 through TLS-11).

## Data and schema changes

- `content/schemas/item-definition.v1.json` and `relic-definition.v1.json`: optional `authored` boolean; missing treated as `true`.
- `content/schemas/balance-export.v1.json`: describes `reports/balance_export.json`.
- `tools/.generated-manifest.json`: SHA-256 sidecar for generator idempotency.

## Acceptance criteria

- [x] `grep -r "M6 content item" content/` returns no matches.
- [x] `npm run validate` fails when any file under `content/items/` has `authored: false` or an empty `description`.
- [x] `.github/workflows/ci.yml` contains no `continue-on-error` on any content-validation step.
- [x] Adding a file at `content/newdomain/thing.json` with no schema mapping fails `npm run validate` with a message naming the tried prefixes.
- [x] `node scripts/validate.mjs` runs all four layers and writes `reports/validation-summary.json`.
- [x] `node scripts/validate.mjs --layer content --layer python` runs exactly those two layers.
- [x] `scripts/run-all-validation.ps1`, `run-automated-tests.ps1`, and `run-mcp-validation.ps1` no longer exist and no doc references them.
- [x] `node scripts/balance/balance-cli.mjs --summary` prints per-rarity stat-total medians and lists outliers above the threshold.
- [x] `python tools/generate_expansion_biomes.py --dry-run` prints the file list and writes nothing.
- [x] Rerunning `python tools/generate_pixel_diorama_materials.py` without `--force` after a manual edit refuses and names the modified file.
- [x] `pre-commit run --all-files` runs ruff, gdformat, eslint, and content validation.
- [x] `gdlint` and `gdformat` agree on a 120-column limit.

## Validation

- `content_suite.gd`: `content.no_unauthored_items` asserts catalog items are authored with non-empty descriptions.
- `m6_suite.gd`: `m6.balance.export_schema` asserts `reports/balance_export.json` matches `balance-export.v1.json` shape.
- `ProcgenCliTests.cs`: `--floor`, `--final-floor`, unknown-argument, and non-integer seed rejection via `ProcgenCliArgs`.

## Related

- Existing behavior: [`../existing_codebase/tools-scripts.md`](../existing_codebase/tools-scripts.md)
- [`ci-cd.md`](ci-cd.md)
- [`content-catalog.md`](content-catalog.md)
- [`validation-harness.md`](validation-harness.md)
- [`packages.md`](packages.md)
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
