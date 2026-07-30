# M3 implementation log

> **Phase:** [M3-SERVER-GENERATION.md](../plan/phases/M3-SERVER-GENERATION.md)  
> **Depends on:** M2 closed — [M2_IMPLEMENTATION_LOG.md](M2_IMPLEMENTATION_LOG.md)  
> **Goal:** Backend owns dungeon generation; Godot plays server definitions; determinism proven.

**Started:** 2026-07-30  
**Closed:** 2026-07-30  
**Validated:** 2026-07-30 (114 Godot tests + C# CI — `./scripts/run-all-validation.ps1`)

---

## Status

| Milestone | Status | Notes |
|-----------|--------|-------|
| PROC-3.1 | ✅ | `SeededRandom` + `LayoutGraphGenerator` |
| PROC-3.2 | ✅ | `ConnectivityValidator` — entrance→boss, reject adjacent boss |
| PROC-3.3 | ✅ | `RoomTypeAssigner` — entrance/boss/secret/treasure/combat |
| PROC-3.4 | ✅ | `EnemyPlacer` — threat budget per tier/level |
| PROC-3.5 | ✅ | `LootPlacer` — loot/traps/boss/exit/secrets + deterministic `instanceId` per item |
| PROC-3.6 | ✅ | `CanonicalJsonSerializer` + `DungeonGenerator` with retry |
| AUTH-3.1 | ✅ | Register/login/refresh, BCrypt + JWT, refresh rotation, auth rate limiting |
| API-3.1 | ✅ | EF models + `InitialCreate` migration |
| API-3.2 | ✅ | `POST /runs`, `GET /runs/{id}/dungeon`, Redis/in-memory cache |
| API-3.3 | ✅ | `POST /runs/{id}/complete`, boss gate, loot id validation |
| NET-3.1 | ✅ | `api_client.gd` + `api_config.gd` autoload, 401 refresh retry |
| FLOW-3.1 | ✅ | `run_flow.gd` API path + fixture fallback; seed in debug overlay |
| SCHEMA-3.1 | ✅ | `packages/shared/openapi/aumbrye-api.v1.yaml` |
| SCHEMA-3.2 | ✅ | `VersionHeaderMiddleware` + client headers |
| TEST-3.1 | ✅ | 17 unit + 9 integration tests |

---

## Validation (2026-07-30)

| Check | Result |
|-------|--------|
| `dotnet test` (unit + integration) | **26/26 pass** |
| Content validator | **15 files OK** |
| Live API (Postgres + Redis) | health → register → create run → GET dungeon → complete run |
| Integration: cache hit on 2nd GET | generator called once only |
| Integration: unknown biome / escape w/o boss / unknown loot | all return 400 |
| DI fix (`DbContext` alias) | integration tests unblocked |

---

## Key paths

| Area | Path |
|------|------|
| Procedural pipeline | `packages/procedural/Generation/DungeonGenerator.cs` |
| Auth API | `services/backend/src/Aumbrye.Api/Endpoints/ApiEndpoints.cs` |
| OpenAPI | `packages/shared/openapi/aumbrye-api.v1.yaml` |
| Godot client | `apps/game/client/scripts/net/api_client.gd` |
| Migration | `services/backend/src/Aumbrye.Infrastructure/Persistence/Migrations/` |

---

## How to run

```bash
# Infrastructure
docker compose up -d

# API (http://localhost:5000)
cd services/backend
dotnet run --project src/Aumbrye.Api

# Apply DB schema (Postgres)
dotnet ef database update --project src/Aumbrye.Infrastructure --startup-project src/Aumbrye.Api

# Tests
dotnet test
```

**Godot E2E (offline):** `dotnet build tools/procgen-cli/ProcgenCli.csproj`, open Godot project, interact with castle portal. New runs and seed runs use `LocalProcgen` → `procgen-cli` (same C# library as server). No API required. Press F1 in castle run to see seed.

**Automated:** `./scripts/run-all-validation.ps1` — C# unit tests (35), content validation, and Godot in-engine suites (114 tests across 13 suites). See [VALIDATION_PLATFORM.md](VALIDATION_PLATFORM.md). Remaining human gates: [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) (M7 polish + carry-over).

---

## Security notes

- Production requires strong `Jwt:Secret` (validated at startup).
- Auth endpoints rate-limited (30 req/min per IP).
- Password length 8–128; email normalized and bounded.
- Refresh tokens hashed at rest; rotated on refresh.
- Version headers enforced on `/api/*` routes.
- Complete-run validates outcome, boss flag, elapsed time, and loot instance IDs against generated definition.

---

## Deferred (post-M3)

| Item | Target | Notes |
|------|--------|-------|
| Biome content schema | — | Done — `biome-definition.v1.json` |
| EF `Migrate()` in prod | M4+ | Dev/testing uses `EnsureCreated`; Postgres via `dotnet ef database update` |
| Gamepad playtest | M7 | See [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) — `TEST-M1-GPAD`, `M2.gamepad.full_loop` |
| External playtest | M7 | `SHIP-7.1` — [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) |
| Feel/UX manual gates | M7 | 17 items — [MANUAL_PLAYTEST_CHECKLIST.md](MANUAL_PLAYTEST_CHECKLIST.md) § M7 |
| Cross-machine seed parity | M7 | `M7.cross_machine.seed` |
| Procgen-cli missing UX | M7 | `M7.procgen_cli.missing_ux` |
| Offline no-hang (API down) | M7 | `M7.offline.no_hang` |
