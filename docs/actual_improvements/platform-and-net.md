# Platform and net — improvement plan

## Current state

`SteamService` is a stub with a Valve test app id and no SDK behind it; `get_auth_ticket_hex()` returns the empty string from both branches of its own conditional, and no backend route would accept a ticket if it did not (see [`../existing_codebase/platform-and-net.md`](../existing_codebase/platform-and-net.md)). `CrashLogger` is a well-shaped autoload that nothing calls, producing at most one untriageable JSON file per crashed session, uploaded nowhere.

These are the two systems that stand between the game and a Steam release. Neither is close.

## Gaps

Carried from [`../existing_codebase/platform-and-net.md`](../existing_codebase/platform-and-net.md): PLT-01 through PLT-15.

## Target design

### 1. Real Steamworks through GodotSteam (PLT-01, PLT-07, PLT-08, PLT-14)

Vendor GodotSteam as a GDExtension rather than switching to a GodotSteam engine build. A custom engine binary would force every contributor and the CI job onto a non-standard Godot, which conflicts with the version pinning in [`ci-cd.md`](ci-cd.md).

- Add `apps/game/client/addons/godotsteam/` containing `godotsteam.gdextension` and the Windows and Linux binaries for the pinned Godot version. Add `steam_api64.dll` and `libsteam_api.so` next to the exported binary through the export preset's "Add" filter.
- Add `apps/game/client/steam_appid.txt` containing the real app id, gitignored, with `steam_appid.txt.example` containing `480` committed. Steamworks reads this file when the game is launched outside the Steam client.
- Resolve the app id in priority order: `AUMBRYE_STEAM_APP_ID` env var, then `res://config/platform.json` key `steamAppId`, then `DEV_APP_ID`. Keep 480 as the fallback so a developer without the SDK still gets a working stub.
- Handle restart-through-Steam properly:

```gdscript
var restart: Dictionary = steam.steamInitEx(true, app_id)
var status := int(restart.get("status", 1))
if status == 1:  # k_ESteamAPIInitResult_FailedGeneric
    _init_stub("steamInitEx: %s" % restart.get("verbal", "unknown"))
    return
if steam.restartAppIfNecessary(app_id):
    get_tree().quit()
    return
```

- Add the callback pump, which the current file lacks entirely:

```gdscript
func _process(_delta: float) -> void:
    if not is_stub_mode and Engine.has_singleton("Steam"):
        Engine.get_singleton("Steam").run_callbacks()
```

- Call `shutdown()` from `_notification(NOTIFICATION_WM_CLOSE_REQUEST)` and from `_exit_tree()`, guarded so it runs once. Steamworks currently never shuts down cleanly.

### 2. Honest stub semantics (PLT-06, PLT-12)

`unlock_achievement` returning `true` in stub mode is the reason `sync_achievements` reports full success while doing nothing. Change the contract to a tri-state:

```gdscript
enum Result { OK, UNAVAILABLE, FAILED }

func unlock_achievement(achievement_id: String) -> Result:
    if not is_available():
        return Result.UNAVAILABLE
    if is_stub_mode:
        return Result.UNAVAILABLE
    ...
```

`sync_achievements` returns `{synced: int, unavailable: int, failed: int}`. `achievement_service.gd:40-41` drops its `not SteamService.is_stub_mode` guard and calls unconditionally, treating `UNAVAILABLE` as a no-op — the stub check belongs inside the service, not at every call site.

Wire `steam_ready` to a one-shot achievement backfill: on ready, push every locally unlocked achievement to Steam so a player who earned them offline gets them on next launch. That is the reason `sync_achievements` exists and it currently has no caller. See [`achievements-meta.md`](achievements-meta.md).

### 3. Steam sign-in, end to end (PLT-02)

This is the feature that lets a Steam player have a cloud save and a leaderboard entry without typing an email address, replacing the automatic dev registration described in [`networking.md`](networking.md) NET-02.

Client:

```gdscript
func get_auth_ticket_hex() -> String:
    if is_stub_mode or not Engine.has_singleton("Steam"):
        return ""
    var steam := Engine.get_singleton("Steam")
    var ticket: Dictionary = steam.getAuthTicketForWebApi("aumbrye")
    # getAuthTicketForWebApi is asynchronous: the buffer arrives on the
    # get_ticket_for_web_api callback, which requires run_callbacks().
    return await _await_web_api_ticket(ticket.get("id", 0))
```

Use `getAuthTicketForWebApi`, not the legacy `getAuthSessionTicket`. The Web API variant is what `AuthenticateUserTicket` expects and it does not require a session handshake. Encode the returned `PackedByteArray` with `ticket_buffer.hex_encode()`.

Backend, new route:

