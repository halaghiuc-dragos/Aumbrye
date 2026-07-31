# System: Setup and CI

> Bootstrap and continuous integration. **M0 complete** (verified 2026-07-29).
> Ongoing release CI: [M7_IMPLEMENTATION_LOG.md](../../design/M7_IMPLEMENTATION_LOG.md) (CI-7.1).

---

## M0 status: complete

Exit gate confirmed locally:

- `docker compose up -d` — Postgres 16 + Redis 7 healthy
- `dotnet run --project src/Aumbrye.Api` — `GET /api/v1/health` → 200
- `npm run dev` (apps/web) — Aumbrye title page
- Godot **4.7** — `empty_world.tscn` runs; WASD movement + mouse look

Next phase: [M2-VERTICAL-SLICE.md](../phases/M2-VERTICAL-SLICE.md). M1 closed: [M1_IMPLEMENTATION_LOG.md](../../design/M1_IMPLEMENTATION_LOG.md).

---

## Implemented (M0)

| ID | Deliverable | Path / notes |
|----|-------------|--------------|
| SETUP-0.1 | Monorepo root | `README.md`, `.gitignore` |
| SETUP-0.2 | Docker infra | `docker-compose.yml`, `.env.example` |
| SETUP-0.3 | Godot skeleton | `apps/game/client/` — capsule player, spring-arm camera, input map |
| SETUP-0.4 | ASP.NET solution | `services/backend/Aumbrye.sln` — Api, Application, Domain, Infrastructure |
| SETUP-0.5 | Web stub | `apps/web/` — React + Vite + TS |
| API-0.1 | Health endpoint | `GET /api/v1/health` → `{ "status": "ok" }` + integration test |
| SCHEMA-0.1 | Schema + validator | `content/schemas/`, `scripts/validate-content/` (Node + Ajv) |
| SCHEMA-0.2 | Dungeon fixture | `content/fixtures/dungeon_definition_v1_minimal.json` |
| CI-0.1 | Workflow | `.github/workflows/ci.yml` — PR + push to `main` |
| CI-0.2 | Backend CI | restore, build, test (.NET 8) |
| CI-0.3 | Web CI | `npm ci` + `npm run build` |
| CI-0.4 | Content CI | `npm run validate` on fixtures |
| DOC-0.1 | Standards | `docs/CODING.md`, `docs/CONTENT_SCHEMA.md`, `docs/ADR/0001-...` |

### Packages wired

| Package | Path |
|---------|------|
| Shared contracts | `packages/shared/` |
| Procedural (stub) | `packages/procedural/` |

---

## Not implemented (deferred — out of M0 scope)

> These were explicitly excluded from M0. Do **not** treat as bugs.

| Area | Deferred item | Target phase |
|------|---------------|--------------|
| Backend | Auth middleware | M3 |
| Backend | Runs, generation, EF entities beyond health | M3 |
| Backend | Production cloud / Docker publish for API | M7 |
| Godot | Combat hitboxes, networking | M1+ |
| Godot | Headless / GdUnit CI | Optional (TEST system) |
| Web | Account UI, wiki, leaderboards, marketing | M4–M6 |
| Web | Cloudflare deploy | M6 |
| Content | Full content packs (enemies, items, biomes) | M1–M6 |
| Procedural | Dungeon generator implementation | M3 |
| CI | Release artifact pipeline | M7 (`CI-7.1`) |
| CI | Deploy pipelines | M7 |
| Docs | Full design bible | Never required for EA |
| Infra | Production Postgres/Redis provisioning | Post-EA ops |

### Repo folders present but empty (placeholders)

- `content/biomes/`, `content/enemies/`, `content/items/` — `.gitkeep` only
- `assets/` tree — not created yet (art pipeline M0+)
- `scripts/codegen/` — not created yet

---

## Major milestones

| Major | Title | Phase | Status |
|-------|-------|-------|--------|
| SETUP-0 | Monorepo + local stack | M0 | **done** |
| CI-0 | PR quality gates | M0 | **done** |
| CI-7 | Release artifacts | M7 | not started |

---

## Agent rules

- Never commit secrets; use `.env.example`.
- CI must fail on schema-invalid content.
- Prefer ubuntu-latest + official .NET/Node actions.
- Godot headless tests are optional until GdUnit is introduced (`TEST` system).
- Godot version: **4.7** (standard build, not .NET — GDScript only per DEC-E02).
