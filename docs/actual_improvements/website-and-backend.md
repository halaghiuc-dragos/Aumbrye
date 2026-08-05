# Website and backend integration — improvement plan

## Current state

The site and the API cannot talk to each other in a browser: the API has no CORS policy and Vite has no dev proxy (see [`../existing_codebase/website-and-backend.md`](../existing_codebase/website-and-backend.md)). The contract between them is a hand-maintained OpenAPI file that nothing generates, validates, or consumes, and which is already two routes behind. `docker compose up` starts Postgres and Redis but not the application. Three P0 issues: WBI-01 (no CORS, no proxy), WBI-02 (leaderboards outside the contract), WBI-03 (a production build silently targets localhost).

None of this affects the Godot client, which is offline-first and must stay that way.

## Gaps

Carried from [`../existing_codebase/website-and-backend.md`](../existing_codebase/website-and-backend.md): WBI-01 through WBI-13.

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

`client.ts:1` currently falls back to `http://localhost:5000` unconditionally. Replace with a mode-aware guard:

```ts
const API_URL = import.meta.env.VITE_API_URL ?? (import.meta.env.DEV ? "" : undefined);
if (API_URL === undefined) {
  throw new Error("VITE_API_URL must be set for production builds.");
}
```

and add a `vite.config.ts` build-time assertion so it fails at `npm run build` rather than at runtime:

```ts
if (mode === "production" && !process.env.VITE_API_URL) {
  throw new Error("VITE_API_URL is required for production builds.");
}
```

The `web-build` job in `.github/workflows/release.yml` sets `VITE_API_URL: ${{ vars.WEB_API_URL }}`.

Rejected alternative: runtime configuration through a fetched `/config.json`. It supports promoting one artifact across environments, which is the better long-term model, but it adds a blocking request before first paint and is not worth it until there is more than one deployed environment. Revisit when staging exists.

### 3. Generated, verified contract (WBI-02, WBI-04, WBI-05, WBI-12)

The chain becomes: C# endpoints annotated with `.Produces<T>()` -> Swashbuckle emits `packages/shared/openapi/aumbrye-api.v1.yaml` -> `openapi-typescript` emits `apps/web/src/api/schema.d.ts` -> `tsc` fails on any field-name mistake. Both generation steps run in CI with `git diff --exit-code`.

Concretely:

- Backend: add Swashbuckle and the spec export as described in [`backend-api.md`](backend-api.md) section 7. Every route gets `.WithName`, `.Produces<T>(200)`, and `.ProducesProblem(4xx)`, including the two leaderboard routes, which also get typed response records in `packages/shared/Contracts/Leaderboards/`.
- Standardize every error body on RFC 7807 `ProblemDetails` so the site has one error shape to handle instead of three (see [`backend-api.md`](backend-api.md) section 6). This is breaking; bump `ApiVersions.ExpectedClientVersion` to `0.4.0`.
- Web: add `openapi-typescript` and the `generate:api` script, delete every hand-written DTO type, and fix `state` -> `stateJson` (which the generated types then enforce). Details in [`website.md`](website.md) section 1.
- Add a `contract` job to `ci.yml`:

```yaml
  contract:
    name: API contract
    runs-on: ubuntu-latest
    timeout-minutes: 15
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-dotnet@v5
        with: { dotnet-version: 8.0.x }
      - uses: actions/setup-node@v5
        with: { node-version: 24 }
      - name: Regenerate OpenAPI from the API
        run: |
          dotnet tool install --global Swashbuckle.AspNetCore.Cli --version 6.9.0
          dotnet build services/backend/src/Aumbrye.Api -c Release
          swagger tofile --yaml --output packages/shared/openapi/aumbrye-api.v1.yaml \
            services/backend/src/Aumbrye.Api/bin/Release/net8.0/Aumbrye.Api.dll v1
      - name: Regenerate web types
        working-directory: apps/web
        run: npm ci && npm run generate:api
      - name: Fail on drift
        run: git diff --exit-code packages/shared/openapi apps/web/src/api/schema.d.ts
```

### 4. One command brings the system up (WBI-06)

Add `services/backend/Dockerfile` (specified in [`ci-cd.md`](ci-cd.md) step 2) and `apps/web/Dockerfile` (Node build stage, nginx runtime stage serving `dist/` with a SPA fallback), then extend `docker-compose.yml` with two profiled services so the existing datastore-only workflow keeps working:

