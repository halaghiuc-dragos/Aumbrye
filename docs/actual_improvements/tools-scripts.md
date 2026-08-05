# Tools and scripts — improvement plan

## Current state

The tooling covers real ground: `procgen-cli` is a working CLI over `packages/procedural`, `validate.mjs` runs 24 schema mappings plus catalog-consistency and stat-key rules, and three PowerShell runners stitch the layers together (see [`../existing_codebase/tools-scripts.md`](../existing_codebase/tools-scripts.md)). Two problems undermine it. First, `scripts/balance/generate-m6-items.ps1` writes the exact placeholder description that `validate.mjs` was written to reject, and the CI step that would catch it is `continue-on-error: true`, so generated filler content ships silently. Second, the runners are Windows-only PowerShell, so no contributor on Linux or macOS can run the full validation locally.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| TLS-01 | P0 | `generate-m6-items.ps1` writes `description = "M6 content item."` and `value = 20` for every item it generates — the literal string `validate.mjs` treats as a placeholder. The generator and the validator directly contradict each other. | `scripts/balance/generate-m6-items.ps1:21-22` vs `scripts/validate-content/validate.mjs:12,295` |
| TLS-02 | P0 | The strict placeholder rule can never fail a build. | `.github/workflows/ci.yml:78-80` sets `continue-on-error: true` on `npm run validate:strict` |
| TLS-03 | P1 | Content files with no `resolveSchemaForFile` mapping print `SKIP (no schema)` and pass. Adding a new content domain gets zero validation with no signal. | `scripts/validate-content/validate.mjs:171-174` |
| TLS-04 | P1 | All three validation runners are `.ps1`. A Linux or macOS contributor cannot run `run-all-validation.ps1` without PowerShell Core, and even then the Godot discovery globs are Windows-only paths. | `scripts/run-mcp-validation.ps1:46-51` |
| TLS-05 | P1 | `balance-cli.ps1` counts JSON files. It reports no damage curve, no XP-per-hour, no item-power distribution, nothing a designer could balance against, but it is named and validated as if it were a balance tool. | `scripts/balance/balance-cli.ps1:20-26`; asserted alive by `apps/game/client/scripts/validation/suites/m6_suite.gd:517-527` on file existence only |
| TLS-06 | P1 | `run-mcp-validation.ps1` runs the scene `res://scenes/debug/mcp_validation.tscn` while CI runs the script `res://scripts/validation/validation_main.gd`. Two entry paths that can diverge without notice. | `scripts/run-mcp-validation.ps1:77` vs `.github/workflows/ci.yml:120` |
| TLS-07 | P2 | `itemType`-versus-folder mismatches are `WARN` only, so an armor item can sit in `content/items/consumables/` forever. | `scripts/validate-content/validate.mjs:265-269` |
| TLS-08 | P2 | Neither PowerShell runner invokes `ruff`. Python lint exists only in CI, so a contributor who runs the full local suite still gets a CI failure. | `scripts/run-automated-tests.ps1:8-21`, `scripts/run-all-validation.ps1:41-66` |
| TLS-09 | P2 | `.pre-commit-config.yaml` has one hook, uses `always_run: true` and `pass_filenames: false`, and runs `npm ci` on every commit. It is both incomplete and slow. | `.pre-commit-config.yaml:1-9` |
| TLS-10 | P2 | The Python generators are one-shot scripts with no `--dry-run`, no `--biome` filter, and no idempotency check, and `generate_expansion_biomes.py` shells into the materials script unconditionally. Rerunning overwrites hand-edits to generated rooms with no warning. | `tools/generate_expansion_biomes.py` `main()` tail; `subprocess.run([...], check=True)` |
| TLS-11 | P2 | `.gdlintrc` disables `max-line-length` while `gdformat.line_length` is 120, so line length is enforced by the formatter and unenforced by the linter — the two disagree about whether it is a rule. | `.gdlintrc:5,8` |

## Target design

**Generated content is never authored content.** `generate-m6-items.ps1` is a scaffolding tool, and scaffolding must be visibly unfinished until a designer finishes it. Two changes make that true:

1. The generator writes `"description": ""` and `"value": null` and adds `"authored": false` to every file it emits.
2. `validate.mjs` fails — always, not just under `--strict-content` — on any item with `authored: false`, an empty description, or a null value, and the CI strict step drops `continue-on-error`.

Rejected alternative: making the generator write plausible-sounding descriptions. That would hide the gap instead of surfacing it and is exactly the "hardcoded value that misleads" case `docs/DOC-CONVENTIONS.md` tags as `FAKE`.

**Unmapped content is a failure, not a skip.** `resolveSchemaForFile` returning `null` becomes a hard error listing the file and the directory prefixes it tried, with a single opt-out list (`UNSCHEMA_ALLOWLIST`) that must be edited deliberately.

