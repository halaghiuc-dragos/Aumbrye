# Networking (Godot client) — improvement plan

## Current state

255 lines across two files (see [`../existing_codebase/networking.md`](../existing_codebase/networking.md)). Cloud save pull has never worked because GET results come back under `definition` and `get_save()` looks under `body`. Every authenticated call silently registers an account on the configured host using a machine-derived email and the hardcoded password `devpassword123`. No request has a timeout. The base URL is `http://` and cannot be configured.

The rule that governs every change here: **the game must be fully playable with no network at all.** Nothing in this plan puts a network call on a blocking path, and `USE_ONLINE_PROCgen` stays `false`.

## Gaps

Carried from [`../existing_codebase/networking.md`](../existing_codebase/networking.md): NET-01 through NET-18.

## Target design

### 1. One correct transport (NET-01, NET-03, NET-08, NET-13, NET-14, NET-15)

The GET/POST return-shape split is the root cause of NET-01. Collapse it: `_request_json` always returns the parsed body under `body`, and `get_dungeon` reads `body` like everything else.

```gdscript
const REQUEST_TIMEOUT_SECONDS := 8.0
const MAX_ATTEMPTS := 3
const RETRY_BASE_DELAY := 0.4  # 0.4s, 0.8s, 1.6s with +/-25% jitter

static func _request_json(url: String, method: int, payload: Dictionary, auth: bool) -> Dictionary:
    for attempt in MAX_ATTEMPTS:
        var result := await _request_once(url, method, payload, auth)
        var code: int = result.get("code", 0)
        if result.get("ok", false):
            return result
        if code == 429 or code >= 500 or code == 0:
            if attempt < MAX_ATTEMPTS - 1:
                await _sleep(_backoff_delay(attempt, result.get("retry_after", 0.0)))
                continue
        return result
    return {"ok": false, "error": "unreachable"}
```

`_request_once` sets `http.timeout = REQUEST_TIMEOUT_SECONDS`, registers the node in a tracked array so `cancel_all()` can free it on quit, and returns `{ok, body, code, error}` uniformly. Retries apply only to 429, 5xx, and transport failures — never to 4xx, which are deterministic.

Status handling gets three named cases:

| Status | Behavior |
|--------|----------|
| 401 | Refresh once, replay once, then give up and clear both tokens |
| 426 | Set `ApiConfig.version_mismatch = true`, emit `version_mismatch` on `ApiConfig`, and stop all further cloud calls for the session. Never retry |
| 429 | Honor `Retry-After` when present, otherwise exponential backoff. Give up after `MAX_ATTEMPTS` |

Reuse a single pooled `HTTPRequest` child added under `ApiConfig` (an autoload, so it lives for the process) instead of creating and freeing a node per call. Godot's `HTTPRequest` handles one request at a time, so keep a small pool of two: one for interactive calls, one for background sync. This also removes the `call_deferred` plus one-frame-await race at `api_client.gd:178-181`.

### 2. Explicit accounts, no silent registration (NET-02)

Delete `ensure_dev_session`. Replace it with `require_session()`, which returns false when there is no stored session and never creates one.

```gdscript
static func require_session() -> bool:
    if ApiConfig.access_token != "":
        return true
    if ApiConfig.refresh_token != "":
        return await refresh_session()
    return false
```

Account creation moves behind explicit player action. Add a "Cloud save" panel to the settings menu with sign-in, sign-up, and sign-out, calling `register` and `login` directly. Everything cloud-related is off until the player signs in; `LocalSave` keeps working exactly as it does now (see [`local-save.md`](local-save.md)).

For development convenience, keep a dev-only path behind `OS.is_debug_build() and OS.has_environment("AUMBRYE_DEV_EMAIL")` requiring both `AUMBRYE_DEV_EMAIL` and `AUMBRYE_DEV_PASSWORD`. Delete the `devpassword123` literal and the dead `devPassword` lookup in `dev_api.json`.

Rejected alternative: keeping automatic registration but hashing the machine id. It still creates unowned accounts on a production host from a shipped binary, which is the actual problem.

