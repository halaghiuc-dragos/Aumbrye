# Backend API

ASP.NET Core 8 Minimal API in `services/backend/`, four projects (`Api`, `Application`, `Domain`, `Infrastructure`) plus two test projects. Seventeen routes under `/api/v1`, JWT bearer auth with rotating refresh tokens and family revocation, EF Core migrations over Postgres (SQLite in-memory for tests), Redis for dungeon cache and leaderboards with in-process fallbacks. The Godot client never requires the API: everything the API does is also done locally (see [`local-save.md`](local-save.md) and [`local-procgen.md`](local-procgen.md)).

## Files

| Path | Role |
|------|------|
| `services/backend/Aumbrye.sln` | Solution, 6 projects |
| `src/Aumbrye.Api/Program.cs` | Host, CORS, auth, rate limiter, health, OpenTelemetry, schema bootstrap, route mapping |
| `src/Aumbrye.Api/Endpoints/ApiEndpoints.cs` | `AuthEndpoints`, `RunsEndpoints`, `SavesEndpoints`, `AccountEndpoints` |
| `src/Aumbrye.Api/Endpoints/LeaderboardsEndpoints.cs` | Leaderboard GET/submit |
| `src/Aumbrye.Api/Endpoints/TelemetryEndpoints.cs` | Crash report ingestion |
| `src/Aumbrye.Api/Auth/ClaimsPrincipalExtensions.cs` | `ClaimsPrincipal.AccountId()` |
| `src/Aumbrye.Api/ProblemResults.cs` | RFC 7807 `Results.Problem` helpers |
| `src/Aumbrye.Api/Middleware/VersionHeaderMiddleware.cs` | Client/content version gate; OPTIONS bypass |
| `src/Aumbrye.Infrastructure/Security/JwtSigningKey.cs` | Base64 JWT secret validation (32-byte minimum) |
| `src/Aumbrye.Infrastructure/Hosted/RefreshTokenCleanupService.cs` | Hourly expired-token purge |
| `src/Aumbrye.Infrastructure/Persistence/Migrations/` | `InitialCreate`, `AddRunLootIds`, `AddAccountDisplayNameAndTokenFamily` |
| `src/Aumbrye.Application/Services/RunService.cs` | Run lifecycle; persists `LootInstanceIdsJson` |
| `src/Aumbrye.Application/Services/LeaderboardService.cs` | Run-derived submission; `ILeaderboardStore` |
| `src/Aumbrye.Application/Services/LootInstanceIds.cs` | `Aumbrye.Application.Services` namespace |
| `packages/shared/Contracts/ApiVersions.cs` | `ExpectedClientVersion` = `"0.4.0"` |
| `packages/shared/openapi/aumbrye-api.v1.yaml` | Committed OpenAPI spec (drift-checked in CI) |

## How it works

### Startup â€” `Program.cs`

1. `useInMemory` when `UseInMemoryStores` or environment `Testing` (`Program.cs`).
2. `JwtSigningKey.FromConfiguration` throws when `Jwt:Secret` is missing or under 32 decoded bytes outside in-memory mode (`JwtSigningKey.cs`).
3. Named CORS policy `"web"` from `Cors:AllowedOrigins`; `UseCors` after `VersionHeaderMiddleware`, before rate limiter.
4. Rate limits: `auth` (30/min), `runs` (10/min/account), `saves` (60/min/account), `public` (120/min/IP); global concurrency 200.
5. Postgres: `ApplyDatabaseSchema()` calls `Migrate()`. In-memory: `EnsureCreated()` only.
6. `UseForwardedHeaders`, `UseHsts`, `UseHttpsRedirection` outside Development; `UseExceptionHandler` + `AddProblemDetails`.
7. Health: `GET /api/v1/health` (liveness); `GET /api/v1/health/ready` (NpgSql + Redis when not in-memory).
8. OpenTelemetry OTLP export when `OTEL_EXPORTER_OTLP_ENDPOINT` is set.
9. Swagger UI outside Production.

### Routes

| Method | Path | Auth | Notes |
|--------|------|------|-------|
| GET | `/api/v1/health` | none | Liveness |
| GET | `/api/v1/health/ready` | none | Readiness (503 when deps down) |
| POST | `/api/v1/auth/register` | none, `auth` | |
| POST | `/api/v1/auth/login` | none, `auth` | |
| POST | `/api/v1/auth/refresh` | none, `auth` | Family reuse detection |
| POST | `/api/v1/auth/logout` | JWT, `auth` | Revokes presented refresh token |
| POST | `/api/v1/runs` | JWT, `runs` | Persists loot id set on run row |
| GET | `/api/v1/runs/{id}/dungeon` | JWT, `runs` | |
| POST | `/api/v1/runs/{id}/complete` | JWT, `runs` | Validates loot against `LootInstanceIdsJson` |
| GET | `/api/v1/saves/current` | JWT, `saves` | |
| PUT | `/api/v1/saves/current` | JWT, `saves` | 409 returns `PutSaveResponse` with `serverStateJson` |
| GET | `/api/v1/leaderboards` | none, `public` | `limit` capped at 100 |
| POST | `/api/v1/leaderboards/submit` | JWT | Body `{runId, optIn}`; derives time from completed run |
| PUT | `/api/v1/account/display-name` | JWT | Max 32 chars, unique |
| DELETE | `/api/v1/account` | JWT | Cascades tokens, runs, save |
| GET | `/api/v1/account/export` | JWT | Full account JSON export |
| POST | `/api/v1/telemetry/crash` | optional | Crash report log |

Errors use RFC 7807 `ProblemDetails` (`application/problem+json`). Client version `0.4.0` required when `X-Client-Version` header is sent.

### Run lifecycle

`CreateRunAsync` derives `generationSeed`, generates dungeon, serializes claimable loot ids to `Run.LootInstanceIdsJson`, caches definition 24h.

`CompleteRunAsync` validates duplicate loot ids with `OrdinalIgnoreCase`, checks ids against persisted column (not regenerated dungeon), sets `RunStatus.Abandoned` for abandoned outcomes.

### Leaderboards

`SubmitFromRunAsync` reads elapsed time from `Run.CompletedAt - Run.CreatedAt`, display name from `Account.DisplayName`. Redis member format: `{accountId:N}|{unixSeconds}|{displayName}` via `LeaderboardMemberFormat`.

### Auth

Refresh rotation sets `ReplacedByTokenHash`; presenting a revoked token revokes the entire `FamilyId`. `RefreshTokenCleanupService` deletes tokens expired more than 7 days ago, hourly.

## Tests

Integration tests cover CORS, run completion after cache eviction, case-variant loot, abandoned status, leaderboard submission rules, logout, token-family revocation, rate limits, ProblemDetails, account delete, and migrations registration. Unit tests cover JWT secret validation and leaderboard member round-trip.

Run: `dotnet test services/backend/Aumbrye.sln`

## Related

- Improvement plan: [`../actual_improvements/backend-api.md`](../actual_improvements/backend-api.md) - **FINISHED**
- [`packages.md`](packages.md) â€” shared DTOs and OpenAPI spec
- [`networking.md`](networking.md) â€” Godot client contract
