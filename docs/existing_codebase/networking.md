# Networking (Godot client)

Two files, 255 lines total: an autoload holding the base URL, two version constants, and two in-memory tokens; and a static-only `RefCounted` wrapping eight API paths in `HTTPRequest` calls. Online dungeon generation is compiled out by a `const false`. What remains live is cloud save pull and push, run completion reporting, and opt-in leaderboard submission — all fire-and-forget, all failing to a warning in the log.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/net/api_config.gd` | 26 lines. Autoload `ApiConfig` (`project.godot:34`). Base URL, version constants, token storage, header builder |
| `apps/game/client/scripts/net/api_client.gd` | 227 lines. `class_name ApiClient`. All static; never instantiated |
| `apps/game/client/config/dev_api.json` | 3 lines. One key, `apiBaseUrl`, read by nothing |

Callers: `apps/game/client/scripts/save/local_save.gd:461-497` (cloud pull and push), `apps/game/client/scripts/app/run_flow.gd:181-215,744,770` (online procgen, run completion, leaderboard submit).

## How it works

### `ApiConfig`

```
const DEFAULT_BASE_URL := "http://localhost:5000"   # api_config.gd:6
const CLIENT_VERSION := "0.3.0"                      # api_config.gd:7
const CONTENT_VERSION := "1"                         # api_config.gd:8
@export var base_url: String = DEFAULT_BASE_URL      # api_config.gd:10
var access_token: String = ""                        # api_config.gd:12
var refresh_token: String = ""                       # api_config.gd:13
```

`get_base_url()` strips whitespace and a trailing slash (`api_config.gd:16-17`). `auth_headers()` returns `Authorization: Bearer <token>`, `X-Client-Version`, `X-Content-Version`, and `Content-Type: application/json` (`api_config.gd:20-26`).

The `@export` on line 10 has no effect: `ApiConfig` is registered as a script autoload (`project.godot:34`), not a scene, so nothing can set the exported value, and no code reads `dev_api.json`'s `apiBaseUrl` into it. The base URL is always the compile-time constant.

`CLIENT_VERSION` and `CONTENT_VERSION` are duplicated from `packages/shared/Contracts/ApiVersions.cs:7-8` with no link between them.

Tokens live in memory only. Nothing writes them to `user://`, so every process launch starts unauthenticated.

### `ApiClient` paths

| Constant | Value | Backend route |
|----------|-------|---------------|
| `AUTH_REGISTER` | `/api/v1/auth/register` | matches `ApiEndpoints.cs:19` |
| `AUTH_LOGIN` | `/api/v1/auth/login` | matches `ApiEndpoints.cs:27` |
| `AUTH_REFRESH` | `/api/v1/auth/refresh` | matches `ApiEndpoints.cs:35` |
| `RUNS_CREATE` | `/api/v1/runs` | matches `ApiEndpoints.cs:59` (group `/api/v1/runs` + `MapPost("/")`; the same URL is used by the passing test at `AuthAndRunsTests.cs:109`) |
| `RUNS_DUNGEON` | `/api/v1/runs/%s/dungeon` | matches `ApiEndpoints.cs:88` |
| `RUNS_COMPLETE` | `/api/v1/runs/%s/complete` | matches `ApiEndpoints.cs:103` |
| `SAVES_CURRENT` | `/api/v1/saves/current` | matches `ApiEndpoints.cs:156,171` |
| `LEADERBOARDS_SUBMIT` | `/api/v1/leaderboards/submit` | matches `LeaderboardsEndpoints.cs:35` |

All eight paths are correct. `GET /api/v1/leaderboards` and `GET /api/v1/health` have no client constant — the game never reads a leaderboard and never probes reachability.

### Request payloads versus the server contract

