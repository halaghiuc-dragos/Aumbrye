# Repository root

Top-level layout of the Aumbrye monorepo: what each root entry is, which entry points start each stack, and which files on disk are untracked local artifacts. Not a runtime system; this doc is the map every other doc in this tree assumes.

## Files

| Path | Role |
|------|------|
| `apps/game/client/` | Godot 4 client project (`project.godot`). Primary gameplay. |
| `apps/web/` | React 19 + TypeScript + Vite marketing/account site. |
| `services/backend/` | ASP.NET Core 8 solution (`Aumbrye.sln`): Api, Application, Domain, Infrastructure, two test projects. |
| `packages/procedural/` | `Aumbrye.Procedural` C# dungeon generator library. |
| `packages/shared/` | `Aumbrye.Shared` C# DTOs plus `openapi/aumbrye-api.v1.yaml`. |
| `content/` | Authored JSON content plus `content/schemas/*.v1.json`. |
| `tools/` | `procgen-cli` (C#) and two Python generators. |
| `scripts/` | PowerShell validation runners, `validate-content/` (Node + Ajv), `balance/`, `tools/`. |
| `assets/` | Shared asset notes. Godot runtime assets live under `apps/game/client/assets/`. |
| `docs/` | `ARCHITECTURE.md`, `DOC-CONVENTIONS.md`, `MCP_AGENT_GUIDE.md`, `ADR/`, `existing_codebase/`, `actual_improvements/`. |
| `.github/workflows/` | `ci.yml`, `release.yml`. |
| `docker-compose.yml` | Postgres 16 + Redis 7 only. |
| `.env.example` | Compose and out-of-Docker API connection variables. |
| `pyproject.toml` | Ruff config for `tools/`. |
| `.gdlintrc` | gdtoolkit lint/format config. |
| `.pre-commit-config.yaml` | Single local hook: content JSON validation. |
| `.gitignore` | 216 lines; secrets, build output, Godot artifacts, reports, seed dumps. |
| `README.md` | Repo onboarding. |

Tracked root-level files, verified with `git ls-files`: `.env.example`, `.gdlintrc`, `.gitignore`, `.pre-commit-config.yaml`, `README.md`, `docker-compose.yml`, `pyproject.toml`.

## How it works

### Entry points

| Stack | Command | Entry symbol |
|-------|---------|--------------|
| Godot client | `godot --path apps/game/client` | `application/run/main_scene` = `res://scenes/ui/title_screen.tscn` (`apps/game/client/project.godot:19`) |
| Godot headless validation | `godot --path . --headless --script res://scripts/validation/validation_main.gd` | `validation_main.gd:7` `_initialize()` |
| API | `dotnet run --project services/backend/src/Aumbrye.Api` | `services/backend/src/Aumbrye.Api/Program.cs:13` |
| Web | `npm run dev` in `apps/web` | `apps/web/src/main.tsx:6` |
| Procgen CLI | `dotnet run --project tools/procgen-cli -- generate <biomeId> <seed>` | `tools/procgen-cli/Program.cs:3` |
| Content validation | `npm run validate` in `scripts/validate-content` | `scripts/validate-content/validate.mjs:166` |
| Full local validation | `./scripts/run-all-validation.ps1` | `scripts/run-all-validation.ps1:41` |

### Stray artifacts at root

Five entries exist on disk but are not part of the tracked tree. Each was verified with `git check-ignore -v`:

| Entry | What it is | Ignored by | Status |
|-------|-----------|-----------|--------|
| `debug-d7fbce.log` | Loose log file | `.gitignore:108` (`*.log`) | Untracked local artifact |
| `seed1.json` | procgen-cli stdout dump | `.gitignore:177` (`/seed*.json`) | Untracked local artifact |
| `seed99999.json` | procgen-cli stdout dump for `TestContext.SEED_B` (`test_context.gd:10`) | `.gitignore:177` | Untracked local artifact |
| `reports/` | Contains `procgen-test.json`, `validation-run.log`, `validation-summary.json` written by `scripts/run-all-validation.ps1:8` | `.gitignore:173` (`reports/`) | Untracked build output |
| `.ruff_cache/` | Ruff cache for version `0.16.1`; self-ignoring via its own `.ruff_cache/.gitignore` | `.ruff_cache/.gitignore:2` | Untracked tool cache |

`.ruff_cache/` is the only one not covered by the repo `.gitignore`. It is excluded only because Ruff writes a self-ignoring `.gitignore` inside the directory; the repo `.gitignore` lists `.pytest_cache/` and `.mypy_cache/` (`.gitignore:192-193`) but not `.ruff_cache/`.

None of the five are tracked, so none pollute clones.

### `.gitignore` coverage of interest

- Secrets, keys, `.env` except `.env.example` (`.gitignore:27-30`)
- `**/appsettings.*.json` with `appsettings.json` and `appsettings.Testing.json` re-allowed (`.gitignore:46-48`)
- Godot `.godot/`, `.import/`, `export_presets.cfg`, `*.pck` (`.gitignore:133-144`)
- `addons/godotsteam/` (`.gitignore:161`) — GodotSteam is not vendored
- `**/config/dev_api.local.json` (`.gitignore:152`)

## Contracts

- **Repo-root resolution from the client**: `ContentLoader` and validation suites derive the repo root as `ProjectSettings.globalize_path("res://").path_join("../../..")` (for example `m6_suite.gd:596`). Moving `apps/game/client/` deeper or shallower breaks every content and doc assertion.
- **Solution cross-boundary references**: `services/backend/Aumbrye.sln:18-20` includes `packages/shared` and `packages/procedural` by relative path. `services/backend/src/Aumbrye.Api/Aumbrye.Api.csproj:17-18` references them with `..\..\..\..\packages\...`.
- **CI working directories** are pinned per job (`.github/workflows/ci.yml:15,35,66,109`), so relocating any of `services/backend`, `apps/web`, `scripts/validate-content`, `apps/game/client` breaks CI.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Root layout and entry points | IMPLEMENTED | `apps/game/client/project.godot:19`, `services/backend/src/Aumbrye.Api/Program.cs:13` |
| `Dockerfile` for the API | ABSENT | Repo-wide `dir /b /s Dockerfile*` returns no match; `release.yml:18` still builds `-f services/backend/Dockerfile` |
| `.ruff_cache/` in repo `.gitignore` | ABSENT | `.gitignore:187-193` lists `__pycache__/`, `*.py[cod]`, `.pytest_cache/`, `.mypy_cache/` only |
| `README.md` accuracy | BROKEN | `README.md:58` claims main scene is `scenes/hub/hub.tscn`; `project.godot:19` is `res://scenes/ui/title_screen.tscn`. `README.md:15,62-64,76-79` link `docs/plan/`, `docs/design/`, `docs/CODING.md`, `docs/CONTENT_SCHEMA.md` — none exist under `docs/` |
| `README.md` Node version | BROKEN | `README.md:23` says Node 20 LTS; `ci.yml:40,72` pin Node 24 |
| Stray root artifacts | PLACEHOLDER | `debug-d7fbce.log`, `seed1.json`, `seed99999.json`, `reports/`, `.ruff_cache/` all present on disk, all untracked |
| Multiplayer / dedicated server code | ABSENT | Repo-wide grep for `multiplayer`, `ENetMultiplayerPeer`, `MultiplayerAPI`, `@rpc`, `rpc(`, `dedicated`, `WebSocketPeer`, `SignalR`, `IHubContext` (case-insensitive, excluding `docs/`) returns zero matches |

## Related

- Improvement plan: [`../actual_improvements/repository-root.md`](../actual_improvements/repository-root.md)
- [`project-config-autoloads.md`](project-config-autoloads.md)
- [`packages.md`](packages.md)
- [`ci-cd.md`](ci-cd.md)
- [`tools-scripts.md`](tools-scripts.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