```
POST /api/v1/auth/steam
Auth: none. Rate limited by the "auth" policy.
Body: { "ticketHex": "<hex>", "appId": 3xxxxxx }
200:  AuthResponse  (same shape as /auth/login)
400:  ProblemDetails "Malformed ticket."
401:  ProblemDetails "Steam rejected the ticket."
502:  ProblemDetails "Steam is unavailable."
```

The handler calls `ISteamAuthService.ValidateAsync(ticketHex, appId)`, which issues:

```
GET https://partner.steam-api.com/ISteamUserAuth/AuthenticateUserTicket/v1/
    ?key=<Steam:WebApiKey>&appid=<appId>&ticket=<ticketHex>&identity=aumbrye
```

It requires `response.params.result == "OK"`, `response.params.vacbanned == false`, `response.params.publisherbanned == false`, and that the returned `steamid` matches nothing already linked to another account. Then it finds or creates an `Account` by `SteamId`, and issues the same token pair as `/auth/login`.

Domain changes: `Account.SteamId` (`bigint`, nullable, unique index) and `Account.Email` becomes nullable, since a Steam-only account has no email. Add a `LinkedAt` timestamp. An existing email account can link a Steam id through `POST /api/v1/account/link-steam` (auth required, same ticket body, 204).

Configuration: `Steam:WebApiKey` from `Steam__WebApiKey`, never committed; `Steam:AppId`; the API refuses to serve `/auth/steam` with 503 when the key is unset, rather than failing at startup, so the API still runs for email accounts without it.

Client fallback stays intact: when `get_auth_ticket_hex()` returns `""` the client shows the email sign-in form. The game remains fully playable signed out; see [`networking.md`](networking.md).

### 4. Steam Cloud as a save mirror (PLT-12)

`read_cloud_file` and `write_cloud_file` exist and are unused. Rather than deleting them, wire them as a second mirror of the local save so a Steam player who reinstalls keeps progress even with no Aumbrye account:

- After every successful `LocalSave` write, if `SteamService.cloud_enabled`, also `write_cloud_file("aumbrye_save.json", payload)`.
- On first launch of a session with an empty or missing local save, read the Steam Cloud copy and adopt it if its `updatedAt` is newer.
- Steam Cloud stays subordinate to the API save when the player is signed in; the resolution order becomes API save, then Steam Cloud, then local. See [`local-save.md`](local-save.md).

Configure the auto-cloud file pattern in the Steamworks partner site rather than relying only on the ISteamRemoteStorage calls, so the mirror works even if the game crashes before writing.

### 5. Crash logging that produces triageable reports (PLT-03, PLT-04, PLT-05, PLT-09, PLT-10, PLT-11)

Payload gains everything a triage needs:

```json
{
  "schemaVersion": 1,
  "gameVersion": "0.4.0",
  "contentVersion": "1",
  "engineVersion": "4.7.0.stable",
  "sessionId": "...",
  "context": "engine_crash",
  "severity": "crash",
  "timestamp": "2026-08-05T14:00:00Z",
  "os": "Windows",
  "osVersion": "10.0.26200",
  "cpu": "...",
  "gpu": "NVIDIA GeForce RTX 4070",
  "gpuDriver": "...",
  "renderer": "forward_plus",
  "locale": "en",
  "scene": "res://scenes/dungeon/dungeon.tscn",
  "runMode": "castle",
  "stack": ["..."],
  "details": {}
}
```

Sources: `ProjectSettings.get_setting("application/config/version")` for `gameVersion` (added as part of [`project-config-autoloads.md`](project-config-autoloads.md)), `Engine.get_version_info()`, `OS.get_version()`, `OS.get_processor_name()`, `RenderingServer.get_video_adapter_name()` and `get_video_adapter_api_version()`, `OS.get_locale_language()`, the current scene path, and `get_stack()` for non-crash errors. Replace `CONTENT_VERSION := "ea-m7"` with `ApiConfig.CONTENT_VERSION` so there is one string.

Reliability and hygiene:

- Keep one `FileAccess` handle open for the session log and call `flush()` after each line instead of reopening per call.
- In `_write_crash_report`, call `file.flush()` then `file.close()` explicitly. Do not allocate dictionaries inside the crash handler beyond what is unavoidable; pre-build the static half of the payload at `_ready`.
- Cap `user://crash_reports/` at 20 files and 5 MB, deleting oldest first on `_ready`.
- Add `log_warning` alongside `log_error`, and route the existing `push_warning`/`push_error` call sites that matter — cloud sync failures, content load failures, save write failures, scene load failures — through `CrashLogger`. Start with `local_save.gd`, `run_flow.gd`, `content_loader.gd`, and `api_client.gd`.

Upload, opt-in only:

