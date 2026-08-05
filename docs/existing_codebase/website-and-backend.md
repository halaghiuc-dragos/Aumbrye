# Website and backend integration

How `apps/web` reaches `services/backend`: a hardcoded base URL, four hand-written `fetch` calls, an OpenAPI file nobody generates from or validates against, and a docker-compose stack that starts the two datastores but not the API. The integration does not currently work in a browser, because the API sends no CORS headers and the site has no dev proxy.

## Files

| Path | Role |
|------|------|
| `apps/web/src/api/client.ts` | The only place the web app talks to the API |
| `apps/web/src/vite-env.d.ts` | Declares `VITE_API_URL` on `ImportMetaEnv` |
| `apps/web/.env.example` | `VITE_API_URL=http://localhost:5000` (tracked) |
| `apps/web/.env.development` | Same single line (untracked, present on disk) |
| `apps/web/vite.config.ts` | React plugin only — no `server.proxy` |
| `packages/shared/openapi/aumbrye-api.v1.yaml` | The declared contract, 8 paths |
| `packages/shared/Contracts/**/*.cs` | The real contract, C# records shared by API, CLI, and tests |
| `docker-compose.yml` | Postgres 16 and Redis 7 only |
| `.env.example` | Compose variables plus two unused connection strings |
| `services/backend/src/Aumbrye.Api/Properties/launchSettings.json` | `http://localhost:5000`, environment `Development` |
| `services/backend/src/Aumbrye.Api/appsettings.json` | Committed default connection strings and JWT secret |
| `README.md:26-54` | The documented four-step local bring-up |

## How it works

### Addresses

`http://localhost:5000` appears in four independent places:

| Location | Purpose |
|----------|---------|
| `services/backend/src/Aumbrye.Api/Properties/launchSettings.json:7` | Where the API actually listens under `dotnet run` |
| `apps/web/src/api/client.ts:1` | The web fallback when `VITE_API_URL` is unset |
| `apps/game/client/scripts/net/api_config.gd:6` | The Godot fallback (`DEFAULT_BASE_URL`) |
| `packages/shared/openapi/aumbrye-api.v1.yaml:7` | The single `servers` entry |

Plus `apps/game/client/config/dev_api.json:2`, whose `apiBaseUrl` key is read by nothing — a repo-wide search for `apiBaseUrl` matches only that file. Nothing derives any of these from a shared source.

The Vite dev server runs on its default port 5173 — `vite.config.ts` sets no `server.port`. So the browser origin is `http://localhost:5173` and the API origin is `http://localhost:5000`. That is cross-origin.

### CORS

`services/backend` contains no `AddCors`, `UseCors`, or any other `Cors` token; a case-sensitive search across every `.cs` file under `services/backend` returns nothing. The middleware pipeline is `VersionHeaderMiddleware`, rate limiter, authentication, authorization (`Program.cs:71-74`).

`apps/web/vite.config.ts:4-6` sets no `server.proxy`, so requests are not same-origin-proxied in development either.

The result: every `fetch` from the site to the API is rejected by the browser. `GET /api/v1/leaderboards` is a simple request, so it reaches the server and the response is discarded for lack of `Access-Control-Allow-Origin`; the page renders "No entries yet". `POST /api/v1/auth/login` carries `Content-Type: application/json`, triggering a preflight that the API answers with 404 or 405 and no CORS headers, so the login never happens. The account page's `.catch`-free code path swallows this.

### Environment variables

`VITE_API_URL` is read at `client.ts:1` and inlined by Vite at build time. There is no runtime configuration: a production bundle built without `VITE_API_URL` set contains the literal `http://localhost:5000`.

`apps/web/.env.example` is tracked; `apps/web/.env.development` is not (it is absent from `git ls-files apps/web`) but exists locally with identical content. `README.md:54` documents copying one to the other.

The repo-root `.env.example` feeds docker-compose (`POSTGRES_USER`, `POSTGRES_PASSWORD`, `POSTGRES_DB`, `POSTGRES_PORT`, `REDIS_PORT` — all consumed as `${VAR:-default}` at `docker-compose.yml:7-11,25`). It also declares:

```
DATABASE_URL=Host=localhost;Port=5432;Database=aumbrye;Username=aumbrye;Password=aumbrye_dev
REDIS_URL=localhost:6379
```

