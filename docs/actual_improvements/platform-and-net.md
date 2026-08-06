# Platform and net — improvement plan

## Status: FINISHED

## Current state

`SteamService` and `CrashLogger` are production implementations with honest stub semantics, GodotSteam GDExtension scaffolding, Steam auth end-to-end, Steam Cloud save mirroring, opt-in crash upload, and `platform_suite.gd` validation. See [`../existing_codebase/platform-and-net.md`](../existing_codebase/platform-and-net.md).

## Gaps

| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| PLT-01 | P0 | Steam integration stub end to end | **FINISHED** — `addons/godotsteam/godotsteam.gdextension`, `steam_service.gd` real init path |
| PLT-02 | P0 | No Steam sign-in path | **FINISHED** — `get_auth_ticket_hex()`, `ApiClient.login_steam()`, `POST /api/v1/auth/steam` |
| PLT-03 | P1 | CrashLogger never called | **FINISHED** — `local_save.gd`, `run_flow.gd`, `content_loader.gd`, `api_client.gd` |
| PLT-04 | P1 | Crash reports not triageable | **FINISHED** — full payload in `crash_logger.gd:_build_static_payload` |
| PLT-05 | P1 | No crash collection/upload | **FINISHED** — retention cap, `PrivacySettings`, `POST /api/v1/telemetry/crash` |
| PLT-06 | P1 | Stub unlock reports success | **FINISHED** — `Result` enum, `sync_achievements` counts |
| PLT-07 | P1 | No `run_callbacks` pump | **FINISHED** — `steam_service.gd:_process` |
| PLT-08 | P1 | No restart-through-Steam | **FINISHED** — `restartAppIfNecessary` + `get_tree().quit()` |
| PLT-09 | P2 | Third content-version string | **FINISHED** — `ApiConfig.CONTENT_VERSION` in crash payload |
| PLT-10 | P2 | Crash report not flushed | **FINISHED** — `flush()` + `close()` in `_write_crash_report` |
| PLT-11 | P2 | Log file reopened per line | **FINISHED** — session `FileAccess` handle in `crash_logger.gd` |
| PLT-12 | P2 | Dead Steam/cloud shutdown paths | **FINISHED** — `achievement_service.gd` backfill, Steam Cloud mirror, idempotent `shutdown()` |
| PLT-13 | P2 | Weak m7 Steam tests | **FINISHED** — removed from `m7_suite.gd`; covered by `platform_suite.gd` |
| PLT-14 | P2 | App id env-only | **FINISHED** — `config/platform.json`, `steam_appid.txt.example`, env priority |
| PLT-15 | P2 | No CrashLogger tests | **FINISHED** — `platform_suite.gd` crash.* tests |

## Target design

(unchanged — implemented as specified)

## Work plan

All steps implemented.

## Data and schema changes

- Backend migration `20260805120000_AddAccountSteamId.cs`: `Accounts.SteamId`, nullable `Email`, `SteamLinkedAt`
- Client: `res://config/platform.json`, `steam_appid.txt.example`, `addons/godotsteam/`
- No `save_migrator.gd` version bump (Steam Cloud mirrors existing save JSON)

## Acceptance criteria

- [x] Stub mode returns `UNAVAILABLE` from `unlock_achievement`
- [x] `sync_achievements` reports zero synced in stub mode
- [x] GodotSteam GDExtension vendored (binaries gitignored; stub without DLLs)
- [x] `get_auth_ticket_hex()` async Web API path
- [x] `POST /api/v1/auth/steam` with `ISteamAuthService`
- [x] Steam Cloud mirror in `local_save.gd`
- [x] Crash payload with stack, versions, GPU, scene
- [x] Retention cap 20 files / 5 MB
- [x] Opt-in crash upload toggle
- [x] `platform_suite.gd` registered and passing (13 tests, headless)

## Validation

| Suite | Result |
|-------|--------|
| `platform_suite.gd` | 13/13 platform tests pass headless (no Steam client) |
| `SteamAuthTests.cs` | 6/6 pass with `FakeSteamAuthService` |

## Related

- Existing behavior: [`../existing_codebase/platform-and-net.md`](../existing_codebase/platform-and-net.md)
- [`networking.md`](networking.md)
- [`backend-api.md`](backend-api.md)
- [`achievements-meta.md`](achievements-meta.md)
- [`local-save.md`](local-save.md)
- [`ci-cd.md`](ci-cd.md)
- [`validation-suites.md`](validation-suites.md)