### 3. Configurable, secure endpoint (NET-04, NET-06)

`ApiConfig` gains a `_ready()` that resolves the base URL in priority order and validates the scheme:

| Priority | Source |
|----------|--------|
| 1 | `AUMBRYE_API_URL` environment variable |
| 2 | `user://api_config.json` key `apiBaseUrl` (player or QA override) |
| 3 | `res://config/dev_api.json` key `apiBaseUrl` (already exists, currently unread) |
| 4 | `DEFAULT_BASE_URL` |

Change `DEFAULT_BASE_URL` to `https://api.aumbrye.example` (the real host once it exists) and reject any resolved URL that is not `https://` in a release build:

```gdscript
if not OS.is_debug_build() and not base_url.begins_with("https://"):
    push_error("ApiConfig: refusing non-HTTPS base URL in a release build")
    base_url = ""
```

An empty `base_url` disables every cloud call, which is a valid and fully playable state. Remove the meaningless `@export`.

### 4. Persisted session (NET-07, NET-09)

Write `{"refreshToken": "...", "accountId": "...", "email": "..."}` to `user://session.json` with `FileAccess.open_encrypted_with_pass` keyed on `OS.get_unique_id()`. Never persist the access token; it lives 15 minutes.

On `ApiConfig._ready`, load the file and attempt a refresh in the background. On a failed refresh, clear **both** tokens and delete the file — fixing NET-09, where only the access token is cleared today. On sign-out, delete the file and call `POST /api/v1/auth/logout` (added in [`backend-api.md`](backend-api.md) step 9).

Encryption here is obfuscation, not real protection — a local attacker can read `OS.get_unique_id()`. It is still correct to not leave a 30-day bearer credential in plaintext, and refresh-token rotation with reuse detection (same backend step) limits the blast radius.

### 5. Correct leaderboard submission (NET-05, NET-17)

`run_flow.gd:771` passes `current_floor` where the contract says `tier`. Once [`backend-api.md`](backend-api.md) step 8 lands, the submission carries only a `runId` and the server derives biome, tier, and elapsed time from its own record, so the client cannot get it wrong:

```gdscript
static func submit_leaderboard(run_id: String, opt_in: bool) -> Dictionary:
    if not opt_in:
        return {"ok": true, "submitted": false, "reason": "opt_out"}
    if not await require_session():
        return {"ok": false, "error": "not signed in"}
    return await _request_json(
        ApiConfig.get_base_url() + LEADERBOARDS_SUBMIT,
        HTTPClient.METHOD_POST, {"runId": run_id, "optIn": true}, true)
```

Until then, the one-line fix is to pass `current_dungeon_tier`.

Add `GET /api/v1/leaderboards` as `fetch_leaderboard(biome_id, tier, limit)` and surface it on the run-result screen as "Top 10 for this biome" when the player is signed in, with a plain "Sign in to see leaderboards" otherwise. Writing to a board the player can never read is not worth the request.

### 6. Visible, honest cloud state (NET-10)

Add to `ApiConfig`:

```gdscript
signal cloud_state_changed(state: int, detail: String)
enum CloudState { DISABLED, SIGNED_OUT, SYNCING, SYNCED, ERROR, VERSION_MISMATCH }
var cloud_state: CloudState = CloudState.DISABLED
```

Every entry and exit of a cloud operation sets the state. The pause menu and the settings cloud panel show a one-line status; the run-result screen shows a small indicator only when the state is `ERROR` or `VERSION_MISMATCH`, with a "Retry" action. Never block the result screen on it — `_cloud_finalize_run` becomes fire-and-forget with no `await` in the transition path.

Stop suppressing `"auth failed"` at `run_flow.gd:749,754`; map it to `SIGNED_OUT`, which is a normal state and renders as nothing.

### 7. Shared version constants (NET-12)

Add a validation assertion (see below) that `ApiConfig.CLIENT_VERSION` equals `ApiVersions.ExpectedClientVersion` parsed out of `packages/shared/Contracts/ApiVersions.cs`, and the same for `CONTENT_VERSION`. Godot cannot import C# constants, so a test is the enforcement mechanism. The `contract` CI job in [`website-and-backend.md`](website-and-backend.md) covers the web side the same way.

