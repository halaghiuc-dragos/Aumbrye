# Backend API — improvement plan

## Current state

Eleven routes, all implemented, backed by EF Core and Redis with in-process fallbacks, covered by 71 tests (see [`../existing_codebase/backend-api.md`](../existing_codebase/backend-api.md)). The architecture is sound; the defects are in deployment readiness and in two seed/comparison bugs that only fire after the 24-hour dungeon cache expires. Four issues are P0: no CORS at all, schema managed by `EnsureCreated()` with a dead migration, a seed mismatch in run completion, and a case-sensitivity mismatch that lets one loot drop be claimed twice.

The Godot client must remain fully playable with the API down. Nothing in this plan makes any client path depend on a server response; see [`networking.md`](networking.md).

## Gaps

Carried from [`../existing_codebase/backend-api.md`](../existing_codebase/backend-api.md): API-01 through API-24.

## Target design

### 1. CORS (API-01)

Named policy driven by configuration, applied before authentication:

```csharp
var allowedOrigins = builder.Configuration.GetSection("Cors:AllowedOrigins").Get<string[]>()
                     ?? ["http://localhost:5173"];
builder.Services.AddCors(options =>
    options.AddPolicy("web", policy => policy
        .WithOrigins(allowedOrigins)
        .WithMethods("GET", "POST", "PUT", "OPTIONS")
        .WithHeaders("Authorization", "Content-Type",
                     ApiVersions.ClientVersionHeader, ApiVersions.ContentVersionHeader)
        .WithExposedHeaders(ApiVersions.ClientVersionHeader)
        .AllowCredentials()
        .SetPreflightMaxAge(TimeSpan.FromHours(1))));
```

`app.UseCors("web")` goes immediately after `UseMiddleware<VersionHeaderMiddleware>()` and before `UseRateLimiter()`. `appsettings.json` gets `"Cors": { "AllowedOrigins": ["http://localhost:5173"] }`; production overrides via `Cors__AllowedOrigins__0`. `AllowAnyOrigin` is rejected: it is incompatible with `AllowCredentials` and this API carries bearer tokens.

`VersionHeaderMiddleware` must skip `OPTIONS` requests, otherwise a preflight carrying no version headers is fine but a preflight is answered before CORS headers are attached. Add `if (HttpMethods.IsOptions(context.Request.Method)) { await _next(context); return; }` as the first line of `InvokeAsync`.

### 2. EF Core migrations (API-02)

- Add `<PackageReference Include="Microsoft.EntityFrameworkCore.Design" Version="8.0.11" />` to `Aumbrye.Infrastructure.csproj`.
- Add a design-time factory so `dotnet ef` does not need to boot the whole host:

```csharp
public sealed class AumbryeDbContextFactory : IDesignTimeDbContextFactory<AumbryeDbContext>
{
    public AumbryeDbContext CreateDbContext(string[] args) =>
        new(new DbContextOptionsBuilder<AumbryeDbContext>()
            .UseNpgsql(Environment.GetEnvironmentVariable("ConnectionStrings__DefaultConnection")
                       ?? "Host=localhost;Port=5432;Database=aumbrye;Username=aumbrye;Password=aumbrye_dev")
            .Options);
}
```

- Delete the hand-written `20260730120000_InitialCreate.cs` and regenerate: `dotnet ef migrations add InitialCreate --project src/Aumbrye.Infrastructure --startup-project src/Aumbrye.Api --output-dir Persistence/Migrations`. Verify the generated `Up` still types `SaveBlobs.JsonData` as `jsonb`; if not, add `.HasColumnType("jsonb")` to the `SaveBlob.JsonData` mapping in `OnModelCreating` and regenerate.
- Replace `ApplyDatabaseSchema()`'s `EnsureCreated()` with `db.Database.Migrate()`, and keep `EnsureCreated()` only on the `useInMemoryStores` SQLite path where migrations do not apply.
- Add `AumbryeDbContextModelSnapshot.cs` (generated) to source control.

Rejected alternative: keeping `EnsureCreated()` and adding an idempotent SQL script. It works exactly once and gives no rollback path.

### 3. Seed and loot correctness (API-03, API-04)

