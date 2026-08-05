# Website — improvement plan

## Current state

Five pages, no router, two API-backed pages, no tests, one 225-line stylesheet (see [`../existing_codebase/website.md`](../existing_codebase/website.md)). Two P0 defects: the account page reads the wrong field name so the character summary never renders, and the absence of a router makes every page unlinkable and unindexable. The site is also unusable in a browser today because the API sends no CORS headers — that half is tracked in [`website-and-backend.md`](website-and-backend.md).

## Gaps

Carried from [`../existing_codebase/website.md`](../existing_codebase/website.md): WEB-01 through WEB-20.

## Target design

### 1. Typed, generated API client (WEB-01, WEB-03, WEB-08)

Stop hand-writing DTO shapes. Generate them from the OpenAPI spec once [`backend-api.md`](backend-api.md) step 11 lands, and hand-write only the transport layer.

`package.json` gains `openapi-typescript` as a dev dependency and a script:

```json
"generate:api": "openapi-typescript ../../packages/shared/openapi/aumbrye-api.v1.yaml -o src/api/schema.d.ts"
```

`src/api/client.ts` becomes a single `request` helper plus thin wrappers:

```ts
import type { paths } from "./schema";

const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:5000";
const CLIENT_VERSION = "0.4.0";
const CONTENT_VERSION = "1";

export class ApiError extends Error {
  constructor(readonly status: number, readonly detail: string) {
    super(detail);
  }
}

async function request<T>(path: string, init: RequestInit = {}, timeoutMs = 10_000): Promise<T> {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(), timeoutMs);
  try {
    const res = await fetch(`${API_URL}${path}`, {
      ...init,
      signal: init.signal ?? controller.signal,
      headers: {
        "Content-Type": "application/json",
        "X-Client-Version": CLIENT_VERSION,
        "X-Content-Version": CONTENT_VERSION,
        ...init.headers,
      },
    });
    if (!res.ok) {
      const problem = await res.json().catch(() => ({}));
      throw new ApiError(res.status, problem.detail ?? problem.error ?? res.statusText);
    }
    return res.status === 204 ? (undefined as T) : ((await res.json()) as T);
  } finally {
    clearTimeout(timer);
  }
}
```

Every caller then handles `ApiError` explicitly. Delete the unused `AuthTokens` type; the generated `components["schemas"]["AuthResponse"]` replaces it, and `stateJson` versus `state` stops being possible to get wrong because `tsc` fails on the typo. Regeneration runs in CI as a drift check alongside the backend job described in [`ci-cd.md`](ci-cd.md).

### 2. Real routing (WEB-02, WEB-11)

Add `react-router` 7 in declarative mode:

| Route | Component | Notes |
|-------|-----------|-------|
| `/` | `Landing` | |
| `/account` | `Account` | |
| `/patch-notes` | `PatchNotes` | |
| `/patch-notes/:version` | `PatchNoteDetail` | new, deep-linkable |
| `/wiki` | `WikiIndex` | new index |
| `/wiki/:slug` | `WikiPage` | deep-linkable, matches the existing `slug` field |
| `/leaderboards` | `Leaderboards` | biome and tier read from and written to the query string |
| `*` | `NotFound` | new |

The nav becomes `<NavLink>` so the active state and `aria-current="page"` come for free. The leaderboard selectors move to `useSearchParams` so a filtered board is a shareable URL.

For indexing, add `vite-plugin-ssg` style prerendering via `vite-react-ssg`, or simpler and preferred here: keep the SPA and add a build-time prerender of the five static routes with `@prerenderer/rollup-plugin`. Marketing pages must return real HTML to a crawler; the account and leaderboard pages do not need it. Per-route `<title>`, `<meta name="description">`, canonical link, and Open Graph tags are set with `react-helmet-async`. Add `public/favicon.svg`, `public/robots.txt`, and a generated `public/sitemap.xml`.

Rejected alternative: migrating to Next.js. It would deliver SSR and metadata handling out of the box but replaces the build system, the deploy target, and the CI job for a five-page site.

### 3. Session handling (WEB-04, WEB-05, WEB-06)

The current model — access token in `localStorage`, refresh token discarded — is both insecure and broken after 15 minutes. Target:

- Keep the access token in memory only, inside an `AuthProvider` context.
- Keep the refresh token in `sessionStorage` under `aumbrye_refresh`, not `localStorage`, so it dies with the tab. A `HttpOnly` cookie would be strictly better but requires the API to set cookies and a shared parent domain; revisit when the deployment topology is fixed in [`website-and-backend.md`](website-and-backend.md).
- `AuthProvider` schedules a refresh at `accessTokenExpiresAt` minus 60 seconds and retries once on a 401.
- `handleRegister` stores the returned tokens and navigates to the signed-in view; no second login.
- Add a "Sign out" button calling `POST /api/v1/auth/logout` (added in [`backend-api.md`](backend-api.md) step 9) and clearing both stores.
- Migrate away from the existing `aumbrye_token` key by deleting it on first load.

