# CI/CD

Two GitHub Actions workflows: `ci.yml` (nine parallel jobs on push and pull request to `main`) and `release.yml` (three build jobs plus a summary, manual dispatch only). Release publishes the API image to GitHub Container Registry; web and Godot artifacts upload as workflow artifacts. Steam upload remains manual.

## Files

| Path | Role |
|------|------|
| `.github/workflows/ci.yml` | Nine parallel jobs with concurrency cancellation and per-job timeouts |
| `.github/workflows/release.yml` | Pushes `ghcr.io/<owner>/aumbrye-api:<tag>` and `:latest`; uploads web and Godot artifacts |
| `.github/workflows/codeql.yml` | Weekly CodeQL analysis for C# and JavaScript/TypeScript |
| `.github/dependabot.yml` | Weekly updates for github-actions, nuget, npm, and pip |
| `services/backend/Dockerfile` | Multi-stage API image (repo-root build context) |
| `services/backend/.dockerignore` | Excludes `bin/`, `obj/`, `tests/` from image context |
| `apps/game/client/.godot-version` | Single source of truth for CI and release Godot version (`4.7.0`) |
| `apps/game/client/export_presets.cfg` | Committed `"Windows Desktop"` preset (no credentials) |
| `scripts/openapi-drift/check-routes.mjs` | Route parity check between API source and OpenAPI spec |

## How it works

### `ci.yml` jobs

All jobs run in parallel with no `needs:` edges, all on `ubuntu-latest`. Top-level `concurrency` cancels superseded runs on the same ref.

| Job | `timeout-minutes` | Working directory | Steps |
|-----|-------------------|-------------------|-------|
| `backend` | 20 | `services/backend` | Restore; `dotnet format --verify-no-changes`; build; procgen-cli build; `dotnet test` with XPlat Code Coverage; upload Cobertura artifact |
| `api-image` | 20 | repo root | `docker build -f services/backend/Dockerfile -t aumbrye-api:ci .` (no push) |
| `web` | 20 | `apps/web` | `npm ci`; lint; build |
| `python-lint` | 20 | repo root | Ruff on `tools/` |
| `content` | 20 | `scripts/validate-content` | `npm run validate:strict`; audio stem check |
| `gdscript-lint` | 20 | repo root | `gdlint` + `gdformat --check` over every `.gd` under `apps/game/client/scripts` (excluding `addons/`) |
| `godot` | 30 | `apps/game/client` | Read `.godot-version`; setup Godot; export diorama anim libraries; headless validation; always upload `mcp_validation.json`; summarize failures to job summary on failure |
| `openapi-drift` | 20 | repo root | `node scripts/openapi-drift/check-routes.mjs` |
| `docs-links` | 20 | repo root | Lychee offline link check on `README.md` and `docs/**/*.md` |

### The godot job dependency chain

The export step runs before validation: `diorama_anim_suite.gd` asserts every path in `AnimLibrary.AUTHORED_LIBRARY_PATHS` resolves, and those `.res` files are produced by the export step (not committed).

### `release.yml` jobs

| Job | `timeout-minutes` | What it does |
|-----|-------------------|--------------|
| `backend-image` | 20 | `docker/login-action` to `ghcr.io`; `docker/build-push-action` with repo-root context, GHA layer cache, push to `ghcr.io/<owner>/aumbrye-api:<tag>` and `:latest` |
| `web-build` | 20 | `npm ci`; build; `upload-artifact` of `apps/web/dist`; optional deploy step when `vars.DEPLOY_WEB == 'true'` |
| `godot-export` | 30 | Godot from `.godot-version` with export templates; `--export-release "Windows Desktop"`; `upload-artifact` |
| `release-summary` | 5 | Echoes artifact locations; states Steam upload is manual |

`m7_suite.gd` `m7.ci.release_workflow` asserts `release.yml` contains `ghcr.io`, does not contain `4.4.0`, and `services/backend/Dockerfile` exists.

## Contracts

- **Godot version** is read from `apps/game/client/.godot-version` in both workflows; `setup_suite.gd` `setup.engine_version_pin` asserts it matches `config/features`.
- **Docker build context** is the repo root (copies `packages/` and `content/`).
- **Export preset** `apps/game/client/export_presets.cfg` is committed; signing credentials go in gitignored `export_presets.local.cfg`.
- **Strict content validation** is a hard gate (`npm run validate:strict`); no `continue-on-error`.
- **OpenAPI drift** fails when API route paths diverge from `packages/shared/openapi/aumbrye-api.v1.yaml`.

## Current state

| Surface | Status |
|---------|--------|
| Nine-job CI on push and PR | IMPLEMENTED |
| Godot version pin from `.godot-version` | IMPLEMENTED |
| API Docker image build in CI (`api-image`) | IMPLEMENTED |
| API image push to GHCR on release | IMPLEMENTED |
| Godot Windows export on clean checkout | IMPLEMENTED |
| Full GDScript lint/format coverage | IMPLEMENTED |
| Strict content rule (hard failure) | IMPLEMENTED |
| Godot validation report artifact + summary | IMPLEMENTED |
| Concurrency cancellation | IMPLEMENTED |
| Job timeouts | IMPLEMENTED |
| `dotnet format --verify-no-changes` | IMPLEMENTED |
| Test coverage artifact (Cobertura) | IMPLEMENTED |
| `dependabot.yml` + CodeQL | IMPLEMENTED |
| Docs link check | IMPLEMENTED |
| OpenAPI route drift check | IMPLEMENTED |
| Steam upload | MANUAL (documented in release summary) |

## Related

- Improvement plan (all gaps finished): [`../actual_improvements/ci-cd.md`](../actual_improvements/ci-cd.md)
- [`export-tools.md`](export-tools.md)
- [`validation-harness.md`](validation-harness.md), [`validation-suites.md`](validation-suites.md)
- [`website-and-backend.md`](website-and-backend.md)