| Call | Client payload | Server DTO | Match |
|------|----------------|-----------|-------|
| `register` / `login` | `{email, password}` | `RegisterRequest`, `LoginRequest` (`AuthContracts.cs:3,5`) | yes |
| `refresh_session` | `{refreshToken}` | `RefreshRequest` (`AuthContracts.cs:7`) | yes |
| `create_run` | `{biomeId, tier, seed?}` | `CreateRunRequest(BiomeId, Seed, Tier)` (`RunContracts.cs:3`) | yes |
| `complete_run` | `{outcome, elapsedSeconds, bossDefeated, lootClaimedInstanceIds}` | `CompleteRunRequest` (`RunContracts.cs:11`) | yes |
| `put_save` | `{stateJson, clientUpdatedAt?}` | `PutSaveRequest` (`SaveContracts.cs:7`) | yes |
| `submit_leaderboard` | `{biomeId, tier, elapsedSeconds, optIn}` | `SubmitLeaderboardRequest` (`LeaderboardsEndpoints.cs:54`) | yes |

Every outbound payload matches. The mismatch is on the way back in: see NET-01.

### `_request_json` — the single transport

`api_client.gd:168-210`. Per call it builds headers (authenticated or version-only), creates a new `HTTPRequest`, `add_child.call_deferred` on `Engine.get_main_loop().root`, awaits one `process_frame`, issues the request, awaits `request_completed`, then `queue_free()`s the node.

Body parsing (`api_client.gd:193-204`): if the trimmed body starts with `{` or `[` it is `JSON.parse_string`d; a non-dictionary result is wrapped as `{"raw": ...}`; anything else is truncated to 200 characters into `{"raw": ...}`.

Return shapes:

| Condition | Returned dictionary |
|-----------|---------------------|
| HTTP outside 2xx | `{ok: false, error: <body.error or body.raw or "HTTP nnn">, code: <status>, body: <dict>}` |
| 2xx and method is GET | `{ok: true, definition: <dict>}` |
| 2xx and method is not GET | `{ok: true, body: <dict>}` |
| `http.request()` returned non-`OK` | `{ok: false, error: "request failed"}` (no `code` key) |

`HTTPRequest.timeout` is never set, so it keeps Godot's default of 0 — no timeout. A server that accepts a connection and never responds leaves the `await` pending forever.

`_post_json_with_retry` (`api_client.gd:160-161`) performs exactly one request. There is no retry and no backoff anywhere in the file.

### Auth

`login` stores tokens from the response (`api_client.gd:21-24`). `_store_tokens` reads `body.tokens.accessToken` and `body.tokens.refreshToken` (`api_client.gd:213-216`), matching `AuthResponse` (`AuthContracts.cs:16`). It ignores `accessTokenExpiresAt`, so nothing schedules a proactive refresh.

`refresh_session` (`api_client.gd:27-35`) returns false when there is no refresh token, otherwise posts and re-stores. On failure it clears `access_token` but leaves `refresh_token` set, so the same dead token is retried on every subsequent 401.

`ensure_dev_session` (`api_client.gd:38-48`) is the only path any gameplay code uses to authenticate. If a token is already held it returns true. Otherwise it derives an email of `dev_<first 8 chars of OS.get_unique_id()>@test.local`, takes a password from `_dev_password()`, attempts `register`, and falls back to `login`.

`_dev_password()` (`api_client.gd:219-227`) reads `AUMBRYE_DEV_PASSWORD` from the environment, then `devPassword` from `apps/game/client/config/dev_api.json` (a key that file does not contain), then returns the literal `"devpassword123"`.

Every authenticated call — `create_run`, `complete_run`, `get_save`, `put_save`, `submit_leaderboard` — begins with `await ensure_dev_session()` and, on a 401, refreshes once and repeats the call.

### What actually runs

`run_flow.gd:17` declares `const USE_ONLINE_PROCgen := false`, and `run_flow.gd:181` guards `_try_online_generate` behind it. Online dungeon generation is unreachable; `LocalProcgen.generate` always runs (`run_flow.gd:185-192`). See [`local-procgen.md`](local-procgen.md).