### 4. Data fetching and states (WEB-09, WEB-16, WEB-17)

- Add `@tanstack/react-query` for the two API-backed pages. It gives loading, error, retry, cancellation, and cache invalidation without hand-rolling four `useState` variables per page.
- Replace the hardcoded biome array with a `GET /api/v1/biomes` call, or, if that route is not added, import the ids from a single generated `src/content/biomes.json` emitted by the procgen CLI so the list has one source. Extend the tier selector to 1-10 to match the API.
- Add an `ErrorBoundary` around `<App />` in `main.tsx` rendering a recoverable fallback.
- Distinguish three leaderboard states explicitly: loading (skeleton rows), error (message plus retry button), empty (the existing "No entries yet").

### 5. Content pipeline (WEB-14, WEB-15, WEB-20)

Move wiki and patch-note bodies to markdown files under `apps/web/content/wiki/*.md` and `apps/web/content/patch-notes/*.md` with YAML front matter (`slug`, `title`, `date`, `version`, `highlights`), loaded through `import.meta.glob` with `vite-plugin-markdown`. Authors edit markdown; the route table is derived from the glob. This keeps the static-hosting model while removing JSX edits from the content path.

Derive the displayed version from a single source: add `"version"` to `apps/web/package.json` matching `ApiVersions.ExpectedClientVersion`, expose it as `__APP_VERSION__` via `define` in `vite.config.ts`, and render it in the footer. Patch-note versions stay independent because they are game versions, but add a note distinguishing them.

Fix the wiki FAQ claim about automatic cloud sync to match what [`networking.md`](networking.md) says the client actually does.

### 6. Quality gates (WEB-07, WEB-10, WEB-18, WEB-19)

- Add Vitest with `jsdom` and `@testing-library/react`, plus `@vitest/coverage-v8`. Add `"test": "vitest run"` and `"test:watch": "vitest"` and wire `npm test` into the `web` CI job.
- Add Playwright for one smoke journey against a mocked API, run in the same job with `npx playwright install --with-deps chromium`.
- Install `eslint-plugin-react-hooks` and `eslint-plugin-jsx-a11y` and add both to `eslint.config.js`. `jsx-a11y` catches most of WEB-18 automatically.
- Add a skip link, `aria-current` via `NavLink`, a `<caption class="visually-hidden">` on the leaderboard table, `role="status"` on the account message paragraph, `:focus-visible` outlines, and a `prefers-reduced-motion` block in `index.css`.
- Add `.nvmrc` containing `24` and `"engines": { "node": ">=24" }` to `package.json`.

### 7. Content and assets (WEB-12, WEB-13)

Replace the three placeholder divs with real screenshots served as `<picture>` elements with AVIF and WebP sources and explicit `width`/`height` to avoid layout shift, or, until art exists, a single honest "Screenshots coming soon" panel rather than three empty boxes. Point the Steam CTA at the real app page once the app id exists; until then link to a mailing-list signup rather than the generic store front.

## Work plan

1. **Fix the save field name** — change `save.state` to `save.stateJson` in `Account.tsx:37-39`, add an error branch for non-2xx. One-line fix, ship immediately. (WEB-01)
2. **Add the `request` helper with `res.ok`, timeout, and version headers**; convert all four functions. (WEB-03)
3. **Add Vitest and the first tests** — see Validation below. Do this before the router refactor so the refactor has a safety net. (WEB-07)
4. **Add `eslint-plugin-react-hooks` and `eslint-plugin-jsx-a11y`**, fix what they flag. (WEB-10, part of WEB-18)
5. **Introduce react-router** with the route table above, `NavLink` nav, `useSearchParams` on leaderboards, and a `NotFound` route. (WEB-02)
6. **Add `AuthProvider`** with in-memory access token, `sessionStorage` refresh token, scheduled refresh, sign-out button, and register-then-signed-in. Depends on the logout route from [`backend-api.md`](backend-api.md) step 9. (WEB-04, WEB-05, WEB-06)
7. **Add react-query** and the three explicit leaderboard states; extend tiers to 10; single-source the biome list. (WEB-09, WEB-16)
8. **Add the error boundary.** (WEB-17)
9. **Add SEO** — `react-helmet-async`, prerender plugin, favicon, `robots.txt`, sitemap. (WEB-11)
10. **Generate the API types** from the OpenAPI spec and delete hand-written DTO shapes. Depends on [`backend-api.md`](backend-api.md) step 11. (WEB-08)
11. **Move content to markdown** and unify the version display. (WEB-14, WEB-15, WEB-20)
12. **Add `.nvmrc`, `engines`, Playwright smoke, and the remaining accessibility affordances.** (WEB-18, WEB-19)
13. **Replace the placeholder art and the Steam link.** (WEB-12, WEB-13)

Step 1 is independent and should land today. Steps 6 and 10 have backend dependencies; everything else is self-contained.

## Data and schema changes

No `content/schemas/` change and no save-format change, so **no `save_migrator.gd` version bump**.

