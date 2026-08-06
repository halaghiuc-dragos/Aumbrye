# Website and backend integration

How `apps/web` reaches `services/backend`: a generated OpenAPI contract, a typed `request` helper with version headers, a Vite dev proxy for same-origin development, a CORS policy on the API for cross-origin production preview, and docker-compose profiles that optionally start the full stack.

## Files

| Path | Role |
|------|------|
| `apps/web/src/api/client.ts` | Typed transport â€” `request`, auth, saves, leaderboards |
| `apps/web/src/api/schema.d.ts` | Generated from OpenAPI via `npm run generate:api` |
| `apps/web/src/auth/AuthProvider.tsx` | In-memory access token, `sessionStorage` refresh, scheduled refresh |
| `apps/web/src/components/VersionGate.tsx` | Reload prompt on HTTP 426 |
| `apps/web/vite.config.ts` | Dev proxy `/api` â†’ `localhost:5000`, `__APP_VERSION__` define, production `VITE_API_URL` guard |
| `apps/web/.env.example` | `VITE_API_URL=` (empty in dev) |
| `packages/shared/openapi/aumbrye-api.v1.yaml` | Generated OpenAPI 3 spec (Swashbuckle) |
| `packages/shared/Contracts/**/*.cs` | C# records shared by API, CLI, and tests |
| `docker-compose.yml` | Postgres, Redis; `api`/`web` under profile `app` |
| `services/backend/Dockerfile` | API container image |
| `apps/web/Dockerfile` | Node build + nginx SPA |
| `.env.example` | Compose + API env vars (no `DATABASE_URL`/`REDIS_URL`) |
| `services/backend/src/Aumbrye.Api/Program.cs` | CORS `"web"` policy, Swagger, `Migrate()` on start |
| `services/backend/src/Aumbrye.Api/appsettings.json` | `Cors:AllowedOrigins` only â€” no secrets |
| `apps/game/client/scripts/net/api_config.gd` | Godot base URL from env / `dev_api.json` / default |

## How it works

### Addresses

Three documented configuration points replace five hardcoded literals:

| Consumer | Source | Default |
|----------|--------|---------|
| API | `ASPNETCORE_URLS` / `launchSettings.json` | `http://localhost:5000` |
| Web | `VITE_API_URL` | `""` in dev (proxy); required in prod |
| Godot | `AUMBRYE_API_URL` â†’ `user://api_config.json` â†’ `res://config/dev_api.json` | `https://api.aumbrye.example` |
| OpenAPI | `servers[0].variables.baseUrl` | `http://localhost:5000` |

### CORS and dev proxy

`Program.cs:88-98` registers policy `"web"` from `Cors:AllowedOrigins` (default `http://localhost:5173`). `UseCors("web")` runs after `VersionHeaderMiddleware` at `Program.cs:216`. `VersionHeaderMiddleware.cs:13-17` bypasses `OPTIONS` so preflights are not version-gated.

`vite.config.ts` proxies `/api` to `http://localhost:5000` in development so the browser origin stays `http://localhost:5173`.

### Environment variables

`VITE_API_URL` is compile-time only. `vite.config.ts` throws when it is unset in production builds. `client.ts:3-6` uses an empty string in dev so URLs are relative (`/api/v1/...`).

Root `.env.example` documents `POSTGRES_*`, `REDIS_PORT`, `JWT_SECRET`, `ConnectionStrings__*`, and `Cors__AllowedOrigins__0`. Nothing reads `DATABASE_URL` or `REDIS_URL`.

### docker-compose

`docker compose up -d` starts Postgres 16 and Redis 7 only. `docker compose --profile app up -d --build` also builds and starts `aumbrye-api` on host port 5000 and `aumbrye-web` on 8081. `JWT_SECRET` uses `${JWT_SECRET:?JWT_SECRET must be set}` on the `api` service.

The API container calls `db.Database.Migrate()` via `DependencyInjection.cs:69-73` on startup.

### The OpenAPI contract

Swashbuckle generates `packages/shared/openapi/aumbrye-api.v1.yaml`. CI regenerates it and fails on drift (`ci.yml` `contract` job and backend `Verify OpenAPI spec` step). `openapi-typescript` produces `apps/web/src/api/schema.d.ts`.

### Version negotiation

`client.ts` sends `X-Client-Version: __APP_VERSION__` (`0.4.0`, matching `ApiVersions.ExpectedClientVersion`) and `X-Content-Version: 1` on every request. `VersionGate.tsx` shows a reload prompt on 426.

### Error shape

API errors use RFC 7807 `ProblemDetails` (`application/problem+json`). `client.ts` throws `ApiError` with `detail` from the problem body.

## Contracts

| Surface | Contract |
|---------|----------|
| Save field | API returns `stateJson`; web reads `save.stateJson` (`Account.tsx`) |
| Auth tokens | `accessTokenExpiresAt` in `AuthTokensResponse` |
| Leaderboard submit | `POST /api/v1/leaderboards/submit` body `{ runId, optIn }` |
| Version headers | `X-Client-Version`, `X-Content-Version` on all `/api` calls when sent |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| CORS policy | IMPLEMENTED | `Program.cs:88-98,216` |
| Vite dev proxy | IMPLEMENTED | `vite.config.ts` `server.proxy` |
| Production API URL guard | IMPLEMENTED | `vite.config.ts`, `client.ts:3-6` |
| Generated OpenAPI + web types | IMPLEMENTED | `aumbrye-api.v1.yaml`, `schema.d.ts`, `ci.yml` `contract` |
| Docker app profile | IMPLEMENTED | `docker-compose.yml` `api`/`web` |
| Env documentation | IMPLEMENTED | `.env.example`, `apps/web/.env.example` |
| Secrets removed from appsettings | IMPLEMENTED | `appsettings.json` |
| Version headers + 426 handling | IMPLEMENTED | `client.ts`, `VersionGate.tsx` |
| Playwright integration tests | IMPLEMENTED | `apps/web/e2e/integration.spec.ts`, `ci.yml` `e2e` |
| Godot `apiBaseUrl` loading | IMPLEMENTED | `api_config.gd` `_ready` / `_resolve_base_url` |
| Deployment topology documented | IMPLEMENTED | `actual_improvements/website-and-backend.md` Â§8 |

## Related

- Improvement plan: [`../actual_improvements/website-and-backend.md`](../actual_improvements/website-and-backend.md) - **FINISHED**
- [`website.md`](website.md) â€” the client side
- [`backend-api.md`](backend-api.md) â€” the server side
- [`packages.md`](packages.md) â€” the shared contracts and the OpenAPI file
- [`networking.md`](networking.md) â€” the Godot client's separate path to the same API
- [`ci-cd.md`](ci-cd.md) â€” CI workflows, API image build, OpenAPI drift check