Live network paths:

| Trigger | Call chain |
|---------|-----------|
| Run finalize (any outcome) | `run_flow.gd:744` `ApiClient.complete_run`, then `run_flow.gd:751` `LocalSave.push_to_cloud()` -> `local_save.gd:497` `ApiClient.put_save` |
| Escape with boss defeated and leaderboard opt-in | `run_flow.gd:770` `ApiClient.submit_leaderboard(current_biome_id, current_floor, elapsed, true)` |
| Explicit cloud pull | `local_save.gd:464` `ApiClient.get_save()` |

`_cloud_finalize_run` swallows failures into `push_warning` and suppresses the string `"auth failed"` entirely (`run_flow.gd:747-755`). Nothing surfaces in the UI. The run result screen is identical whether the server accepted the run or was never running.

`run_flow.gd:771` passes `current_floor` where the API expects `tier`; `create_run` passes `current_dungeon_tier` (`run_flow.gd:196`). The same run therefore reports two different tier values.

`local_save.gd:459-485` (`sync_from_cloud`) authenticates, calls `get_save()`, and bails when `stateJson` is empty. It also refuses to overwrite when a local active run exists (`local_save.gd:472-474`) and backs up the local save before applying server state (`local_save.gd:478-479`). `push_to_cloud` (`local_save.gd:489-515`) handles the 409 conflict by backing up, applying the server state, and returning `{ok: false, conflict: true}`.

The 409 branch in `put_save` reads `body.state` (`api_client.gd:132`), which is what the server's anonymous conflict object actually returns (`ApiEndpoints.cs:200`). That path is correct.

## Absent