New files under `apps/web/`: `.nvmrc`, `public/favicon.svg`, `public/robots.txt`, `public/sitemap.xml`, `src/api/schema.d.ts` (generated), `src/auth/AuthProvider.tsx`, `src/components/ErrorBoundary.tsx`, `src/components/NotFound.tsx`, `content/wiki/*.md`, `content/patch-notes/*.md`, `src/**/*.test.tsx`, `e2e/smoke.spec.ts`, `playwright.config.ts`, `vitest.config.ts`.

Removed: `src/content/wiki/pages.json`, `src/content/patch-notes/entries.json` (converted to markdown).

New dependencies: `react-router` 7, `@tanstack/react-query` 5, `react-helmet-async` 2. New dev dependencies: `vitest`, `@vitest/coverage-v8`, `jsdom`, `@testing-library/react`, `@testing-library/user-event`, `@testing-library/jest-dom`, `msw`, `@playwright/test`, `eslint-plugin-react-hooks`, `eslint-plugin-jsx-a11y`, `openapi-typescript`, `vite-plugin-markdown`, `@prerenderer/rollup-plugin`.

## Acceptance criteria

- [ ] Signing in on the account page renders the character name and level from the API.
- [ ] A 401 from `GET /saves/current` shows an explicit "Session expired, please sign in again" message.
- [ ] `/wiki/controls`, `/patch-notes/0.6.0`, and `/leaderboards?biomeId=crystal_caverns&tier=3` all load directly from a cold browser and render the right content.
- [ ] The browser back button moves between site pages.
- [ ] `curl https://<site>/wiki/controls` returns HTML containing the controls text (prerender working).
- [ ] Every route sets a unique `<title>` and `<meta name="description">`.
- [ ] `robots.txt` and `sitemap.xml` are served and the sitemap lists every prerendered route.
- [ ] After 16 minutes of idle, the account page is still signed in and still loads the character (refresh working).
- [ ] Sign out clears both stores and returns to the login form; reloading does not restore the session.
- [ ] Registering signs the user in with no second form submission.
- [ ] The leaderboard page shows a skeleton while loading, an error with a retry button on failure, and "No entries yet" only when the API returns an empty list.
- [ ] The tier selector offers 1 through 10.
- [ ] `npm run lint` passes with `react-hooks` and `jsx-a11y` enabled and `--max-warnings 0`.
- [ ] `npm test` runs and passes; coverage over `src/api` and `src/auth` is above 80 percent.
- [ ] `npx playwright test` passes the smoke journey against a mocked API.
- [ ] A thrown render error shows the fallback UI instead of a blank page.
- [ ] Keyboard-only navigation reaches every control, the active nav item reports `aria-current="page"`, and a skip link is the first focusable element.
- [ ] `npm run generate:api` produces no diff in CI.

## Validation

Vitest unit and component tests in `apps/web/src/`, with MSW mocking the API:

| Test file | Asserts |
|-----------|---------|
| `api/client.test.ts` | `request` throws `ApiError` with the status and detail on 400/401/500; resolves on 200; aborts after the timeout; sends both version headers |
| `pages/Account.test.tsx` | Renders the character name and level from a `stateJson` payload — this is the regression test for WEB-01 |
| `pages/Account.test.tsx` | A 401 from `getSave` renders the session-expired message |
| `pages/Account.test.tsx` | Register stores tokens and lands on the signed-in view without a second submit |
| `pages/Account.test.tsx` | Sign out clears `sessionStorage` and returns to the form |
| `auth/AuthProvider.test.tsx` | Refreshes 60 seconds before expiry using fake timers; a failed refresh signs out |
| `pages/Leaderboards.test.tsx` | Loading skeleton, then rows; a 500 renders the error with a retry button; an empty list renders "No entries yet" |
| `pages/Leaderboards.test.tsx` | Changing the biome updates the query string and refetches |
| `App.test.tsx` | Every nav link routes to the right page and sets `aria-current` |
| `App.test.tsx` | An unknown path renders `NotFound` |
| `components/ErrorBoundary.test.tsx` | A child that throws renders the fallback |

Playwright, `apps/web/e2e/smoke.spec.ts`: load `/`, follow the nav to each of the five pages asserting the URL and heading, deep-link to `/wiki/controls`, register and sign in against the mock, and assert the character line renders.

CI additions to the `web` job in `.github/workflows/ci.yml`: `npm test -- --coverage`, `npm run generate:api && git diff --exit-code src/api/schema.d.ts`, and the Playwright run. See [`ci-cd.md`](ci-cd.md).

## Related

- Existing behavior: [`../existing_codebase/website.md`](../existing_codebase/website.md)
- [`website-and-backend.md`](website-and-backend.md) — CORS, `VITE_API_URL`, deployment
- [`backend-api.md`](backend-api.md) — logout, ProblemDetails, generated spec
- [`packages.md`](packages.md) — the OpenAPI contract the types come from
- [`ci-cd.md`](ci-cd.md) — the `web` job and the new gates
