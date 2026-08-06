# Website and backend integration — improvement plan

## Status: FINISHED

## Current state

The site and API integrate in the browser: CORS policy `"web"` plus a Vite dev proxy restore the local loop; production builds require `VITE_API_URL`; OpenAPI is generated from Swashbuckle and consumed by `openapi-typescript`; `docker compose --profile app` starts API and web with migrations; Playwright integration tests and a `contract` CI job guard drift. See [`../existing_codebase/website-and-backend.md`](../existing_codebase/website-and-backend.md).

## Gaps

| ID | Sev | Gap | Status | Evidence |
|----|-----|-----|--------|----------|
| WBI-01 | P0 | No CORS on the API and no dev proxy on the site | **FINISHED** | `Program.cs:88-98,216` `AddCors`/`UseCors`; `apps/web/vite.config.ts` `server.proxy` |
| WBI-02 | P0 | Leaderboard routes absent from OpenAPI | **FINISHED** | `packages/shared/openapi/aumbrye-api.v1.yaml` `/api/v1/leaderboards` paths |
| WBI-03 | P0 | Production build silently targets localhost | **FINISHED** | `apps/web/vite.config.ts` build guard; `apps/web/src/api/client.ts:3-6` |
| WBI-04 | P1 | Hand-written DTO shapes with field mismatches | **FINISHED** | `apps/web/src/api/schema.d.ts` generated; `Account.tsx` reads `stateJson` |
| WBI-05 | P1 | OpenAPI not generated or verified | **FINISHED** | `.github/workflows/ci.yml` `contract` job; backend `Verify OpenAPI spec` step |
| WBI-06 | P1 | `docker compose up` does not start the application | **FINISHED** | `docker-compose.yml` `api`/`web` services with `profiles: ["app"]` |
| WBI-07 | P1 | `.env.example` documents unused variables | **FINISHED** | `.env.example` — only consumed vars; `DATABASE_URL`/`REDIS_URL` removed |
| WBI-08 | P1 | Committed secrets in `appsettings.json` | **FINISHED** | `appsettings.json` — no `Jwt:Secret` or connection passwords |
| WBI-09 | P1 | Web client sends no version headers | **FINISHED** | `apps/web/src/api/client.ts` `X-Client-Version`/`X-Content-Version`; `VersionGate.tsx` on 426 |
| WBI-10 | P1 | No cross-boundary test | **FINISHED** | `apps/web/e2e/integration.spec.ts`; `.github/workflows/ci.yml` `e2e` job |
| WBI-11 | P2 | API base URL duplicated in five places | **FINISHED** | Three documented config points — see Target design §7 and twin doc |
| WBI-12 | P2 | Inconsistent error shapes | **FINISHED** | `ProblemResults` + `ProducesProblem`; `ApiVersions.ExpectedClientVersion = "0.4.0"` |
| WBI-13 | P2 | No deployment topology documented | **FINISHED** | Target design §8 below |

## Target design

### 1. Both a CORS policy and a dev proxy (WBI-01)

Two independent fixes, both wanted.

The API policy is specified in [`backend-api.md`](backend-api.md) section 1: a named `"web"` policy reading `Cors:AllowedOrigins` from configuration, `AllowCredentials`, explicit methods and headers, one-hour preflight cache, and an `OPTIONS` bypass in `VersionHeaderMiddleware`. Defaults to `["http://localhost:5173"]`.

The Vite proxy makes local development same-origin so a CORS regression cannot silently break the dev loop:

```ts
// apps/web/vite.config.ts
export default defineConfig(({ mode }) => ({
  plugins: [react()],
  server: {
    port: 5173,
    strictPort: true,
    proxy: mode === "development"
      ? { "/api": { target: "http://localhost:5000", changeOrigin: true } }
      : undefined,
  },
  build: { sourcemap: true },
}));
```

With the proxy in place, `VITE_API_URL` defaults to the empty string in development so `client.ts` builds relative URLs (`/api/v1/...`) and the browser never leaves origin 5173. Production still uses an absolute origin, which is why the CORS policy is still required.

### 2. Fail the build when the API URL is not configured (WBI-03)

`client.ts` uses a mode-aware guard and `vite.config.ts` throws at build time when `VITE_API_URL` is unset in production. The `web-build` job in `.github/workflows/release.yml` sets `VITE_API_URL: ${{ vars.WEB_API_URL }}`.

### 3. Generated, verified contract (WBI-02, WBI-04, WBI-05, WBI-12)

Chain: C# endpoints with `.Produces<T>()` → Swashbuckle emits `packages/shared/openapi/aumbrye-api.v1.yaml` → `openapi-typescript` emits `apps/web/src/api/schema.d.ts` → `tsc` fails on drift. CI `contract` job runs `git diff --exit-code` on both files plus a version parity assertion.

### 4. One command brings the system up (WBI-06)

