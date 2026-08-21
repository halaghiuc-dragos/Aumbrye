# Working rules for this repository

## No CI, no Dependabot, no tests

Standing decision by the project owner. These are not to be added back, and not to be proposed:

- **No GitHub Actions.** `.github/workflows/` must not exist. `.github/` keeps `CODEOWNERS` and
  `PULL_REQUEST_TEMPLATE.md` and nothing else.
- **No Dependabot.** No `.github/dependabot.yml`, no renovate, no automated dependency PRs.
- **No test files, anywhere.** No unit tests, integration tests, e2e specs, snapshot tests or test
  runners — in any language, in any package. Nothing named `test_*`, `*_test.*`, `*.test.*`,
  `*.spec.*`, and no `tests/` or `__tests__/` directories.

If a task seems to want one of these, do the task without it and say so.

## What verification looks like instead

Checking work is still expected; it just does not take the form of a committed test suite. Run
these by hand:

| what | how |
|---|---|
| everything | `node scripts/validate.mjs` — dotnet build, content, `ruff`, Godot smoke test |
| the game boots | `godot --path apps/game/client --headless -- --smoke-test` |
| every script compiles clean | `res://scenes/debug/lint_scripts.tscn` — warnings are errors |
| cited paths exist | `node scripts/check-doc-paths.mjs` |
| floor generation | `res://scenes/debug/definition_health.tscn` |
| character options | `res://scenes/debug/combination_audit.tscn` |
| the camera follows | `res://scenes/debug/camera_follow_audit.tscn` |
| how it looks | the `res://scenes/debug/capture_*.tscn` contact sheets |

These live under `scenes/debug/` and `scripts/tools/` and are diagnostics, not a test suite: they
are run deliberately when someone wants an answer, they are not wired to any hook, and nothing
fails a commit because of them.
