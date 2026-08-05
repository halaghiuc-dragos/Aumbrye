# Website

React 19 + Vite 6 + TypeScript single-page marketing and account site in `apps/web/`. Five pages selected by a `useState` value; there is no router. Two pages are pure static content compiled from JSON, two call the API, one is a landing page with placeholder art slots. No tests.

## Files

| Path | Role |
|------|------|
| `apps/web/index.html` | 12 lines. Root div and the `main.tsx` module script |
| `apps/web/src/main.tsx` | 10 lines. `createRoot` in `StrictMode` |
| `apps/web/src/App.tsx` | 52 lines. Header, nav, page switch, footer |
| `apps/web/src/pages/Landing.tsx` | 28 lines. Hero, Steam CTA, three placeholder screenshot slots |
| `apps/web/src/pages/Account.tsx` | 82 lines. Login/register form, character summary |
| `apps/web/src/pages/Leaderboards.tsx` | 80 lines. Biome and tier selectors, results table |
| `apps/web/src/pages/Wiki.tsx` | 15 lines. Renders `content/wiki/pages.json` |
| `apps/web/src/pages/PatchNotes.tsx` | 22 lines. Renders `content/patch-notes/entries.json` |
| `apps/web/src/api/client.ts` | 38 lines. Four `fetch` wrappers |
| `apps/web/src/content/wiki/pages.json` | 3 wiki pages: controls, biomes, faq |
| `apps/web/src/content/patch-notes/entries.json` | 2 entries: 0.6.0 and 0.5.0 |
| `apps/web/src/index.css` | 225 lines, hand-written, one media query |
| `apps/web/src/vite-env.d.ts` | Types `import.meta.env.VITE_API_URL` |
| `apps/web/vite.config.ts` | 6 lines. `plugins: [react()]` and nothing else |
| `apps/web/tsconfig.app.json` | `strict`, `noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch` all on |
| `apps/web/eslint.config.js` | Flat config: `js.configs.recommended` + `tseslint.configs.recommended` |
| `apps/web/package.json` | `dev`, `build` (`tsc -b && vite build`), `preview`, `lint` (`--max-warnings 0`) |
| `apps/web/.env.example` | `VITE_API_URL=http://localhost:5000` |

Tracked: 21 files (`git ls-files apps/web`). Untracked and present on disk: `.env.development`, `dist/`, `node_modules/`.

Dependencies are `react` and `react-dom` only (`package.json:12-15`). No router, no state library, no CSS framework, no data-fetching library, no test runner.

## How it works

### Navigation

`App.tsx:8` declares `type Page = "home" | "account" | "patch-notes" | "wiki" | "leaderboards"`. `App.tsx:19` holds the current page in `useState`, `App.tsx:28-37` renders one nav button per entry of the `NAV` array, and `App.tsx:41-45` renders the matching component with `&&` guards.

Consequences: the URL never changes, every page is `/`, there is no browser history, no deep link, no bookmark, no back button, no 404 route, and no server-side rendering or prerender. Crawlers see only the landing page.

### API client

`client.ts:1` resolves `const API_URL = import.meta.env.VITE_API_URL ?? "http://localhost:5000"`. Vite inlines this at build time, so the deployed bundle hardcodes whatever `VITE_API_URL` was set to during `npm run build`.

Four functions, all the same shape — `fetch`, then `return res.json()` with no status check:

| Function | Request | Notes |
|----------|---------|-------|
| `register(email, password)` | `POST /api/v1/auth/register` | `client.ts:9-16` |
| `login(email, password)` | `POST /api/v1/auth/login` | `client.ts:18-25` |
| `getLeaderboards(biomeId, tier=1)` | `GET /api/v1/leaderboards?biomeId=&tier=` | `client.ts:27-31`. Never sends `limit` |
| `getSave(accessToken)` | `GET /api/v1/saves/current` with `Authorization: Bearer` | `client.ts:33-38` |

No `AbortController`, no timeout, no retry, no refresh-token handling, no `X-Client-Version` or `X-Content-Version` header. The version headers are optional server-side (`services/backend/src/Aumbrye.Api/Middleware/VersionHeaderMiddleware.cs:18,29`) so omitting them passes.

`client.ts:3-7` exports a type `AuthTokens` with fields `accessToken`, `refreshToken`, `expiresAt`. Nothing imports it, and the backend field is `accessTokenExpiresAt` (`packages/shared/Contracts/Auth/AuthContracts.cs:12`), so the type is both unused and wrong.

### Account page

