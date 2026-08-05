# Repository root — improvement plan

## Current state

The root layout is coherent and every stack has a working entry point (see [`../existing_codebase/repository-root.md`](../existing_codebase/repository-root.md)). Five untracked artifacts sit at root (`debug-d7fbce.log`, `seed1.json`, `seed99999.json`, `reports/`, `.ruff_cache/`); four are covered by `.gitignore`, `.ruff_cache/` is covered only by Ruff's own self-ignoring file. The bigger problem is that `README.md` — the first file a new contributor reads — points at six documentation paths that no longer exist and states the wrong main scene and the wrong Node version.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| REP-01 | P0 | `README.md` links six paths that do not exist: `docs/plan/00-AGENT-README.md`, `docs/plan/01-LOCKED-DECISIONS.md`, `docs/plan/M-PHASES-STATUS.md`, `docs/plan/07-EA-DEFINITION-OF-DONE.md`, `docs/design/AUDIT_2026-08.md`, `docs/CODING.md`, `docs/CONTENT_SCHEMA.md`. Only `ARCHITECTURE.md`, `DOC-CONVENTIONS.md`, `MCP_AGENT_GUIDE.md`, `ADR/`, `existing_codebase/`, `actual_improvements/` exist under `docs/`. | `README.md:15,62-64,76-79` vs `docs/` listing |
| REP-02 | P1 | `README.md` states the Godot main scene is `scenes/hub/hub.tscn`; the project boots `res://scenes/ui/title_screen.tscn`. | `README.md:58` vs `apps/game/client/project.godot:19` |
| REP-03 | P1 | `README.md` requires Node 20 LTS; both CI Node jobs pin Node 24. | `README.md:23` vs `.github/workflows/ci.yml:40,72` |
| REP-04 | P1 | `README.md:86` claims "283 Godot + 79 backend tests as of M6 close". The runner currently registers 24 suites and the last local report recorded 429 client assertions. The number is stale and unverifiable from code. | `README.md:86`, `apps/game/client/scripts/validation/validation_runner.gd:13-38` |
| REP-05 | P2 | `.ruff_cache/` is not in the repo `.gitignore`; it is only ignored because Ruff writes `.ruff_cache/.gitignore`. A Ruff version that stops doing that would start dirtying `git status`. | `.gitignore:187-193`, `.ruff_cache/.gitignore:2` |
| REP-06 | P2 | Root has no `.editorconfig`, so C#, GDScript, TypeScript, Python, YAML, and JSON all rely on per-tool config with no shared line-ending or indentation rule. | Root listing: no `.editorconfig` |
| REP-07 | P2 | No `CONTRIBUTING.md`, `LICENSE`, `SECURITY.md`, or `CODEOWNERS`. The remote is a public GitHub repo (`README.md:83`). | Root listing; `.github/` contains only `workflows/` |
| REP-08 | P2 | `.pre-commit-config.yaml` runs only content JSON validation. It does not run `ruff`, `gdformat`, `eslint`, or `dotnet format`, so every other lint failure is discovered in CI. | `.pre-commit-config.yaml:1-9` |

## Target design

**Root is a self-describing entry surface.** A contributor who clones the repo and reads only `README.md` can build and run all four stacks, and every link in that README resolves. The README does not restate facts that live in code (test counts, scene names) unless a CI check enforces the restatement.

Chosen approach for doc links: point `README.md` at `docs/ARCHITECTURE.md` and the two paired doc trees, and add a CI link checker that fails on broken relative Markdown links inside `docs/` and `README.md`. Alternative rejected: recreating `docs/plan/` to satisfy the old links — the plan tree was deliberately replaced by the paired `existing_codebase/` + `actual_improvements/` trees defined in `docs/DOC-CONVENTIONS.md`, and resurrecting it would reintroduce roadmap-as-documentation.

Target root additions:

```
.editorconfig
CONTRIBUTING.md
LICENSE
SECURITY.md
.github/CODEOWNERS
.github/PULL_REQUEST_TEMPLATE.md
services/backend/Dockerfile        # owned by ci-cd.md / website-and-backend.md
```

Target `.editorconfig`:

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
insert_final_newline = true
trim_trailing_whitespace = true
indent_style = space
indent_size = 4

[*.{gd,tscn,tres,godot}]
indent_style = tab

[*.{ts,tsx,js,mjs,json,yml,yaml}]
indent_size = 2

[*.cs]
indent_size = 4
csharp_new_line_before_open_brace = all