Extract the derivation so it cannot drift again:

```csharp
private static int GenerationSeedFor(Run run) =>
    DungeonSeedDeriver.GenerationSeed(run.Seed, run.Tier, 1);
```

Call it from `GetDungeonDefinitionAsync` and from the `CompleteRunAsync` cache-miss branch. Change the duplicate check at `RunService.cs:136` to `StringComparer.OrdinalIgnoreCase` so it matches the loot map's comparer at `LootInstanceIds.cs:10`.

Better still, remove the cache-miss regeneration path from completion entirely and persist the loot id set on the `Run` row at creation time. Add `Run.LootInstanceIdsJson` (Postgres `jsonb`, nullable) populated from `LootInstanceIds.ParseLoot` in `CreateRunAsync`. Completion then validates against durable state instead of a regenerated dungeon, and cache expiry stops being a correctness boundary. This is the recommended path; it requires a migration (`AddRunLootIds`).

### 4. Verified leaderboard submissions (API-07, API-08, API-09, API-10, API-16)

Replace the free-form submit route with one derived from a completed run.

```
POST /api/v1/leaderboards/submit
Auth: Bearer (required)
Body: { "runId": "<guid>", "optIn": true }
200:  { "submitted": true, "rank": 14 }
200:  { "submitted": false, "reason": "opt_out" }
400:  { "error": "Run is not completed." }
403:  { "error": "Run belongs to another account." }
404:  { "error": "Run not found." }
```

The service reads `Run.CompletedAt - Run.CreatedAt` and `Run.BiomeId`/`Run.Tier` from the database. The client no longer supplies a time. `SubmitLeaderboardRequest` and a new `LeaderboardResponse`/`LeaderboardEntryResponse` move to `packages/shared/Contracts/Leaderboards/LeaderboardContracts.cs`, and both leaderboard endpoints return those typed records instead of anonymous objects.

```
GET /api/v1/leaderboards?biomeId=forgotten_castle&tier=1&limit=10
Auth: none. Rate limited by the "public" policy.
200: { "biomeId": "...", "tier": 1,
       "entries": [ { "accountId": "...", "displayName": "...",
                      "elapsedSeconds": 214.5, "submittedAt": "2026-08-05T12:00:00Z" } ] }
400: { "error": "limit must be between 1 and 100." }
```

Add `Account.DisplayName` (max length 32, unique index, defaulted at registration to `"Wanderer-" + accountId.ToString("N")[..6]`) and a `PUT /api/v1/account/display-name` route so the leaderboard shows a real name. Store it in the Redis member as `"{accountId:N}|{unixSeconds}|{displayName}"` and parse all three parts on read, so `SubmittedAt` stops being fabricated. Cap `limit` at 100.

Replace the static fields in `InMemoryLeaderboardService` with instance fields on a registered singleton, and cap retention at 1000 entries per key.

### 5. Security hardening (API-05, API-06, API-11, API-13, API-14)

- Drop `Secret` from `appsettings.json` entirely and make the guard unconditional outside `useInMemoryStores`: throw when `Jwt:Secret` is missing or shorter than 32 characters, in every environment. Document `Jwt__Secret` in `.env.example`.
- Replace the pad-and-truncate at `Program.cs:28` and `AuthInfrastructure.cs:26` with `Convert.FromBase64String(secret)` requiring at least 32 decoded bytes, and generate secrets with `openssl rand -base64 48`. Truncation of a long secret is silent key weakening.
- Add rate-limit policies alongside `"auth"`: `"runs"` (10 per minute per authenticated account, partitioned on the `NameIdentifier` claim, `QueueLimit` 0), `"saves"` (60 per minute per account), `"public"` (120 per minute per remote IP). Attach `RequireRateLimiting("runs")` to the runs group, `"saves"` to the saves group, `"public"` to `GET /leaderboards`. Add a global concurrency limiter of 200.
- Add `app.UseForwardedHeaders(new ForwardedHeadersOptions { ForwardedHeaders = ForwardedHeaders.XForwardedFor | ForwardedHeaders.XForwardedProto })` as the very first middleware, plus `UseHsts()` and `UseHttpsRedirection()` outside Development. Without forwarded headers the IP-partitioned limiter sees only the proxy address.
- Add `POST /api/v1/auth/logout` (auth required, body `{ "refreshToken": "..." }`, 204) that revokes the presented token, and refresh-token reuse detection: give `RefreshToken` a `FamilyId` and a `ReplacedByTokenHash`; presenting an already-revoked token revokes the entire family and returns 401. Add a hosted `RefreshTokenCleanupService` deleting rows where `ExpiresAt < UtcNow - 7 days`, running hourly.

