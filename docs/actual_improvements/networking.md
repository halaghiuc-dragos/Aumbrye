# Networking (Godot client) — improvement plan

## Status: FINISHED

All gaps NET-01 through NET-18 are implemented except the deferred `runId`-only leaderboard submission (work-plan step 11), which remains blocked on [`backend-api.md`](backend-api.md) step 8. Evidence: `net_suite.gd` (18 tests), `api_config.gd`, `api_client.gd`, settings/pause/results UI, `run_flow.gd` fire-and-forget finalize.

## Current state

Implemented. See [`../existing_codebase/networking.md`](../existing_codebase/networking.md). Cloud save pull works via unified `body` key; explicit sign-in replaces silent registration; transport has 8s timeout, pooled nodes, retry/backoff, and 426/429 handling; session persists encrypted in `user://session.json`.

## Gaps

| ID | Sev | Status | Evidence |
|----|-----|--------|----------|
| NET-01 | P0 | FINISHED | `_request_json` returns `body` for GET; `get_save` reads `body.stateJson`; `net_suite.gd` `net.transport.get_returns_body_key`, `net.save.round_trip_with_stub` |
| NET-02 | P0 | FINISHED | `ensure_dev_session` deleted; `require_session()` at `api_client.gd:75-91`; settings cloud panel; `net.auth.require_session_without_credentials_returns_false` |
| NET-03 | P0 | FINISHED | `REQUEST_TIMEOUT_SECONDS := 8.0`; `_cloud_finalize_run` fire-and-forget; `net.transport.timeout_is_set`, `net.offline.run_finalize_does_not_block` |
| NET-04 | P1 | FINISHED | `DEFAULT_BASE_URL` is `https://`; release HTTPS guard `api_config.gd:210-213`; `net.config.rejects_http_in_release` |
| NET-05 | P1 | FINISHED (tier) | `current_dungeon_tier` at `run_flow.gd:857`; `net.leaderboard.submits_dungeon_tier`. `runId`-only submit deferred to backend step 8 |
| NET-06 | P1 | FINISHED | `_resolve_base_url()` priority chain `api_config.gd:188-214`; `net.config.base_url_priority` |
| NET-07 | P1 | FINISHED | `persist_session` / `load_session` `api_config.gd:127-172`; `net.auth.session_round_trip` |
| NET-08 | P1 | FINISHED | Retry loop `api_client.gd:209-224`; `net.transport.retries_on_429_then_succeeds`, `net.transport.does_not_retry_on_400` |
| NET-09 | P1 | FINISHED | `refresh_session` calls `clear_session()` on failure; `net.auth.failed_refresh_clears_both_tokens` |
| NET-10 | P1 | FINISHED | `CloudState` + `cloud_state_changed`; pause/settings/results UI; auth-failed suppression removed from `run_flow.gd` |
| NET-11 | P1 | FINISHED | `net_suite.gd` registered in `validation_runner.gd` `SUITE_PATHS` |
| NET-12 | P2 | FINISHED | `net.config.version_constants_match_shared` parses `ApiVersions.cs` |
| NET-13 | P2 | FINISHED | 426 → `VERSION_MISMATCH`; 429 backoff; `net.transport.426_sets_version_mismatch` |
| NET-14 | P2 | FINISHED | Two-node pool under `ApiConfig`; no per-call `queue_free` |
| NET-15 | P2 | FINISHED | `cancel_all()` on `NOTIFICATION_WM_CLOSE_REQUEST`; `net.transport.cancel_all_frees_nodes` |
| NET-16 | P2 | FINISHED | `USE_ONLINE_PROCgen` documented; `_try_online_generate` restored `run_flow.gd:201-219` |
| NET-17 | P2 | FINISHED | `fetch_leaderboard`; results screen top-10 panel |
| NET-18 | P2 | FINISHED | `devpassword123` and `devPassword` lookup removed; `net.auth.no_hardcoded_password` |

## Target design

Implemented as specified below. See existing_codebase twin for live paths and line references.

### 1. One correct transport (NET-01, NET-03, NET-08, NET-13, NET-14, NET-15)

`_request_json` always returns parsed body under `body`. Pooled `HTTPRequest` nodes (2), `timeout = 8.0`, retry on 429/5xx/transport only, `cancel_all()` on quit.

### 2. Explicit accounts (NET-02)