- Add a "Send crash reports" toggle in the settings privacy section, default off, persisted in settings (see [`ui/settings.md`](ui/settings.md)).
- When on, on `_ready`, post any pending reports to `POST /api/v1/telemetry/crash` (auth optional; the report carries no account id unless signed in), then delete them on a 2xx. Never block startup: fire and forget with a 5-second timeout.
- Strip the `user://` path prefix and the OS user name from every string before sending.

Rejected alternative: Sentry via `sentry-godot`. It gives better grouping and symbolication out of the box, but it adds a third-party binary dependency, a data-processing agreement, and an outbound endpoint that is not the project's own. Revisit if the volume of self-hosted reports becomes unmanageable.

### 6. Meaningful tests (PLT-13, PLT-15)

`m7.steam.achievement_sync_stub` asserts `synced >= 0` on an `int` and cannot fail; `m7.steam.auth_ticket_deferred` asserts the feature is absent. Both are replaced by the suite below.

## Work plan

1. **Fix the stub contract** — tri-state `unlock_achievement`, `{synced, unavailable, failed}` from `sync_achievements`, drop the caller-side stub guard at `achievement_service.gd:40`. No SDK needed. (PLT-06)
2. **Add clean shutdown and the callback pump** — `_process` calling `run_callbacks()` when not stubbed, `shutdown()` from `NOTIFICATION_WM_CLOSE_REQUEST`. Harmless without the SDK, correct with it. (PLT-07, PLT-12)
3. **Add app-id resolution from `res://config/platform.json`** and commit `steam_appid.txt.example`. (PLT-14)
4. **Rebuild the crash payload** — full environment, stack, one content-version string, flush and close, capped retention, session handle held open. (PLT-04, PLT-09, PLT-10, PLT-11)
5. **Route real call sites through `CrashLogger`** — `local_save.gd`, `run_flow.gd`, `content_loader.gd`, `api_client.gd`. (PLT-03)
6. **Add the crash-logger validation tests.** (PLT-15)
7. **Vendor GodotSteam** as a GDExtension, add the export-preset file additions, verify the real init path against app id 480 and the Steam client. (PLT-01)
8. **Handle restart-through-Steam.** (PLT-08)
9. **Implement `getAuthTicketForWebApi`** on the client behind the callback pump. (PLT-02)
10. **Add `POST /api/v1/auth/steam` and `ISteamAuthService`** on the backend, plus the `SteamId` migration and the nullable-email change. (PLT-02)
11. **Wire Steam sign-in into the settings cloud panel** from [`networking.md`](networking.md) step 7, as the preferred option when a ticket is available. (PLT-02)
12. **Mirror saves to Steam Cloud.** (PLT-12)
13. **Add opt-in crash upload** and the `POST /api/v1/telemetry/crash` route. (PLT-05)
14. **Replace the three m7 Steam assertions** with the new suite. (PLT-13)

Steps 1-6 need no SDK and no real app id, and should land first. Steps 7-12 are blocked on a Steamworks partner account and a real app id; that dependency should be resolved before any of them is scheduled.

## Data and schema changes

Backend migration `AddAccountSteamId`:

| Change | Detail |
|--------|--------|
| `Accounts.SteamId` | `bigint NULL`, unique filtered index `WHERE "SteamId" IS NOT NULL` |
| `Accounts.Email` | becomes `NULL`-able; existing rows unaffected |
| `Accounts.SteamLinkedAt` | `timestamptz NULL` |

Apply before deploying the image that serves `/auth/steam`. Backward compatible with the running version.

`Account.Email` becoming nullable means `AuthService.LoginAsync` must reject a null-email match and `JwtTokenService.CreateAccessToken` must tolerate a missing email claim (`services/backend/src/Aumbrye.Infrastructure/Security/AuthInfrastructure.cs:40`).

Client-side: new `res://config/platform.json`, new gitignored `apps/game/client/steam_appid.txt` with a committed `.example`, new `apps/game/client/addons/godotsteam/`. Crash payload gains `schemaVersion: 1`; existing files without it are treated as version 0 and simply deleted by the retention pass.

No save-format change, so **no `save_migrator.gd` version bump**. Steam Cloud mirroring writes the same payload `local_save.gd` already produces.

New configuration keys: `Steam__WebApiKey`, `Steam__AppId` on the backend, documented in `.env.example` per [`website-and-backend.md`](website-and-backend.md).

## Acceptance criteria