### 6. Operability (API-12, API-17, API-23)

- `builder.Services.AddProblemDetails()` plus `app.UseExceptionHandler()` outside Development, so every unhandled exception becomes RFC 7807 with a trace id. Then delete the one-off try/catch at `ApiEndpoints.cs:65-85` and return the same shape everywhere.
- Standardize every error body on `ProblemDetails` rather than `{ "error": "..." }`. This is a breaking change for `apps/web/src/api/client.ts` and `apps/game/client/scripts/net/api_client.gd`; land it together with the changes in [`website-and-backend.md`](website-and-backend.md) and [`networking.md`](networking.md), and bump `ApiVersions.ExpectedClientVersion` to `0.4.0`.
- Health checks:

```
GET /api/v1/health          -> 200 { "status": "ok" }            (unchanged, liveness)
GET /api/v1/health/ready    -> 200 { "status": "Healthy", "checks": [...] } | 503
```

Register `AddHealthChecks().AddNpgSql(conn, name: "postgres").AddRedis(redisConn, name: "redis")` (skip both when `useInMemoryStores`) and map readiness with `RequireHost` left open so the container `HEALTHCHECK` from [`ci-cd.md`](ci-cd.md) can call it.

- Add OpenTelemetry tracing and metrics with the ASP.NET Core, HttpClient, and Npgsql instrumentations, exporting OTLP when `OTEL_EXPORTER_OTLP_ENDPOINT` is set and doing nothing otherwise. Add a `RunsCreated`, `RunsCompleted`, and `LootClaimsRejected` counter.

### 7. Generated OpenAPI (API-18)

Add `Swashbuckle.AspNetCore` 6.9.0, annotate every endpoint with `.Produces<T>(200)`, `.ProducesProblem(400)`, `.ProducesProblem(401)` and a `WithName`, serve the UI only outside Production, and add a `dotnet swagger tofile` step that writes `packages/shared/openapi/aumbrye-api.v1.yaml`. The CI drift check is specified in [`packages.md`](packages.md) step 5 and [`ci-cd.md`](ci-cd.md) step 10.

### 8. Cleanups (API-15, API-19, API-20, API-21, API-22, API-24)

- Set `Run.Status = RunStatus.Abandoned` when the outcome is `abandoned`, and update the `(AccountId, Status)` index consumers.
- Move `LootInstanceIds` into `namespace Aumbrye.Application.Services`.
- Replace the three copies of `GetAccountId` with one `ClaimsPrincipal.AccountId()` extension in `Aumbrye.Api/Auth/ClaimsPrincipalExtensions.cs`.
- Return `PutSaveResponse` with `Conflict = true` from the 409 path, adding a `ServerStateJson` field to the record, instead of an anonymous object.
- Add `DELETE /api/v1/account` (auth required, 204) cascading to refresh tokens, runs, and the save blob, and `GET /api/v1/account/export` returning the full state as JSON.
- Multi-floor server runs are out of scope for this plan. Track the unused `floorIndex`/`isFinalFloor` parameters in [`run-flow.md`](run-flow.md); do not delete them, the procgen package supports them.

## Work plan

