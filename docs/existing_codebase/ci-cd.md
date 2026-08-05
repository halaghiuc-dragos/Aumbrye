# CI/CD

Two GitHub Actions workflows: `ci.yml` (six parallel jobs on push and pull request to `main`) and `release.yml` (three build jobs plus a summary, manual dispatch only). There is no deployment step and no Docker image build that can succeed.

## Files

| Path | Role |
|------|------|
| `.github/workflows/ci.yml` | 121 lines, 6 jobs, triggers `push` and `pull_request` on `main` |
| `.github/workflows/release.yml` | 66 lines, 4 jobs, trigger `workflow_dispatch` with a required `tag` string input |

`.github/` contains nothing else — no `CODEOWNERS`, no issue or PR templates, no `dependabot.yml`.

## How it works

### `ci.yml` jobs

All six jobs run in parallel with no `needs:` edges, all on `ubuntu-latest`.

| Job | `name` | Working directory | Steps |
|-----|--------|-------------------|-------|
| `backend` | Backend | `services/backend` | `setup-dotnet@v5` 8.0.x; `dotnet restore Aumbrye.sln`; `dotnet build Aumbrye.sln --no-restore -c Release`; `dotnet build ../../tools/procgen-cli/ProcgenCli.csproj -c Release`; `dotnet test Aumbrye.sln --no-build -c Release --verbosity normal` |
| `web` | Web | `apps/web` | `setup-node@v5` node 24, `cache: npm`, `cache-dependency-path: apps/web/package-lock.json`; `npm ci`; `npm run lint`; `npm run build` |
| `python-lint` | Python lint (tools) | repo root | `setup-python@v5` 3.12; `pip install ruff && ruff check tools/` |
| `content` | Content validation | `scripts/validate-content` | `setup-node@v5` node 24; `npm ci`; `npm run validate`; `npm run validate:strict` with `continue-on-error: true` |
| `gdscript-lint` | GDScript lint | repo root | `setup-python@v5` 3.12; `pip install gdtoolkit`; `gdlint $FILES`; `gdformat --check $FILES` over an 8-file allowlist |
| `godot` | Godot validation | `apps/game/client` | `chickensoft-games/setup-godot@v1` version `4.4.0`, `include-templates: false`; `godot --path . --headless --script res://scripts/tools/export_diorama_anim_libraries.gd`; `godot --path . --headless --script res://scripts/validation/validation_main.gd` |

All jobs use `actions/checkout@v5`.

### The gdlint allowlist

`.github/workflows/ci.yml:93-100` defines `$FILES` as exactly eight paths:

```
apps/game/client/scripts/app/game_facade.gd
apps/game/client/scripts/app/run_scene_router.gd
apps/game/client/scripts/app/content_loader.gd
apps/game/client/scripts/ui/inventory_ui_layout.gd
apps/game/client/scripts/validation/validation_runner.gd
apps/game/client/scripts/validation/suites/save_suite.gd
apps/game/client/scripts/validation/suites/cross_stack_parity_suite.gd
apps/game/client/scripts/validation/suites/perf_gate_suite.gd
```

The step is labelled "gdlint + gdformat check (§9 health scripts)". `apps/game/client` contains 271 `.gd` files outside `addons/` (305 including `addons/`), so the allowlist covers 8 of 271, or 3.0 percent.

### The godot job dependency chain

The export step runs before the validation step, and it must: `diorama_anim_suite.gd:16-30` asserts every path in `AnimLibrary.AUTHORED_LIBRARY_PATHS` resolves, and those six `.res` files under `res://assets/animations/diorama/` are produced by the export step. They are not committed — `git ls-files assets/animations/diorama` returns nothing and the directory does not exist on a clean checkout. See [`export-tools.md`](export-tools.md).

### `release.yml` jobs

