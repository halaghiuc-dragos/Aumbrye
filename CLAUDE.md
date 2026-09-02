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
| every door leads somewhere, every room connects | `res://scenes/debug/floor_connectivity_audit.tscn` — add `-- --seeds=N` |
| character options | `res://scenes/debug/combination_audit.tscn` |
| every icon resolves to artwork | `res://scenes/debug/icon_atlas_audit.tscn` |
| icon sheets match their source | `python tools/icon-gen/atlas_build.py --check` |
| item condition rolls and scales | `res://scenes/debug/item_quality_audit.tscn` |
| shadows follow the day-night cycle | `res://scenes/debug/shadow_cycle_audit.tscn` |
| the player↔enemy exchange is in band | `node scripts/balance/balance-cli.mjs` |
| gear stats reach combat, caps hold | `res://scenes/debug/combat_stats_audit.tscn` |
| every item has its own icon, condition reads | `res://scenes/debug/inventory_ux_audit.tscn` |
| every scene loads and is skinned | `res://scenes/debug/scene_sweep.tscn` — add `-- --verbose` for the full list |
| what each scene costs per frame | `res://scenes/debug/perf_audit.tscn` — needs a display; headless reports no GPU cost |
| where a dungeon floor's draw calls go | `res://scenes/debug/draw_call_probe.tscn` |
| frame matches the pick | `res://scenes/debug/frame_audit.tscn` |
| camera zooms and un-zooms | `res://scenes/debug/camera_zoom_audit.tscn` |
| the camera follows | `res://scenes/debug/camera_follow_audit.tscn` |
| how it looks | the `res://scenes/debug/capture_*.tscn` contact sheets |

These live under `scenes/debug/` and `scripts/tools/` and are diagnostics, not a test suite: they
are run deliberately when someone wants an answer, they are not wired to any hook, and nothing
fails a commit because of them.
