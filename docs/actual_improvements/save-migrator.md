# Save migrator — improvement plan

## Current state
`SaveMigrator` (`apps/game/client/scripts/save/save_migrator.gd`, 83 lines) advances a save from v1 to `CURRENT_VERSION := 4` through three steps and refuses anything it cannot. See [`../existing_codebase/save-migrator.md`](../existing_codebase/save-migrator.md). The chain structure is sound — each step re-reads `schemaVersion`, so it is data-driven rather than fall-through — but every step touches only `activeRun`. No step has ever normalised `character`, `inventory`, `talents`, `flags`, `currencies`, `storage`, `itemInstances`, `recipes`, `runRelics`, `quests`, `meta`, or `wavesActiveRun`. No backup is taken before a migration runs, character files receive no backups at all, and a save from a *newer* build is reported through the same channel as corruption, so a client downgrade quarantines a healthy save. `MIGRATION_DOC` points at `docs/SAVE_MIGRATIONS.md`, which does not exist.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| MIG-01 | P0 | No backup is taken before a migration is applied; a step that produces an invalid document destroys the only copy, because per-character backups are never written | `save_migrator.gd:10-27` has no backup call; `local_save.gd:684-693` returns before the rotation; `local_save.gd:747-748` copies only `SAVE_PATH` |
| MIG-02 | P0 | A migration failure inside `load_character` returns `false` with no quarantine, no backup restore, and no `save_failed`, so a broken character slot presents as a missing slot | `local_save.gd:254-256` vs `local_save.gd:36-38` |
| MIG-03 | P0 | Migrations cover only `activeRun`; a v1 save whose `inventory.equipped.weapon` is a String, or whose `talents` values are floats from `JSON.parse_string`, reaches services unrepaired | `save_migrator.gd:33`, `49`, `62`; coercion is left to `grid_inventory.gd:373-376` and `local_save.gd:703-737` |
| MIG-04 | P1 | A save with `schemaVersion > CURRENT_VERSION` is reported as `unsupported schemaVersion N` and quarantined as corrupt, so a downgraded client deletes a good save | `save_migrator.gd:25-26`, `local_save.gd:36-38`, `local_save.gd:649-655` |
| MIG-05 | P1 | `_fail` returns a replacement dictionary that discards all user data; the caller can only recover because the file happens to still be on disk | `save_migrator.gd:76-82` |
| MIG-06 | P1 | `docs/SAVE_MIGRATIONS.md`, named by `MIGRATION_DOC`, does not exist, so there is no record of what each version changed | `save_migrator.gd:7` |
| MIG-07 | P2 | `migrate()` returns the caller's object unchanged when already current, so a mutation by the caller edits the parsed document in place | `save_migrator.gd:12-13` |
| MIG-08 | P2 | There is no `migrate_range` or dry-run entry point, so no tool can report what a save *would* become without applying it | `save_migrator.gd:10-27` |

## Target design

### Registered steps with a self-check
The chain becomes a declared table so adding a version cannot skip the `if` ladder, and every step is verified to have produced what it claimed:

```gdscript
const CURRENT_VERSION := 5
const MIGRATION_DOC := "docs/SAVE_MIGRATIONS.md"

const STEPS: Array[Dictionary] = [
    {"from": 1, "to": 2, "fn": "_migrate_v1_to_v2", "summary": "activeRun floor fields"},
    {"from": 2, "to": 3, "fn": "_migrate_v2_to_v3", "summary": "activeRun.runMode; drop floorDefinitions"},
    {"from": 3, "to": 4, "fn": "_migrate_v3_to_v4", "summary": "lastCheckpoint; snapshot.worldFlags"},
    {"from": 4, "to": 5, "fn": "_migrate_v4_to_v5", "summary": "typed sections; equipped instances; accountId reset"},
]

static func migrate(data: Dictionary) -> Dictionary
static func plan(from_version: int) -> Array[Dictionary]   ## dry run: the steps that would apply
static func describe(from_version: int) -> String          ## human-readable summary for logs and UI
```

`migrate()` walks `STEPS`, and after each call asserts `int(result.get("schemaVersion", 0)) == step.to`; a step that fails to advance the version is a programming error and produces `_fail(data, "step %d->%d did not advance version")` rather than silently looping.

### Newer saves are not corruption
Split the two outcomes so `LocalSave` can react differently:

```gdscript
static func classify(data: Dictionary) -> int   ## returns one of the RESULT_* constants
const RESULT_CURRENT := 0
const RESULT_MIGRATABLE := 1
const RESULT_TOO_NEW := 2
const RESULT_UNKNOWN := 3
```

`_fail` gains a `kind` field:

```gdscript
{
    "migrationFailed": true,
    "migrationKind": "too_new" | "missing_version" | "unknown_version" | "step_error",
    "migrationReason": String,
    "originalSchemaVersion": int,
    "requiredVersion": CURRENT_VERSION,
}
```

`LocalSave` treats `migrationKind == "too_new"` as *refuse to load, do not quarantine, do not delete*: the file stays where it is, `save_failed("save_from_newer_build")` is emitted, and the continue menu shows "This save was made by a newer version of Aumbrye." Every other kind follows the existing quarantine and backup path.

Chosen over silently attempting to load a newer save: reading a document whose semantics you do not know is how progress gets corrupted permanently. Refusing without deleting is the only safe option and costs the player nothing.

### Pre-migration backup
Migration becomes responsible for its own safety net, because it is the only code that knows a rewrite is about to happen:

```gdscript
## In LocalSave, called from _load_document before SaveMigrator.migrate.
func _snapshot_before_migration(path: String, from_version: int) -> String:
    var target := "%s%s.premigrate_v%d_%s.json" % [
        BACKUP_DIR,
        _active_character_id if _active_character_id != "" else "legacy",
        from_version,
        Time.get_datetime_string_from_system().replace(":", "-"),
    ]
    DirAccess.copy_absolute(path, target)
    return target
```

It runs only when `SaveMigrator.classify(parsed) == RESULT_MIGRATABLE`, so an already-current load costs nothing. The artefact path is included in the `save_failed` payload and in the log line, so a player who reports a broken migration can be pointed at an exact file. Pre-migration artefacts are pruned to the five most recent per character alongside the rotating backups.

### Full-document v4→v5 step
This is the step that repays MIG-03 by normalising every section the runtime actually reads:

```gdscript
static func _migrate_v4_to_v5(data: Dictionary) -> Dictionary:
    var copy: Dictionary = data.duplicate(true)
    copy["schemaVersion"] = 5
    _normalize_character(copy)
    _normalize_currencies(copy)
    _normalize_inventory(copy)
    _normalize_storage(copy)
    _normalize_talents(copy)
    _normalize_flags(copy)
    _normalize_quests(copy)
    _normalize_item_instances(copy)
    _normalize_meta(copy)
    _normalize_active_run(copy)
    return copy
```

Each helper is total and never throws:

| Helper | Repairs |
|--------|---------|
| `_normalize_character` | Ensures `name` (default `Wanderer`), `classId` (String), int `level >= 1`, int `xp >= 0`, int `appearanceTheme`, `appearance` through `CharacterAppearance.sanitize`; drops `lastHubMessage` |
| `_normalize_currencies` | Ensures a Dictionary; int `gold >= 0`; `coins` defaults to `gold` |
| `_normalize_inventory` | Ensures `schemaVersion = 1`, int `gridWidth`/`gridHeight` >= 1, `slots` is an Array of Dictionaries with a String `itemId` and int `quantity >= 1`, ints on `x`/`y`/`rollSeed`/`upgradeLevel`/`durability`, `affixes` is an Array of `{affixId: String, value: float}`, `rarity` normalised through `RarityRegistry.normalize`, an `instanceId` synthesised when absent; `equipped` becomes a Dictionary with all nine `Equipment.SLOT_ORDER` keys, converting a legacy `equipped.weapon` String into `{"itemId": s, "quantity": 1}` |
| `_normalize_storage` | Same as `_normalize_inventory` when `storage` is present |
| `_normalize_talents` | Values coerced to int `>= 0`; unknown node ids retained (the tree may re-add them) but counted and logged; `talentPointsSpent` coerced to int and clamped to the sum of `rank * costPerRank` for nodes that still exist |
| `_normalize_flags` | Values restricted to bool / int / float / String; anything else dropped |
| `_normalize_quests` | Values coerced to String state, except `<id>_progress` keys which must be Dictionaries |
| `_normalize_item_instances` | Ensures a Dictionary whose entries are Dictionaries; drops malformed entries |
| `_normalize_meta` | Ensures a Dictionary and that the four known sub-keys `accessibility`, `leaderboard`, `hub_tutorial`, `achievements` are Dictionaries when present |
| `_normalize_active_run` | Existing v3→v4 guarantees plus `schemaVersion = 5`, `clearedFloors` as an Array of ints, `worldFlags` namespacing (see [`world-state.md`](world-state.md)), and the `playerDead` recovery described in [`run-flow.md`](run-flow.md) |

