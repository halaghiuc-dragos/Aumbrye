# CI/CD — improvement plan

## Current state

`ci.yml` runs six parallel jobs covering backend build and test, web lint and build, Ruff on `tools/`, content schema validation, GDScript lint over an eight-file allowlist, and headless Godot validation (see [`../existing_codebase/ci-cd.md`](../existing_codebase/ci-cd.md)). Two of the three `release.yml` build jobs cannot succeed: `backend-image` builds a `Dockerfile` that does not exist anywhere in the repo, and `godot-export` needs a gitignored `export_presets.cfg`. CI installs Godot 4.4.0 while the project declares feature version 4.7, so every headless run parses the project with a mismatched engine. Nothing deploys.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CID-01 | P0 | Godot version skew. CI and release install `4.4.0`; the project declares `4.7`. Validation results and the shipped export come from an engine three minor versions behind the authoring engine. | `.github/workflows/ci.yml:115`, `.github/workflows/release.yml:48` vs `apps/game/client/project.godot:20` |
| CID-02 | P0 | `release.yml` `backend-image` references `services/backend/Dockerfile`, which does not exist. A repo-wide search for `Dockerfile*` returns nothing. The job fails on every dispatch. | `.github/workflows/release.yml:18`; no `Dockerfile` in the repo |
| CID-03 | P0 | `release.yml` `godot-export` requires an export preset named `"Windows Desktop"` from `export_presets.cfg`, which is gitignored. The job fails on a clean checkout. | `.github/workflows/release.yml:54`, `.gitignore:135` |
| CID-04 | P1 | gdlint and gdformat run on 8 of 271 non-addon `.gd` files — 3.0 percent. The other 263 files have no style or lint gate at all. | `.github/workflows/ci.yml:93-100`; 271 `.gd` files under `apps/game/client` excluding `addons/` |
| CID-05 | P1 | The strict content rule is `continue-on-error: true`, so placeholder item descriptions never fail a build. | `.github/workflows/ci.yml:78-80` |
| CID-06 | P1 | The godot job never uploads `mcp_validation.json`. When validation fails, the log shows only the counts printed at `validation_runner.gd:115-124`, not which assertions failed with which messages. | `.github/workflows/ci.yml:119-120`; report written to `user://mcp_validation.json` at `validation_runner.gd:11,112` |
| CID-07 | P1 | Nothing deploys or publishes. `release-summary` echoes a string; no image push, no artifact registry, no web host, no `steamcmd`. | `.github/workflows/release.yml:60-65` |
| CID-08 | P1 | No `concurrency` group. Pushing three commits to a PR runs three full six-job matrices to completion. | Neither workflow declares `concurrency:` |
| CID-09 | P2 | No `timeout-minutes` on any job. A hung headless Godot run consumes the full 6-hour runner default. | Neither workflow sets `timeout-minutes` |
| CID-10 | P2 | No C# formatting gate (`dotnet format --verify-no-changes`) and no analyzer enforcement, so C# style is unchecked while GDScript, Python, and TypeScript all have gates. | `.github/workflows/ci.yml:16-28` |
| CID-11 | P2 | No test coverage collection or reporting on `dotnet test`. | `.github/workflows/ci.yml:28` |
| CID-12 | P2 | No `dependabot.yml` and no dependency or secret scanning. The repo pins `actions/checkout@v5`, `setup-dotnet@v5`, `setup-node@v5`, `setup-python@v5`, `setup-godot@v1`, `upload-artifact@v4` by major tag with no update automation. | `.github/` contains only `workflows/` |
| CID-13 | P2 | No documentation link check, so `README.md` can and does link six nonexistent doc paths. | See [`repository-root.md`](repository-root.md) gap REP-01 |
| CID-14 | P2 | No OpenAPI drift check, so `packages/shared/openapi/aumbrye-api.v1.yaml` is already two endpoints behind. | See [`packages.md`](packages.md) gap PKG-06 |

## Target design

**Version pinning has a single source.** `apps/game/client/.godot-version` holds the exact patch version. Both workflows read it in a preceding step. A validation assertion checks it matches `config/features`. See [`project-config-autoloads.md`](project-config-autoloads.md) gap CFG-01 for the client-side half.

**The API ships as a container.** Add `services/backend/Dockerfile` as a multi-stage build. It must copy `content/` because `packages/procedural/Content/ContentPaths.cs:21-28` walks up from `AppContext.BaseDirectory` looking for a `content` directory, and set `AUMBRYE_CONTENT_ROOT` explicitly so the walk is not needed:

```dockerfile
# syntax=docker/dockerfile:1
FROM mcr.microsoft.com/dotnet/sdk:8.0 AS build
WORKDIR /src
COPY services/backend/Aumbrye.sln services/backend/
COPY services/backend/src/ services/backend/src/
COPY packages/ packages/
RUN dotnet restore services/backend/src/Aumbrye.Api/Aumbrye.Api.csproj
RUN dotnet publish services/backend/src/Aumbrye.Api/Aumbrye.Api.csproj \
    -c Release -o /app/publish --no-restore

FROM mcr.microsoft.com/dotnet/aspnet:8.0 AS runtime
WORKDIR /app
RUN adduser --system --group --no-create-home aumbrye
COPY --from=build /app/publish .
COPY content/ /app/content/
ENV AUMBRYE_CONTENT_ROOT=/app/content \
    ASPNETCORE_URLS=http://+:8080 \
    ASPNETCORE_ENVIRONMENT=Production
EXPOSE 8080
USER aumbrye
HEALTHCHECK --interval=30s --timeout=3s --start-period=20s --retries=3 \
  CMD ["dotnet", "Aumbrye.Api.dll", "--healthcheck"]
ENTRYPOINT ["dotnet", "Aumbrye.Api.dll"]
```

The build context must be the repo root, not `services/backend`, because it copies `packages/` and `content/`. `release.yml:18` changes accordingly. Rejected alternative: a single-stage `sdk` image — it triples image size and ships the compiler into production.

**The export preset is committed.** `export_presets.cfg` is currently gitignored because it can hold signing credentials. Split it: commit `apps/game/client/export_presets.cfg` containing only the `"Windows Desktop"` preset with no credential fields, and keep `export_presets.local.cfg` gitignored for signing. Update `.gitignore:135` to `**/export_presets.local.cfg`. Rejected alternative: generating the preset in CI with a heredoc — it puts export configuration in YAML where no one maintaining the game will find it.

**Every GDScript file is linted.** Replace the 8-file allowlist with a repo-wide glob and a shrinking exclusion list:

```yaml
      - name: gdlint + gdformat
        run: |
          pip install gdtoolkit
          mapfile -t FILES < <(find apps/game/client/scripts -name '*.gd' -not -path '*/addons/*')
          gdlint "${FILES[@]}"
          gdformat --check "${FILES[@]}"
```

If flipping all 271 files at once produces too large a diff to review, land it as a `gdformat` write commit first (formatting only, no logic change), then enable `--check`. There is no third option worth taking: an allowlist that covers 3 percent of files provides no signal.

**Failures are diagnosable.** The godot job copies the report out of the Godot user directory and uploads it, always:

```yaml
      - name: Collect validation report
        if: always()
        run: |
          mkdir -p "$GITHUB_WORKSPACE/artifacts"
          cp ~/.local/share/godot/app_userdata/Aumbrye/mcp_validation.json \
             "$GITHUB_WORKSPACE/artifacts/mcp_validation.json" || true
      - uses: actions/upload-artifact@v4
        if: always()
        with:
          name: godot-validation-report
          path: artifacts/mcp_validation.json
      - name: Summarize failures
        if: failure()
        run: |
          jq -r '.tests[] | select(.pass == false) | "FAIL \(.id): \(.message)"' \
            "$GITHUB_WORKSPACE/artifacts/mcp_validation.json" >> "$GITHUB_STEP_SUMMARY"
```

**Release publishes real artifacts.** `backend-image` pushes to GitHub Container Registry (`ghcr.io/<owner>/aumbrye-api:<tag>` plus `:latest`) using `docker/login-action` and `docker/build-push-action` with GitHub Actions layer caching. `web-build` keeps the artifact upload and adds an optional deploy step gated on a `DEPLOY_WEB` repository variable. `godot-export` uploads the Windows build. Steam upload stays manual — `steamcmd` needs a Steam Guard secret and a real app id, and neither exists yet; the summary job states this explicitly rather than implying automation.

## Work plan

1. **Pin the Godot version from a file** — add `apps/game/client/.godot-version`; add a `read-godot-version` step with an output to both workflows; replace both `version: 4.4.0` literals. (CID-01)
2. **Add `services/backend/Dockerfile`** — the multi-stage build above. Add `services/backend/.dockerignore` excluding `bin/`, `obj/`, `tests/`. Change `release.yml:18` to `docker build -f services/backend/Dockerfile -t aumbrye-api:${{ inputs.tag }} .` with the repo root as context. (CID-02)
3. **Add a Docker build to `ci.yml`** — new job `api-image` that builds the image (no push) on every PR so the Dockerfile cannot rot the way the reference at `release.yml:18` did. (CID-02)
4. **Commit the export preset** — add `apps/game/client/export_presets.cfg` with only the `"Windows Desktop"` preset and no credentials; change `.gitignore:135` to ignore `**/export_presets.local.cfg` instead. (CID-03)
5. **Add `concurrency` and `timeout-minutes`** — top-level `concurrency: { group: "${{ github.workflow }}-${{ github.ref }}", cancel-in-progress: true }` in `ci.yml`; `timeout-minutes: 20` on `backend`, `web`, `content`, `gdscript-lint`, `python-lint` and `timeout-minutes: 30` on `godot`. (CID-08, CID-09)
6. **Upload and summarize the validation report** — the three steps above added to the `godot` job. (CID-06)
7. **Widen the gdlint scope** — land a `gdformat`-only formatting commit across `apps/game/client/scripts`, then replace `ci.yml:93-100` with the `find`-based glob. (CID-04)
8. **Remove `continue-on-error` from the strict content step** — after [`tools-scripts.md`](tools-scripts.md) steps 1-2 make the content pass. Merge the two content steps into one `npm run validate:strict`. (CID-05)
9. **Add `dotnet format` and coverage** — `dotnet format Aumbrye.sln --verify-no-changes` step in the `backend` job; `dotnet test ... --collect:"XPlat Code Coverage" --results-directory ./coverage` plus an `upload-artifact` of the Cobertura XML. (CID-10, CID-11)
10. **Add `docs-links` and `openapi-drift` jobs** — link checker over `README.md` and `docs/**/*.md`; spec-drift diff as specified in [`packages.md`](packages.md) step 5. (CID-13, CID-14)
11. **Add `.github/dependabot.yml`** — weekly ecosystems `github-actions` (root), `nuget` (`/services/backend`, `/packages/procedural`, `/packages/shared`, `/tools/procgen-cli`), `npm` (`/apps/web`, `/scripts/validate-content`), `pip` (root). Enable secret scanning and CodeQL for C# and JavaScript. (CID-12)
12. **Make `release.yml` publish** — `docker/login-action@v3` against `ghcr.io` with `${{ secrets.GITHUB_TOKEN }}`, `docker/build-push-action@v6` with `push: true`, `tags: ghcr.io/${{ github.repository_owner }}/aumbrye-api:${{ inputs.tag }},ghcr.io/${{ github.repository_owner }}/aumbrye-api:latest`, `cache-from: type=gha`, `cache-to: type=gha,mode=max`. Add `permissions: { contents: read, packages: write }` to the job. (CID-07)

