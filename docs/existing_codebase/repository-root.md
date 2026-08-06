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
| `.editorconfig` | Shared charset, EOL, indentation across stacks. |
| `.pre-commit-config.yaml` | Content validation, `ruff` on `tools/`, `gdformat` on health GDScript set, `eslint` on staged `apps/web` files. |
| `.gitignore` | Secrets, build output, Godot artifacts, reports, seed dumps, `.ruff_cache/`. |
| `README.md` | Repo onboarding. |
| `CONTRIBUTING.md` | Branch model, validation commands, doc conventions. |
| `LICENSE` | Project license. |
| `SECURITY.md` | Security reporting. |
| `.github/CODEOWNERS` | Default review routing. |
| `.github/PULL_REQUEST_TEMPLATE.md` | PR checklist template. |

Tracked root-level files include the hygiene set above plus `.env.example`, `.gdlintrc`, `.gitignore`, `.pre-commit-config.yaml`, `README.md`, `docker-compose.yml`, `pyproject.toml`, `.editorconfig`, `CONTRIBUTING.md`, `LICENSE`, `SECURITY.md`, `.github/CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md`.

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
| Full local validation | `node scripts/validate.mjs` | `scripts/validate.mjs` |

### Stray artifacts at root

Five entries exist on disk but are not part of the tracked tree. Each was verified with `git check-ignore -v`:

| Entry | What it is | Ignored by | Status |
|-------|-----------|-----------|--------|
| `debug-d7fbce.log` | Loose log file | `.gitignore:108` (`*.log`) | Untracked local artifact |
| `seed1.json` | procgen-cli stdout dump | `.gitignore:177` (`/seed*.json`) | Untracked local artifact |
| `seed99999.json` | procgen-cli stdout dump for `TestContext.SEED_B` (`test_context.gd:10`) | `.gitignore:177` | Untracked local artifact |
| `reports/` | Contains `validation-summary.json` and `balance_export.json` written by `scripts/validate.mjs` and `balance-cli.mjs` | `.gitignore:173` (`reports/`) | Untracked build output |
| `.ruff_cache/` | Ruff cache | `.gitignore:194` (`.ruff_cache/`) | Untracked tool cache |

All five stray entries are untracked and do not pollute clones.

### `.gitignore` coverage of interest

- Secrets, keys, `.env` except `.env.example` (`.gitignore:27-30`)
- `**/appsettings.*.json` with `appsettings.json` and `appsettings.Testing.json` re-allowed (`.gitignore:46-48`)
- Godot `.godot/`, `.import/`, `export_presets.cfg`, `*.pck` (`.gitignore:133-144`)
- `addons/godotsteam/` (`.gitignore:161`) â€” GodotSteam is not vendored
- `**/config/dev_api.local.json` (`.gitignore:152`)

## Contracts

- **Repo-root resolution from the client**: `ContentLoader` and validation suites derive the repo root as `ProjectSettings.globalize_path("res://").path_join("../../..")` (for example `m6_suite.gd:596`). Moving `apps/game/client/` deeper or shallower breaks every content and doc assertion.
- **Solution cross-boundary references**: `services/backend/Aumbrye.sln:18-20` includes `packages/shared` and `packages/procedural` by relative path. `services/backend/src/Aumbrye.Api/Aumbrye.Api.csproj:17-18` references them with `..\..\..\..\packages\...`.
- **CI working directories** are pinned per job (`.github/workflows/ci.yml:15,35,66,109`), so relocating any of `services/backend`, `apps/web`, `scripts/validate-content`, `apps/game/client` breaks CI.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Root layout and entry points | IMPLEMENTED | `apps/game/client/project.godot:19`, `services/backend/src/Aumbrye.Api/Program.cs:13` |
| Contributor hygiene files | IMPLEMENTED | `.editorconfig`, `CONTRIBUTING.md`, `LICENSE`, `SECURITY.md`, `.github/CODEOWNERS`, `.github/PULL_REQUEST_TEMPLATE.md` |
| `docs-links` CI job | IMPLEMENTED | `ci.yml:128` `lychee-action@v2` on `README.md` and `docs/**/*.md` |
| `setup.readme_main_scene` | IMPLEMENTED | `setup_suite.gd:90` asserts README names `application/run/main_scene` |
| Pre-commit coverage | IMPLEMENTED | `.pre-commit-config.yaml` â€” content, ruff, gdformat, eslint |
| `Dockerfile` for the API | IMPLEMENTED | `services/backend/Dockerfile`; built in CI `api-image` and `release.yml` |
| `.ruff_cache/` in repo `.gitignore` | IMPLEMENTED | `.gitignore:194` |
| `README.md` accuracy | IMPLEMENTED | `README.md` links `docs/ARCHITECTURE.md` and paired doc trees; main scene `scenes/ui/title_screen.tscn`; Node 24 |
| Stray root artifacts | PLACEHOLDER | `debug-d7fbce.log`, `seed1.json`, `seed99999.json`, `reports/`, `.ruff_cache/` on disk, all untracked |
| Multiplayer / dedicated server code | ABSENT | Repo-wide grep for `multiplayer`, `ENetMultiplayerPeer`, `MultiplayerAPI`, `@rpc`, `rpc(`, `dedicated`, `WebSocketPeer`, `SignalR`, `IHubContext` (case-insensitive, excluding `docs/`) returns zero matches |

## Related

- Improvement plan: [`../actual_improvements/repository-root.md`](../actual_improvements/repository-root.md) - **FINISHED**
- [`project-config-autoloads.md`](project-config-autoloads.md)
- [`packages.md`](packages.md)
- [`ci-cd.md`](ci-cd.md)
- [`tools-scripts.md`](tools-scripts.md)
- [`../ARCHITECTURE.md`](../ARCHITECTURE.md)
