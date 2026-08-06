# Website — improvement plan

## Status: FINISHED

## Current state

The marketing site in `apps/web/` now uses `react-router-dom` 7 with deep-linkable routes, a typed OpenAPI-backed API client, `AuthProvider` session handling with scheduled refresh, `@tanstack/react-query` on API-backed pages, markdown-driven wiki and patch notes, Vitest/Playwright coverage, and SEO assets (helmet metadata, prerender, favicon, `robots.txt`, `sitemap.xml`). See [`../existing_codebase/website.md`](../existing_codebase/website.md).

## Gaps

| ID | Sev | Status | Gap | Evidence |
|----|-----|--------|-----|----------|
| WEB-01 | P0 | FINISHED | `loadCharacter` reads `stateJson` | `apps/web/src/pages/Account.tsx`; regression in `apps/web/src/pages/Account.test.tsx` |
| WEB-02 | P0 | FINISHED | Real routing with `BrowserRouter` | `apps/web/src/App.tsx` |
| WEB-03 | P1 | FINISHED | `request` helper checks `res.ok`, timeout, version headers | `apps/web/src/api/client.ts`; `apps/web/src/api/client.test.ts` |
| WEB-04 | P1 | FINISHED | Access token in memory; refresh in `sessionStorage` | `apps/web/src/auth/AuthProvider.tsx` |
| WEB-05 | P1 | FINISHED | Register signs in immediately | `apps/web/src/pages/Account.tsx`; `Account.test.tsx` |
| WEB-06 | P1 | FINISHED | Sign out calls logout and clears stores | `AuthProvider.tsx`; `client.ts:logout` |
| WEB-07 | P1 | FINISHED | Vitest + MSW tests; CI `npm test -- --coverage` | `apps/web/src/**/*.test.tsx`; `.github/workflows/ci.yml` |
| WEB-08 | P1 | FINISHED | Generated `schema.d.ts`; hand-written `AuthTokens` removed | `apps/web/src/api/schema.d.ts`; `npm run generate:api` |
| WEB-09 | P1 | FINISHED | Biomes from `src/content/biomes.json`; tiers 1–10 | `apps/web/src/pages/Leaderboards.tsx` |
| WEB-10 | P1 | FINISHED | `eslint-plugin-react-hooks` enabled | `apps/web/eslint.config.js` |
| WEB-11 | P2 | FINISHED | `react-helmet-async`, prerender, favicon, robots, sitemap | `Layout.tsx`, `vite.config.ts`, `apps/web/public/*` |
| WEB-12 | P2 | FINISHED | Honest screenshots panel | `apps/web/src/pages/Landing.tsx` |
| WEB-13 | P2 | FINISHED | Mailing-list CTA until Steam app id exists | `Landing.tsx:19-24` |
| WEB-14 | P2 | FINISHED | Wiki/patch notes in markdown | `apps/web/content/wiki/*.md`, `content/patch-notes/*.md`, `loader.ts` |
| WEB-15 | P2 | FINISHED | Site version `0.3.0` via `__APP_VERSION__` | `package.json`, `vite.config.ts`, footer in `Layout.tsx` |
| WEB-16 | P2 | FINISHED | react-query loading/cancel on leaderboards | `Leaderboards.tsx`; `Leaderboards.test.tsx` |
| WEB-17 | P2 | FINISHED | `ErrorBoundary` around app | `main.tsx`, `ErrorBoundary.tsx` |
| WEB-18 | P2 | FINISHED | Skip link, `aria-current`, table caption, live regions, focus/motion CSS | `Layout.tsx`, `index.css` |
| WEB-19 | P2 | FINISHED | `.nvmrc` + `engines.node >=24` | `apps/web/.nvmrc`, `package.json` |
| WEB-20 | P2 | FINISHED | FAQ matches manual cloud sync behavior | `apps/web/content/wiki/faq.md` |

## Target design

Implemented as specified in the original plan: typed API client from OpenAPI, react-router routes, AuthProvider with in-memory access token and `sessionStorage` refresh token, react-query data fetching, markdown content pipeline, Vitest/Playwright gates, and SEO prerender for static routes.

## Work plan

All 13 steps landed. Backend logout route is declared in `packages/shared/openapi/aumbrye-api.v1.yaml`; the API implementation remains tracked in [`backend-api.md`](backend-api.md).

## Data and schema changes

No `content/schemas/` change and no save-format change — **no `save_migrator.gd` version bump**.

## Acceptance criteria

- [x] Signing in on the account page renders the character name and level from the API.
- [x] A 401 from `GET /saves/current` shows an explicit "Session expired, please sign in again" message.
- [x] `/wiki/controls`, `/patch-notes/0.6.0`, and `/leaderboards?biomeId=crystal_caverns&tier=3` all load directly from a cold browser and render the right content.
- [x] The browser back button moves between site pages.
- [x] Prerender configured for static routes via `@prerenderer/rollup-plugin` in `vite.config.ts`.
- [x] Every route sets a unique `<title>` and `<meta name="description">` via `PageHelmet`.
- [x] `robots.txt` and `sitemap.xml` are served and the sitemap lists prerendered routes.
- [x] Scheduled refresh 60 s before `accessTokenExpiresAt` in `AuthProvider`.
- [x] Sign out clears both stores and returns to the login form.
- [x] Registering signs the user in with no second form submission.
- [x] Leaderboard page shows skeleton, error with retry, and "No entries yet" only for empty API responses.
- [x] The tier selector offers 1 through 10.
- [x] `npm run lint` uses `react-hooks` and `jsx-a11y` with `--max-warnings 0`.
- [x] `npm test` and Playwright smoke configured in CI.
- [x] Thrown render errors show fallback UI.
- [x] Skip link, `aria-current`, keyboard focus styles.
- [x] `npm run generate:api` drift check in CI.

## Validation

| Test file | Asserts |
|-----------|---------|
| `api/client.test.ts` | `ApiError` on 400; 200 resolve; version headers; timeout abort |
| `pages/Account.test.tsx` | `stateJson` character line; 401 session-expired; register sign-in; sign-out clears `sessionStorage` |
| `auth/AuthProvider.test.tsx` | Refresh 60 s before expiry; failed refresh signs out |
| `pages/Leaderboards.test.tsx` | Skeleton, 500 error+retry, empty list, query-string refetch |
| `App.test.tsx` | Nav routing + `aria-current`; `NotFound` |
| `components/ErrorBoundary.test.tsx` | Fallback on throw |
| `e2e/smoke.spec.ts` | Full nav journey, deep link, mocked register + character line |

CI (`web` job): lint, `npm test -- --coverage`, `generate:api` drift, build, Playwright smoke.

## Related

- Existing behavior: [`../existing_codebase/website.md`](../existing_codebase/website.md)
- [`website-and-backend.md`](website-and-backend.md) — CORS, `VITE_API_URL`, deployment
- [`backend-api.md`](backend-api.md) — logout implementation on API host
- [`packages.md`](packages.md) — OpenAPI contract
- [`ci-cd.md`](ci-cd.md) — the `web` job
