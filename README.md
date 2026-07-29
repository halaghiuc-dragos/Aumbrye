# Aumbrye

Single-player action roguelite RPG with Soulslike combat. Early Access target: Windows via Steam.

## Repository layout

| Path | Purpose |
|------|---------|
| `apps/game/client/` | Godot 4 client |
| `apps/web/` | React + TypeScript + Vite website |
| `services/backend/` | ASP.NET Core 8 API |
| `packages/shared/` | Shared DTOs and contracts (C#) |
| `packages/procedural/` | Dungeon generator library (C#) |
| `content/` | JSON content definitions + JSON Schema |
| `docs/plan/` | Implementation plan (agent entry: `docs/plan/00-AGENT-README.md`) |

## Prerequisites

| Tool | Version |
|------|---------|
| Godot | 4.7 (standard build) |
| .NET SDK | 8.x |
| Node.js | 20 LTS |
| Docker | Compose v2 |

## First boot

### 1. Infrastructure

```bash
docker compose up -d postgres redis
```

Copy `.env.example` to `.env` if you need to override defaults.

### 2. Backend API

```bash
cd services/backend
dotnet restore
dotnet run --project src/Aumbrye.Api
```

Health check: `GET http://localhost:5000/api/v1/health` → `{ "status": "ok" }`

### 3. Web

```bash
cd apps/web
npm install
npm run dev
```

Set `VITE_API_URL` in `.env.development` (see `.env.example` in `apps/web/`).

### 4. Godot client

Open `apps/game/client/project.godot` in Godot 4.7. Run the combat arena (`scenes/debug/combat_arena.tscn`).

### 5. Content validation

```bash
cd scripts/validate-content
npm install
npm run validate
```

## Documentation

- [Coding standards](docs/CODING.md)
- [Content schema guide](docs/CONTENT_SCHEMA.md)
- [ADR-0001: Client/server authority](docs/ADR/0001-client-server-authority.md)
- [Implementation plan](docs/plan/00-AGENT-README.md)

## Development

- Default branch: `main`
- PRs required; CI runs backend tests, web build, and content schema validation.
