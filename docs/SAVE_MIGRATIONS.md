# Save migrations

| From | To | Changes |
|------|-----|---------|
| 0 (missing) | — | Rejected; fresh start |
| 1 | 2 | Add `activeRun.currentFloor`, `activeRun.maxFloors`, `activeRun.floorDefinitions` |
| 2 | 3 | Add `activeRun.runMode` (default `"castle"`); **remove** `floorDefinitions` (chunking) |
| 3 | — | Current |

## Active run schema (v3)

Multi-floor runs store:

- `runMode` (`"castle"` | `"endless"`)
- `currentFloor` (int, ≥1)
- `maxFloors` (int; 10 castle, 999999 endless)
- `dungeonDefinition` (current floor layout only)
- `snapshot` (player/enemy/loot state)

**Removed in v3:** `floorDefinitions` map — prior floors regenerated from seed on descend/continue.

## Waves run schema (`wavesActiveRun`)

Separate block at save root (not inside `activeRun`):

- `runMode`: `"waves"`
- `currentWave`, `prepActive`, `lobbyReady`
- `chestsOpened`, `wavesInventory`, `seed`

## Policy

- Main save `schemaVersion` is migrated via `SaveMigrator` on load (`CURRENT_VERSION = 3`).
- Steam Cloud bridge (STEAM-7.3): when Steam SDK available, `SteamService.write_cloud_file` mirrors `user://aumbrye_save.json`; backend `GET/PUT /saves/current` remains source of truth when logged in.
- M4 sample saves without `activeRun` migrate cleanly; v1 active runs gain floor fields at floor 1; v2 saves lose `floorDefinitions` on upgrade to v3.