`Account.tsx:7` seeds the token from `localStorage.getItem("aumbrye_token")`. `handleLogin` (`Account.tsx:11-23`) checks `data.error`, reads `data.tokens?.accessToken`, writes it to state and to `localStorage`, then calls `loadCharacter`. `handleRegister` (`Account.tsx:25-33`) shows "Registered — you can log in now" and **discards the token pair the register endpoint already returned** (`services/backend/src/Aumbrye.Api/Endpoints/ApiEndpoints.cs:24`), forcing a second round trip.

`loadCharacter` (`Account.tsx:35-47`) reads `save.state`. The endpoint returns `stateJson` (`packages/shared/Contracts/Saves/SaveContracts.cs:4`, serialized at `ApiEndpoints.cs:168`), so the `if (save.state)` guard is always false and the character line never renders. There is no error branch: a 401 falls through silently.

Only the access token is stored. The refresh token is never captured, so the session ends after the 15-minute access-token lifetime with no recovery path, and there is no log-out control to clear `localStorage`.

`Account.tsx:79` renders the line "OAuth (Google/Discord) deferred to post-EA — see known issues."

### Leaderboards page

`Leaderboards.tsx:4-10` hardcodes the five biome ids and labels, duplicating `packages/procedural/Biome/BiomeCatalog.cs`. The tier selector offers 1 through 5 (`Leaderboards.tsx:46`) while the API accepts 1 through 10 (`services/backend/src/Aumbrye.Application/Services/RunService.cs:42`).

`useEffect` (`Leaderboards.tsx:25-32`) refetches on every biome or tier change. `.then` sets `data.entries ?? []`; `.catch` sets a fixed message "Could not load leaderboards. Is the API running?". Because `client.ts:30` returns `res.json()` regardless of status, a 500 with a JSON error body lands in `.then`, produces `entries = []`, and renders "No entries yet" instead of an error. There is no loading state and no `AbortController`, so rapid selector changes can race.

### Static content pages

`Wiki.tsx:1` and `PatchNotes.tsx:1` import their JSON directly, so the content is bundled at build time and TypeScript infers the shape from the literal. Editing content requires a rebuild and redeploy. The wiki has 3 pages; patch notes have 2 entries, newest `0.6.0` dated 2026-07-31.

Three unrelated version numbers coexist: `package.json:4` says `0.1.0`, the newest patch note says `0.6.0`, and `ApiVersions.ExpectedClientVersion` says `0.3.0`.

### Styling

One hand-written stylesheet, `index.css`, 225 lines. Content is capped at `max-width: 960px` (`index.css:65`), forms at `32rem` (`index.css:94`), and there is a single breakpoint at `600px` that stacks the header (`index.css:220-225`). No CSS modules, no preprocessor, no design tokens beyond raw hex values. No `prefers-reduced-motion` block and no `:focus-visible` rules.

### Build and lint

`npm run build` runs `tsc -b && vite build`, so type errors fail the build. `tsconfig.app.json:15-19` enables `strict`, `noUnusedLocals`, `noUnusedParameters`, `noFallthroughCasesInSwitch`, and `noUncheckedSideEffectImports`. `npm run lint` runs `eslint src --max-warnings 0`. Both run in CI (`.github/workflows/ci.yml`, `web` job).

`eslint.config.js:8` extends only `js.configs.recommended` and `tseslint.configs.recommended`. Neither `eslint-plugin-react-hooks` nor `eslint-plugin-react-refresh` is installed, so the exhaustive-deps rule that would flag the `useEffect` in `Leaderboards.tsx` is not enforced.

`vite.config.ts` sets only the React plugin: no `base`, no `build.outDir` or `sourcemap`, no `server.proxy`. A dev proxy would have hidden the missing backend CORS policy; without one the site cannot talk to the API from a browser at all (see [`website-and-backend.md`](website-and-backend.md)).

## Absent