1. **Add CORS and the OPTIONS bypass** — section 1, plus `Cors:AllowedOrigins` in `appsettings.json` and `.env.example`. Unblocks the entire website. (API-01)
2. **Fix the two correctness bugs** — `GenerationSeedFor(run)` helper and the `OrdinalIgnoreCase` duplicate check. Two-line change, ship before anything structural. (API-03, API-04)
3. **Wire up migrations** — Design package, `IDesignTimeDbContextFactory`, regenerate `InitialCreate`, snapshot committed, `Migrate()` in `ApplyDatabaseSchema`. (API-02)
4. **Persist loot ids on the run** — migration `AddRunLootIds`, populate in `CreateRunAsync`, validate against the column in `CompleteRunAsync`, delete the regeneration fallback. (API-03)
5. **Harden secrets and the key** — remove the committed secret, unconditional guard, base64 key with a 32-byte minimum. Coordinate with deployment: the API will refuse to start until `Jwt__Secret` is set. (API-05, API-06)
6. **Add the remaining rate-limit policies and forwarded headers.** (API-11, API-13)
7. **Add ProblemDetails and the exception handler**, bump `ExpectedClientVersion` to `0.4.0`, update both clients in the same PR. (API-12)
8. **Rework leaderboards** — shared contracts, run-derived submission, `Account.DisplayName` migration, three-part Redis member, instance state in the in-memory service, `limit` cap. (API-07 through API-10, API-16)
9. **Add logout, reuse detection, and the cleanup service.** (API-14)
10. **Add readiness health checks and OpenTelemetry.** (API-17, API-23)
11. **Add Swashbuckle and the spec export.** (API-18)
12. **Cleanups** — abandoned status, namespace, claims extension, typed conflict response, account delete and export. (API-15, API-19 through API-22)

Steps 1 and 2 are independent and should land first. Step 4 depends on 3. Step 7 is the only breaking change and needs both clients in the same PR.

## Data and schema changes

Three EF Core migrations, in order:

| Migration | Change |
|-----------|--------|
| `InitialCreate` | Regenerated from the model; replaces the hand-written file. No schema difference intended — verify with `dotnet ef migrations script` against a database created by the old `EnsureCreated()`. |
| `AddRunLootIds` | `Runs.LootInstanceIdsJson jsonb NULL` |
| `AddAccountDisplayNameAndTokenFamily` | `Accounts.DisplayName varchar(32) NOT NULL` with a unique index and a backfill of `'Wanderer-' \|\| left(replace(id::text,'-',''),6)`; `RefreshTokens.FamilyId uuid NOT NULL` backfilled to `Id`; `RefreshTokens.ReplacedByTokenHash varchar(128) NULL` |

Deployment order for each: apply the migration first (all three are additive and backward compatible with the running image), then roll the new image. `AddAccountDisplayNameAndTokenFamily` needs the backfill in the same migration so the `NOT NULL` constraint holds.

Save-state JSON is unchanged, so **no `save_migrator.gd` version bump** and no `content/schemas/` change.

`ApiVersions.ExpectedClientVersion` goes `0.3.0` -> `0.4.0` in step 7. Older clients get 426 from `VersionHeaderMiddleware`; that is the intended behavior and the Godot client stays playable offline regardless.

## Acceptance criteria

- [ ] `curl -H "Origin: http://localhost:5173" -X OPTIONS http://localhost:5000/api/v1/auth/login -i` returns 204 with `Access-Control-Allow-Origin: http://localhost:5173`.
- [ ] The React site can register, log in, read a save, and read leaderboards from a browser with no proxy.
- [ ] `dotnet ef migrations list --project src/Aumbrye.Infrastructure --startup-project src/Aumbrye.Api` lists the migrations, and a fresh `docker compose up` plus `dotnet ef database update` produces a working schema.
- [ ] No `EnsureCreated()` call remains outside the `useInMemoryStores` branch.
- [ ] Completing a run whose cache entry has been evicted accepts the same loot ids the client saw at creation.
- [ ] Claiming the same instance id in two different letter cases returns 400.
- [ ] The API refuses to start in any environment when `Jwt:Secret` is unset or under 32 decoded bytes.
- [ ] `POST /api/v1/leaderboards/submit` with a `runId` belonging to another account returns 403; with an active run returns 400.
- [ ] `GET /api/v1/leaderboards` returns real display names and real `submittedAt` values from Redis.
- [ ] The 11th and later `POST /api/v1/runs` within a minute from one account returns 429.
- [ ] An unhandled exception returns `application/problem+json` with a trace id and no stack trace.
- [ ] `GET /api/v1/health/ready` returns 503 when Postgres is stopped and 200 when it is running.
- [ ] `POST /api/v1/auth/logout` invalidates the refresh token; presenting a revoked token afterwards returns 401 and revokes the family.
- [ ] `packages/shared/openapi/aumbrye-api.v1.yaml` is generated, contains all 14 routes, and CI fails when it drifts.
- [ ] The Godot client, launched with the API unreachable, reaches the hub and completes a run with no error dialog.