[*.md]
trim_trailing_whitespace = false
```

Target `.gitignore` addition, placed next to the existing Python cache block:

```gitignore
.ruff_cache/
```

Target README structure (headings only; content must be verified against code at write time):

1. What Aumbrye is, one paragraph.
2. Prerequisites table — Godot version taken from `project.godot` `config/features`, .NET 8.x, Node 24 (matching CI), Docker Compose v2.
3. Run the game — `godot --path apps/game/client`, main scene `scenes/ui/title_screen.tscn`, note that the client is fully playable with no backend.
4. Run the optional services — `docker compose up -d`, `dotnet run --project services/backend/src/Aumbrye.Api`, `npm run dev` in `apps/web`.
5. Validation — `./scripts/run-all-validation.ps1` and the three CI-equivalent commands, with no hardcoded pass counts.
6. Documentation — links to `docs/ARCHITECTURE.md`, `docs/DOC-CONVENTIONS.md`, `docs/existing_codebase/_INDEX.md`, `docs/actual_improvements/_INDEX.md`, `docs/ADR/`.

## Work plan

1. **Add `.editorconfig`** — new file at root with the content above. No behavior change; editors pick it up immediately. (REP-06)
2. **Add `.ruff_cache/` to `.gitignore`** — one line under the "Python caches" block at `.gitignore:189`. (REP-05)
3. **Rewrite `README.md`** — replace the dead links with `docs/ARCHITECTURE.md` and the two doc-tree indexes; correct the main scene to `scenes/ui/title_screen.tscn`; correct Node to 24; delete the hardcoded test counts at `README.md:86` and replace with the command to run. (REP-01, REP-02, REP-03, REP-04)
4. **Add a docs link checker job to CI** — new job `docs-links` in `.github/workflows/ci.yml` running `lychee --offline --no-progress README.md 'docs/**/*.md'` (or an equivalent Node checker) so REP-01 cannot recur. Job is required on `pull_request`. (REP-01)
5. **Add `CONTRIBUTING.md`, `LICENSE`, `SECURITY.md`, `.github/CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md`** — `CONTRIBUTING.md` states the branch model (`main`, PR required), the four validation commands, and the doc-convention requirement from `docs/DOC-CONVENTIONS.md`. (REP-07)
6. **Extend `.pre-commit-config.yaml`** — add `ruff check tools/`, `gdformat --check` over the same file set the CI gdscript job uses (see [`ci-cd.md`](ci-cd.md) gap CID-04), and `npm run lint` in `apps/web` restricted to staged files. Keep hooks fast: use `pass_filenames: true` where the tool supports it instead of `always_run: true`. (REP-08)

Each step is independently landable; none touch source code or the play path.

## Data and schema changes

None. No `content/schemas/` file changes and no save-format change, so no `save_migrator.gd` version bump.

## Acceptance criteria

- [ ] Every relative Markdown link in `README.md` and under `docs/` resolves to an existing file, enforced by the `docs-links` CI job.
- [ ] `README.md` names `scenes/ui/title_screen.tscn` as the main scene.
- [ ] `README.md` names Node 24, matching `.github/workflows/ci.yml:40,72`.
- [ ] `README.md` contains no hardcoded pass/fail test counts.
- [ ] `git status --porcelain` is empty on a clean clone after running `ruff check tools/` and `./scripts/run-all-validation.ps1`.
- [ ] `.editorconfig`, `CONTRIBUTING.md`, `LICENSE`, `SECURITY.md`, `.github/CODEOWNERS` exist at their target paths.
- [ ] `pre-commit run --all-files` executes ruff, gdformat, eslint, and content validation.

## Validation

- Extend `apps/game/client/scripts/validation/suites/setup_suite.gd` with `setup.readme_main_scene`: read the repo-root `README.md` via `ProjectSettings.globalize_path("res://").path_join("../../..")` and assert it contains the value of `ProjectSettings.get_setting("application/run/main_scene")`. This turns REP-02 into a permanent regression guard inside the same suite that already asserts the main scene.
- The `docs-links` CI job covers REP-01 and REP-07 link rot.
- Manual: on a fresh clone, follow `README.md` end to end on Windows and confirm each of the four stacks starts. Automation is not possible because it requires a Godot editor install and Docker.

## Related

- Existing behavior: [`../existing_codebase/repository-root.md`](../existing_codebase/repository-root.md)
- [`ci-cd.md`](ci-cd.md) — the `docs-links` job and the missing `Dockerfile`
- [`tools-scripts.md`](tools-scripts.md) — pre-commit hook coverage
- [`project-config-autoloads.md`](project-config-autoloads.md) — main scene and Godot version
