# Networking (Godot client)

Autoload `ApiConfig` holds the resolved base URL, cloud-state enum, encrypted session metadata, and a two-node `HTTPRequest` pool. Static `ApiClient` wraps auth, runs, saves, and leaderboards behind a unified `_request_json` transport with timeout, retry, and status handling. Online dungeon generation remains compiled out (`USE_ONLINE_PROCgen := false`); live paths are explicit sign-in, cloud save pull/push, run completion, and opt-in leaderboard read/write â€” all non-blocking on the result-screen transition.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/net/api_config.gd` | Autoload `ApiConfig` (`project.godot:35`). Base URL resolution, `CloudState`, token storage, session file I/O, HTTP pool, `cancel_all()` |
| `apps/game/client/scripts/net/api_client.gd` | `class_name ApiClient`. Static transport + auth + API methods |
| `apps/game/client/config/dev_api.json` | `apiBaseUrl` fallback (priority 3) |
| `apps/game/client/scripts/validation/suites/net_suite.gd` | 18 automated assertions for this layer (`validation_runner.gd` `SUITE_PATHS`) |

Callers: `apps/game/client/scripts/save/local_save.gd:514-571` (cloud pull/push), `apps/game/client/scripts/app/run_flow.gd:188-220,824-860` (online procgen stub, fire-and-forget finalize, leaderboard), `apps/game/client/scripts/ui/settings_ui.gd` (cloud panel), `apps/game/client/scripts/ui/pause_menu.gd` (cloud status), `apps/game/client/scripts/ui/results_screen.gd` (leaderboard panel, error indicator).

## How it works

### `ApiConfig`

```
const DEFAULT_BASE_URL := "https://api.aumbrye.example"   # api_config.gd:10
const CLIENT_VERSION := "0.3.0"                            # api_config.gd:11
const CONTENT_VERSION := "1"                               # api_config.gd:12
const REQUEST_TIMEOUT_SECONDS := 8.0                       # api_config.gd:13
enum CloudState { DISABLED, SIGNED_OUT, SYNCING, SYNCED, ERROR, VERSION_MISMATCH }
signal cloud_state_changed(state: int, detail: String)
signal version_mismatch
```

`_ready()` (`api_config.gd:38-42`) initializes the HTTP pool, resolves `base_url`, sets initial `cloud_state`, and loads `user://session.json` for a background refresh.

Base URL priority (`api_config.gd:188-214`):

| Priority | Source |
|----------|--------|
| 1 | `AUMBRYE_API_URL` environment variable |
| 2 | `user://api_config.json` key `apiBaseUrl` |
| 3 | `res://config/dev_api.json` key `apiBaseUrl` via `ContentLoader.load_json` |
| 4 | `DEFAULT_BASE_URL` |

Release builds reject non-`https://` URLs (`api_config.gd:210-213`); an empty `base_url` disables all cloud calls.

Session file `user://session.json` (`api_config.gd:14,127-172`): encrypted with `FileAccess.open_encrypted_with_pass` keyed on `OS.get_unique_id()`. Stores `refreshToken`, `accountId`, `email` â€” never the access token. Failed refresh calls `clear_session()` (both tokens + file delete).

HTTP pool (`api_config.gd:86-124`): two `HTTPRequest` children; `acquire_http()` / `release_http()`; `cancel_all()` on `NOTIFICATION_WM_CLOSE_REQUEST`.

### `ApiClient` paths

| Constant | Value |
|----------|-------|
| `AUTH_REGISTER` | `/api/v1/auth/register` |
| `AUTH_LOGIN` | `/api/v1/auth/login` |
| `AUTH_REFRESH` | `/api/v1/auth/refresh` |
| `AUTH_LOGOUT` | `/api/v1/auth/logout` |
| `RUNS_CREATE` | `/api/v1/runs` |
| `RUNS_DUNGEON` | `/api/v1/runs/%s/dungeon` |
| `RUNS_COMPLETE` | `/api/v1/runs/%s/complete` |
| `SAVES_CURRENT` | `/api/v1/saves/current` |
| `LEADERBOARDS` | `/api/v1/leaderboards` |
| `LEADERBOARDS_SUBMIT` | `/api/v1/leaderboards/submit` |

