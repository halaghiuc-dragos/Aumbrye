# Save migrator

`SaveMigrator` is an 83-line `RefCounted` static utility that gates every validated save load. It refuses to load a document it cannot bring to the current version, which makes it the single decision point for whether a save file is playable. It is on the live play path: `LocalSave.load_into_services()` and `LocalSave.load_character()` both call it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/save/save_migrator.gd` | `SaveMigrator` — version constant, `migrate()`, three step functions, `_fail()` |
| `apps/game/client/scripts/save/local_save.gd` | Only caller; also re-exports the version as `SAVE_SCHEMA_VERSION` |
| `apps/game/client/scripts/dungeon/run_floor_config.gd` | Supplies `MAX_FLOORS` used by the v1→v2 step |

## How it works

### Constants
| Constant | Value | Line |
|----------|-------|------|
| `CURRENT_VERSION` | `4` | 6 |
| `MIGRATION_DOC` | `docs/SAVE_MIGRATIONS.md` | 7 |

`local_save.gd:11` sets `SAVE_SCHEMA_VERSION := SaveMigrator.CURRENT_VERSION`, so the writer and the migrator can never disagree on the target version.

### `migrate(data) -> Dictionary` (lines 10-27)
1. Reads `version = int(data.get("schemaVersion", 0))`.
2. `version == CURRENT_VERSION` → returns `data` unchanged (no deep copy, no normalisation).
3. `version == 0` → `_fail(data, "missing schemaVersion")`.
4. Applies `_migrate_v1_to_v2`, `_migrate_v2_to_v3`, `_migrate_v3_to_v4` in sequence, re-reading `schemaVersion` from the returned dictionary after each step so the chain is data-driven rather than fall-through.
5. If the result is still not `CURRENT_VERSION` → `_fail(data, "unsupported schemaVersion %d" % version)`.

A version above `CURRENT_VERSION` (a save written by a newer build) falls through every `if` and lands on the final `_fail`, reported as `unsupported schemaVersion 5`.

### Migration steps
Each step deep-copies with `data.duplicate(true)` and touches only `activeRun`; none of them modify `character`, `inventory`, `talents`, `flags`, `currencies`, `storage`, `itemInstances`, `recipes`, `runRelics`, `quests`, `meta`, or `wavesActiveRun`.

**`_migrate_v1_to_v2` (lines 30-43)** — sets `schemaVersion = 2`; when `activeRun` is a non-empty Dictionary, defaults `currentFloor` to `1`, `maxFloors` to `RunFloorConfig.MAX_FLOORS` (10), and `floorDefinitions` to `{}`.

**`_migrate_v2_to_v3` (lines 46-56)** — sets `schemaVersion = 3`; when `activeRun` is a non-empty Dictionary, defaults `runMode` to `"castle"` and **erases** `floorDefinitions` (the key the previous step had just added, dropped in favour of `RunFlow`'s in-memory floor cache).

**`_migrate_v3_to_v4` (lines 59-73)** — sets `schemaVersion = 4`; when `activeRun` is a non-empty Dictionary, defaults `lastCheckpoint` to `{}`, defaults `snapshot.worldFlags` to `{}` when `snapshot` is a Dictionary that lacks it, and stamps `activeRun.schemaVersion = 4`.

### Failure contract
`_fail(data, reason)` (lines 76-82) `push_error`s and returns a *replacement* dictionary, not the original:

```gdscript
{
    "migrationFailed": true,
    "migrationReason": reason,
    "originalSchemaVersion": int(data.get("schemaVersion", 0)),
}
```

All user data is discarded from the returned value. `LocalSave` checks `data.get("migrationFailed", false)` at `local_save.gd:36` and `local_save.gd:255`:

- `load_into_services()` calls `_handle_corrupt_save(migrationReason)`, which quarantines `SAVE_PATH`, walks the rotating backups, and emits `save_failed`.
- `load_character()` simply returns `false` — no quarantine, no backup walk, no signal.

## Contracts

**Called by:** `local_save.gd:35` (`load_into_services`), `local_save.gd:254` (`load_character`).

**Not called by:** the `_ready` warm load at `local_save.gd:64-73`, which parses `_cached_state` from raw JSON directly.

**Depends on:** `RunFloorConfig.MAX_FLOORS`.

**Result keys the caller must handle:** `migrationFailed`, `migrationReason`, `originalSchemaVersion`.

**Documentation pointer:** `MIGRATION_DOC` names `docs/SAVE_MIGRATIONS.md`.

**`activeRun` keys the chain guarantees at v4:** `currentFloor`, `maxFloors`, `runMode`, `lastCheckpoint`, `schemaVersion`, and `snapshot.worldFlags` when a `snapshot` exists. `floorDefinitions` is guaranteed absent.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Sequential v1→v2→v3→v4 chain with per-step re-read | IMPLEMENTED | `save_migrator.gd:16-24` |
| Refusal of version 0 and of unknown versions | IMPLEMENTED | `save_migrator.gd:14-15`, `save_migrator.gd:25-26` |
| Coverage of non-`activeRun` sections | ABSENT | All three steps touch only `activeRun` (`save_migrator.gd:33`, `49`, `62`); no step normalises `character`, `inventory`, `talents`, `flags`, `currencies`, `storage`, `itemInstances`, `recipes`, `runRelics`, `quests`, `meta`, or `wavesActiveRun` |
| Backup taken before a migration is applied | ABSENT | No backup call in `save_migrator.gd`; `LocalSave._rotate_backups` runs on write, not before load, and only for `SAVE_PATH` (`local_save.gd:694-695`, `740-748`) |
| Character-file backup coverage during migration failure | ABSENT | `load_character` returns `false` at `local_save.gd:255-256` without quarantine or backup restore; per-character backups are never written at all (`local_save.gd:684-693`) |
| Newer-than-current saves | PARTIAL | Reported as `unsupported schemaVersion N` via the same path as corruption (`save_migrator.gd:26`), so a downgraded client quarantines a perfectly good save |
| `_fail` discards user data | PARTIAL | `save_migrator.gd:78-82` returns a replacement dictionary; the original is only still reachable because `LocalSave` kept the file until `_handle_corrupt_save` copies it |
| `migrate()` on an already-current save | PARTIAL | Returns the same object without duplication (`save_migrator.gd:12-13`), so `_apply_save_data`'s `duplicate(true)` is the only isolation |
| `docs/SAVE_MIGRATIONS.md` | ABSENT | Named by `save_migrator.gd:7` but not present in the repository |
| Downgrade / rollback path | ABSENT | Only forward steps exist in `save_migrator.gd` |

## Related
- Improvement plan: [`../actual_improvements/save-migrator.md`](../actual_improvements/save-migrator.md)
- [`local-save.md`](local-save.md), [`character-service.md`](character-service.md), [`inventory-service.md`](inventory-service.md), [`run-flow.md`](run-flow.md), [`content-catalog.md`](content-catalog.md)