- [ ] With no SDK present, the game launches, `is_stub_mode` is true, and `unlock_achievement` returns `UNAVAILABLE` rather than `OK`.
- [ ] `sync_achievements` reports zero synced in stub mode.
- [ ] With GodotSteam vendored and the Steam client running, `is_stub_mode` is false, `overlay_available` is true, and Shift+Tab opens the overlay in game.
- [ ] Unlocking an achievement in game shows the Steam toast.
- [ ] Achievements earned while offline are pushed to Steam on the next launch with the client running.
- [ ] Launching the exported binary directly relaunches it through Steam and exits cleanly.
- [ ] Quitting the game calls `steamShutdown` exactly once.
- [ ] `get_auth_ticket_hex()` returns a non-empty hex string with the Steam client running.
- [ ] `POST /api/v1/auth/steam` with a valid ticket returns the same `AuthResponse` shape as `/auth/login` and creates an account with a `SteamId` and no email.
- [ ] A tampered or replayed ticket returns 401.
- [ ] With `Steam__WebApiKey` unset, `/auth/steam` returns 503 and every other route still works.
- [ ] A player signed in through Steam can push and pull a cloud save and appear on a leaderboard.
- [ ] The game is fully playable with Steam absent, with the SDK present but the client closed, and with the API down.
- [ ] A crash report contains a stack, the engine version, the game version, the GPU name, and the current scene.
- [ ] `user://crash_reports/` never exceeds 20 files or 5 MB.
- [ ] A save write failure produces a `CrashLogger` error line.
- [ ] With the crash-upload toggle off, no telemetry request is ever issued; with it on, pending reports upload once and are deleted.
- [ ] No uploaded report contains an absolute `user://` path or an OS user name.

## Validation

New suite `apps/game/client/scripts/validation/suites/platform_suite.gd`, registered in `validation_runner.gd` `SUITE_PATHS`. Every test must pass headless with no Steam client and no SDK.

| Test id | Asserts |
|---------|---------|
| `platform.steam.stub_reports_unavailable` | `unlock_achievement` returns `UNAVAILABLE` in stub mode — the PLT-06 regression test |
| `platform.steam.sync_reports_zero_synced` | `sync_achievements(["boss_slayer"]).synced == 0` in stub mode |
| `platform.steam.app_id_priority` | Env var beats `res://config/platform.json` beats `DEV_APP_ID` |
| `platform.steam.auth_ticket_empty_in_stub` | Returns `""` and issues no request |
| `platform.steam.shutdown_is_idempotent` | Two `shutdown()` calls emit `steam_shutdown` once |
| `platform.steam.no_callbacks_pumped_in_stub` | `_process` performs no singleton lookup when stubbed |
| `platform.crash.payload_has_required_fields` | `schemaVersion`, `gameVersion`, `contentVersion`, `engineVersion`, `os`, `gpu`, `scene`, `stack` all present and non-empty |
| `platform.crash.content_version_matches_api_config` | The payload's `contentVersion` equals `ApiConfig.CONTENT_VERSION` — the PLT-09 regression test |
| `platform.crash.log_error_writes_a_line` | One `log_error` produces exactly one parseable JSON line in the session log |
| `platform.crash.log_error_flushes` | The line is readable from a second handle before the writer is freed |
| `platform.crash.retention_prunes_oldest` | With 25 synthetic report files, `_ready` leaves 20 and keeps the newest |
| `platform.crash.upload_disabled_by_default` | With the setting off, no HTTP request is issued |
| `platform.crash.scrubs_user_paths` | A payload containing a `user://` absolute path is sanitized before upload |

Backend xUnit, `services/backend/tests/Aumbrye.IntegrationTests/SteamAuthTests.cs`, with `ISteamAuthService` faked:

| Test | Asserts |
|------|---------|
| `SteamAuth_ValidTicket_CreatesAccountAndReturnsTokens` | 200, an account with `SteamId` set and `Email` null |
| `SteamAuth_ValidTicketForExistingSteamId_ReturnsSameAccount` | No duplicate account |
| `SteamAuth_RejectedTicket_ReturnsUnauthorized` | 401 |
| `SteamAuth_BannedAccount_ReturnsUnauthorized` | `vacbanned: true` yields 401 |
| `SteamAuth_MissingWebApiKey_ReturnsServiceUnavailable` | 503, and `/auth/login` still returns 200 |
| `LinkSteam_AlreadyLinkedToAnotherAccount_ReturnsConflict` | 409 |

Replace `m7.steam.stub_init`, `m7.steam.achievement_sync_stub`, and `m7.steam.auth_ticket_deferred` in `m7_suite.gd:377-411` with a single delegation to `platform_suite`; do not leave two suites asserting the same surface.

## Related

- Existing behavior: [`../existing_codebase/platform-and-net.md`](../existing_codebase/platform-and-net.md)
- [`networking.md`](networking.md) — the sign-in panel and the dev-registration removal this unblocks
- [`backend-api.md`](backend-api.md) — where `/auth/steam` and `/telemetry/crash` slot in
- [`achievements-meta.md`](achievements-meta.md) — the local store and the backfill
- [`local-save.md`](local-save.md) — the Steam Cloud mirror and the resolution order
- [`ci-cd.md`](ci-cd.md) — export presets, the real app id, and the Steam upload step
- [`validation-suites.md`](validation-suites.md) — where `platform_suite.gd` is registered