(`.env.example:11-12`). Nothing reads either one. The API reads `ConnectionStrings:DefaultConnection` and `ConnectionStrings:Redis` (`services/backend/src/Aumbrye.Infrastructure/DependencyInjection.cs:38,40`), which map to the environment variables `ConnectionStrings__DefaultConnection` and `ConnectionStrings__Redis`. A repo-wide search for `DATABASE_URL` and `REDIS_URL` matches only `.env.example` itself.

### docker-compose

`docker-compose.yml` defines exactly two services (`docker-compose.yml:2,20`): `postgres:16` with a named volume and a `pg_isready` health check, and `redis:7` with a named volume and a `redis-cli ping` health check. Both restart unless stopped and both publish to the host.

There is no `api` service and no `web` service. There is no `Dockerfile` anywhere in the repository to build one from, though `.github/workflows/release.yml:18` tries to build `services/backend/Dockerfile`. Local bring-up is the four manual steps at `README.md:26-54`: compose up the datastores, `dotnet run` the API in one terminal, `npm run dev` the site in another, open Godot separately.

### The OpenAPI contract

`packages/shared/openapi/aumbrye-api.v1.yaml` is OpenAPI 3.0.3 with 8 path items (`:9,15,29,43,57,78,97,120`) and a `bearerAuth` security scheme. It is hand-maintained: the API registers `AddEndpointsApiExplorer()` (`Program.cs:46`) but no `AddSwaggerGen`, `UseSwagger`, or `MapOpenApi`, so nothing generates or checks it.

Nothing consumes it either. `apps/web` has no `openapi-typescript`, `orval`, or `swagger-codegen` dependency; `client.ts` declares its own types by hand. The C# side shares real types through `packages/shared/Contracts/`, so the API, the integration tests, and the procgen CLI cannot drift from each other — but the web app is outside that guarantee, and so is the Godot client.

The spec is already behind the implementation: `/api/v1/leaderboards` and `/api/v1/leaderboards/submit` are mapped at `services/backend/src/Aumbrye.Api/Endpoints/LeaderboardsEndpoints.cs:11,35` and absent from the spec, and `apps/web/src/pages/Leaderboards.tsx` is built entirely on the undocumented one.

### Field-level mismatches

| Web expects | API sends | Evidence |
|-------------|-----------|----------|
| `save.state` | `stateJson` | `apps/web/src/pages/Account.tsx:37-39` vs `packages/shared/Contracts/Saves/SaveContracts.cs:4` |
| `AuthTokens.expiresAt` | `accessTokenExpiresAt` | `apps/web/src/api/client.ts:6` vs `packages/shared/Contracts/Auth/AuthContracts.cs:12` |
| `data.tokens.accessToken` | `tokens.accessToken` | Matches (`Account.tsx:18` vs `AuthContracts.cs:16`) |
| `data.error` | `{ "error": "..." }` | Matches for auth (`Account.tsx:14` vs `ApiEndpoints.cs:23,31`) |
| `entries[].displayName`, `elapsedSeconds`, `submittedAt` | same names | Matches (`Leaderboards.tsx:12-17` vs `LeaderboardsEndpoints.cs:25-31`) |

The first row is why the account page never shows a character.

### Version negotiation

`VersionHeaderMiddleware` gates any `/api` path on `X-Client-Version` and `X-Content-Version` when present (`services/backend/src/Aumbrye.Api/Middleware/VersionHeaderMiddleware.cs:13-38`), expecting `0.3.0` and `1` (`packages/shared/Contracts/ApiVersions.cs:7-8`). The web client sends neither header, so it is never version-checked and would keep calling a future incompatible API. The Godot client does send them — see [`networking.md`](networking.md).

### Secrets

`services/backend/src/Aumbrye.Api/appsettings.json` commits a working Postgres password (`:18`) and the JWT signing secret `dev-only-change-me-in-production-32chars!!` (`:13`). The production guard at `Program.cs:19-24` only fires when `ASPNETCORE_ENVIRONMENT` is exactly `Production`, so a staging deployment signs tokens with a value that is public on GitHub.

## Absent