**One cross-platform runner.** Replace the three `.ps1` entry points with `scripts/validate.mjs`, a Node script that runs the same four layers and works anywhere Node 24 runs. Keep thin `.ps1` and `.sh` wrappers so muscle memory and CI both keep working. Node is chosen over Python because the repo already requires Node 24 for two CI jobs and ships a Node validator, whereas Python is needed only by two generators.

Target `scripts/validate.mjs` layers:

| Layer | Command | Failure mode |
|-------|---------|--------------|
| `dotnet` | `dotnet build tools/procgen-cli/ProcgenCli.csproj -c Debug` then `dotnet test services/backend/Aumbrye.sln` | non-zero exit |
| `content` | `node scripts/validate-content/validate.mjs --strict-content` | non-zero exit |
| `python` | `ruff check tools/` | non-zero exit |
| `godot` | `<godot> --path apps/game/client --headless --script res://scripts/validation/validation_main.gd` | non-zero exit or `failed > 0` in the report |

Godot binary resolution order: `--godot <path>` argument, `GODOT_BIN`, `godot` on `PATH`, then platform-appropriate defaults (`%LOCALAPPDATA%\Programs\Godot\*` on Windows, `/usr/local/bin/godot` and `~/.local/bin/godot` on Linux, `/Applications/Godot.app/Contents/MacOS/Godot` on macOS). The report path is resolved per platform: `%APPDATA%/Godot/app_userdata/Aumbrye/` on Windows, `~/.local/share/godot/app_userdata/Aumbrye/` on Linux, `~/Library/Application Support/Godot/app_userdata/Aumbrye/` on macOS.

`scripts/validate.mjs` accepts `--layer <name>` (repeatable) so a contributor can run one layer, and writes the same `reports/validation-summary.json` `schemaVersion: 1` shape the current runner produces so nothing downstream breaks.

**One Godot validation entry point.** `validation_main.gd` becomes the single entry; `res://scenes/debug/mcp_validation.tscn` keeps its runner node so the editor Play button still works, but every script and CI step invokes `validation_main.gd`.

**A balance CLI that reports balance.** `scripts/balance/balance-cli.mjs` replaces the PowerShell version and emits `reports/balance_export.json`:

```json
{
  "schemaVersion": 1,
  "generatedAt": "...",
  "enemies": { "count": 0, "byBiome": {}, "threatCostHistogram": {}, "hpPerLevelSlope": 0.0 },
  "items": { "count": 0, "byRarity": {}, "byEquipmentSlot": {}, "statTotalsByRarity": {}, "unauthoredCount": 0 },
  "weapons": { "count": 0, "dpsByWeaponId": {}, "staminaPerDamage": {} },
  "progression": { "levelCap": 0, "xpToLevel": [], "runsToLevelCap": 0.0 },
  "outliers": [ { "kind": "item_stat_total", "id": "...", "value": 0.0, "medianForRarity": 0.0, "ratio": 0.0 } ]
}
```

`--summary` prints the outlier table; `--fail-on-outliers <ratio>` exits non-zero when any item's stat total exceeds `ratio` times the median for its rarity, so balance regressions can gate CI.

**Idempotent generators.** Both Python tools gain `--dry-run`, `--only <biomeId>` (repeatable), and a refusal to overwrite any file whose content differs from what the generator last produced unless `--force` is passed. Track this with a sidecar `tools/.generated-manifest.json` mapping generated path to SHA-256 at generation time.

## Work plan

1. **Stop generating placeholder descriptions** — edit `scripts/balance/generate-m6-items.ps1:21-22` to write `description = ""`, `value = $null`, and `authored = $false`. (TLS-01)
2. **Make unauthored content a hard failure** — in `scripts/validate-content/validate.mjs`, move the placeholder check out of the `strictContent` branch (`validate.mjs:295`) and extend it to reject `authored: false`, empty `description`, or null `value` on any file under `content/items/` and `content/relics/`. Add `authored` to `content/schemas/item-instance.v1.json` and `relic-definition.v1.json`. (TLS-01)
3. **Remove `continue-on-error`** — delete `.github/workflows/ci.yml:80`, and merge the two content steps into one `npm run validate:strict`. Land after step 2 so CI is green when it flips. (TLS-02)
4. **Fail on unmapped content** — change `validate.mjs:171-174` to count a failure and print the attempted prefixes; add an explicit `UNSCHEMA_ALLOWLIST` set for any file legitimately outside the schema system. (TLS-03)
5. **Promote `itemType` mismatch to a failure** — change `validate.mjs:266` from `console.warn` to `console.error` and increment `errors`. (TLS-07)
6. **Write `scripts/validate.mjs`** — the four-layer cross-platform runner described above, with per-platform Godot and report resolution. Add `scripts/validate.ps1` and `scripts/validate.sh` one-line wrappers. Keep the three existing `.ps1` files until step 8. (TLS-04, TLS-08)
7. **Unify the Godot entry point** — change `scripts/run-mcp-validation.ps1:77` and the new runner to invoke `--script res://scripts/validation/validation_main.gd`, matching `.github/workflows/ci.yml:120`. (TLS-06)
8. **Retire the PowerShell runners** — delete `run-all-validation.ps1`, `run-automated-tests.ps1`, `run-mcp-validation.ps1`; update `README.md` and any doc that references them. (TLS-04)
9. **Rewrite the balance CLI** — new `scripts/balance/balance-cli.mjs` emitting the schema above with `--summary` and `--fail-on-outliers`. Delete `scripts/balance/balance-cli.ps1` and update `m6_suite.gd:517-527` to assert the new path and, more usefully, that `reports/balance_export.json` conforms to `content/schemas/balance-export.v1.json`. (TLS-05)
10. **Make the Python generators idempotent** — add `--dry-run`, `--only`, `--force`, and `tools/.generated-manifest.json` to both scripts; make `generate_expansion_biomes.py` pass its own flags through to the materials subprocess. (TLS-10)
11. **Expand pre-commit** — replace the single hook with four: `ruff check` (`files: ^tools/.*\.py$`), `gdformat --check` over the CI allowlist (see [`ci-cd.md`](ci-cd.md) gap CID-04), `eslint` in `apps/web` (`files: ^apps/web/src/`), and content validation (`files: ^content/`). Drop `always_run: true` and `npm ci` in favor of `pass_filenames: true` and a cached install. (TLS-09)
12. **Reconcile the line-length rules** — remove `max-line-length` from the `.gdlintrc` `disabled` list and set the gdlint max to 120 so linter and formatter agree. Fix or reflow any file that then fails. (TLS-11)

