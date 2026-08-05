# Platform and net (Steam, crash logging)

Two autoloads, 203 lines total. `SteamService` wraps GodotSteam behind a stub that activates whenever the SDK is missing, which is always — the plugin is not vendored and the only addon in the project is `godot_mcp`. `CrashLogger` writes JSON crash reports and structured error lines to `user://crash_reports/`; nothing in the codebase calls its logging methods.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/platform/steam_service.gd` | 138 lines. Autoload `SteamService` (`project.godot:44`) |
| `apps/game/client/scripts/platform/crash_logger.gd` | 65 lines. Autoload `CrashLogger` (`project.godot:45`) |

Referenced by `apps/game/client/scripts/app/game_facade.gd:48` (exposed in a services dictionary), `apps/game/client/scripts/meta/achievement_service.gd:40-41` (the only functional caller), and `apps/game/client/scripts/validation/suites/m7_suite.gd:377-411`.

## How it works

### `SteamService` state

| Field | Default | Meaning |
|-------|---------|---------|
| `enabled` | `false` -> `true` after init | Init completed, stub or real |
| `is_stub_mode` | `true` | No real Steamworks behind the calls |
| `overlay_available` | `false` | Set from `isOverlayEnabled()` only in the real path |
| `cloud_enabled` | `false` | Set from `isCloudEnabledForApp()` only in the real path |
| `app_id` | `DEV_APP_ID` = `480` | Valve's public Spacewar test app id (`steam_service.gd:8,14`) |

Signals `steam_ready` and `steam_shutdown` (`steam_service.gd:5-6`) have no listeners anywhere in the project.

### Initialization

`_ready` sets `PROCESS_MODE_ALWAYS`, resolves the app id, and initializes (`steam_service.gd:19-22`).

`_resolve_app_id` reads `AUMBRYE_STEAM_APP_ID` from the environment and uses it when it parses as an integer (`steam_service.gd:25-29`). There is no other source; nothing reads a config file or an export preset.

`_initialize` (`steam_service.gd:32-39`):

| Condition | Path |
|-----------|------|
| `app_id == 480` and no `steam` feature tag | `_init_stub("No AUMBRYE_STEAM_APP_ID — dev stub active")` |
| `steam` feature tag present, or a non-default app id | `_try_godot_steam()` |
| otherwise | `_init_stub("GodotSteam not compiled — dev stub active")` |

`_try_godot_steam` (`steam_service.gd:42-60`) bails to the stub when `ClassDB.class_exists("Steam")` is false, then when `Engine.get_singleton("Steam")` is null, then when `steamInitEx(true, app_id)` returns a non-zero `status`. On success it sets `enabled`, clears `is_stub_mode`, reads the overlay and cloud flags, and emits `steam_ready`.

No GodotSteam build is present. `apps/game/client/addons/` contains exactly one directory, `godot_mcp`. There is no `Steam` class, no GDExtension, and no custom `steam` feature tag in `project.godot`. Every launch therefore ends in `_init_stub`, which sets `enabled = true` and `is_stub_mode = true` and emits `steam_ready` (`steam_service.gd:63-70`).

The real path also never calls `Steam.run_callbacks()`. GodotSteam requires that per frame for any callback to be delivered — overlay state changes, `storeStats` results, and auth-ticket responses all arrive through it. `_process` and `_physics_process` are not defined in this file.

`steamInitEx(true, app_id)` passes `true` for the restart-through-Steam argument but the returned `restart` dictionary is only checked for `status`; there is no `restart_app_if_necessary` handling and no `get_tree().quit()` on a required relaunch (`steam_service.gd:51-54`).

### Surface

| Method | Stub behavior | Real behavior | Callers |
|--------|---------------|---------------|---------|
| `is_available()` | `true` | `true` | `steam_service.gd` internally; `m7_suite.gd:382` |
| `unlock_achievement(id)` | returns `true` without doing anything (`:80-81`) | `setAchievement` + `storeStats` | `achievement_service.gd:41`, guarded by `not SteamService.is_stub_mode` |
| `sync_achievements(ids)` | returns `ids.size()` | same loop | `m7_suite.gd:392` only |
| `read_cloud_file(name)` | `""` (`:102-103`) | `Steam.fileRead` | none |
| `write_cloud_file(name, data)` | `false` (`:112-113`) | `Steam.fileWrite` | none |
| `get_auth_ticket_hex()` | `""` | `""` | `m7_suite.gd:402` only |
| `shutdown()` | clears state, emits | `steamShutdown` then the same | none |

`get_auth_ticket_hex` (`steam_service.gd:121-125`) is the whole of the Steam auth-ticket feature:

```gdscript
func get_auth_ticket_hex() -> String:
	# STEAM-7.4 deferred — returns empty in stub/dev mode.
	if is_stub_mode:
		return ""
	return ""