## Validation

New xUnit tests in `services/backend/tests/Aumbrye.IntegrationTests/`:

| Test | Asserts |
|------|---------|
| `CorsTests.Preflight_FromAllowedOrigin_ReturnsAllowOriginHeader` | `OPTIONS /api/v1/auth/login` with `Origin: http://localhost:5173` returns the allow-origin and allow-headers response headers |
| `CorsTests.Preflight_FromUnknownOrigin_OmitsAllowOrigin` | A disallowed origin gets no `Access-Control-Allow-Origin` |
| `RunCompletionTests.CompleteRun_AfterCacheEviction_AcceptsOriginalLootIds` | Evict the cache entry, then complete with an id taken from the creation response; expect 200 |
| `RunCompletionTests.CompleteRun_CaseVariantDuplicateLootId_ReturnsBadRequest` | Same GUID in upper and lower case returns 400 |
| `RunCompletionTests.CompleteRun_Abandoned_SetsAbandonedStatus` | The `Run` row reads back `RunStatus.Abandoned` |
| `LeaderboardTests.Submit_ForCompletedRun_ReturnsRank` | Full create/complete/submit flow returns `submitted: true` and a rank |
| `LeaderboardTests.Submit_ForOtherAccountsRun_ReturnsForbidden` | 403 |
| `LeaderboardTests.Submit_ForActiveRun_ReturnsBadRequest` | 400 |
| `LeaderboardTests.Get_LimitAboveCap_ReturnsBadRequest` | `limit=1000` returns 400 |
| `AuthTests.Logout_ThenRefresh_ReturnsUnauthorized` | 401 after logout |
| `AuthTests.ReusedRefreshToken_RevokesFamily` | Presenting a rotated-away token twice invalidates the newest token too |
| `RateLimitTests.RunsGroup_EleventhRequestInWindow_Returns429` | Per-account limiter |
| `ErrorHandlingTests.UnhandledException_ReturnsProblemDetails` | `application/problem+json`, no stack trace, populated `traceId` |
| `HealthTests.Ready_WithBrokenDatabase_Returns503` | Point the connection string at a closed port |
| `AccountTests.Delete_RemovesRunsTokensAndSave` | 204 and no rows remain |

New xUnit tests in `services/backend/tests/Aumbrye.UnitTests/`:

| Test | Asserts |
|------|---------|
| `JwtSecretTests.ShortSecret_Throws` | Under 32 decoded bytes throws at construction |
| `JwtSecretTests.LongSecret_UsesAllBytes` | A 64-byte secret is not truncated; two different 64-byte secrets sharing a 32-byte prefix produce different signatures |
| `MigrationTests.ModelHasNoPendingChanges` | `context.Database.GetPendingMigrations()` is empty and the model snapshot matches (`dotnet ef migrations has-pending-model-changes` equivalent) |
| `LeaderboardMemberTests.RoundTripsAccountTimestampAndName` | The three-part Redis member parses back exactly |

Godot-side: no new validation suite is needed for this plan, but the offline guarantee is asserted by the existing `flow_suite` — confirm it still passes with no network. See [`validation-suites.md`](validation-suites.md).

## Related

- Existing behavior: [`../existing_codebase/backend-api.md`](../existing_codebase/backend-api.md)
- [`website-and-backend.md`](website-and-backend.md) — CORS origins, docker-compose, `.env.example`
- [`packages.md`](packages.md) — shared contracts and the generated OpenAPI spec
- [`networking.md`](networking.md) — the Godot client's contract with these routes
- [`ci-cd.md`](ci-cd.md) — Dockerfile, container health check, spec drift job
- [`platform-and-net.md`](platform-and-net.md) — the Steam ticket exchange this API does not have