`talentPointsSpent` clamping matters: an over-spent counter silently locks the player out of talents forever, and `ProgressionService.get_available_talent_points()` (`progression_service.gd:26-27`) has no way to detect it.

### Data preservation on failure
`_fail` stops discarding the document:

```gdscript
static func _fail(data: Dictionary, kind: String, reason: String) -> Dictionary:
    push_error("SaveMigrator: %s — refusing load (%s)" % [reason, kind])
    var out := data.duplicate(true)
    out["migrationFailed"] = true
    out["migrationKind"] = kind
    out["migrationReason"] = reason
    out["originalSchemaVersion"] = int(data.get("schemaVersion", 0))
    out["requiredVersion"] = CURRENT_VERSION
    return out
```

Keeping the payload lets a future repair tool salvage `character` and `inventory` from a document that failed on some other section, and costs one deep copy on a path that already failed.

### Isolation
`migrate()` returns `data.duplicate(true)` even in the already-current case, so the caller can never mutate the parsed JSON by accident.

### `docs/SAVE_MIGRATIONS.md`
Created as a table, one row per step, generated to match `STEPS`: version pair, the `summary` string, the keys added, the keys removed, and the recovery behaviour if the step fails. A `content_suite` assertion keeps the file and `STEPS` in sync so the document cannot rot.

## Work plan

1. **Add `STEPS`, `classify`, `plan`, `describe`, and the self-check in `migrate()`** — `save_migrator.gd`: table-driven walk, per-step version assertion, deep copy on the current-version path. No new version yet. Closes MIG-07, MIG-08.
2. **Split the failure taxonomy** — `save_migrator.gd`: `_fail(data, kind, reason)`, preserve the payload, add `migrationKind` and `requiredVersion`. `local_save.gd:36-38` and `254-256` branch on `migrationKind`; `too_new` refuses without quarantine and emits `save_failed("save_from_newer_build")`. Closes MIG-04, MIG-05.
3. **Route `load_character` through the shared recovery path** — depends on step 4 of [`local-save.md`](local-save.md) (`_load_document` / `_recover_from_corruption`). Closes MIG-02.
4. **Pre-migration snapshot** — `local_save.gd`: `_snapshot_before_migration`, called only for `RESULT_MIGRATABLE`, pruned to five per character, path reported in `save_failed`. Closes MIG-01.
5. **Write `_migrate_v4_to_v5` and the ten `_normalize_*` helpers, bump `CURRENT_VERSION` to 5** — `save_migrator.gd`. Closes MIG-03.
6. **Author `docs/SAVE_MIGRATIONS.md` and the sync assertion** — new doc plus `content_suite` check against `STEPS`. Closes MIG-06.

## Data and schema changes

**Version bump: `save_migrator.gd` `CURRENT_VERSION` 4 → 5.** `local_save.gd:11` picks this up through `SAVE_SCHEMA_VERSION`, and `_validate_save` / `SaveValidator` accept `1..5`. This is the same single bump described in [`local-save.md`](local-save.md), [`run-flow.md`](run-flow.md), and [`world-state.md`](world-state.md); the four plans share one version step.

**New keys guaranteed at v5:**

| Section | Guarantee |
|---------|-----------|
| `character` | `name`, `classId`, `level`, `xp`, `appearanceTheme`, `appearance`; `lastHubMessage` removed |
| `currencies` | `gold` and `coins` both present as ints |
| `inventory.equipped` | All nine `Equipment.SLOT_ORDER` keys present as Dictionaries |
| `inventory.slots[*]` | `itemId`, `quantity`, `x`, `y`, `instanceId` present; `rarity` normalised; `affixes` well-formed |
| `talents` | int ranks; `talentPointsSpent` clamped to the reachable total |
| `flags`, `quests`, `meta`, `itemInstances` | Container types guaranteed |
| `activeRun` | `schemaVersion: 5`, `clearedFloors` ints, namespaced `worldFlags`, no `playerDead` |

**Schema files to update:** `content/schemas/character-state.v2.json` (new, described in [`local-save.md`](local-save.md)) must allow `schemaVersion` up to `5`, and `content/schemas/inventory.v2.json` (new) must describe the nine-slot `equipped` Dictionary and the full slot key set. `scripts/validate-content/validate.mjs` gains the two fixture mappings.