- **Multiplayer, co-op, peer-to-peer, or dedicated-server code.** A repo-wide case-insensitive search for `multiplayer`, `dedicated_server`, `ENetMultiplayer`, `MultiplayerAPI`, `rpc(`, and `co-op` matches only prose under `docs/`. No `.gd`, `.tscn`, `.cs`, or `.ts` file matches. `project.godot` declares no `network/` settings.
- **Token persistence.** No `user://` write of `access_token` or `refresh_token`; `api_config.gd:12-13` are plain in-memory fields.
- **Reachability probe.** No call to `GET /api/v1/health` and no online/offline state anywhere.
- **Request timeout, retry, or backoff.** `HTTPRequest.timeout` is never assigned; `_post_json_with_retry` issues one request.
- **Request cancellation.** No `HTTPRequest.cancel_request()` call; nothing aborts in-flight requests on scene change or quit.
- **TLS.** The only base URL is `http://`. No certificate configuration, no `https` scheme anywhere in the client.
- **426 and 429 handling.** Neither status is matched anywhere; both fall through to the generic error string at `api_client.gd:206`.
- **Any UI for account state.** No login screen, no "signed in as", no cloud-sync indicator. Searched `apps/game/client/scenes/ui/` and `scripts/ui/`.
- **Unit or integration tests for this layer.** No validation suite exercises `ApiClient`; `m6_suite.gd:459` only asserts a wiring string, and `setup_suite.gd:27` only asserts the `ApiConfig` autoload exists.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| NET-01 | P0 | `get_save()` reads `result.body`, but `_request_json` returns GET results under `definition`. `stateJson` is therefore always `""`, `sync_from_cloud` always returns false, and cloud save pull has never worked. | `api_client.gd:107,110` vs `api_client.gd:208-209`; consumed at `local_save.gd:468-471` |
| NET-02 | P0 | `ensure_dev_session` silently registers a real account on whatever host `base_url` points at, using an email derived from the machine id and the hardcoded password `devpassword123`. This is on the run-completion path in shipped builds. | `api_client.gd:38-48,219-227`; reached from `run_flow.gd:744,751,770` |
| NET-03 | P0 | No request timeout. `HTTPRequest.timeout` is left at 0, so a reachable-but-unresponsive host suspends the `await` in `_cloud_finalize_run` indefinitely, during the run-result transition. | `api_client.gd:178-189`; called from `run_flow.gd:744` |
| NET-04 | P1 | Base URL is `http://`, so bearer tokens and full save state travel in cleartext. There is no way to configure `https` short of editing the constant. | `api_config.gd:6,10` |
| NET-05 | P1 | Leaderboard submission passes `current_floor` as `tier`, while `create_run` passes `current_dungeon_tier`. The board is keyed on the wrong value. | `run_flow.gd:771` vs `run_flow.gd:196` |
| NET-06 | P1 | `ApiConfig.base_url` cannot be configured. The `@export` is meaningless on a script autoload and `dev_api.json`'s `apiBaseUrl` is read by nothing. | `api_config.gd:10`, `project.godot:34`, `config/dev_api.json:2` (no reader in the repo) |
| NET-07 | P1 | Tokens are never persisted, so every launch performs a register-then-login round trip before the first cloud operation. | `api_config.gd:12-13` |
| NET-08 | P1 | `_post_json_with_retry` does not retry. There is no backoff on 5xx or 429 anywhere. | `api_client.gd:160-161` |
| NET-09 | P1 | A failed refresh clears `access_token` but keeps `refresh_token`, so a permanently invalid token is re-sent on every 401 for the rest of the session. | `api_client.gd:34` |
| NET-10 | P1 | Cloud failures are `push_warning` only and `"auth failed"` is suppressed outright. A player whose cloud save never syncs gets no signal. | `run_flow.gd:747-755`, `local_save.gd:466` |
| NET-11 | P1 | No test covers this layer. NET-01 is a one-word bug that any round-trip test would have caught. | No `ApiClient` reference in `scripts/validation/suites/` except the string at `m6_suite.gd:459` |
| NET-12 | P2 | `CLIENT_VERSION` and `CONTENT_VERSION` are hand-copied from `ApiVersions.cs`; nothing detects divergence. | `api_config.gd:7-8` vs `packages/shared/Contracts/ApiVersions.cs:7-8` |
| NET-13 | P2 | 426 (version mismatch) and 429 (rate limited) are indistinguishable from any other error, so the client cannot prompt for an update or back off. | `api_client.gd:205-207` |
| NET-14 | P2 | A fresh `HTTPRequest` node is created, deferred-added to the root window, and freed per call, with a single `process_frame` await standing in for tree-entry synchronization. | `api_client.gd:178-190` |
| NET-15 | P2 | In-flight requests are never cancelled. A scene change or quit during `_cloud_finalize_run` leaves an orphan node awaiting `request_completed`. | No `cancel_request` in the file |
| NET-16 | P2 | `USE_ONLINE_PROCgen` is a compile-time `false`, so `_try_online_generate`, `create_run`, and `get_dungeon` are dead code — roughly 60 lines across the two files that cannot execute. | `run_flow.gd:17,181` |
| NET-17 | P2 | The client never reads a leaderboard, only writes to one, so the in-game achievement for submitting is the only feedback a player gets. | No `GET /api/v1/leaderboards` constant in `api_client.gd:6-13` |
| NET-18 | P2 | `_dev_password()` looks for a `devPassword` key in `dev_api.json`, which that file does not define, so the fallback literal is always used unless `AUMBRYE_DEV_PASSWORD` is exported. | `api_client.gd:223-227` vs `config/dev_api.json:1-3` |

## Related

- Improvement plan: [`../actual_improvements/networking.md`](../actual_improvements/networking.md)
- [`backend-api.md`](backend-api.md) — the routes and DTOs on the other end
- [`local-save.md`](local-save.md) — `sync_from_cloud` and `push_to_cloud`
- [`local-procgen.md`](local-procgen.md) — what runs instead of `create_run`
- [`platform-and-net.md`](platform-and-net.md) — the Steam service that shares the "online" surface
- [`run-flow.md`](run-flow.md) — the callers at run finalize
