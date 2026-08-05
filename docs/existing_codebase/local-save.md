# Local save

`LocalSave` is the autoload that owns all persistence: the character roster, per-character JSON files, the legacy single-file save, rotating backups, corruption quarantine, active-run records, and the optional cloud push/pull. It is on the live play path — every gold change, inventory change, flag write, and run transition calls `autosave()`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/save/local_save.gd` | Autoload `LocalSave` (855 lines) — the entire persistence layer |
| `apps/game/client/scripts/save/save_migrator.gd` | `SaveMigrator` — version gate applied on every load |
| `apps/game/client/scripts/save/character_service.gd` | Supplies `currencies`, `flags`, `quests`, `classId`, appearance |
| `apps/game/client/scripts/save/character_appearance.gd` | Sanitizes the `character.appearance` sub-document |

## How it works

### Paths and constants (`local_save.gd:5-11`)
| Constant | Value |
|----------|-------|
| `SAVE_PATH` | `user://aumbrye_save.json` |
| `ROSTER_PATH` | `user://character_roster.json` |
| `CHARACTERS_DIR` | `user://characters/` |
| `BACKUP_PATH` | `user://aumbrye_save.conflict_backup.json` |
| `BACKUP_DIR` | `user://backups/` |
| `BACKUP_COUNT` | `5` |
| `SAVE_SCHEMA_VERSION` | `SaveMigrator.CURRENT_VERSION` = `4` |

Rotating backups live at `user://backups/aumbrye_save_<0..4>.json` (`_rotating_backup_path`, line 751). Quarantined corrupt files go to `user://aumbrye_save.corrupt_<timestamp>.json` (`_handle_corrupt_save`, line 652).

### Two storage layouts coexist
`_write_save()` (`local_save.gd:681-700`) branches on `_active_character_id`:

- **Non-empty** (the normal case after character creation): writes only `user://characters/<id>.json`, updates the roster entry metadata, saves the roster, and **returns before the backup rotation and before touching `SAVE_PATH`**.
- **Empty** (legacy / pre-roster state): rotates backups when `SAVE_PATH` exists, then writes `SAVE_PATH`.

The consequence is that the rotating-backup system at `local_save.gd:740-748` only ever copies `SAVE_PATH`. Per-character files under `user://characters/` receive no backup copies at all.

### Boot sequence
`_ready()` (`local_save.gd:59-73`): ensures `BACKUP_DIR` and `CHARACTERS_DIR` exist, loads the roster, runs `_migrate_legacy_save_if_needed()`, then warm-loads `_cached_state` from the active character file if present, else from `SAVE_PATH`. This warm load parses raw JSON directly and does **not** run `SaveMigrator.migrate` or `_validate_save`.

`_migrate_legacy_save_if_needed()` (line 794): when the roster has no characters but `SAVE_PATH` exists and contains a `character.classId`, copies the whole save into a new `user://characters/<generated id>.json`, adds a roster entry, and marks it active. `SAVE_PATH` is left in place.

Character ids come from `_generate_character_id()` (line 790): `"warden_%d" % (Time.get_ticks_usec() % 1000000000)`.

### Boot modes
`BootMode` enum (line 50): `NONE`, `NEW_GAME`, `CONTINUE_MAIN`, `CONTINUE_BACKUP`, `CONTINUE_CHARACTER`. UI queues a mode (`queue_boot_new_game`, `queue_boot_continue_main`, `queue_boot_continue_character`, `queue_boot_continue_backup`) and `execute_boot()` (line 195) dispatches:

| Mode | Action |
|------|--------|
| `NEW_GAME` | `_apply_new_game_boot()` |
| `CONTINUE_CHARACTER` | `load_character(_boot_character_id)` |
| `CONTINUE_MAIN` | `load_character(_active_character_id)` if set, else `load_into_services()` |
| `CONTINUE_BACKUP` | `restore_backup(_boot_backup_index)` |
| default | `load_into_services()` when `has_save()` |

`_apply_new_game_boot()` (line 218) generates a character id, calls `_reset_to_defaults()`, applies name/class/appearance, sets the class on `CharacterService`, adds `ClassCatalog.get_starting_weapon_item_id(class_id)` to the inventory, equips it, adds the roster entry, and autosaves.

### Load path
`load_into_services()` (line 23) is the only fully validated read:
1. Missing file → `false`.
2. Empty text → `_handle_corrupt_save("empty_file")`.
3. Unparseable or non-Dictionary → `_handle_corrupt_save("corrupt_json")`.
4. `SaveMigrator.migrate(data)`; `migrationFailed` → `_handle_corrupt_save(migrationReason)`.
5. `_validate_save(data)` fails → `_handle_corrupt_save("corrupt_schema")`.
6. `_apply_save_data(data)`, emit `save_loaded`.