**Failure and recovery behaviour.** Three distinct outcomes, none of which loses permanent progress silently:

| Situation | Behaviour |
|-----------|-----------|
| `schemaVersion` missing or unknown | Quarantine to `<path>.corrupt_<timestamp>.json`, walk that character's backups newest-first, `save_failed("missing_version" \| "unknown_version")` |
| `schemaVersion > 5` | File left untouched, `save_failed("save_from_newer_build")`, continue menu shows the newer-build message, roster entry retained |
| A `_normalize_*` helper drops data | Load succeeds; one `push_warning` per section names the count and kind of dropped entries; the pre-migration artefact path is logged |
| A step fails its version assertion | `_fail(..., "step_error", ...)` with the payload preserved, then the corruption path |

A missing content id behind a normalised slot is explicitly not a migration failure: the slot survives migration and is dropped later by `GridInventory` with a warning, so removing an item from `content/items/` cannot brick a save.

## Acceptance criteria
- [ ] Loading a v4 character file writes `user://backups/<characterId>.premigrate_v4_<timestamp>.json` before any step runs, and loading an already-v5 file writes no such artefact. (MIG-01)
- [ ] A character file with `schemaVersion: 99` is quarantined, backup 0 is restored, and `save_failed` is emitted. (MIG-02)
- [ ] A v1 save with `equipped.weapon` as a String, float `talents` ranks, and `talentPointsSpent` exceeding the reachable total migrates to a v5 document with an instance-shaped `equipped.weapon`, int ranks, and a clamped counter. (MIG-03)
- [ ] A save with `schemaVersion: 6` leaves the file on disk, emits `save_failed("save_from_newer_build")`, and produces no `corrupt_*` artefact. (MIG-04)
- [ ] A failed migration result still contains the original `character` and `inventory` sections alongside `migrationFailed`. (MIG-05)
- [ ] `docs/SAVE_MIGRATIONS.md` has one row per entry in `SaveMigrator.STEPS` with matching `from`, `to`, and `summary`. (MIG-06)
- [ ] Mutating the dictionary returned by `migrate()` for an already-current save does not alter the input dictionary. (MIG-07)
- [ ] `SaveMigrator.plan(1)` returns four step descriptors and applies nothing. (MIG-08)

## Validation
Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `save.migrate.chain_v1_to_v5` | A minimal v1 document reaches `schemaVersion: 5` with every v5 guarantee present |
| `save.migrate.step_table_matches_current_version` | `STEPS.back().to == CURRENT_VERSION` and the `from`/`to` pairs are contiguous from 1 |
| `save.migrate.too_new_is_not_corruption` | `schemaVersion: 6` yields `migrationKind == "too_new"` and `LocalSave` leaves the file in place |
| `save.migrate.failure_preserves_payload` | A version-0 document returns a result containing the original `character` |
| `save.migrate.premigrate_artefact_written` | v4 → v5 load creates exactly one `premigrate_v4_*` artefact and none on a second, already-current load |
| `save.migrate.normalizes_equipped_legacy_string` | `equipped.weapon` String becomes `{"itemId": s, "quantity": 1}` |
| `save.migrate.normalizes_float_talents` | `{"arms_1": 2.0}` becomes `{"arms_1": 2}` |
| `save.migrate.clamps_overspent_talent_points` | `talentPointsSpent: 999` with two ranked nodes clamps to the reachable total and `get_available_talent_points()` is non-negative |
| `save.migrate.normalizes_affix_arrays` | A slot with a malformed `affixes` entry keeps the well-formed entries and drops the rest |
| `save.migrate.dry_run_applies_nothing` | `plan(1)` leaves the input document byte-identical |
| `save.migrate.current_version_is_deep_copied` | Mutating the result of a current-version `migrate()` does not affect the input |

Extend `apps/game/client/scripts/validation/suites/content_suite.gd` with `content.docs.save_migrations_in_sync`, parsing `docs/SAVE_MIGRATIONS.md` and asserting a row exists for every `SaveMigrator.STEPS` entry with a matching summary string.

## Related
- Existing state: [`../existing_codebase/save-migrator.md`](../existing_codebase/save-migrator.md)
- [`local-save.md`](local-save.md), [`run-flow.md`](run-flow.md), [`world-state.md`](world-state.md), [`inventory-service.md`](inventory-service.md), [`progression-service.md`](progression-service.md), [`content-catalog.md`](content-catalog.md)