Steps 1-6 are independently landable and immediately useful. Step 7 needs the formatting commit first. Step 8 depends on the content work in [`tools-scripts.md`](tools-scripts.md).

## Data and schema changes

None under `content/schemas/`. No save-format change, so **no `save_migrator.gd` version bump**.

New tracked files: `services/backend/Dockerfile`, `services/backend/.dockerignore`, `apps/game/client/.godot-version`, `apps/game/client/export_presets.cfg`, `.github/dependabot.yml`.

## Acceptance criteria

- [ ] Neither workflow contains a hardcoded Godot version; both read `apps/game/client/.godot-version`.
- [ ] `docker build -f services/backend/Dockerfile .` from the repo root produces an image that answers `GET /api/v1/health` with `{"status":"ok"}`.
- [ ] The `api-image` CI job builds the image on every pull request.
- [ ] `release.yml` on dispatch pushes `ghcr.io/<owner>/aumbrye-api:<tag>` and `:latest`.
- [ ] `godot --headless --path apps/game/client --export-release "Windows Desktop" out.exe` succeeds on a clean checkout with no local file creation.
- [ ] `gdlint` and `gdformat --check` run over every `.gd` file under `apps/game/client/scripts` and pass.
- [ ] `.github/workflows/ci.yml` contains no `continue-on-error`.
- [ ] A failing godot job uploads `godot-validation-report` and writes every failing assertion id and message to the job summary.
- [ ] Pushing a second commit to an open PR cancels the first run.
- [ ] Every job declares `timeout-minutes`.
- [ ] `dotnet format Aumbrye.sln --verify-no-changes` passes in CI.
- [ ] `dotnet test` uploads a Cobertura coverage artifact.
- [ ] `.github/dependabot.yml` covers github-actions, nuget, npm, and pip.
- [ ] A PR that breaks a relative link in `docs/` fails the `docs-links` job.
- [ ] A PR that adds an endpoint without regenerating the OpenAPI spec fails the `openapi-drift` job.

## Validation

- Extend `apps/game/client/scripts/validation/suites/m7_suite.gd` `m7.ci.release_workflow` (currently a file-existence check at `m7_suite.gd:502-508`) to also assert `.github/workflows/release.yml` contains `ghcr.io` and does not contain `4.4.0`, and that `services/backend/Dockerfile` exists.
- Add `setup.engine_version_pin` to `setup_suite.gd` asserting `.godot-version` matches `config/features[0]` (shared with [`project-config-autoloads.md`](project-config-autoloads.md)).
- Add `services/backend/tests/Aumbrye.IntegrationTests/` case `Health_RespondsUnderProductionEnvironment` so the container's `ASPNETCORE_ENVIRONMENT=Production` path is exercised, including the `Jwt:Secret` guard at `services/backend/src/Aumbrye.Api/Program.cs:19-24`.
- Manual: dispatch `release.yml` once against a throwaway tag and confirm all three artifacts land. Automating a full release dispatch in CI is not worthwhile.

## Related

- Existing behavior: [`../existing_codebase/ci-cd.md`](../existing_codebase/ci-cd.md)
- [`project-config-autoloads.md`](project-config-autoloads.md) — CID-01 twin gap CFG-01
- [`website-and-backend.md`](website-and-backend.md) — the container and its configuration
- [`tools-scripts.md`](tools-scripts.md) — CID-05 depends on TLS-01
- [`packages.md`](packages.md) — CID-14
- [`export-tools.md`](export-tools.md) — the godot job's export step
- [`validation-suites.md`](validation-suites.md) — what the godot job asserts
