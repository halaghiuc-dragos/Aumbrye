# Backend API

ASP.NET Core 8 Minimal API in `services/backend/`, four projects (`Api`, `Application`, `Domain`, `Infrastructure`) plus two test projects. Eleven routes under `/api/v1`, JWT bearer auth with rotating refresh tokens, EF Core over Postgres (SQLite in-memory for tests), Redis for the dungeon cache and leaderboards with in-process fallbacks. The Godot client never requires it: everything the API does is also done locally by the client (see [`local-save.md`](local-save.md) and [`local-procgen.md`](local-procgen.md)).

## Files

| Path | Role |
|------|------|
| `services/backend/Aumbrye.sln` | Solution, 6 projects |
| `src/Aumbrye.Api/Program.cs` | 84 lines. Host, auth, rate limiter, schema bootstrap, route mapping |
| `src/Aumbrye.Api/Endpoints/ApiEndpoints.cs` | 219 lines. `AuthEndpoints`, `RunsEndpoints`, `SavesEndpoints` |
| `src/Aumbrye.Api/Endpoints/LeaderboardsEndpoints.cs` | 58 lines. `LeaderboardsEndpoints` plus the `SubmitLeaderboardRequest` record |
| `src/Aumbrye.Api/Middleware/VersionHeaderMiddleware.cs` | Client/content version gate |
| `src/Aumbrye.Api/appsettings.json` | JWT and connection-string defaults |
| `src/Aumbrye.Api/appsettings.Testing.json` | `UseInMemoryStores` profile |
| `src/Aumbrye.Application/Abstractions/IApplicationServices.cs` | 102 lines. Every service interface and result record |
| `src/Aumbrye.Application/Services/AuthService.cs` | Register, login, refresh, token issue |
| `src/Aumbrye.Application/Services/RunService.cs` | Run create/fetch/complete plus `ProceduralDungeonGenerator` |
| `src/Aumbrye.Application/Services/SaveService.cs` | Save get/put with last-write conflict detection |
| `src/Aumbrye.Application/Services/CharacterStateService.cs` | `CharacterStateDefaults`, `TalentValidator`, `ProgressionApplier` |
| `src/Aumbrye.Application/Services/LeaderboardService.cs` | `ILeaderboardService` + in-memory implementation |
| `src/Aumbrye.Application/Services/LootInstanceIds.cs` | Parses claimable loot ids out of a dungeon definition |
| `src/Aumbrye.Domain/Entities/*.cs` | `Account`, `RefreshToken`, `Run`, `SaveBlob` |
| `src/Aumbrye.Infrastructure/DependencyInjection.cs` | Composition root, `ApplyDatabaseSchema()` |
| `src/Aumbrye.Infrastructure/Persistence/AumbryeDbContext.cs` | 46 lines, four entities |
| `src/Aumbrye.Infrastructure/Persistence/Migrations/20260730120000_InitialCreate.cs` | Hand-written migration, not wired up |
| `src/Aumbrye.Infrastructure/Caching/DungeonCache.cs` | `RedisDungeonCache` + `InMemoryDungeonCache` |
| `src/Aumbrye.Infrastructure/Caching/RedisLeaderboardService.cs` | Redis sorted-set leaderboard |
| `src/Aumbrye.Infrastructure/Security/AuthInfrastructure.cs` | `BcryptPasswordHasher`, `JwtTokenService` |
| `tests/Aumbrye.UnitTests/` | 16 files, 59 `[Fact]`/`[Theory]` methods |
| `tests/Aumbrye.IntegrationTests/` | 3 test files, 12 test methods, `WebApplicationFactory<Program>` |

Request and response DTOs live in `packages/shared/Contracts/` and are shared with the CLI and tests; see [`packages.md`](packages.md).

## How it works

### Startup — `Program.cs`

1. `useInMemory` is true when `UseInMemoryStores` config is set or the environment is `Testing` (`Program.cs:15-16`).
2. When not in-memory and `IsProduction()`, a `Jwt:Secret` containing the substring `dev-only` throws `InvalidOperationException` at startup (`Program.cs:19-24`). The check does not fire in Development or Staging.
3. `AddInfrastructure` registers everything (`Program.cs:26`).
4. The signing key is `Encoding.UTF8.GetBytes(jwtSecret.PadRight(32)[..32])` — exactly 32 bytes, right-padded with spaces if short and **truncated if longer** (`Program.cs:28`, same logic at `AuthInfrastructure.cs:26`).
5. JWT bearer validation: issuer, audience, lifetime, signing key, `ClockSkew` 1 minute (`Program.cs:33-43`).
6. One rate-limit policy, `"auth"`: fixed window, 30 permits per minute, queue 0, rejection 429 (`Program.cs:47-56`). No global limiter.
7. Schema bootstrap: `EnsureCreated()` in both branches (`Program.cs:60-69`, `DependencyInjection.cs:65-70`).
8. Middleware order: `VersionHeaderMiddleware`, rate limiter, authentication, authorization (`Program.cs:71-74`). No CORS, no HTTPS redirection, no exception handler, no static files.

