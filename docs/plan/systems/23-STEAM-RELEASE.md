# System: Steam and Release

## Major milestones

| Major | Title | Phase |
|-------|-------|-------|
| STEAM-7 | Steamworks integration | M7 |
| SHIP-7 | Playtest + store + launch | M7 |

## Minor milestones

| ID | Title | Phase |
|----|-------|-------|
| STEAM-7.1 | Init + overlay + ownership | M7 |
| STEAM-7.2 | Achievements sync | M7 |
| STEAM-7.3 | Cloud bridge | M7 |
| STEAM-7.4 | Auth ticket optional | M7 |
| SHIP-7.1 | Closed playtest | M7 |
| SHIP-7.2 | Store + trailer | M7 |
| SHIP-7.3 | RC + EA live | M7 |
| CI-7.1 | Release workflow | M7 |

## Platforms

- Primary ship: Windows Steam
- Verify Linux/macOS exports; not blockers
- Browser experimental only

## Steam integration stub (client)

`SteamService` autoload (`scripts/platform/steam_service.gd`) provides env-gated init:

| Variable | Purpose |
|----------|---------|
| `AUMBRYE_STEAM_APP_ID` | Real Steam App ID for `steamInitEx`. Omit in dev to use stub mode. |

**Dev / CI (no App ID):** stub mode — achievements log locally, cloud/auth ticket return empty.

**Production:** set `AUMBRYE_STEAM_APP_ID`, build with GodotSteam (`steam` feature), export via
`export_presets.cfg` (MCP addon excluded).

**Blocked without credentials:** real App ID, Steamworks SDK path, depot upload, store page.
Document App ID in deploy secrets only — never commit.

### Init flow

1. `_resolve_app_id()` reads `AUMBRYE_STEAM_APP_ID`.
2. If unset and GodotSteam missing → `_init_stub()` (overlay/cloud off).
3. If GodotSteam present + valid App ID → `steamInitEx`, enable overlay/cloud.
4. `AchievementService` calls `SteamService.unlock_achievement()` when not in stub mode.

### Post-ship

- STEAM-7.2: sync full achievement catalog on login.
- STEAM-7.3: cloud save bridge via `read_cloud_file` / `write_cloud_file`.
- STEAM-7.4: auth ticket for optional backend validation.

## Hotfix

Document day-one hotfix path in `docs/RUNBOOK_HOTFIX.md` during SHIP-7.3.