### 8. Dead code (NET-16, NET-18)

Keep `USE_ONLINE_PROCgen`, `_try_online_generate`, `create_run`, and `get_dungeon`. Server-authoritative generation is the anti-cheat foundation for leaderboards and deleting it would have to be rebuilt. Instead, document the flag in `run_flow.gd:17` with a comment stating it is intentionally off pending server-authoritative runs, and add the round-trip to the validation suite listed below so it cannot silently rot. Delete the `devPassword` lookup and the `devpassword123` literal outright.

## Work plan

1. **Fix `get_save()`** — unify `_request_json` on a single `body` key and update `get_dungeon`'s reader at `run_flow.gd:206`. Restores cloud save pull. (NET-01)
2. **Fix the leaderboard tier** — `current_dungeon_tier` instead of `current_floor` at `run_flow.gd:771`. One word. (NET-05)
3. **Add the timeout and the pooled node** — `http.timeout = 8.0`, two pooled `HTTPRequest` children under `ApiConfig`, `cancel_all()` on `NOTIFICATION_WM_CLOSE_REQUEST`. (NET-03, NET-14, NET-15)
4. **Add retry, backoff, and status handling** — 429/5xx/transport retries with jitter, explicit 426 and 429 branches. (NET-08, NET-13)
5. **Add the cloud-state signal and remove the warning suppression**; make `_cloud_finalize_run` non-blocking. (NET-10)
6. **Add base-URL resolution and the HTTPS guard.** (NET-04, NET-06)
7. **Replace `ensure_dev_session` with `require_session`**, add the settings cloud panel with sign in, sign up, and sign out, delete the hardcoded password. This is the change that stops shipped builds creating accounts. (NET-02, NET-18)
8. **Persist the refresh token** encrypted; clear both tokens on refresh failure. (NET-07, NET-09)
9. **Add the version-constant assertion.** (NET-12)
10. **Add `fetch_leaderboard` and the run-result panel.** (NET-17)
11. **Switch leaderboard submission to `runId`** once [`backend-api.md`](backend-api.md) step 8 lands. (NET-05)
12. **Add the validation suite** below. (NET-11)

Steps 1-3 are one-line to one-function fixes and should land first. Step 7 depends on 6 and on the settings UI. Step 11 depends on the backend.

## Data and schema changes

New file: `user://session.json`, encrypted, containing `refreshToken`, `accountId`, `email`. It is not part of the save format and is not read by `save_migrator.gd`, so **no `save_migrator.gd` version bump**. A missing or unreadable file means signed out.

New optional file: `user://api_config.json` with `{"apiBaseUrl": "..."}`. Absent by default.

`res://config/dev_api.json` keeps `apiBaseUrl` and gains no `devPassword` key. No `content/schemas/` change.

`ApiConfig.CLIENT_VERSION` goes `0.3.0` -> `0.4.0` in lockstep with `ApiVersions.ExpectedClientVersion` when [`backend-api.md`](backend-api.md) step 7 lands.

## Acceptance criteria

- [ ] With the API running and a signed-in account, `LocalSave.sync_from_cloud()` returns true and applies the server state.
- [ ] With the API stopped, launching the game reaches the hub, starts a run, kills the boss, escapes, and shows the result screen with no stall, no error dialog, and no more than one log line.
- [ ] With the API stopped, run finalize adds no measurable time to the result-screen transition.
- [ ] A host that accepts connections and never responds fails each call in about 8 seconds, not indefinitely.
- [ ] No account is created on any host unless the player signs up through the settings panel.
- [ ] The string `devpassword123` does not appear anywhere in the client.
- [ ] A release build with a non-HTTPS resolved base URL disables cloud features and logs an error rather than sending a token in the clear.
- [ ] `AUMBRYE_API_URL`, `user://api_config.json`, and `res://config/dev_api.json` each override the default, in that priority order.
- [ ] Signing in, quitting, and relaunching leaves the player signed in without re-entering credentials.
- [ ] A refresh that fails clears both tokens and deletes `user://session.json`.
- [ ] A 429 response is retried with backoff; a 400 is not retried.
- [ ] A 426 response sets `VERSION_MISMATCH`, stops further cloud calls, and shows an update prompt.
- [ ] The leaderboard submission for a tier-3 run reports tier 3.
- [ ] The run-result screen shows the top 10 for the biome when signed in.
- [ ] Quitting mid-request frees every `HTTPRequest` node with no orphan warning in the log.
- [ ] `ApiConfig.CLIENT_VERSION` matches `ApiVersions.ExpectedClientVersion`, asserted by a test.