`public partial class Program;` at `Program.cs:84` exists so `WebApplicationFactory<Program>` can bind.

### Version gate — `VersionHeaderMiddleware`

Applies to any path starting `/api`. If `X-Client-Version` is present and not equal to `ApiVersions.ExpectedClientVersion` (`"0.3.0"`, `packages/shared/Contracts/ApiVersions.cs:7`) the response is 426 with `{"error": "..."}`. If `X-Content-Version` is present and not `"1"` (`ApiVersions.cs:8`) the response is 400. Absent headers pass (`VersionHeaderMiddleware.cs:18,29`).

### Routes

Eleven routes. `Auth` requires none, `Runs` and `Saves` are `RequireAuthorization()` at group level, `Leaderboards` is anonymous for GET and authorized for POST.

| Method | Path | Auth | Request | Success | Failures | Evidence |
|--------|------|------|---------|---------|----------|----------|
| GET | `/api/v1/health` | none | — | 200 `HealthResponse{status}` | — | `Program.cs:76` |
| POST | `/api/v1/auth/register` | none, `auth` limiter | `RegisterRequest{email,password}` | 200 `AuthResponse` | 400 `{error}` | `ApiEndpoints.cs:19-25` |
| POST | `/api/v1/auth/login` | none, `auth` limiter | `LoginRequest{email,password}` | 200 `AuthResponse` | 401 `{error}` | `ApiEndpoints.cs:27-33` |
| POST | `/api/v1/auth/refresh` | none, `auth` limiter | `RefreshRequest{refreshToken}` | 200 `AuthResponse` | 401 `{error}` | `ApiEndpoints.cs:35-41` |
| POST | `/api/v1/runs` | JWT | `CreateRunRequest{biomeId,seed?,tier}` | 200 `CreateRunResponse{runId,seed,biomeId,definitionJson}` | 400 `{error}`, 401, 500 `{error}` | `ApiEndpoints.cs:59-86` |
| GET | `/api/v1/runs/{id:guid}/dungeon` | JWT | — | 200 raw `application/json` definition | 401, 404 empty | `ApiEndpoints.cs:88-101` |
| POST | `/api/v1/runs/{id:guid}/complete` | JWT | `CompleteRunRequest{outcome,elapsedSeconds,bossDefeated,lootClaimedInstanceIds?}` | 200 `CompleteRunResponse{runId,status,progression?}` | 400 `{error}`, 401 | `ApiEndpoints.cs:103-138` |
| GET | `/api/v1/saves/current` | JWT | — | 200 `SaveResponse{stateJson,updatedAt}` | 400 `{error}`, 401 | `ApiEndpoints.cs:156-169` |
| PUT | `/api/v1/saves/current` | JWT | `PutSaveRequest{stateJson,clientUpdatedAt?}` | 200 `PutSaveResponse{updatedAt,conflict}` | 400 `{error}`, 401, 409 `{error,state,updatedAt}` | `ApiEndpoints.cs:171-209` |
| GET | `/api/v1/leaderboards` | none | query `biomeId?`, `tier?`, `limit?` | 200 `{biomeId,tier,entries[]}` | — | `LeaderboardsEndpoints.cs:11-33` |
| POST | `/api/v1/leaderboards/submit` | JWT | `SubmitLeaderboardRequest{biomeId,tier,elapsedSeconds,optIn}` | 200 `{submitted:true}` or `{submitted:false,reason:"opt_out"}` | 401 | `LeaderboardsEndpoints.cs:35-48` |

The `SaveResponse` field is `stateJson` (`packages/shared/Contracts/Saves/SaveContracts.cs:4`) and it carries the character state re-serialized as a **string**, not as a nested object (`ApiEndpoints.cs:167-168`). The 409 conflict body is an anonymous object whose `state` field is also a string (`ApiEndpoints.cs:197-202`), and it does not use the `PutSaveResponse.Conflict` flag that `SaveContracts.cs:13` declares.

