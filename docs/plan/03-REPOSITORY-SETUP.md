# Repository and Setup

> Greenfield bootstrap — **M0 complete** (2026-07-29). Milestone inventory: [systems/00-SETUP-CI.md](systems/00-SETUP-CI.md).

---

## Target tree

```
aumbrye/
  apps/
    web/                      # React + TS + Vite
    game/
      client/                 # Godot 4.7 project root
  services/
    backend/                  # ASP.NET Core 8 solution
  packages/
    shared/                   # DTOs, OpenAPI, shared contracts (C#)
    procedural/               # Dungeon generator library (C#)
  content/
    schemas/                  # JSON Schema
    biomes/                   # placeholder
    enemies/                  # placeholder
    items/                    # placeholder
    weapons/                  # not yet created
    dialogue/                 # not yet created
    quests/                   # not yet created
    affixes/                  # not yet created
  docs/
    plan/                     # Implementation plan
    ADR/                      # Architecture decision records
    design/                   # not yet created
  assets/                     # not yet created
  scripts/
    validate-content/         # M0 — Node validator
    codegen/                  # not yet created
  .github/
    workflows/ci.yml          # M0 — backend, web, content jobs
  docker-compose.yml
  README.md
  .gitignore
```

---

## Tooling versions (pinned)

| Tool | Version |
|------|---------|
| Godot | **4.7** (standard build, GDScript) |
| .NET SDK | 8.x |
| Node.js | 20 LTS |
| Docker | Compose v2 |
| PostgreSQL | 16 |
| Redis | 7 |
| Git | 2.x |

---

## Environment files

Local overrides are **gitignored**. Copy from the committed examples on first setup:

| Local file (gitignored) | Copy from |
|----------------------|-----------|
| `services/backend/src/Aumbrye.Api/appsettings.Development.json` | `appsettings.Development.json.example` |
| `apps/web/.env.development` | `.env.example` |
| `.env` (repo root, for Docker Compose) | `.env.example` |

| Committed template | Purpose |
|--------------------|---------|
| `services/backend/src/Aumbrye.Api/appsettings.json` | Non-environment defaults (use User Secrets / env for production) |
| `apps/game/client/config/dev_api.json` | Local API base URL for Godot |
| `.env.example` at repo root | Documented compose secrets (no real secrets committed) |

**Never commit:** `.env`, `appsettings.Development.json`, `.cursor/mcp.json`, `reports/`, `seed*.json` dumps — see root `.gitignore`.

---

## First-boot commands (verified)

```bash
# Local config (gitignored — copy once)
cp services/backend/src/Aumbrye.Api/appsettings.Development.json.example services/backend/src/Aumbrye.Api/appsettings.Development.json
cp apps/web/.env.example apps/web/.env.development

# Infra
docker compose up -d postgres redis

# Backend
cd services/backend
dotnet restore
dotnet run --project src/Aumbrye.Api
# → http://localhost:5000/api/v1/health

# Web
cd apps/web
npm install
npm run dev

# Godot
# Open apps/game/client/project.godot in Godot 4.7
# Run scenes/debug/empty_world.tscn (WASD + mouse)

# Content validation
cd scripts/validate-content
npm install
npm run validate
```

---

## GitHub

- Default branch: `main`
- Branch naming: `feat/DOMAIN-x.y-slug`, `fix/...`, `chore/...`
- PR required for `main`
- Conventional Commits preferred: `feat:`, `fix:`, `docs:`, `chore:`, `test:`

---

## Setup milestones (historical)

| Milestone | Status |
|-----------|--------|
| SETUP-0 — Repository skeleton | **done** |
| SETUP-1 — Local stack boots | **done** |
| SETUP-2 — CI gates green | **done** (workflow committed; runs on GitHub after push) |
