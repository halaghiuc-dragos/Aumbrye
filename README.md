# Aumbrye

Single-player action roguelite with soulslike combat, built in Godot. The game is fully offline: the
backend and web site in this repository are optional, and the client ships with them switched off
(`ApiConfig.ONLINE_ENABLED` is `false`, so the game never contacts the API).

## The game

- **Title, character creation, hub.** The hub holds the run portals, the merchant, the blacksmith,
  storage, the quest board and the door to the training arena.
- **The Descent** is the main mode: floors of 8–10 rooms, five floors to a block, a boss at the end
  of each block, across ten biomes. Floors are generated from a seed; each floor follows an
  authored recipe (`content/progression/floor_recipes.json`). **The Long Dark** (endless) opens after
  clearing Depth 10, and **Ember Expedition** is a short three-floor run.
- **Training arena.** Practice parry, dodge, guard break, poise break and stamina recovery, and
  fight any boss you have already beaten again with no penalty.
- **Parked modes.** The Vigil (waves) and the other alternate modes in `content/modes/catalog.json`
  carry `"parked": true`: their content ships, but the hub hides their portals.

## Repository layout

| Path | What lives there |
|------|------------------|
| `apps/game/client` | The Godot project (scripts, scenes, assets, translations) |
| `content/` | All game data as JSON, plus `schemas/`; the client reads it at runtime |
| `apps/web` | Optional React site (Vite) |
| `services/backend` | Optional ASP.NET Core API (accounts, saves, run validation) |
| `packages/procedural` | C# floor generator used by the backend; the game uses the GDScript generator |
| `packages/shared` | Shared contracts and the OpenAPI spec |
| `tools/blender` | Blender scripts that build every model (`.glb`) and icon in the game |
| `tools/icon-gen`, `tools/*.py`, `tools/*.mjs` | Icon atlas, class icon and input-glyph generators |
| `tools/procgen-cli` | Command-line wrapper around `packages/procedural` |
| `scripts/` | Validation, balance and documentation checks |
| `docs/BUGS_AND_ENHANCEMENTS.md` | The backlog |
| `reports/` | Output of the validation and balance tools |

## Prerequisites

| Tool | Version |
|------|---------|
| Godot | 4.7 (Forward Plus; `config/features` in `apps/game/client/project.godot`) |
| .NET SDK | 10 (`global.json`) |
| Node.js | 24 (`.nvmrc`) |
| Docker | Compose v2, only for the optional services |
| Blender | Only to rebuild models and icons (headless `-b`) |
| Python 3 with Pillow | Only to rebuild the icon atlases; `ruff` is optional |

## Run the game

```bash
godot --path apps/game/client
```

The main scene is `scenes/ui/main_menu.tscn`. The hub, dungeon runs, combat and results need no API
or database.

## Run the optional services

```bash
docker compose up -d
```

starts Postgres and Redis. Copy `.env.example` to `.env` to override the defaults. `JWT_SECRET` must
be set for the `app` profile (`docker compose --profile app up`), which also builds the API and web
site.

```bash
dotnet run --project services/backend/src/Aumbrye.Api
```

Health check: `GET http://localhost:5000/api/v1/health`.

```bash
cd apps/web
npm install
npm run dev
```

Leave `VITE_API_URL` empty in development; Vite proxies `/api` to `localhost:5000` (see
`apps/web/.env.example`).

## Validation

There is no CI and there are no test suites (see `CLAUDE.md`). Checks are run by hand.

```bash
node scripts/validate.mjs
```

runs four layers: dotnet build, content (schemas and translations), Python lint, and the Godot
smoke test. Run one layer with `--layer dotnet|content|python|godot`. `scripts/validate.sh` and
`scripts/validate.ps1` are wrappers.

```bash
node scripts/validate.mjs --layer content
node scripts/check-doc-paths.mjs
node scripts/balance/balance-cli.mjs --summary
godot --path apps/game/client --headless -- --smoke-test
```

`CLAUDE.md` lists every in-engine diagnostic (`apps/game/client/scenes/debug/*.tscn`), what each
checks, and how to rebuild the Blender models and icons. `validate.mjs` and `balance-cli.mjs`
rewrite files under `reports/`.

## Development

- Default branch: `main`.
- Pull requests use `.github/PULL_REQUEST_TEMPLATE.md`; run `node scripts/validate.mjs` first.
- Fixed items are deleted from `docs/BUGS_AND_ENHANCEMENTS.md`, not marked done.
- Security reports: see `SECURITY.md`.