```yaml
  api:
    profiles: ["app"]
    build: { context: ., dockerfile: services/backend/Dockerfile }
    container_name: aumbrye-api
    depends_on:
      postgres: { condition: service_healthy }
      redis: { condition: service_healthy }
    environment:
      ASPNETCORE_ENVIRONMENT: Development
      ASPNETCORE_URLS: http://+:8080
      ConnectionStrings__DefaultConnection: Host=postgres;Port=5432;Database=${POSTGRES_DB:-aumbrye};Username=${POSTGRES_USER:-aumbrye};Password=${POSTGRES_PASSWORD:-aumbrye_dev}
      ConnectionStrings__Redis: redis:6379
      Jwt__Secret: ${JWT_SECRET:?JWT_SECRET must be set}
      Cors__AllowedOrigins__0: http://localhost:5173
      Cors__AllowedOrigins__1: http://localhost:8081
    ports: ["5000:8080"]

  web:
    profiles: ["app"]
    build: { context: ., dockerfile: apps/web/Dockerfile, args: { VITE_API_URL: http://localhost:5000 } }
    container_name: aumbrye-web
    depends_on: [api]
    ports: ["8081:80"]
```

`docker compose up -d` keeps starting only the datastores; `docker compose --profile app up -d --build` starts everything. `JWT_SECRET` uses the `:?` form so compose fails loudly rather than starting an API with a public key.

The API container applies migrations on start (`Migrate()` from [`backend-api.md`](backend-api.md) step 3), so no separate migration step is needed locally.

### 5. Honest, complete environment documentation (WBI-07, WBI-08)

Rewrite the root `.env.example` to list only variables something reads:

```
# docker compose (datastores)
POSTGRES_USER=aumbrye
POSTGRES_PASSWORD=aumbrye_dev
POSTGRES_DB=aumbrye
POSTGRES_PORT=5432
REDIS_PORT=6379

# API (docker compose --profile app, or exported before `dotnet run`)
# Generate with: openssl rand -base64 48
JWT_SECRET=
ConnectionStrings__DefaultConnection=Host=localhost;Port=5432;Database=aumbrye;Username=aumbrye;Password=aumbrye_dev
ConnectionStrings__Redis=localhost:6379
Cors__AllowedOrigins__0=http://localhost:5173
```

Delete `DATABASE_URL` and `REDIS_URL`. Delete `Jwt:Secret` and the `ConnectionStrings` password from `appsettings.json` entirely; the API refuses to start without them, in every environment, per [`backend-api.md`](backend-api.md) step 5. Rotate the committed secret and treat the current value as public.

Add `apps/web/.env.example` guidance for `VITE_API_URL=` (empty in development, absolute in production) and keep `.env.development` gitignored.

### 6. Send version headers from the web client (WBI-09)

`client.ts`'s `request` helper adds `X-Client-Version` and `X-Content-Version` on every call (see [`website.md`](website.md) section 1). Source the values from `__APP_VERSION__`, injected by `vite.config.ts` `define` from `package.json`, and keep `package.json:version` equal to `ApiVersions.ExpectedClientVersion`. A `contract` job assertion checks the two agree.

The web client must then handle 426: render "This page is out of date, please reload" and force a hard reload once.

### 7. One source for the API base URL (WBI-11)

Five copies today. Reduce to configuration in each consumer plus one documented default:

| Consumer | Source of truth after the change |
|----------|----------------------------------|
| API listener | `ASPNETCORE_URLS`, with `launchSettings.json` for local F5 only |
| Web | `VITE_API_URL`, empty in dev (proxy), required in prod |
| Godot | `ApiConfig.base_url`, loaded from `res://config/dev_api.json` `apiBaseUrl` at autoload `_ready` — that loading does not exist today, see [`networking.md`](networking.md) NET-06 |
| OpenAPI | `servers` becomes a templated variable with `http://localhost:5000` as the default value |

That is three real configuration points, each documented in `.env.example` or its own config file, instead of five hardcoded literals.

### 8. End-to-end coverage (WBI-10, WBI-13)

Add a Playwright job that runs the real API and the real site together, so a CORS or contract regression fails CI:

```yaml
  e2e:
    name: End-to-end
    runs-on: ubuntu-latest
    timeout-minutes: 25
    services:
      postgres:
        image: postgres:16
        env: { POSTGRES_USER: aumbrye, POSTGRES_PASSWORD: aumbrye_dev, POSTGRES_DB: aumbrye }
        ports: ["5432:5432"]
        options: >-
          --health-cmd "pg_isready -U aumbrye" --health-interval 5s
          --health-timeout 5s --health-retries 5
      redis:
        image: redis:7
        ports: ["6379:6379"]
        options: --health-cmd "redis-cli ping" --health-interval 5s --health-retries 5
    steps:
      - uses: actions/checkout@v5
      - uses: actions/setup-dotnet@v5
        with: { dotnet-version: 8.0.x }
      - uses: actions/setup-node@v5
        with: { node-version: 24 }
      - name: Start API
        env:
          Jwt__Secret: ${{ secrets.CI_JWT_SECRET }}
          ConnectionStrings__DefaultConnection: Host=localhost;Port=5432;Database=aumbrye;Username=aumbrye;Password=aumbrye_dev
          ConnectionStrings__Redis: localhost:6379
          Cors__AllowedOrigins__0: http://localhost:4173
        run: |
          dotnet run --project services/backend/src/Aumbrye.Api -c Release &
          npx wait-on http://localhost:5000/api/v1/health --timeout 90000
      - name: Build and serve the site
        working-directory: apps/web
        env: { VITE_API_URL: http://localhost:5000 }
        run: |
          npm ci && npm run build
          npx vite preview --port 4173 &
          npx wait-on http://localhost:4173 --timeout 60000
      - name: Playwright
        working-directory: apps/web
        run: npx playwright install --with-deps chromium && npx playwright test --project=integration
```

Note the deliberate use of `vite preview` on 4173 with an absolute `VITE_API_URL`: this exercises the real cross-origin path and therefore the CORS policy, which a proxied dev server would hide.

For deployment topology, document the intended production shape in this file once chosen. The recommended shape is the site on a static host or CDN at `https://aumbrye.example` and the API at `https://api.aumbrye.example`, cross-origin with an explicit allow-list — not a path-based reverse proxy, because the static site benefits from CDN caching that a shared origin complicates.

## Work plan

1. **Add the Vite dev proxy and `server.port: 5173`.** Restores the local dev loop immediately, independent of any backend change. (WBI-01)
2. **Add the API CORS policy and the `OPTIONS` bypass.** (WBI-01)
3. **Guard `VITE_API_URL` at build time** and set it in the release workflow. (WBI-03)
4. **Rewrite both `.env.example` files, remove committed secrets, rotate the JWT secret.** (WBI-07, WBI-08)
5. **Add the Dockerfiles and the `app` compose profile.** Depends on [`ci-cd.md`](ci-cd.md) step 2. (WBI-06)
6. **Add typed leaderboard contracts and Swashbuckle spec generation.** (WBI-02, WBI-05)
7. **Add `openapi-typescript` to the web app**, delete hand-written types, fix `stateJson`. (WBI-04)
8. **Standardize on ProblemDetails and bump the client version to `0.4.0`**, updating both clients in one PR. (WBI-12)
9. **Send version headers from the web client and handle 426.** (WBI-09)
10. **Add the `contract` CI job.** (WBI-05)
11. **Add the `e2e` CI job and the Playwright integration project.** (WBI-10)
12. **Template the OpenAPI `servers` entry and document the three configuration points.** (WBI-11, WBI-13)

Steps 1-4 are independently landable and unblock everything else. Steps 6-8 must land together with the client changes in [`website.md`](website.md) and [`networking.md`](networking.md).

## Data and schema changes

No `content/schemas/` change and no save-format change, so **no `save_migrator.gd` version bump**.

`ApiVersions.ExpectedClientVersion` goes `0.3.0` -> `0.4.0` at step 8. Both clients update in the same PR. The Godot client remains fully playable offline regardless of the header outcome.

New tracked files: `services/backend/Dockerfile`, `services/backend/.dockerignore`, `apps/web/Dockerfile`, `apps/web/nginx.conf`, `apps/web/playwright.config.ts`, `apps/web/e2e/integration.spec.ts`, `apps/web/src/api/schema.d.ts`.