```

Both branches return the empty string. There is no `getAuthSessionTicket` call, no ticket buffer, and no hex encoding.

There is no backend counterpart either. A case-insensitive search for `steam` across every `.cs` file under `services/backend` returns no match: no `/api/v1/auth/steam` route, no `ISteamAuthService`, no Steam Web API key in `appsettings.json`. Even if the client produced a ticket, nothing would accept it.

`achievement_service.gd:40-41` calls `unlock_achievement` only when `not SteamService.is_stub_mode`, so in the current build the Steam achievement path never executes. In-game achievements are tracked locally; see [`achievements-meta.md`](achievements-meta.md).

Steam Cloud is unused: `read_cloud_file` and `write_cloud_file` have no callers, and `local_save.gd` writes to `user://` directly (see [`local-save.md`](local-save.md)).

### `CrashLogger`

`_ready` sets `PROCESS_MODE_ALWAYS`, builds `_session_id` as `"<unix seconds>-<randi()>"`, and creates `user://crash_reports/` recursively (`crash_logger.gd:11-14,62-64`).

`_notification` writes a crash report on `NOTIFICATION_CRASH` (`crash_logger.gd:17-19`). `_write_crash_report` serializes the payload to `user://crash_reports/crash_<session>.json` with tab indentation (`crash_logger.gd:32-38`); it does not call `flush()` or `close()`.

`log_error(context, details)` and `log_exception(context, error)` append one JSON line to `user://crash_reports/session_<session>.log` (`crash_logger.gd:22-29,52-59`). Each call opens the file `READ_WRITE`, falls back to `WRITE` if that fails, seeks to the end, writes a line, and lets the handle drop.

The payload (`crash_logger.gd:41-49`):

```json
{
  "contentVersion": "ea-m7",
  "sessionId": "1754400000-1234567",
  "context": "...",
  "timestamp": "2026-08-05T14:00:00",
  "os": "Windows",
  "details": {}
}
```

`CONTENT_VERSION := "ea-m7"` (`crash_logger.gd:6`) is a third, unrelated content-version string. `ApiConfig.CONTENT_VERSION` is `"1"` (`apps/game/client/scripts/net/api_config.gd:8`) and `ApiVersions.ExpectedContentVersion` is `"1"` (`packages/shared/Contracts/ApiVersions.cs:8`).

No engine version, game version, GPU, driver, renderer, locale, scene, or stack trace is recorded. `get_stack()` is never called.

`log_error` and `log_exception` have **no callers**. A repo-wide search for `CrashLogger` matches only `project.godot:45`, `game_facade.gd:12,48`, and the definition itself. The only thing this autoload can ever write is a single crash JSON on `NOTIFICATION_CRASH`.

Nothing uploads, rotates, or deletes anything under `user://crash_reports/`.

### Validation coverage

`m7_suite.gd:377-411` instantiates the script directly (not the autoload), adds it as a child, waits a frame, and records three results:

| Test id | Assertion | Note |
|---------|-----------|------|
| `m7.steam.stub_init` | `is_available() and is_stub_mode` | Passes only in stub mode; would fail with a real SDK |
| `m7.steam.achievement_sync_stub` | `synced >= 0` | An `int` return is always `>= 0`; the assertion cannot fail |
| `m7.steam.auth_ticket_deferred` | `ticket == ""` | Asserts the feature is absent |

`CrashLogger` has no test of any kind.

## Absent

- **GodotSteam.** `apps/game/client/addons/` contains only `godot_mcp`. No `.gdextension`, no `Steam` class, no vendored binaries, no `steam_api64.dll`.
- **A real Steam app id.** `DEV_APP_ID` is 480, Valve's public Spacewar test id. Nothing in the repository holds a real one.
- **`Steam.run_callbacks()`.** The service defines no `_process` or `_physics_process`.
- **Steam auth-ticket generation.** `get_auth_ticket_hex` returns `""` from both branches.
- **Steam auth-ticket exchange on the backend.** No `steam` match in any `.cs` file under `services/backend`; no route, service, or configuration key.
- **Steam Cloud usage.** `read_cloud_file` and `write_cloud_file` have no callers.
- **Steam stats, rich presence, DLC, Workshop, Steam Input, Steam Deck detection.** None appear in the file.
- **Crash-report upload.** No Sentry, Bugsnag, Backtrace, or HTTP post. Reports stay in `user://`.
- **Stack traces in crash reports.** `get_stack()` is not called.
- **Any caller of `CrashLogger.log_error` or `log_exception`.**
- **Log rotation or a retention cap on `user://crash_reports/`.**
- **A crash-report opt-in or privacy notice.** Not required while reports never leave the machine, but it becomes required with upload.

