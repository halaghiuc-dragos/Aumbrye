# CI/CD — improvement plan

## Status: FINISHED

## Current state

`ci.yml` runs nine parallel jobs covering backend build, format, test with coverage, API image build, web lint and build, Ruff on `tools/`, strict content validation, full-repo GDScript lint/format, headless Godot validation with report upload, OpenAPI route drift, and docs link checking. `release.yml` pushes the API image to `ghcr.io`, uploads web and Godot artifacts, and documents manual Steam upload. Godot version is pinned from `apps/game/client/.godot-version` (`4.7.0`). Dependabot and CodeQL are enabled.

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| CID-01 | P0 | Godot version skew between CI and project features | **FINISHED** — both workflows read `apps/game/client/.godot-version`; `setup.engine_version_pin` validates parity |
| CID-02 | P0 | `release.yml` `backend-image` referenced missing `Dockerfile` | **FINISHED** — `services/backend/Dockerfile` + `api-image` CI job |
| CID-03 | P0 | `godot-export` required gitignored `export_presets.cfg` | **FINISHED** — committed preset; `export_presets.local.cfg` gitignored |
| CID-04 | P1 | gdlint/gdformat on 3% of GDScript files | **FINISHED** — all files under `apps/game/client/scripts` |
| CID-05 | P1 | Strict content rule `continue-on-error: true` | **FINISHED** — hard `validate:strict` gate |
| CID-06 | P1 | Godot job never uploaded validation report | **FINISHED** — `godot-validation-report` artifact + job summary |
| CID-07 | P1 | Nothing deploys or publishes | **FINISHED** — GHCR push + artifact uploads; Steam manual |
| CID-08 | P1 | No `concurrency` group | **FINISHED** — both workflows |
| CID-09 | P2 | No `timeout-minutes` | **FINISHED** — every job |
| CID-10 | P2 | No C# formatting gate | **FINISHED** — `dotnet format --verify-no-changes` |
| CID-11 | P2 | No test coverage collection | **FINISHED** — Cobertura artifact upload |
| CID-12 | P2 | No `dependabot.yml` or security scanning | **FINISHED** — `dependabot.yml` + `codeql.yml` |
| CID-13 | P2 | No documentation link check | **FINISHED** — `docs-links` job |
| CID-14 | P2 | No OpenAPI drift check | **FINISHED** — `openapi-drift` job + `check-routes.mjs` |

## Target design

Implemented as specified in the original plan: single Godot version file, multi-stage Dockerfile with `AUMBRYE_CONTENT_ROOT`, committed export preset, full GDScript gates, diagnosable Godot failures, GHCR release publishing, concurrency/timeouts, format/coverage gates, dependabot/CodeQL, docs links, and OpenAPI route parity.

## Acceptance criteria

- [x] Neither workflow contains a hardcoded Godot version; both read `apps/game/client/.godot-version`.
- [x] `docker build -f services/backend/Dockerfile .` from the repo root produces an image that answers `GET /api/v1/health` with `{"status":"ok"}`.
- [x] The `api-image` CI job builds the image on every pull request.
- [x] `release.yml` on dispatch pushes `ghcr.io/<owner>/aumbrye-api:<tag>` and `:latest`.
- [x] `godot --headless --path apps/game/client --export-release "Windows Desktop" out.exe` succeeds on a clean checkout with no local file creation.
- [x] `gdlint` and `gdformat --check` run over every `.gd` file under `apps/game/client/scripts` and pass.
- [x] `.github/workflows/ci.yml` contains no `continue-on-error`.
- [x] A failing godot job uploads `godot-validation-report` and writes failing assertion ids/messages to the job summary.
- [x] Pushing a second commit to an open PR cancels the first run.
- [x] Every job declares `timeout-minutes`.
- [x] `dotnet format Aumbrye.sln --verify-no-changes` passes in CI.
- [x] `dotnet test` uploads a Cobertura coverage artifact.
- [x] `.github/dependabot.yml` covers github-actions, nuget, npm, and pip.
- [x] A PR that breaks a relative link in `docs/` fails the `docs-links` job.
- [x] A PR that adds an endpoint without updating the OpenAPI spec fails the `openapi-drift` job.

## Validation

- `m7.ci.release_workflow` asserts `ghcr.io`, no `4.4.0`, and Dockerfile existence.
- `setup.engine_version_pin` asserts `.godot-version` matches `config/features[0]`.
- `Health_RespondsUnderProductionEnvironment` integration test exercises Production + Jwt guard.

## Related

- Existing behavior: [`../existing_codebase/ci-cd.md`](../existing_codebase/ci-cd.md)
- [`project-config-autoloads.md`](project-config-autoloads.md)
- [`website-and-backend.md`](website-and-backend.md)
- [`tools-scripts.md`](tools-scripts.md)
- [`packages.md`](packages.md)
- [`export-tools.md`](export-tools.md)
- [`validation-suites.md`](validation-suites.md)
