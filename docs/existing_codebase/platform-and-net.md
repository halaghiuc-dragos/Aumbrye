# Platform and net (Steam, crash logging)

`SteamService` and `CrashLogger` are live autoloads on the play path. Steam runs in honest stub mode without vendored GodotSteam binaries; crash reports are written locally with optional upload when the player opts in.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/platform/steam_service.gd` | Autoload `SteamService` — init, callbacks, achievements, cloud I/O, Web API ticket |
| `apps/game/client/scripts/platform/crash_logger.gd` | Autoload `CrashLogger` — structured logs, retention, opt-in upload |
| `apps/game/client/scripts/platform/privacy_settings.gd` | `send_crash_reports` toggle persisted in save meta |
| `apps/game/client/config/platform.json` | Default `steamAppId` (480) |
| `apps/game/client/steam_appid.txt.example` | Committed Spacewar example for local Steam launches |
| `apps/game/client/addons/godotsteam/godotsteam.gdextension` | GodotSteam GDExtension manifest (binaries gitignored) |
| `apps/game/client/scripts/validation/suites/platform_suite.gd` | 13 headless validation tests |
| `services/backend/src/Aumbrye.Infrastructure/Security/SteamAuthService.cs` | Steam Web API ticket validation |
| `services/backend/tests/Aumbrye.IntegrationTests/SteamAuthTests.cs` | Six integration tests with `FakeSteamAuthService` |

## How it works

### `SteamService`

| Field | Meaning |
|-------|---------|
| `enabled` | Init completed (stub or real) |
| `is_stub_mode` | `true` when GodotSteam class missing or init failed |
| `overlay_available` / `cloud_enabled` | From Steamworks when not stubbed |
| `app_id` | Resolved: `AUMBRYE_STEAM_APP_ID` → `config/platform.json` → `steam_appid.txt` → `480` |

`enum Result { OK, UNAVAILABLE, FAILED }` — `unlock_achievement` returns `UNAVAILABLE` in stub mode. `sync_achievements` returns `{synced, unavailable, failed}`.

`_process` calls `Steam.run_callbacks()` when not stubbed. `shutdown()` is idempotent via `_shutdown_emitted`. `steam_ready` triggers achievement backfill in `achievement_service.gd`.

`get_auth_ticket_hex()` uses `getAuthTicketForWebApi("aumbrye")` and awaits the callback buffer.

### `CrashLogger`

Payload includes `schemaVersion`, `gameVersion`, `contentVersion` (`ApiConfig.CONTENT_VERSION`), engine/OS/GPU/scene/stack. Session log uses one open `FileAccess` with `flush()` per line. Retention prunes to 20 files / 5 MB on `_ready`. When `PrivacySettings.send_crash_reports` is true, pending `crash_*.json` files upload to `POST /api/v1/telemetry/crash`.

### Backend

- `POST /api/v1/auth/steam` — `{ticketHex, appId}` → `AuthResponse`; 503 when `Steam:WebApiKey` unset
- `POST /api/v1/account/link-steam` — link ticket to signed-in account (409 on conflict)
- `POST /api/v1/telemetry/crash` — accepts JSON crash report, returns 204
- `Accounts.SteamId` (`bigint`, unique filtered), nullable `Email`, `SteamLinkedAt`

### Steam Cloud mirror

`local_save.gd` writes `aumbrye_save.json` to Steam Cloud after each successful save when `SteamService.cloud_enabled`, and adopts a newer cloud copy on boot when local save is empty.

## Contracts

| Consumer | Surface |
|----------|---------|
| `achievement_service.gd` | `sync_achievements` on `steam_ready`; `unlock_achievement` unconditional |
| `settings_ui.gd` | Steam sign-in button, privacy crash toggle, cloud panel |
| `ApiClient` | `login_steam`, `upload_crash_report` |

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| GodotSteam binaries | ABSENT (gitignored) | `addons/godotsteam/README.md`; stub path active |
| Steam stub semantics | IMPLEMENTED | `steam_service.gd:unlock_achievement`, `platform_suite.gd` |
| Steam auth end-to-end | IMPLEMENTED | `api_client.gd:login_steam`, `AuthService.AuthenticateSteamAsync`, `SteamAuthTests.cs` |
| Crash logging wired | IMPLEMENTED | `local_save.gd`, `run_flow.gd`, `content_loader.gd`, `api_client.gd` |
| Crash upload opt-in | IMPLEMENTED | `privacy_settings.gd`, `settings_ui.gd`, `TelemetryEndpoints.cs` |
| Validation | IMPLEMENTED | `platform_suite.gd` (13 tests) |

## Related

- Improvement plan: [`../actual_improvements/platform-and-net.md`](../actual_improvements/platform-and-net.md)
- [`networking.md`](networking.md)
- [`backend-api.md`](backend-api.md)
- [`achievements-meta.md`](achievements-meta.md)
- [`local-save.md`](local-save.md)
- [`validation-suites.md`](validation-suites.md)