`load_character(id)` (line 242) runs the same migrate + validate steps but on failure returns `false` silently — it does not quarantine, does not restore a backup, and does not emit `save_failed`.

`_validate_save()` (line 616) checks exactly three things: `1 <= schemaVersion <= 4`, `data.has("inventory")`, and `inventory.schemaVersion == 1`. Nothing else is validated.

### Corruption handling
`_handle_corrupt_save(reason)` (line 649): copies `SAVE_PATH` to a timestamped `corrupt_*` file, deletes `SAVE_PATH`, `push_error`s, then walks `list_backups()` and returns on the first successful `restore_backup(index)` after emitting `save_failed(reason)`. If no backup restores, it emits `save_failed(reason)` and calls `_reset_to_defaults()`.

### Save payload
`_build_save_payload()` (line 562) assembles:

| Key | Source |
|-----|--------|
| `schemaVersion` | `SAVE_SCHEMA_VERSION` (4) |
| `accountId` | `_cached_state.accountId`, default `00000000-0000-4000-8000-000000000000` |
| `character` | `_character()` merged with live `ProgressionService.level` / `.xp`, `CharacterService.class_id`, `.appearance_theme`, `.appearance_profile` |
| `currencies` | `{"gold": CharacterService.gold, "coins": CharacterService.get_coins()}` |
| `inventory` | `InventoryService.get_save_inventory()` |
| `storage` | `StorageService.get_save_storage()` |
| `itemInstances` | `_cached_state.itemInstances`, default `{}` |
| `talents` | `ProgressionService.talents` |
| `talentPointsSpent` | `ProgressionService.talent_points_spent` |
| `flags` | `CharacterService.flags` |
| `quests` | `CharacterService.quests` |
| `recipes` | `_cached_state.recipes`, default `[]` |
| `runRelics` | `RunBuffs.to_save_array()` |
| `activeRun` | copied from `_cached_state` when present |
| `wavesActiveRun` | copied from `_cached_state` when present |
| `meta` | copied from `_cached_state` when present |
| `cloudUpdatedAt` | when `_cloud_updated_at != ""` |

`character` sub-keys, from `_default_character()` (line 603) plus writers: `name` (default `Wanderer`), `classId`, `level`, `xp`, `appearanceTheme`, `appearance`, `lastHubMessage`, `firstPersonCamera`.

`meta` is a free-form namespace written by three services: `accessibility` (`accessibility_settings.gd:26`), `leaderboard` (`leaderboard_settings.gd:18`), `hub_tutorial` (`hub_tutorial_service.gd:30`), and `achievements` (`achievement_service.gd:105`).

### `itemInstances` does not round-trip
`itemInstances` is read from `_cached_state` and written straight back (`local_save.gd:581`). No code path ever inserts a key into it: `_reset_to_defaults` sets it to `{}` (line 636) and `_normalize_save_integers` only normalises entries that already exist (lines 724-729). A repository-wide search for `itemInstances` finds writers only in the backend (`services/backend/src/Aumbrye.Application/Services/CharacterStateService.cs:41,158-160`), never in the client. Affix data actually persists inside `inventory.slots[*]` and `inventory.equipped[*]`, which `GridInventory.to_save_dict()` deep-copies (`grid_inventory.gd:30-37`) and `from_save_dict()` restores through `_normalize_slot` (`grid_inventory.gd:40-48`). Round-tripped per-slot keys therefore include `itemId`, `quantity`, `x`, `y`, `instanceId`, `rarity`, `affixes`, `rollSeed`, `upgradeLevel`, `durability`, and the dungeon-key trio `keyId` / `lockId` / `keyLabel`.

### Integer normalisation
`_normalize_save_integers()` (line 703) forces `int` on `inventory.gridWidth`, `gridHeight`, `schemaVersion`, on every slot's `quantity` / `x` / `y` / `rollSeed` (`_normalize_slot_integers`, line 733), on `equipped[*]`, on `talentPointsSpent`, and on `itemInstances[*]`. This exists because `JSON.parse_string` returns floats.

### Active run and waves records
| Method | Line | Key |
|--------|------|-----|
| `get_active_run` / `set_active_run` / `clear_active_run` | 349 / 354 / 359 | `activeRun` |
| `get_waves_active_run` / `set_waves_active_run` / `clear_waves_active_run` | 366 / 371 / 376 | `wavesActiveRun` |
| `has_continuable_run` | 334 | requires non-empty `activeRun`, `playerDead` falsy, non-empty `snapshot` Dictionary, and `snapshot.player.health > 0` when present |
| `has_continuable_waves_run` | 383 | same snapshot checks plus `currentWave >= 0` |

`set_active_run` and `set_waves_active_run` each call `autosave()`, so a floor transition writes the whole payload to disk.