### Transport

`_request_json` (`api_client.gd:209-224`) returns `{ok, body, code, error?}` for all methods including GET. Retries up to `MAX_ATTEMPTS` (3) on 429, 5xx, and transport failure (`code == 0`); never on 4xx except handled branches. `HTTPRequest.timeout = 8.0` via `ApiConfig.REQUEST_TIMEOUT_SECONDS`.

Status handling:

| Status | Behavior |
|--------|----------|
| 401 | Caller refreshes once and replays once (`_authed_json`, `api_client.gd:187-201`) |
| 426 | `ApiConfig.mark_version_mismatch()` â€” no further cloud calls |
| 429 | Honors `Retry-After` or exponential backoff with jitter |

`set_transport_override(Callable)` (`api_client.gd:20-25`) injects a stub for `net_suite.gd`.

### Auth

`require_session()` (`api_client.gd:75-91`) returns false when unsigned-in; never auto-registers. Dev-only login when `OS.is_debug_build()` and both `AUMBRYE_DEV_EMAIL` and `AUMBRYE_DEV_PASSWORD` are set.

`login` / `register` persist session via `ApiConfig.persist_session()`. `logout()` posts `AUTH_LOGOUT` then `clear_session()`.

Settings cloud panel (`settings_ui.gd`): email/password fields, sign-in, sign-up, sign-out; status line bound to `cloud_state_changed`.

### Live paths

| Trigger | Call chain |
|---------|-----------|
| Run finalize | `run_flow.gd:824` `_cloud_finalize_run` (fire-and-forget) â†’ `ApiClient.complete_run` + `LocalSave.push_to_cloud` |
| Escape + leaderboard opt-in | `run_flow.gd:857` `_submit_leaderboard_async(current_biome_id, current_dungeon_tier, ...)` |
| Explicit cloud pull | `local_save.gd:514` `sync_from_cloud` â†’ `ApiClient.get_save` |
| Results screen | `results_screen.gd` `fetch_leaderboard` top-10 panel when signed in |

`USE_ONLINE_PROCgen` is `false` with an intentional-off comment (`run_flow.gd:28-29`). `_try_online_generate` (`run_flow.gd:201-219`) calls `create_run` + `get_dungeon` when the flag is enabled.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Unified GET/POST `body` key | IMPLEMENTED | `api_client.gd:273`; `net_suite.gd` `net.transport.get_returns_body_key` |
| Explicit sign-in (no silent register) | IMPLEMENTED | `api_client.gd:75-91`; settings cloud panel |
| Request timeout 8s | IMPLEMENTED | `api_config.gd:13`; `api_client.gd:246` |
| HTTPS default + release guard | IMPLEMENTED | `api_config.gd:10,210-213` |
| Configurable base URL | IMPLEMENTED | `api_config.gd:188-214` |
| Leaderboard tier = dungeon tier | IMPLEMENTED | `run_flow.gd:857` `current_dungeon_tier` |
| Encrypted session persistence | IMPLEMENTED | `api_config.gd:127-172` |
| Retry / 426 / 429 handling | IMPLEMENTED | `api_client.gd:209-224,241-243` |
| Cloud state signal + UI | IMPLEMENTED | `api_config.gd:8,65-80`; pause/settings/results |
| Non-blocking run finalize | IMPLEMENTED | `run_flow.gd:824-838` |
| `fetch_leaderboard` + results panel | IMPLEMENTED | `api_client.gd:168-177`; `results_screen.gd` |
| `net_suite.gd` validation | IMPLEMENTED | `validation_runner.gd` `SUITE_PATHS` |
| Leaderboard submit by `runId` only | ABSENT | Blocked on `backend-api.md` step 8; client still sends `biomeId`/`tier`/`elapsedSeconds` |

## Related

- Improvement plan: [`../actual_improvements/networking.md`](../actual_improvements/networking.md) - **FINISHED**
- [`backend-api.md`](../actual_improvements/backend-api.md) â€” logout route, run-derived leaderboards
- [`local-save.md`](local-save.md) â€” `sync_from_cloud` and `push_to_cloud`
- [`run-flow.md`](run-flow.md) â€” run finalize callers