Both leaderboard responses are anonymous objects with no shared contract type. `SubmitLeaderboardRequest` is declared in the API project rather than in `packages/shared` (`LeaderboardsEndpoints.cs:54-58`).

Every endpoint is implemented. Nothing returns 501 or a hardcoded fixture. There are no stub routes.

### Auth flow

`AuthService.RegisterAsync` lowercases and trims the email, requires an `@` and length under 256, requires an 8-128 character password, rejects duplicates, and creates the account **with a default `SaveBlob`** built by `CharacterStateDefaults.Create` (`AuthService.cs:23-49`). Passwords use BCrypt work factor 11 (`AuthInfrastructure.cs:9`).

`IssueTokensAsync` mints a 15-minute JWT with `NameIdentifier` and `Email` claims (`AuthInfrastructure.cs:31-50`, lifetime from `Jwt:AccessTokenMinutes`, default 15 at `AuthInfrastructure.cs:27-28`), and a 64-byte base64 refresh token stored only as a lowercase SHA-256 hex hash with a 30-day expiry (`AuthService.cs:79-86`, `AuthInfrastructure.cs:52-58`).

`RefreshAsync` looks the token up by hash, rejects it unless `IsActive` (`RefreshToken.cs:12`: not revoked and not expired), **revokes it**, and issues a fresh pair (`AuthService.cs:61-73`). That is rotation. There is no reuse-detection family revocation, no logout endpoint, and no cleanup job for expired rows.

The default account state (`CharacterStateService.cs:11-46`) is `schemaVersion` 1, character `Wanderer` level 1, gold 0, a 6x4 inventory holding one `castle_sword` equipped in the weapon slot, and empty `itemInstances`, `talents`, `flags`, `recipes`, `runRelics`.

### Run lifecycle

`CreateRunAsync` (`RunService.cs:26-87`):
- loads the account with its save blob, 400 if missing;
- rejects unknown biomes via `BiomeCatalog.TryGet`, tiers outside 1-10, and seeds below 1;
- reads `character.level` out of the save for `playerLevel`, default 1;
- picks `baseSeed = seed ?? RandomNumberGenerator.GetInt32(1, int.MaxValue)`;
- derives `generationSeed = DungeonSeedDeriver.GenerationSeed(baseSeed, tier, 1)` and generates with it (`RunService.cs:56,63`);
- persists the `Run` row with the **base** seed and the definition checksum, then caches the definition JSON for 24 hours (`RunService.cs:17,70-84`);
- returns the base seed and the full definition JSON inline.

`GetDungeonDefinitionAsync` reads the cache, and on a miss re-derives with `GenerationSeed(run.Seed, run.Tier, 1)` and re-caches (`RunService.cs:96-108`). This matches creation.

`CompleteRunAsync` (`RunService.cs:111-210`) validates in order: run exists and belongs to the caller; not already completed; outcome is one of `escaped`/`died`/`abandoned`; `escaped` requires `bossDefeated`; elapsed seconds in `[0, 86400]`; at most 64 loot claims; no duplicate ids under `StringComparer.Ordinal`; `escaped` requires at least 5 seconds; every id parses as a GUID; every id appears in the definition's loot map. It then applies progression, re-validates talents, writes the save blob, and marks the run `Completed`.

On a cache miss it regenerates with `run.Seed` — the **base** seed, not `GenerationSeed(...)` (`RunService.cs:152-157`). That is a different dungeon than the one the player played.

`LootInstanceIds.ParseLoot` walks `placements.loot[].items[]` collecting `instanceId -> (itemId, quantity)` into an `OrdinalIgnoreCase` dictionary (`LootInstanceIds.cs:8-40`). The file declares no namespace (`LootInstanceIds.cs:3`).

`ProgressionApplier.ApplyRunOutcome` (`CharacterStateService.cs:89-146`) computes `runXp = BaseXpPerRun + (tier-1) * TierXpBonus` scaled by 1.0 / `DeathXpFraction` / `AbandonedXpFraction`, updates `character.xp` and `character.level` from the XP curve, grants loot only when `escaped`, clears `activeRun`, wipes `runRelics` on death or abandon, and returns the talent points earned plus a human-readable economy note. Equipment loot is rolled deterministically by `AffixRoller.Roll(instanceId, itemId)` and written into `itemInstances` plus a new inventory slot; stackables merge into an existing non-instanced slot (`CharacterStateService.cs:148-222`).