- **CORS policy.** No `Cors` token under `services/backend`.
- **Vite dev proxy.** No `server` block in `apps/web/vite.config.ts`.
- **Dockerfile for the API or the site.** No `Dockerfile` anywhere in the repository.
- **`api` or `web` service in docker-compose.** `docker-compose.yml` has two services, both datastores.
- **Runtime configuration for the web app.** `VITE_API_URL` is compile-time only; there is no `/config.json` fetch or `window.__ENV__` shim.
- **Generated or validated client from the OpenAPI spec.** No generator dependency in `apps/web/package.json`, no drift check in `.github/workflows/ci.yml`.
- **Any end-to-end test crossing the boundary.** No Playwright, Cypress, or `WebApplicationFactory`-plus-browser test. The backend integration tests exercise the API in-process only.
- **Reverse proxy or single-origin deployment config.** No nginx, Caddy, Traefik, or Kubernetes manifest.
- **`Cors__AllowedOrigins` or `Jwt__Secret` in `.env.example`.**

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| WBI-01 | P0 | No CORS on the API and no dev proxy on the site, so no browser request from the site to the API can succeed. Account and leaderboard pages are dead. | No `Cors` under `services/backend`; `apps/web/vite.config.ts:4-6` |
| WBI-02 | P0 | The site's leaderboard page depends on two routes that are absent from the OpenAPI contract. | `apps/web/src/pages/Leaderboards.tsx:26` -> `LeaderboardsEndpoints.cs:11,35`; spec paths at `aumbrye-api.v1.yaml:9,15,29,43,57,78,97,120` |
| WBI-03 | P0 | A production build with `VITE_API_URL` unset silently ships `http://localhost:5000` as the API base. There is no build-time guard. | `apps/web/src/api/client.ts:1`; `.github/workflows/release.yml` `web-build` job sets no env |
| WBI-04 | P1 | The web app hand-writes DTO shapes instead of generating them, and two of them are already wrong (`state`/`stateJson`, `expiresAt`/`accessTokenExpiresAt`). | `client.ts:3-7`, `Account.tsx:37` vs `SaveContracts.cs:4`, `AuthContracts.cs:12` |
| WBI-05 | P1 | Nothing generates or verifies the OpenAPI file, so it drifts silently and is already two routes behind. | `Program.cs:46` with no Swagger registration; no drift job in `.github/workflows/ci.yml` |
| WBI-06 | P1 | `docker compose up` does not start the application, only its datastores, so there is no single command that produces a running system. | `docker-compose.yml:2,20`; `README.md:26-54` |
| WBI-07 | P1 | `.env.example:11-12` declares `DATABASE_URL` and `REDIS_URL`, which nothing reads. The variables the API actually needs (`ConnectionStrings__DefaultConnection`, `ConnectionStrings__Redis`, `Jwt__Secret`) are undocumented. | `.env.example:11-12` vs `DependencyInjection.cs:38,40` |
| WBI-08 | P1 | A working database password and the JWT signing secret are committed, and the production guard does not cover Staging. | `appsettings.json:13,18`; `Program.cs:19-24` |
| WBI-09 | P1 | The web client sends no `X-Client-Version` or `X-Content-Version`, so it is exempt from the version gate the Godot client obeys. | `client.ts:9-38` vs `VersionHeaderMiddleware.cs:18,29` |
| WBI-10 | P1 | No test of any kind crosses the web-to-API boundary; WBI-01 and the `stateJson` mismatch both shipped. | No e2e test in the repository |
| WBI-11 | P2 | The API base URL is duplicated in five places with no shared source. | `launchSettings.json:7`, `client.ts:1`, `api_config.gd:6`, `dev_api.json:2`, `aumbrye-api.v1.yaml:7` |
| WBI-12 | P2 | Error shapes differ by endpoint family (`{error}` from auth, runs, saves; anonymous objects from leaderboards; framework defaults elsewhere), and the site handles only the first. | `ApiEndpoints.cs:23,31`, `LeaderboardsEndpoints.cs:21-32`, `Account.tsx:14` |
| WBI-13 | P2 | No reverse-proxy or single-origin deployment configuration exists, so the CORS fix is the only viable path and nothing documents the intended topology. | No proxy config in the repository |

## Related

- Improvement plan: [`../actual_improvements/website-and-backend.md`](../actual_improvements/website-and-backend.md)
- [`website.md`](website.md) — the client side
- [`backend-api.md`](backend-api.md) — the server side
- [`packages.md`](packages.md) — the shared contracts and the OpenAPI file
- [`networking.md`](networking.md) — the Godot client's separate path to the same API
- [`ci-cd.md`](ci-cd.md) — the missing Dockerfile and the missing drift check
