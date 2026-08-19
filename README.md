# Aumbrye

Single-player action roguelite RPG with Soulslike combat. Early Access target: Windows via Steam. The Godot client is fully playable offline — no backend or web stack required for the core loop.

## Prerequisites

| Tool | Version |
|------|---------|
| Godot | 4.7 (standard build; see `apps/game/client/project.godot` `config/features`) |
| .NET SDK | 8.x |
| Node.js | 24 |
| Docker | Compose v2 |

## Run the game

Open `apps/game/client/project.godot` in Godot 4.7, or from a shell:

```bash
godot --path apps/game/client
```

Press **F5** — main scene is **`scenes/ui/title_screen.tscn`**. Hub, dungeon runs, combat, and results work with no API or database.

## Run the optional services

Infrastructure (Postgres + Redis):

```bash
docker compose up -d
```

Copy `.env.example` to `.env` if you need to override defaults.

Backend API:

```bash
dotnet run --project services/backend/src/Aumbrye.Api
```

Health check: `GET http://localhost:5000/api/v1/health` → `{ "status": "ok" }`

Web site:

```bash
cd apps/web
npm install
npm run dev
```

Set `VITE_API_URL` in `.env.development` (see `apps/web/.env.example`).

Content schema validation:

```bash
cd scripts/validate-content
npm install
npm run validate
```

## Validation

Full local suite (dotnet, content, Python lint, Godot in-engine):

```bash
node scripts/validate.mjs
```

Cross-platform wrappers: `./scripts/validate.ps1` (Windows) or `./scripts/validate.sh` (Linux/macOS).

Run individual layers:

```bash
node scripts/validate.mjs --layer content --layer python
```

Individual commands (run these when iterating on one layer):

```bash
dotnet test services/backend/Aumbrye.sln --configuration Release
```

```bash
npm run validate:strict
```

```bash
godot --path apps/game/client --headless --script res://scripts/validation/validation_main.gd
```

```bash
pip install ruff && ruff check tools/
```

Balance export:

```bash
node scripts/balance/balance-cli.mjs --summary
```

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Documentation conventions](docs/DOC-CONVENTIONS.md)
- [Remaining points](docs/remaining_points.md)
- [Save migrations](docs/SAVE_MIGRATIONS.md)
- [Manual validation checklist](docs/validation/manual-checklist.md)
- [ADR-0001: Client/server authority](docs/ADR/0001-client-server-authority.md)

## Development

- Remote: `https://github.com/halaghiuc-dragos/Aumbrye`
- Default branch: `main`
- Pull requests required; see [CONTRIBUTING.md](CONTRIBUTING.md)
- Validation is local: run `node scripts/validate.mjs` before opening a pull request (see [CONTRIBUTING.md](CONTRIBUTING.md))