`TalentValidator.ValidateTalents` rejects unknown nodes, negative ranks, ranks above `MaxRank`, unmet `Requires` prerequisites, and total spend above `TalentPointsForLevel(level, tree.TalentPointsPerLevel)` (`CharacterStateService.cs:51-84`). It runs on both `PUT /saves/current` and run completion.

`Run.Status` never becomes `RunStatus.Abandoned`; the enum value at `Run.cs:7` is declared and never assigned anywhere in the solution, because the `abandoned` outcome still sets `Completed` (`RunService.cs:205`).

### Saves

`GetCurrentAsync` returns the stored blob, or a freshly built default state stamped with `UtcNow` when the account has no blob (`SaveService.cs:23-27`). `PutCurrentAsync` force-overwrites `accountId` and `schemaVersion` on the incoming state, validates talents, then compares `SaveBlob.UpdatedAt` against the caller's `clientUpdatedAt`: if the server row is newer it returns a conflict carrying the server state and the server wins (`SaveService.cs:45-63`). Unparseable stored JSON silently falls back to defaults (`SaveService.cs:86-99`).

### Persistence

`AumbryeDbContext` maps four entities (`AumbryeDbContext.cs:10-13`) with a unique index on `Account.Email`, an index on `RefreshToken.TokenHash`, a composite index on `(Run.AccountId, Run.Status)`, and `SaveBlob` keyed by `AccountId` in a one-to-one with `Account` (`AumbryeDbContext.cs:17-44`).

Schema creation is `db.Database.EnsureCreated()` (`DependencyInjection.cs:69`, `Program.cs:64`). The migration at `Persistence/Migrations/20260730120000_InitialCreate.cs` is a correct hand-written Postgres schema — it even types `SaveBlobs.JsonData` as `jsonb` (`20260730120000_InitialCreate.cs:79`), which `EnsureCreated` does not do — but it carries no `[Migration]` attribute, there is no `AumbryeDbContextModelSnapshot`, and `Aumbrye.Infrastructure.csproj:10-18` does not reference `Microsoft.EntityFrameworkCore.Design`. The `dotnet ef database update` command in its own doc comment (`20260730120000_InitialCreate.cs:9`) cannot run.

### Caching and leaderboards

`AddInfrastructure` picks implementations by mode (`DependencyInjection.cs:21-53`):

| Mode | DbContext | Dungeon cache | Leaderboard |
|------|-----------|---------------|-------------|
| `useInMemoryStores` | SQLite `:memory:` shared, singleton open connection | `InMemoryDungeonCache` | `InMemoryLeaderboardService` |
| Redis connection string set | Npgsql | `RedisDungeonCache` | `RedisLeaderboardService` |
| Redis connection string empty | Npgsql | `InMemoryDungeonCache` | `InMemoryLeaderboardService` |

`RedisDungeonCache` catches `RedisException` on both get and set and falls back to a per-process `ConcurrentDictionary` (`DungeonCache.cs:24-29,44-50`), so a Redis outage degrades rather than fails. Key format `dungeon:{runId:N}`.

`RedisLeaderboardService` stores a sorted set per `leaderboard:{biomeId}:tier{tier}` with member `"{accountId:N}|{unixSeconds}"` scored by elapsed seconds (`RedisLeaderboardService.cs:12-18`). On read it parses the account id out of the member but discards the timestamp and returns `DateTimeOffset.UtcNow` as `SubmittedAt` (`RedisLeaderboardService.cs:37`). `DisplayName` is the first eight characters of the account GUID in both implementations (`LeaderboardService.cs:30`, `RedisLeaderboardService.cs:33`); no display name is stored on `Account`.

`InMemoryLeaderboardService` keeps a `static readonly List<LeaderboardEntry>` guarded by a static lock (`LeaderboardService.cs:21-22`) — process-global, unbounded, and shared across every DI scope and across xUnit test classes in the same assembly.

### Tests

71 test methods total. `dotnet test Aumbrye.sln` runs them in CI (`.github/workflows/ci.yml:28`).

| Project | Files | Covers |
|---------|-------|--------|
| `Aumbrye.UnitTests` | 16 | Dungeon generation, seed derivation, seed reproducibility, layout graph, final floor, M5 biomes, theme loot tables, affix rolling, XP curve, run economy, talent validation, biome catalog, content catalog, procgen CLI, assembly shape |
| `Aumbrye.IntegrationTests` | 3 | Health, register/login/refresh, 426 version gate, create-run/get-dungeon/complete-run flow, unknown biome, escape without boss, double completion, dungeon cache hit counting, unknown loot id, save round trip, illegal talents, stale-client conflict |

