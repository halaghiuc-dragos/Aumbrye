# Website

React 19 + Vite 6 + TypeScript marketing and account site in `apps/web/`. Eight routed pages (landing, account, patch-note list/detail, wiki index/article, leaderboards, 404) behind `react-router-dom` 7. Two pages call the API through a typed client and react-query; wiki and patch notes load from markdown at build time. Vitest component tests and a Playwright smoke journey run in CI.

## Files

| Path | Role |
|------|------|
| `apps/web/index.html` | Root shell, default meta description, favicon link |
| `apps/web/src/main.tsx` | `HelmetProvider`, `ErrorBoundary`, `QueryClientProvider`, `AuthProvider`, `App` |
| `apps/web/src/App.tsx` | `BrowserRouter` route table |
| `apps/web/src/components/Layout.tsx` | Skip link, `NavLink` nav, footer with `__APP_VERSION__`, `PageHelmet` helper |
| `apps/web/src/components/NotFound.tsx` | 404 route |
| `apps/web/src/components/ErrorBoundary.tsx` | Recoverable render fallback |
| `apps/web/src/components/VersionGate.tsx` | Reload banner on HTTP 426 version mismatch |
| `apps/web/src/auth/AuthProvider.tsx` | In-memory access token, `sessionStorage` refresh, scheduled refresh, logout |
| `apps/web/src/api/client.ts` | `request` helper, `ApiError`, auth/save/leaderboard wrappers |
| `apps/web/src/api/schema.d.ts` | Generated OpenAPI types (`npm run generate:api`) |
| `apps/web/src/content/loader.ts` | `import.meta.glob` over markdown content |
| `apps/web/src/content/biomes.json` | Five EA biome ids for leaderboards |
| `apps/web/content/wiki/*.md` | Wiki articles with YAML front matter |
| `apps/web/content/patch-notes/*.md` | Patch notes with front matter |
| `apps/web/public/favicon.svg` | Site favicon |
| `apps/web/public/robots.txt` | Crawler rules + sitemap pointer |
| `apps/web/public/sitemap.xml` | Static and content routes |
| `apps/web/vite.config.ts` | `__APP_VERSION__` define, prerender plugin |
| `apps/web/vitest.config.ts` | jsdom tests, 80% coverage gate on `api/` + `auth/` |
| `apps/web/playwright.config.ts` | Smoke e2e against preview server |
| `apps/web/e2e/smoke.spec.ts` | Nav journey with mocked API |
| `apps/web/.nvmrc` | Node 24 |
| `apps/web/package.json` | version `0.3.0`, `engines.node >=24`, test/lint/generate scripts |

## How it works

### Navigation

`App.tsx` mounts a `BrowserRouter` with nested `Layout` routes: `/`, `/account`, `/patch-notes`, `/patch-notes/:version`, `/wiki`, `/wiki/:slug`, `/leaderboards`, and `*` â†’ `NotFound`. `Layout.tsx` renders `<NavLink>` items; the active link receives `aria-current="page"`. Leaderboards read and write `biomeId` and `tier` via `useSearchParams`.

### API client

`client.ts` resolves `VITE_API_URL` (empty string in dev for same-origin MSW/proxy, required in production). Every call goes through `request`, which sets `X-Client-Version` (`__APP_VERSION__`, currently `0.3.0`) and `X-Content-Version: 1`, enforces a 10 s timeout, throws `ApiError` on non-2xx, and maps HTTP 426 to `VersionMismatchError`.

| Function | Request |
|----------|---------|
| `register` / `login` / `refresh` | `POST /api/v1/auth/*` |
| `logout` | `POST /api/v1/auth/logout` with bearer + `{ refreshToken }` |
| `getLeaderboards` | `GET /api/v1/leaderboards?biomeId=&tier=` |
| `getSave` | `GET /api/v1/saves/current` with bearer |

Types come from `schema.d.ts`; the old hand-written `AuthTokens` export is **ABSENT**.

### Session handling

`AuthProvider` keeps the access token in React state only. The refresh token lives in `sessionStorage` under `aumbrye_refresh`. On mount it deletes legacy `localStorage` key `aumbrye_token`, restores the session via `refresh`, and schedules the next refresh 60 s before `accessTokenExpiresAt`. `signOut` clears both stores and calls `logout`. Register and login both call `applyAuth` immediately.

### Account page

`Account.tsx` uses react-query for `getSave`. It parses `stateJson` (not `state`) for `character.name` and `character.level`. A 401 after one refresh attempt surfaces "Session expired, please sign in again". Status messages use `role="status"`.

### Leaderboards page

`Leaderboards.tsx` loads biome ids from `biomes.json`, offers tiers 1â€“10, and uses react-query with skeleton rows, explicit error+retry, and "No entries yet" only when the API returns an empty `entries` array.

### Static content

`loader.ts` eagerly imports `content/wiki/*.md` and `content/patch-notes/*.md` via `gray-matter` front matter. The wiki FAQ states that cloud sync is manual from the game client, matching [`networking.md`](networking.md).

### SEO and prerender

`PageHelmet` sets title, description, canonical, and Open Graph tags per route. `vite.config.ts` prerenders `/`, `/account`, `/patch-notes`, `/wiki`, and `/leaderboards` at build time via `@prerenderer/rollup-plugin`.

### Quality gates

`npm run lint` enables `react-hooks` and `jsx-a11y`. `npm test` runs Vitest with MSW. CI also runs `generate:api` drift and Playwright smoke.

## Contracts

- Refresh token storage key: `aumbrye_refresh` (`sessionStorage`)
- Legacy key removed on load: `aumbrye_token` (`localStorage`)
- Save field read by account page: `stateJson`
- Client version header value: `package.json` `version` / `__APP_VERSION__` (`0.3.0`, matches `ApiVersions.ExpectedClientVersion`)
- OpenAPI logout route declared at `packages/shared/openapi/aumbrye-api.v1.yaml` (`POST /api/v1/auth/logout`)

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Routing + deep links | IMPLEMENTED | `App.tsx`, `Layout.tsx` |
| Typed API client | IMPLEMENTED | `client.ts`, `schema.d.ts` |
| Session refresh + logout | IMPLEMENTED | `AuthProvider.tsx` |
| Leaderboard loading states | IMPLEMENTED | `Leaderboards.tsx` |
| Markdown content | IMPLEMENTED | `content/wiki`, `content/patch-notes`, `loader.ts` |
| SEO metadata + prerender | IMPLEMENTED | `PageHelmet`, `vite.config.ts`, `public/*` |
| Unit + e2e tests | IMPLEMENTED | `src/**/*.test.tsx`, `e2e/smoke.spec.ts` |
| Landing screenshots | PLACEHOLDER | `Landing.tsx` "Screenshots coming soon" panel |
| API logout server handler | ABSENT on API host | OpenAPI contract present; see [`backend-api.md`](backend-api.md) |

## Related

- Improvement plan: [`../actual_improvements/website.md`](../actual_improvements/website.md) - **FINISHED**
- [`website-and-backend.md`](website-and-backend.md) â€” `VITE_API_URL`, CORS, deployment
- [`backend-api.md`](backend-api.md) â€” API routes this client calls
- [`ci-cd.md`](ci-cd.md) â€” the `web` job