`require_session()` never creates accounts. Settings cloud panel for sign-in/sign-up/sign-out. Dev path behind `AUMBRYE_DEV_EMAIL` + `AUMBRYE_DEV_PASSWORD` in debug builds only.

### 3. Configurable secure endpoint (NET-04, NET-06)

Priority: env → `user://api_config.json` → `dev_api.json` → default. Release builds reject non-HTTPS.

### 4. Persisted session (NET-07, NET-09)

Encrypted `user://session.json`; failed refresh clears both tokens and deletes file; sign-out calls `POST /api/v1/auth/logout`.

### 5. Leaderboard (NET-05, NET-17)

Tier fix landed (`current_dungeon_tier`). `fetch_leaderboard` + results panel. `runId`-only submit waits on backend.

### 6. Cloud state UI (NET-10)

`CloudState` enum + signal; pause/settings status; results error/version indicator with retry.

### 7. Version constants (NET-12)

`net.config.version_constants_match_shared` assertion.

### 8. Dead code cleanup (NET-16, NET-18)

Online procgen path kept and tested; hardcoded password removed.

## Work plan

1. **Fix `get_save()`** — FINISHED (`api_client.gd`, `net_suite.gd`)
2. **Fix leaderboard tier** — FINISHED (`run_flow.gd:857`)
3. **Timeout + pooled nodes** — FINISHED (`api_config.gd`, `api_client.gd`)
4. **Retry, backoff, status handling** — FINISHED (`api_client.gd`)
5. **Cloud-state signal + non-blocking finalize** — FINISHED (`api_config.gd`, `run_flow.gd`, UI)
6. **Base-URL resolution + HTTPS guard** — FINISHED (`api_config.gd`)
7. **require_session + settings cloud panel** — FINISHED (`api_client.gd`, `settings_ui.gd`)
8. **Encrypted session persistence** — FINISHED (`api_config.gd`)
9. **Version-constant assertion** — FINISHED (`net_suite.gd`)
10. **fetch_leaderboard + run-result panel** — FINISHED (`api_client.gd`, `results_screen.gd`)
11. **Switch leaderboard to `runId`** — DEFERRED (backend-api step 8)
12. **Validation suite** — FINISHED (`net_suite.gd`)

## Data and schema changes

`user://session.json` (encrypted, not in save migrator). `user://api_config.json` optional. No `save_migrator.gd` version bump.

## Acceptance criteria

- [x] With API running and signed-in account, `LocalSave.sync_from_cloud()` returns true and applies server state (NET-01, NET-07)
- [x] With API stopped, game reaches hub, runs, and shows result screen without stall (`net.offline.*`)
- [x] Run finalize adds no measurable time to result-screen transition (fire-and-forget)
- [x] Unresponsive host fails in ~8 seconds (`REQUEST_TIMEOUT_SECONDS`)
- [x] No account created unless player signs up via settings (`require_session`)
- [x] `devpassword123` absent from client (`net.auth.no_hardcoded_password`)
- [x] Release build with non-HTTPS URL disables cloud and logs error
- [x] URL priority env → user → dev → default (`net.config.base_url_priority`)
- [x] Sign-in persists across relaunch (`net.auth.session_round_trip`)
- [x] Failed refresh clears tokens and deletes session file
- [x] 429 retried; 400 not retried
- [x] 426 sets `VERSION_MISMATCH` and stops cloud calls
- [x] Leaderboard submission uses dungeon tier
- [x] Results screen shows top 10 when signed in
- [x] Quit frees HTTPRequest nodes (`cancel_all`)
- [x] `CLIENT_VERSION` matches `ApiVersions.cs` (test assertion)

## Validation

Suite `apps/game/client/scripts/validation/suites/net_suite.gd` — 18 tests, all IDs from original plan. Registered in `validation_runner.gd` `SUITE_PATHS`.

Run locally:

```text
Godot --path apps/game/client --headless --script res://scripts/validation/validation_main.gd -- --test=net
```

## Related

- Existing behavior: [`../existing_codebase/networking.md`](../existing_codebase/networking.md)
- [`backend-api.md`](backend-api.md) — logout, run-derived leaderboards (step 11 blocker)
- [`local-save.md`](local-save.md)
- [`platform-and-net.md`](platform-and-net.md)
- [`validation-suites.md`](validation-suites.md)
- [`run-flow.md`](run-flow.md)
