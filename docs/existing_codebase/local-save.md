# Local save

`LocalSave` is the autoload that owns all persistence: character roster, per-character JSON files, legacy single-file save, per-character rotating backups, corruption quarantine/recovery, active-run records, deferred autosave, and optional cloud push/pull.

## Files

| Path | Role |
|------|------|
| `apps/game/client/scripts/save/local_save.gd` | Autoload — roster, load/write, backups, cloud, autosave coalescing |
| `apps/game/client/scripts/save/save_validator.gd` | Deep validation returning named problem strings |
| `apps/game/client/scripts/save/save_migrator.gd` | Version gate (`CURRENT_VERSION` = 6) on every load |
| `apps/game/client/scripts/save/character_service.gd` | Supplies currencies, flags, quests, appearance |
| `content/schemas/character-state.v2.json` | Runtime save schema descriptor |

## How it works

### One write path

`_active_save_path()` resolves either `user://characters/<id>.json` or legacy `user://aumbrye_save.json`. `_write_save()` always writes through a `.tmp` file, validates with `SaveValidator`, renames atomically, then rotates per-character backups under `user://backups/<characterId>_<0..4>.json`.

### One load path

`_load_document()` is used by both legacy and roster loads: parse → `SaveMigrator.migrate` → `SaveValidator.validate` → apply, or `_recover_from_corruption()` (quarantine, backup walk, `save_failed` / `backup_restored`). Warm load in `_ready` uses the same migrate+validate path. Saves from newer builds (`too_new`) are refused without quarantine.

Pre-migration snapshots: `user://backups/<characterId>.premigrate_v<N>_<timestamp>.json`.

### Payload highlights

- `itemInstances` is derived on save from inventory/storage slots and used only to reconcile missing `affixes` on load.
- `accountId` from `ApiConfig` session or roster `localAccountId`.
- `recipes` populated by `BlacksmithService.unlock_recipe()` → `LocalSave.add_recipe()`.
- `patch_meta(meta)` updates cached meta without autosave; callers use `request_autosave(DEFERRED|IMMEDIATE)`.
- Floor transitions call `set_active_run(..., flush=false)` + coalesced `request_autosave()`.

## Contracts

- **Signals:** `save_loaded`, `save_failed(reason)`, `cloud_sync_completed`, `backup_restored(index)`.
- **Boot modes:** `NEW_GAME`, `CONTINUE_MAIN`, `CONTINUE_BACKUP`, `CONTINUE_CHARACTER`.
- **Autoload consumers:** `CharacterService`, `InventoryService`, `RunFlow`, `HubTutorialService`, cloud via `ApiClient`.

## Current state

| Surface | Status | Evidence |
|---------|--------|----------|
| Per-character rotating backups | IMPLEMENTED | `_rotate_backups(source, character_id)` |
| Corruption recovery | IMPLEMENTED | `_recover_from_corruption`, quarantine artefacts |
| Warm load migration | IMPLEMENTED | `_warm_load_path` |
| SaveValidator | IMPLEMENTED | `save_validator.gd` |
| itemInstances reconciliation | IMPLEMENTED | `_build_item_instances`, `_reconcile_item_instances` |
| Cloud conflict backup | IMPLEMENTED | `_backup_local_save` per character |
| Autosave coalescing | IMPLEMENTED | `request_autosave`, `AUTOSAVE_MIN_INTERVAL` |
| Schema v2 + fixtures | IMPLEMENTED | `character-state.v2.json`, validate.mjs mapping |
| Account id resolution | IMPLEMENTED | `_resolve_account_id()` |
| Recipe unlock persistence | IMPLEMENTED | `add_recipe()` |

## Related

- Improvement plan: [`../actual_improvements/local-save.md`](../actual_improvements/local-save.md) — **FINISHED**
- [`save-migrator.md`](save-migrator.md), [`character-service.md`](character-service.md), [`inventory-service.md`](inventory-service.md), [`run-flow.md`](run-flow.md)