`services/backend/Dockerfile` and `apps/web/Dockerfile` (nginx SPA fallback) extend `docker-compose.yml` with profiled `api` and `web` services. `docker compose up -d` keeps datastores only; `docker compose --profile app up -d --build` starts everything. `JWT_SECRET` uses `:?` so compose fails when unset.

### 5. Honest, complete environment documentation (WBI-07, WBI-08)

Root `.env.example` lists only variables something reads. `apps/web/.env.example` documents `VITE_API_URL`. `appsettings.json` contains no secret and no password.

### 6. Send version headers from the web client (WBI-09)

`client.ts` adds `X-Client-Version` and `X-Content-Version` on every call, sourced from `__APP_VERSION__` (`package.json:version` = `ApiVersions.ExpectedClientVersion`). The site renders a reload prompt on 426 via `VersionGate.tsx`.

### 7. One source for the API base URL (WBI-11)

| Consumer | Source of truth |
|----------|-----------------|
| API listener | `ASPNETCORE_URLS`, with `launchSettings.json` for local F5 only |
| Web | `VITE_API_URL`, empty in dev (proxy), required in prod |
| Godot | `ApiConfig.base_url`, loaded from `res://config/dev_api.json` `apiBaseUrl` at autoload `_ready` |
| OpenAPI | `servers[0].variables.baseUrl.default` = `http://localhost:5000` |

### 8. End-to-end coverage and deployment topology (WBI-10, WBI-13)

Playwright `integration` project in CI runs the real API (`vite preview` on 4173 with absolute `VITE_API_URL`) to exercise CORS.

**Production topology (chosen):** static site on a CDN at `https://aumbrye.example`, API at `https://api.aumbrye.example`, cross-origin with an explicit CORS allow-list — not a path-based reverse proxy, so the static site keeps CDN caching without shared-origin complexity.

## Work plan

All steps complete — see gap table evidence column.

## Data and schema changes

No `content/schemas/` change and no save-format change — **no `save_migrator.gd` version bump**.

`ApiVersions.ExpectedClientVersion` is `0.4.0`. Both web (`apps/web/package.json`) and Godot (`api_config.gd` `CLIENT_VERSION`) match.

## Acceptance criteria

- [x] `npm run dev` plus `dotnet run` gives a working login and leaderboard in a browser with no CORS error in the console.
- [x] `npm run build && npx vite preview` with an absolute `VITE_API_URL` also works, proving the CORS policy and not just the proxy.
- [x] `npm run build` fails with a clear message when `VITE_API_URL` is unset.
- [x] `docker compose --profile app up -d --build` yields a healthy API on 5000 and the site on 8081, with migrations applied.
- [x] `docker compose up -d` still starts only Postgres and Redis.
- [x] `docker compose --profile app up` fails immediately with a readable error when `JWT_SECRET` is unset.
- [x] Every variable in `.env.example` is read by something; `DATABASE_URL` and `REDIS_URL` are gone.
- [x] `appsettings.json` contains no secret and no password.
- [x] `packages/shared/openapi/aumbrye-api.v1.yaml` is generated and documents all routes including leaderboards.
- [x] The `contract` CI job fails on spec or `schema.d.ts` drift.
- [x] `apps/web/src/api/client.ts` declares no hand-written DTO types.
- [x] Every API error the site can receive is `application/problem+json` and renders through `ApiError.detail`.
- [x] The site sends version headers on every request and shows a reload prompt on 426.
- [x] `apps/web/package.json:version` equals `ApiVersions.ExpectedClientVersion`, asserted in CI.
- [x] The `e2e` job runs Playwright integration tests against the real API.
- [x] The Godot client still reaches the hub and completes a run with the API stopped (existing `godot` CI job).

## Validation

| Suite | Asserts |
|-------|---------|
| `apps/web/e2e/integration.spec.ts` | CORS health, register/sign-in, session refresh, leaderboards empty/populated, version gate, `/wiki/controls` deep link |
| `services/backend/tests/Aumbrye.IntegrationTests/CorsTests.cs` | Preflight allow/deny origins; OPTIONS not rejected with 426 |
| `contract` CI job | OpenAPI + `schema.d.ts` drift; `package.json` version = `ApiVersions.ExpectedClientVersion` |
| `godot` CI job | Headless validation with no API reachable |

## Related

- Existing behavior: [`../existing_codebase/website-and-backend.md`](../existing_codebase/website-and-backend.md)
- [`backend-api.md`](backend-api.md) — CORS policy, ProblemDetails, Swashbuckle, migrations
- [`website.md`](website.md) — the `request` helper, generated types, version headers
- [`packages.md`](packages.md) — the shared contracts and the OpenAPI file
- [`ci-cd.md`](ci-cd.md) — Dockerfiles, the `contract` and `e2e` jobs, release variables
- [`networking.md`](networking.md) — the Godot client's independent path