## Gaps

| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| PLT-01 | P0 | Steam integration is a stub end to end. The app id is Valve's test id 480, GodotSteam is not vendored, and every launch resolves to `_init_stub`. Achievements, overlay, and cloud do nothing. | `steam_service.gd:8,33-39,63-70`; `apps/game/client/addons/` contains only `godot_mcp` |
| PLT-02 | P0 | `get_auth_ticket_hex()` returns `""` from both branches of its own conditional, and no backend route would accept a ticket. There is no Steam sign-in path at all. | `steam_service.gd:121-125`; no `steam` match under `services/backend/**/*.cs` |
| PLT-03 | P1 | `CrashLogger.log_error` and `log_exception` are never called. The autoload can only ever produce a single file, on a notification that is unreliable on Windows. | No `CrashLogger.log_` call in the repository; `crash_logger.gd:17-19` |
| PLT-04 | P1 | Crash reports carry no stack trace, engine version, game version, GPU, driver, or scene — only OS name and a free-text message. They cannot be triaged. | `crash_logger.gd:41-49` |
| PLT-05 | P1 | Nothing collects crash reports. They accumulate in `user://crash_reports/` with no rotation, no size cap, and no upload. | `crash_logger.gd:5,32-38,52-59` |
| PLT-06 | P1 | `unlock_achievement` returns `true` in stub mode without unlocking anything, so `sync_achievements` reports full success while doing nothing. | `steam_service.gd:80-81,91-98` |
| PLT-07 | P1 | The real Steam path never calls `Steam.run_callbacks()`, so with a real SDK no Steam callback would ever be delivered. | No `_process` in `steam_service.gd`; `run_callbacks` absent from the repository |
| PLT-08 | P1 | `steamInitEx(true, ...)` requests restart-through-Steam but the result is only checked for `status`; a required relaunch is ignored. | `steam_service.gd:51-54` |
| PLT-09 | P2 | `CONTENT_VERSION := "ea-m7"` is a third content-version string, unrelated to the `"1"` used by the client and the API. | `crash_logger.gd:6` vs `api_config.gd:8`, `packages/shared/Contracts/ApiVersions.cs:8` |
| PLT-10 | P2 | `_write_crash_report` never flushes or closes. Inside a crash handler the report may be truncated or empty. | `crash_logger.gd:36-38` |
| PLT-11 | P2 | `_append_log` reopens and re-seeks the log file on every call, so a hot error path would issue three syscalls per line. | `crash_logger.gd:52-59` |
| PLT-12 | P2 | `shutdown()`, `sync_achievements()`, `read_cloud_file()`, and `write_cloud_file()` have no callers, and `steam_ready`/`steam_shutdown` have no listeners. Steamworks is never shut down cleanly. | Repo-wide search for each name |
| PLT-13 | P2 | `m7.steam.achievement_sync_stub` asserts `synced >= 0` on an `int`, which cannot fail, and `m7.steam.auth_ticket_deferred` asserts the feature is missing. Neither would catch a regression. | `m7_suite.gd:392-410` |
| PLT-14 | P2 | The Steam app id can only come from an environment variable; there is no config file or export-preset feature tag. | `steam_service.gd:25-29` |
| PLT-15 | P2 | `CrashLogger` has no validation coverage. | No `crash` test id in `scripts/validation/suites/` |

## Related

- Improvement plan: [`../actual_improvements/platform-and-net.md`](../actual_improvements/platform-and-net.md)
- [`networking.md`](networking.md) — the API client that would consume a Steam ticket
- [`backend-api.md`](backend-api.md) — the exchange endpoint that does not exist
- [`achievements-meta.md`](achievements-meta.md) — the local achievement store behind `unlock_achievement`
- [`local-save.md`](local-save.md) — why Steam Cloud is unused
- [`validation-suites.md`](validation-suites.md) — `m7_suite`
- [`ci-cd.md`](ci-cd.md) — the release export that would need a real app id