- **Router.** No `react-router`, `wouter`, `@tanstack/router`, or any history manipulation. Verified by `package.json:12-26` and by the `useState` switch at `App.tsx:19`.
- **Tests.** No `vitest`, `jest`, `@testing-library/*`, `playwright`, or `*.test.tsx` under `apps/web`. The `web` CI job runs lint and build only.
- **Error boundary, suspense, loading states, and empty-vs-error distinction.** No `ErrorBoundary` component anywhere.
- **SEO and social metadata.** `index.html` has only `charset`, `viewport`, and `<title>Aumbrye</title>` — no description, canonical, Open Graph, Twitter card, favicon, `robots.txt`, or sitemap.
- **Analytics, cookie consent, privacy policy, terms.** No such page or script.
- **Accessibility affordances.** No skip link, no `aria-current` on the active nav button, no `<caption>` on the leaderboard table, no live region for the status message, no focus styles beyond browser defaults.
- **Token refresh and logout.** `client.ts` has no `refresh` function; `Account.tsx` has no sign-out control.
- **Download or press-kit page.** The only outbound link is the generic Steam store front (`Landing.tsx:13`).
- **`.nvmrc` or `engines`.** CI pins Node 24 in the workflow only.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| WEB-01 | P0 | `loadCharacter` reads `save.state` but the API returns `stateJson`. The signed-in character summary never renders, which is the only reason the account page exists. | `Account.tsx:37-39` vs `packages/shared/Contracts/Saves/SaveContracts.cs:4` |
| WEB-02 | P0 | No router. Every page is `/`, so no page can be linked, bookmarked, shared, or indexed, and the back button leaves the site. | `App.tsx:19,41-45`; no router dependency at `package.json:12-15` |
| WEB-03 | P1 | Every API call returns `res.json()` without checking `res.ok`, so HTTP errors are indistinguishable from empty results. | `client.ts:15,24,30,37` |
| WEB-04 | P1 | The access token is stored in `localStorage`, readable by any injected script, and the refresh token is discarded, so the session silently dies after 15 minutes. | `Account.tsx:7,20`; lifetime at `services/backend/src/Aumbrye.Api/appsettings.json:14` |
| WEB-05 | P1 | Registration discards the token pair the API already returned and asks the user to log in again. | `Account.tsx:27-33` vs `services/backend/src/Aumbrye.Api/Endpoints/ApiEndpoints.cs:24` |
| WEB-06 | P1 | No log-out control. `aumbrye_token` can only be cleared through devtools. | `Account.tsx:52-59` |
| WEB-07 | P1 | Zero tests. The `web` CI job runs lint and build only, so WEB-01 shipped undetected. | No test file under `apps/web`; `.github/workflows/ci.yml` `web` job |
| WEB-08 | P1 | The exported `AuthTokens` type is unused and its `expiresAt` field does not match the API's `accessTokenExpiresAt`. | `client.ts:3-7` vs `packages/shared/Contracts/Auth/AuthContracts.cs:12` |
| WEB-09 | P1 | The biome list is hardcoded in the page and duplicates `BiomeCatalog`; the tier selector stops at 5 while the API accepts 10. | `Leaderboards.tsx:4-10,46` vs `services/backend/src/Aumbrye.Application/Services/RunService.cs:42` |
| WEB-10 | P1 | `eslint-plugin-react-hooks` is not installed, so `useEffect` dependency errors are not caught. | `eslint.config.js:8`, `package.json:16-26` |
| WEB-11 | P2 | No SEO or social metadata, no favicon, no `robots.txt`, no sitemap. A marketing site cannot be indexed or shared. | `index.html:3-7` |
| WEB-12 | P2 | The landing page ships three literal placeholder divs reading "Trailer / screenshot slot", "Biome showcase", "Combat highlight". | `Landing.tsx:22-24` |
| WEB-13 | P2 | The Steam CTA points at `https://store.steampowered.com/`, the generic store front, not an app page. | `Landing.tsx:13` |
| WEB-14 | P2 | Wiki and patch notes are compiled into the bundle; publishing a patch note requires a code change, a CI run, and a redeploy. | `Wiki.tsx:1`, `PatchNotes.tsx:1` |
| WEB-15 | P2 | Three unrelated version numbers: package `0.1.0`, newest patch note `0.6.0`, expected client `0.3.0`. | `package.json:4`, `src/content/patch-notes/entries.json:4`, `packages/shared/Contracts/ApiVersions.cs:7` |
| WEB-16 | P2 | No loading state and no request cancellation on the leaderboards fetch; fast selector changes can render a stale response. | `Leaderboards.tsx:25-32` |
| WEB-17 | P2 | No error boundary. A render-time exception blanks the whole page. | `main.tsx:6-10` |
| WEB-18 | P2 | Accessibility: no skip link, no `aria-current` on the active nav button, no table caption, no live region for status text, no `:focus-visible` or `prefers-reduced-motion` rules. | `App.tsx:28-37`, `Leaderboards.tsx:54-61`, `Account.tsx:78`, `index.css` |
| WEB-19 | P2 | No `.nvmrc` or `engines` field; the Node version exists only in the workflow. | `package.json:1-27` |
| WEB-20 | P2 | The wiki FAQ states "local save syncs to cloud when logged in", which the Godot client does not do automatically. | `src/content/wiki/pages.json:16`; see [`networking.md`](networking.md) |

## Related

- Improvement plan: [`../actual_improvements/website.md`](../actual_improvements/website.md)
- [`website-and-backend.md`](website-and-backend.md) — `VITE_API_URL`, CORS, the OpenAPI contract
- [`backend-api.md`](backend-api.md) — the routes this client calls
- [`ci-cd.md`](ci-cd.md) — the `web` job