| Job | `name` | What it does |
|-----|--------|--------------|
| `backend-image` | API Docker image | `docker build -t aumbrye-api:${{ inputs.tag }} -f services/backend/Dockerfile services/backend` |
| `web-build` | Web static build | node 24, `npm ci`, `npm run build`, `upload-artifact@v4` of `apps/web/dist` as `web-dist-<tag>` |
| `godot-export` | Godot Windows export | `setup-godot@v1` version `4.4.0` with `include-templates: true`; `godot --headless --path . --export-release "Windows Desktop" ../../../artifacts/godot/aumbrye.exe`; `upload-artifact@v4` as `godot-export-<tag>` |
| `release-summary` | Release summary | `needs: [backend-image, web-build, godot-export]`; echoes `"Release artifacts prepared for tag <tag>. Steam upload requires manual confirm (CI-7.1)."` |

`m7_suite.gd:502-508` asserts the release workflow file exists (`m7.ci.release_workflow`, checklist ref `CI-7.1`).

## Contracts

- **Working directories are pinned per job** (`ci.yml:15,35,66,109`). Moving `services/backend`, `apps/web`, `scripts/validate-content`, or `apps/game/client` breaks CI.
- **Lockfile paths are pinned for the npm cache** (`ci.yml:42,73`).
- **The godot job's step order is a hard dependency**: export before validate.
- **`release.yml` requires `apps/game/client/export_presets.cfg`** to contain a preset literally named `"Windows Desktop"`. That file is gitignored (`.gitignore:135`), so it does not exist in a fresh checkout.
- **Exit code contract**: `validation_runner.gd:48` computes `1 if _ctx.failed > 0 else 0` and calls `get_tree().quit(exit_code)`, which is what fails the godot job.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Six-job CI on push and PR | IMPLEMENTED | `.github/workflows/ci.yml:3-7,9` |
| Backend build + test in CI | IMPLEMENTED | `.github/workflows/ci.yml:21-28` |
| Web lint + build in CI | IMPLEMENTED | `.github/workflows/ci.yml:43-48` |
| Godot version pin | BROKEN | `.github/workflows/ci.yml:115` and `release.yml:48` pin `4.4.0`; `apps/game/client/project.godot:20` declares `config/features=PackedStringArray("4.7", "Forward Plus")` |
| `release.yml` `backend-image` job | BROKEN | `release.yml:18` builds `-f services/backend/Dockerfile`; a repo-wide `dir /b /s Dockerfile*` finds no `Dockerfile` anywhere |
| `release.yml` `godot-export` job | BROKEN | Requires `export_presets.cfg`, which `.gitignore:135` excludes from the repo |
| gdlint / gdformat coverage | PARTIAL | 8 of 271 non-addon `.gd` files (`ci.yml:93-100`) |
| Strict content rule | BROKEN | `ci.yml:78-80` marks `npm run validate:strict` `continue-on-error: true` |
| Deployment | ABSENT | Neither workflow pushes an image, publishes a package, deploys the API, or uploads the web build to a host. `release-summary` only echoes a string (`release.yml:65`) |
| Steam upload | ABSENT | `release.yml:65` states it "requires manual confirm"; there is no `steamcmd` step |
| Code coverage reporting | ABSENT | `dotnet test` at `ci.yml:28` has no `--collect` or coverage upload |
| Dependency scanning / `dependabot.yml` | ABSENT | `.github/` contains only `workflows/` |
| C# format enforcement | ABSENT | No `dotnet format --verify-no-changes` step |
| Concurrency cancellation | ABSENT | Neither workflow declares a `concurrency:` block, so superseded pushes keep running |
| Job timeouts | ABSENT | No `timeout-minutes` on any job |
| Artifact retention of the validation report | ABSENT | The godot job writes `user://mcp_validation.json` (`validation_runner.gd:11`) and never uploads it, so a CI failure shows only the summary line from `validation_runner.gd:115-124` |
| Godot export templates in CI | PARTIAL | `ci.yml:116` sets `include-templates: false` (correct for headless validation); `release.yml:49` sets `true` |

## Related

- Improvement plan: [`../actual_improvements/ci-cd.md`](../actual_improvements/ci-cd.md)
- [`export-tools.md`](export-tools.md) — the export step the godot job depends on
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md) — what the godot job runs
- [`tools-scripts.md`](tools-scripts.md) — the local equivalents
- [`project-config-autoloads.md`](project-config-autoloads.md) — the 4.7 feature tag
- [`website-and-backend.md`](website-and-backend.md) — the missing API container