## Data and schema changes

- `content/schemas/item-instance.v1.json` and `content/schemas/relic-definition.v1.json` gain an optional boolean `authored`. `validate.mjs` treats a missing `authored` as `true` so existing hand-authored files need no edit.
- New `content/schemas/balance-export.v1.json` describing the `reports/balance_export.json` shape.
- New sidecar `tools/.generated-manifest.json` (not under `content/`, so no schema needed) mapping generated path to SHA-256.
- No `user://` save-format change, so **no `save_migrator.gd` version bump**.

## Acceptance criteria

- [ ] `grep -r "M6 content item" content/` returns no matches.
- [ ] `npm run validate` (non-strict) fails when any file under `content/items/` has `authored: false` or an empty `description`.
- [ ] `.github/workflows/ci.yml` contains no `continue-on-error` on any content-validation step.
- [ ] Adding a file at `content/newdomain/thing.json` with no schema mapping fails `npm run validate` with a message naming the tried prefixes.
- [ ] `node scripts/validate.mjs` runs all four layers to completion on Windows, Linux, and macOS and writes `reports/validation-summary.json`.
- [ ] `node scripts/validate.mjs --layer content --layer python` runs exactly those two layers.
- [ ] `scripts/run-all-validation.ps1`, `run-automated-tests.ps1`, and `run-mcp-validation.ps1` no longer exist and no doc references them.
- [ ] `node scripts/balance/balance-cli.mjs --summary` prints per-rarity stat-total medians and lists outliers above the threshold.
- [ ] `python tools/generate_expansion_biomes.py --dry-run` prints the file list and writes nothing.
- [ ] Rerunning `python tools/generate_pixel_diorama_materials.py` without `--force` after a manual edit refuses and names the modified file.
- [ ] `pre-commit run --all-files` runs ruff, gdformat, eslint, and content validation.
- [ ] `gdlint` and `gdformat` agree on a 120-column limit.

## Validation

- Extend `apps/game/client/scripts/validation/suites/content_suite.gd` with `content.no_unauthored_items`: load `content/items/catalog.json`, load each referenced item file through `ContentLoader`, and assert none has `authored == false` or `description == ""`. This makes TLS-01 fail in-engine as well as in the Node validator.
- Extend `apps/game/client/scripts/validation/suites/m6_suite.gd` — replace the `m6.balance.cli` file-existence check (`m6_suite.gd:517-527`) with `m6.balance.export_schema`, asserting `reports/balance_export.json` exists and validates against `content/schemas/balance-export.v1.json`.
- Add `services/backend/tests/Aumbrye.UnitTests/ProcgenCliTests.cs` cases for `--floor`, `--final-floor`, unknown-argument rejection, and non-integer seed rejection, once the parser is extracted from the top-level statements into a testable `static class ProcgenCliArgs`.
- Manual only: confirming the synthesized biome audio from `generate-biome-audio.mjs` is distinguishable per biome. Everything else above is automatable.

## Related

- Existing behavior: [`../existing_codebase/tools-scripts.md`](../existing_codebase/tools-scripts.md)
- [`ci-cd.md`](ci-cd.md) — TLS-02 and the gdlint allowlist
- [`content-catalog.md`](content-catalog.md) — the authored-content bar TLS-01 violates
- [`validation-harness.md`](validation-harness.md) — TLS-06 entry-point unification
- [`packages.md`](packages.md) — the library behind `procgen-cli`
- [`00-QUALITY-BAR.md`](00-QUALITY-BAR.md)