### Cloud sync
`sync_from_cloud()` (line 460) pulls: ensures a dev session if `ApiConfig.access_token` is empty, calls `ApiClient.get_save()`, refuses to overwrite when `get_active_run()` is non-empty, backs the local file up to `BACKUP_PATH` when `_cloud_updated_at` differs from the server value, then applies the server state — server always wins. `push_to_cloud()` (line 489) pushes and, on `conflict`, backs up locally and applies the server state, returning `{"ok": false, "conflict": true}`. `_backup_local_save()` (line 666) only copies `SAVE_PATH`, so a conflict on a roster character backs up nothing.

### Deletion
`delete_save()` (line 410) removes `SAVE_PATH`, the active character file, clears `_cached_state`, `_cloud_updated_at`, `_active_character_id`, and resets the roster. `delete_character(id)` (line 424) removes one character file and its roster entry. `delete_character_slot(index)` (line 444) deletes the active character when `index < 0`, otherwise deletes rotating backup `index`.

## Contracts

**Signals:** `save_loaded`, `save_failed(reason: String)`, `cloud_sync_completed(server_won: bool)`, `backup_restored(index: int)`.

**Autoload dependencies:** `SaveMigrator`, `InventoryService`, `StorageService`, `ProgressionService`, `CharacterService`, `RunBuffs`, `WavesRunService`, `CharacterAppearance`, `ClassCatalog`, `GridInventory`, `ApiConfig`, `ApiClient`, `RunFlow` (only for `RunFlow.last_hub_message` in `_default_character`, line 611).

**Roster document** (`user://character_roster.json`): `{"characters": [{"id", "name", "classId", "level", "savedAt"}], "activeId": String}`.

**Slot label contract:** `list_character_slots()` (line 143) skips any roster entry with an empty `classId` and formats `label` as `"<name> — <classId> (Lv<level>)"`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Per-character JSON save, roster, boot modes | IMPLEMENTED | `local_save.gd:195-264`, `765-855` |
| Corruption quarantine + backup restore for the legacy path | IMPLEMENTED | `local_save.gd:649-663` |
| Rotating backups for per-character saves | ABSENT | `_write_save` returns at `local_save.gd:693` before reaching the rotation at `694-695`; `_rotate_backups` only copies `SAVE_PATH` (`local_save.gd:747-748`) |
| `load_character` corruption handling | PARTIAL | Returns `false` at `local_save.gd:250-258` without quarantine, backup restore, or `save_failed` |
| Boot warm-load bypasses migration and validation | PARTIAL | `local_save.gd:64-73` assigns `_cached_state` from raw JSON |
| `itemInstances` | FAKE | Declared and preserved (`local_save.gd:581`) but no client code ever writes a key; the backend does (`CharacterStateService.cs:158-160`) |
| Affix / rarity / upgrade round-trip via inventory slots | IMPLEMENTED | `grid_inventory.gd:30-48`, `local_save.gd:703-737` |
| `_validate_save` depth | PARTIAL | Checks only `schemaVersion` range, `inventory` presence, and `inventory.schemaVersion == 1` (`local_save.gd:616-625`) |
| Conflict backup for roster characters | ABSENT | `_backup_local_save` only copies `SAVE_PATH` (`local_save.gd:666-669`) |
| Autosave frequency | PARTIAL | `set_active_run` autosaves the full payload on every floor transition (`local_save.gd:354-356`, called from `run_flow.gd:607`) |
| `accountId` | FAKE | Hardcoded nil-UUID default at `local_save.gd:576` |
| Character id uniqueness | PARTIAL | `Time.get_ticks_usec() % 1000000000` (`local_save.gd:791`) with no collision check against the roster |
| `recipes` array | STUB | Persisted at `local_save.gd:585` but no code writes into it; `RecipeCatalog` reads only from `content/recipes/` |
| Runtime save shape versus `content/schemas/character-state.v1.json` | PARTIAL | Schema pins `schemaVersion` to `1` and sets `additionalProperties: false` (`content/schemas/character-state.v1.json:7,20`) while the runtime writes version 4 plus `talentPointsSpent`, `quests`, `wavesActiveRun`, `meta`, `cloudUpdatedAt` |

## Related
- Improvement plan: [`../actual_improvements/local-save.md`](../actual_improvements/local-save.md)
- [`save-migrator.md`](save-migrator.md), [`character-service.md`](character-service.md), [`character-appearance.md`](character-appearance.md), [`inventory-service.md`](inventory-service.md), [`run-flow.md`](run-flow.md), [`content-catalog.md`](content-catalog.md)
- Owned elsewhere: [`backend-api.md`](backend-api.md), [`ui/continue_menu.md`](ui/continue_menu.md), [`ui/character_create.md`](ui/character_create.md)
