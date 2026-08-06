# Save migrations

Version history for `SaveMigrator` (`apps/game/client/scripts/save/save_migrator.gd`). `CURRENT_VERSION` is **6**. Each row matches one entry in `SaveMigrator.STEPS`.

| From | To | Summary | Keys added | Keys removed | Recovery on failure |
|------|-----|---------|------------|--------------|---------------------|
| 1 | 2 | activeRun floor fields | `activeRun.currentFloor`, `activeRun.maxFloors`, `activeRun.floorDefinitions` | — | File quarantined; pre-migration artefact at `user://backups/<characterId>.premigrate_v1_<timestamp>.json` |
| 2 | 3 | activeRun.runMode; drop floorDefinitions | `activeRun.runMode` | `activeRun.floorDefinitions` | File quarantined; pre-migration artefact retained |
| 3 | 4 | lastCheckpoint; snapshot.worldFlags | `activeRun.lastCheckpoint`, `activeRun.snapshot.worldFlags`, `activeRun.schemaVersion` | — | File quarantined; pre-migration artefact retained |
| 4 | 5 | typed sections; equipped instances; accountId reset | `character.appearance`, `character.appearanceTheme`, `currencies.coins`, `inventory.equipped.<slot>`, `inventory.slots[*].instanceId`, `activeRun.clearedFloors`, `activeRun.schemaVersion` | `character.lastHubMessage`, `activeRun.playerDead`, `activeRun.floorDefinitions` | `playerDead` with checkpoint restores snapshot; without checkpoint drops `activeRun` only; other sections preserved |
| 5 | 6 | meta.achievements mythic_loot renamed to aumbral_loot | `meta.achievements.aumbral_loot` (when `mythic_loot` was true) | `meta.achievements.mythic_loot` | File quarantined; pre-migration artefact retained |

## v6 guarantees

After migration to version 6, achievement unlock keys use `aumbral_loot` instead of legacy `mythic_loot` under `meta.achievements`.

## v5 guarantees

After migration to version 5, these sections are normalized:

- **character** — `name`, `classId`, `level`, `xp`, `appearanceTheme`, `appearance`; `lastHubMessage` removed
- **currencies** — `gold` and `coins` as ints `>= 0`
- **inventory** / **storage** — `schemaVersion: 1`, grid dimensions, slot instances with `itemId`, `quantity`, `instanceId`, normalized `rarity` and `affixes`; `equipped` has all nine `Equipment.SLOT_ORDER` keys
- **talents** — int ranks `>= 0`; `talentPointsSpent` clamped to reachable total
- **flags** — bool / int / float / String values only
- **quests** — string states; `<id>_progress` as dictionaries
- **itemInstances** — dictionary of dictionaries
- **meta** — dictionary; known sub-keys are dictionaries when present
- **activeRun** — `schemaVersion: 5`, `clearedFloors` as int array, namespaced `worldFlags`, no `playerDead`

## Newer builds

Saves with `schemaVersion > 6` are refused without quarantine. `LocalSave` emits `save_failed("save_from_newer_build")` and leaves the file on disk.

## Related

- [`actual_improvements/save-migrator.md`](actual_improvements/save-migrator.md)
- [`existing_codebase/save-migrator.md`](existing_codebase/save-migrator.md)