## Validation

New suite `apps/game/client/scripts/validation/suites/net_suite.gd`, registered in `validation_runner.gd` `SUITE_PATHS`. It must pass with no server running, so every server-dependent assertion goes through a stub `HTTPRequest` double injected into `ApiClient`.

| Test id | Asserts |
|---------|---------|
| `net.config.version_constants_match_shared` | `ApiConfig.CLIENT_VERSION` and `CONTENT_VERSION` equal the values parsed from `packages/shared/Contracts/ApiVersions.cs:7-8` |
| `net.config.base_url_priority` | Environment variable beats `user://api_config.json` beats `res://config/dev_api.json` beats the default |
| `net.config.rejects_http_in_release` | With `OS.is_debug_build()` stubbed false, an `http://` URL yields an empty `base_url` |
| `net.transport.get_returns_body_key` | A stubbed 200 GET produces `{ok: true, body: {...}}` — the NET-01 regression test |
| `net.transport.timeout_is_set` | The `HTTPRequest` used for a call has `timeout == 8.0` |
| `net.transport.retries_on_429_then_succeeds` | Two 429s then a 200 yields three attempts and `ok: true` |
| `net.transport.does_not_retry_on_400` | Exactly one attempt |
| `net.transport.426_sets_version_mismatch` | `ApiConfig.cloud_state == VERSION_MISMATCH` and no further request is issued |
| `net.transport.cancel_all_frees_nodes` | After `cancel_all()`, no `HTTPRequest` child remains under `ApiConfig` |
| `net.auth.require_session_without_credentials_returns_false` | No register or login request is issued |
| `net.auth.no_hardcoded_password` | `api_client.gd` source contains no `devpassword` substring |
| `net.auth.failed_refresh_clears_both_tokens` | Both `access_token` and `refresh_token` are empty and `user://session.json` is gone |
| `net.auth.session_round_trip` | Write, reload, and recover a refresh token from the encrypted file |
| `net.save.round_trip_with_stub` | `put_save` then `get_save` through the stub returns the same `stateJson` |
| `net.save.conflict_applies_server_state` | A stubbed 409 backs up locally and applies the server state |
| `net.offline.run_finalize_does_not_block` | With `base_url` empty, `_cloud_finalize_run` returns within one frame |
| `net.offline.no_requests_when_signed_out` | A full simulated run issues zero HTTP requests |
| `net.leaderboard.submits_dungeon_tier` | The submitted `tier` equals `current_dungeon_tier`, not `current_floor` |

Backend-side coverage for the same contract lives in [`backend-api.md`](backend-api.md); the two must be changed together whenever a DTO moves.

## Related

- Existing behavior: [`../existing_codebase/networking.md`](../existing_codebase/networking.md)
- [`backend-api.md`](backend-api.md) — logout, run-derived leaderboards, ProblemDetails, version bump
- [`local-save.md`](local-save.md) — `sync_from_cloud` and `push_to_cloud`, which NET-01 blocks
- [`platform-and-net.md`](platform-and-net.md) — Steam sign-in as the eventual replacement for email accounts
- [`website-and-backend.md`](website-and-backend.md) — the parallel contract work on the web side
- [`validation-suites.md`](validation-suites.md) — where `net_suite.gd` is registered
- [`run-flow.md`](run-flow.md) — the callers at run finalize
