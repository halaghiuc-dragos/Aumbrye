# Save migrator

`SaveMigrator` is a `RefCounted` static utility that gates every validated save load. It refuses to load a document it cannot bring to the current version, which makes it the single decision point for whether a save file is playable. It is on the live play path: `LocalSave.load_into_services()` and `LocalSave.load_character()` both route through `_load_document()`, which calls `SaveMigrator.migrate()`.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/save/save_migrator.gd` | `SaveMigrator` — version constant, `STEPS`, `classify()`, `plan()`, `describe()`, `migrate()`, five step functions, `_normalize_*` helpers, `_fail()` |
| `apps/game/client/scripts/save/local_save.gd` | Caller; `_load_document`, `_snapshot_before_migration`, `_recover_from_corruption`; re-exports version as `SAVE_SCHEMA_VERSION` |
| `apps/game/client/scripts/app/world_flags.gd` | Legacy `worldFlags` id mapping during v4→v5 |
| `apps/game/client/scripts/dungeon/run_floor_config.gd` | Supplies `MAX_FLOORS` used by the v1→v2 step |
| `docs/SAVE_MIGRATIONS.md` | Human-readable migration history (`MIGRATION_DOC`) |

## How it works

### Constants
| Constant | Value | Line |
|----------|-------|------|
| `CURRENT_VERSION` | `6` | 6 |
| `MIGRATION_DOC` | `docs/SAVE_MIGRATIONS.md` | 7 |
| `RESULT_CURRENT` / `RESULT_MIGRATABLE` / `RESULT_TOO_NEW` / `RESULT_UNKNOWN` | `0` / `1` / `2` / `3` | 11-14 |

`local_save.gd:11` sets `SAVE_SCHEMA_VERSION := SaveMigrator.CURRENT_VERSION`, so the writer and the migrator agree on the target version.

### `STEPS` table (lines 26-52)
Five registered steps from v1→v6. Each entry has `from`, `to`, `fn`, and `summary`. `plan(from_version)` returns the steps that would apply without mutating input. `describe(from_version)` returns a human-readable summary string.

### `classify(data) -> int` (lines 96-104)
Returns `RESULT_CURRENT`, `RESULT_MIGRATABLE`, `RESULT_TOO_NEW`, or `RESULT_UNKNOWN` before `migrate()` runs. `LocalSave` uses this to decide whether to write a pre-migration snapshot and whether to quarantine on failure.

### `migrate(data) -> Dictionary` (lines 124-158)
1. `version == CURRENT_VERSION` → returns `data.duplicate(true)` (deep copy).
2. `version > CURRENT_VERSION` → `_fail(..., "too_new", ...)`.
3. `version == 0` → `_fail(..., "missing_version", ...)`.
4. Walks `STEPS`; after each step asserts `schemaVersion == step.to` or returns `_fail(..., "step_error", ...)`.
5. If still not `CURRENT_VERSION` → `_fail(..., "unknown_version", ...)`.

### Migration steps
**v1→v2** — `activeRun` floor defaults (`currentFloor`, `maxFloors`, `floorDefinitions`).

**v2→v3** — `activeRun.runMode`; erases `floorDefinitions`.

**v3→v4** — `activeRun.lastCheckpoint`, `snapshot.worldFlags`, `activeRun.schemaVersion`.

**v4→v5** — Full-document normalization via `_normalize_character`, `_normalize_currencies`, `_normalize_inventory`, `_normalize_storage`, `_normalize_talents`, `_normalize_flags`, `_normalize_quests`, `_normalize_item_instances`, `_normalize_meta`, `_normalize_active_run`. Resets nil `accountId`, recovers `playerDead` from `lastCheckpoint`, namespaces `worldFlags` through `WorldFlags.migrate_legacy_id`.

**v5→v6** — Renames `meta.achievements.mythic_loot` to `aumbral_loot` when the legacy key was true (see [`achievements-meta.md`](achievements-meta.md)).

### Failure contract
`_fail(data, kind, reason)` (lines 571-579) preserves the original payload and adds:

```gdscript
{
    "migrationFailed": true,
    "migrationKind": "too_new" | "missing_version" | "unknown_version" | "step_error",
    "migrationReason": String,
    "originalSchemaVersion": int,
    "requiredVersion": CURRENT_VERSION,
}
```

`LocalSave._load_document` treats `migrationKind == "too_new"` as refuse-without-quarantine (`save_failed("save_from_newer_build")`). All other failure kinds route through `_recover_from_corruption`.

### Pre-migration snapshot
`LocalSave._snapshot_before_migration` (called when `classify == RESULT_MIGRATABLE`) writes `user://backups/<characterId>.premigrate_v<from>_<timestamp>.json` and prunes to five per character.

## Contracts

**Called by:** `local_save.gd` `_load_document`.

**Depends on:** `RunFloorConfig`, `Equipment`, `CharacterAppearance`, `RarityRegistry`, `ContentLoader`, `WorldFlags`.

**Documentation pointer:** `MIGRATION_DOC` → `docs/SAVE_MIGRATIONS.md`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Table-driven v1→v6 chain with per-step version assertion | IMPLEMENTED | `save_migrator.gd:26-52`, `migrate()` |
| `classify`, `plan`, `describe` | IMPLEMENTED | `save_migrator.gd` |
| Full-document v4→v5 normalization | IMPLEMENTED | `save_migrator.gd` `_normalize_*` |
| v5→v6 achievement key rename | IMPLEMENTED | `_migrate_v5_to_v6` |
| Pre-migration snapshot before migratable load | IMPLEMENTED | `local_save.gd` `_snapshot_before_migration` |
| Newer-than-current saves refused without quarantine | IMPLEMENTED | `save_migrator.gd:128-133`, `local_save.gd` `_load_document` |
| `_fail` preserves user payload | IMPLEMENTED | `save_migrator.gd:571-579` |
| `migrate()` deep-copies current-version input | IMPLEMENTED | `save_migrator.gd:126-127` |
| `docs/SAVE_MIGRATIONS.md` | IMPLEMENTED | `docs/SAVE_MIGRATIONS.md` |
| `load_character` shared recovery path | IMPLEMENTED | `local_save.gd` `_load_document`, `_recover_from_corruption` |

## Related
- Improvement plan: [`../actual_improvements/save-migrator.md`](../actual_improvements/save-migrator.md)
- [`local-save.md`](local-save.md), [`character-service.md`](character-service.md), [`inventory-service.md`](inventory-service.md), [`run-flow.md`](run-flow.md), [`world-state.md`](world-state.md)