Modified: `docker-compose.yml`, `.env.example`, `apps/web/.env.example`, `apps/web/vite.config.ts`, `services/backend/src/Aumbrye.Api/appsettings.json` (secrets removed), `packages/shared/openapi/aumbrye-api.v1.yaml` (now generated).

Rotate `Jwt:Secret` before or with step 4. Every existing access and refresh token becomes invalid; that is acceptable because the current secret is public.

## Acceptance criteria

- [ ] `npm run dev` plus `dotnet run` gives a working login and leaderboard in a browser with no CORS error in the console.
- [ ] `npm run build && npx vite preview` with an absolute `VITE_API_URL` also works, proving the CORS policy and not just the proxy.
- [ ] `npm run build` fails with a clear message when `VITE_API_URL` is unset.
- [ ] `docker compose --profile app up -d --build` yields a healthy API on 5000 and the site on 8081, with migrations applied.
- [ ] `docker compose up -d` still starts only Postgres and Redis.
- [ ] `docker compose --profile app up` fails immediately with a readable error when `JWT_SECRET` is unset.
- [ ] Every variable in `.env.example` is read by something; `DATABASE_URL` and `REDIS_URL` are gone.
- [ ] `appsettings.json` contains no secret and no password.
- [ ] `packages/shared/openapi/aumbrye-api.v1.yaml` is generated and documents all 14 routes including both leaderboard routes.
- [ ] The `contract` CI job fails on a PR that adds an endpoint without regenerating the spec, and on one that regenerates the spec without regenerating `schema.d.ts`.
- [ ] `apps/web/src/api/client.ts` declares no DTO types of its own.
- [ ] Every API error the site can receive is `application/problem+json` and renders through one code path.
- [ ] The site sends `X-Client-Version` and `X-Content-Version` on every request and shows a reload prompt on 426.
- [ ] `apps/web/package.json:version` equals `ApiVersions.ExpectedClientVersion`, asserted in CI.
- [ ] The `e2e` job passes and fails when CORS is removed from the API.
- [ ] The Godot client still reaches the hub and completes a run with the API stopped.

## Validation

Playwright integration project, `apps/web/e2e/integration.spec.ts`, run against the real API:

| Test | Asserts |
|------|---------|
| `health` | The API answers `GET /api/v1/health` from the browser origin with an `Access-Control-Allow-Origin` header |
| `register and sign in` | Registering lands signed in with no second submit, and the character line shows the default `Wanderer — Level 1` |
| `session survives expiry` | With the access-token lifetime configured to one minute, the page is still signed in after 90 seconds |
| `leaderboards empty` | With no submissions, the table shows "No entries yet" and no error |
| `leaderboards populated` | After a scripted create-run/complete/submit through the API, the entry appears with the right display name and time |
| `version gate` | Overriding the client version header to `0.0.1` produces the reload prompt, not a blank page |
| `deep link` | `/wiki/controls` loads directly and renders the controls text |

Backend xUnit, `services/backend/tests/Aumbrye.IntegrationTests/CorsTests.cs`: preflight from an allowed origin returns the allow headers; preflight from a disallowed origin does not; a preflight with no version headers is not rejected with 426 (this is the `OPTIONS` bypass regression test).

Shell assertion in the `contract` job: `test "$(jq -r .version apps/web/package.json)" = "$(grep -oP 'ExpectedClientVersion = "\K[^"]+' packages/shared/Contracts/ApiVersions.cs)"`.

Godot offline guarantee: the existing headless validation run in the `godot` CI job executes with no API reachable, which is the standing regression test that nothing here made the client depend on a server. See [`validation-suites.md`](validation-suites.md).

## Related

- Existing behavior: [`../existing_codebase/website-and-backend.md`](../existing_codebase/website-and-backend.md)
- [`backend-api.md`](backend-api.md) — CORS policy, ProblemDetails, Swashbuckle, migrations
- [`website.md`](website.md) — the `request` helper, generated types, version headers
- [`packages.md`](packages.md) — the shared contracts and the OpenAPI file
- [`ci-cd.md`](ci-cd.md) — Dockerfiles, the `contract` and `e2e` jobs, release variables
- [`networking.md`](networking.md) — the Godot client's independent path