`AumbryeWebApplicationFactory` sets environment `Testing` and swaps `IDungeonGenerator` for `CountingDungeonGenerator` (`AuthAndRunsTests.cs:16-27`), which is how the cache-hit assertions at `AuthAndRunsTests.cs:186-194` verify the generator is called exactly once per run.

Not covered by any test: CORS, leaderboard endpoints over HTTP, refresh-token revocation and reuse, the rate limiter, `EnsureCreated` against Postgres, the migration file, expired-cache run completion, and case-variant loot ids.

## Absent

- **CORS.** No `AddCors`, `UseCors`, or `Cors` string anywhere under `services/backend`. The React site at a different origin cannot call the API from a browser.
- **Dockerfile.** No `Dockerfile` exists anywhere in the repository, though `.github/workflows/release.yml:18` builds `services/backend/Dockerfile`.
- **Steam auth-ticket exchange.** No route, service, or configuration mentions Steam. A case-insensitive search for `steam` across `services/backend/**/*.cs` returns nothing. See [`platform-and-net.md`](platform-and-net.md).
- **Multiplayer, co-op, or dedicated-server code.** A repo-wide case-insensitive search for `multiplayer`, `dedicated_server`, `ENetMultiplayer`, `MultiplayerAPI`, `rpc(`, and `co-op` matches only prose in `docs/`. No `.cs`, `.gd`, `.ts`, or `.tscn` file matches.
- **OpenAPI/Swagger UI.** `AddEndpointsApiExplorer()` is called (`Program.cs:46`) but no `AddSwaggerGen`, `UseSwagger`, or `MapOpenApi` follows. The spec at `packages/shared/openapi/aumbrye-api.v1.yaml` is maintained by hand.
- **Health checks with dependencies.** `GET /api/v1/health` returns a constant. No `AddHealthChecks`, no DB or Redis probe.
- **Logout, token revocation, account deletion, password reset, email verification.** No route for any of them.
- **Global exception handling.** Only `POST /api/v1/runs` has a try/catch (`ApiEndpoints.cs:65-85`). No `UseExceptionHandler`, no `ProblemDetails`.
- **Structured logging or telemetry.** No Serilog, no OpenTelemetry, one ad-hoc `ILogger` at `ApiEndpoints.cs:57`.
- **Multi-floor runs.** `IDungeonGenerator.Generate` takes `floorIndex` and `isFinalFloor` (`IApplicationServices.cs:100-101`) but every call site passes the defaults 1 and false (`RunService.cs:63,101-106,152-157`).

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| API-01 | P0 | No CORS policy. A browser on any other origin is blocked, which disables the entire website account and leaderboard flow. | No `Cors` match under `services/backend`; `Program.cs:71-74` |
| API-02 | P0 | Schema is created by `EnsureCreated()`, so the hand-written migration never runs and no schema change can ever be applied to an existing database. `Microsoft.EntityFrameworkCore.Design` is not referenced, so `dotnet ef` cannot generate one either. | `DependencyInjection.cs:69`, `Program.cs:64`, `20260730120000_InitialCreate.cs:11` (no `[Migration]`), `Aumbrye.Infrastructure.csproj:10-18` |
| API-03 | P0 | `CompleteRunAsync` regenerates the definition from the **base** seed on a cache miss while creation and fetch use the **derived** seed. After the 24-hour TTL, every valid loot claim is rejected as unknown. | `RunService.cs:152-157` vs `RunService.cs:56,100` |
| API-04 | P0 | Loot duplicate detection is `StringComparer.Ordinal` but the loot map is `OrdinalIgnoreCase`, so `"AB-..."` and `"ab-..."` both pass and both grant the same item. | `RunService.cs:136` vs `LootInstanceIds.cs:10` |
| API-05 | P1 | The default JWT secret is committed and the guard only fires in `IsProduction()`. Any Development or Staging deployment signs tokens with a public constant. | `appsettings.json:13`, `Program.cs:19-24` |
| API-06 | P1 | The signing key is padded or truncated to exactly 32 bytes, so a 64-character secret silently uses only its first 32 characters. | `Program.cs:28`, `AuthInfrastructure.cs:26` |
| API-07 | P1 | `POST /leaderboards/submit` accepts any time for any biome and tier with no reference to a completed run. Any authenticated account can post a one-second world record. | `LeaderboardsEndpoints.cs:35-48` |
| API-08 | P1 | Leaderboard display names are the first 8 hex characters of the account GUID. There is no display-name column on `Account`. | `LeaderboardService.cs:30`, `RedisLeaderboardService.cs:33`, `Account.cs:3-12` |
| API-09 | P1 | `RedisLeaderboardService` encodes the submission timestamp into the member string then throws it away on read and returns `UtcNow`. | `RedisLeaderboardService.cs:17` vs `:37` |
| API-10 | P1 | Leaderboard endpoints are absent from the OpenAPI spec and their responses are untyped anonymous objects; `SubmitLeaderboardRequest` lives in the API project instead of `packages/shared`. | `LeaderboardsEndpoints.cs:21-32,54-58`; `packages/shared/openapi/aumbrye-api.v1.yaml` has no `/leaderboards` path |
| API-11 | P1 | Rate limiting covers only the three auth routes. `POST /runs` triggers a full dungeon generation and is unlimited. | `Program.cs:47-56`; no `RequireRateLimiting` outside `ApiEndpoints.cs:25,33,41` |
| API-12 | P1 | No global exception handler. An unhandled exception in any endpoint except `POST /runs` returns the framework's raw response. | `Program.cs:71-74`; try/catch only at `ApiEndpoints.cs:65-85` |
| API-13 | P1 | No HTTPS redirection, HSTS, or forwarded-headers middleware, so a reverse-proxy deployment cannot see the real scheme or client IP. | `Program.cs:71-74` |
| API-14 | P1 | Refresh tokens rotate but there is no reuse detection, no logout or revoke route, and no cleanup of expired rows. `RefreshTokens` grows forever. | `AuthService.cs:61-73`; no delete or revoke endpoint |
| API-15 | P2 | `RunStatus.Abandoned` is declared and never assigned; an abandoned run is stored as `Completed`. | `Run.cs:7`, `RunService.cs:205` |
| API-16 | P2 | `InMemoryLeaderboardService` holds process-global static mutable state that is unbounded and shared across DI scopes and test classes. | `LeaderboardService.cs:21-22` |
| API-17 | P2 | `GET /health` returns a constant and never probes Postgres or Redis, so an orchestrator sees a healthy pod with a dead database. | `Program.cs:76` |
| API-18 | P2 | `AddEndpointsApiExplorer()` is registered but nothing consumes it — no Swagger UI, no generated spec. The OpenAPI file is hand-maintained and already drifted. | `Program.cs:46`; see [`packages.md`](packages.md) |
| API-19 | P2 | `LootInstanceIds` is declared in the global namespace. | `LootInstanceIds.cs:3` |
| API-20 | P2 | `GetAccountId(ClaimsPrincipal)` is copy-pasted in three places instead of being one extension. | `ApiEndpoints.cs:143-147`, `ApiEndpoints.cs:214-218`, `LeaderboardsEndpoints.cs:41-43` |
| API-21 | P2 | `PutSaveResponse.Conflict` is declared but never set; the 409 path returns an anonymous object instead. | `packages/shared/Contracts/Saves/SaveContracts.cs:13` vs `ApiEndpoints.cs:197-208` |
| API-22 | P2 | No account deletion or data export route, so there is no way to satisfy a deletion request. | No `MapDelete` anywhere under `services/backend` |
| API-23 | P2 | No structured logging or telemetry; a single ad-hoc logger exists on one endpoint group. | `ApiEndpoints.cs:57` |
| API-24 | P2 | Server-side runs are single-floor only: `floorIndex` and `isFinalFloor` are never passed anything but their defaults. | `IApplicationServices.cs:100-101` vs `RunService.cs:63,101-106,152-157` |

## Related

- Improvement plan: [`../actual_improvements/backend-api.md`](../actual_improvements/backend-api.md)
- [`packages.md`](packages.md) — the shared DTOs and the OpenAPI spec
- [`website-and-backend.md`](website-and-backend.md) — CORS, `VITE_API_URL`, docker-compose
- [`networking.md`](networking.md) — the Godot client's view of these routes
- [`ci-cd.md`](ci-cd.md) — where `dotnet test` runs and where the Dockerfile is expected
- [`local-save.md`](local-save.md), [`local-procgen.md`](local-procgen.md) — the offline equivalents
