# Local save — improvement plan

## Status: FINISHED

## Current state
`LocalSave` (`apps/game/client/scripts/save/local_save.gd`) persists per-character JSON with unified `_load_document` / `_write_save` paths, per-character rotating backups, atomic temp-and-rename writes, `SaveValidator` deep validation, derived `itemInstances`, pre-migration snapshots (via `SaveMigrator`), deferred autosave coalescing, and `SaveMigrator.CURRENT_VERSION` (6) through `SAVE_SCHEMA_VERSION`. See [`../existing_codebase/local-save.md`](../existing_codebase/local-save.md).

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| SAV-01 | P0 | Per-character saves got no backups | **FINISHED** — `_active_save_path`, parameterized `_rotate_backups` |
| SAV-02 | P0 | `load_character` silent corruption | **FINISHED** — `_load_document` + `_recover_from_corruption` |
| SAV-03 | P0 | Warm load skipped migration | **FINISHED** — `_warm_load_path` migrates + validates |
| SAV-04 | P0 | `itemInstances` dead passthrough | **FINISHED** — `_build_item_instances` + reconciliation on load |
| SAV-05 | P1 | Cloud conflict backed up only legacy path | **FINISHED** — `_backup_local_save` per character, path in result |
| SAV-06 | P1 | Shallow `_validate_save` | **FINISHED** — `SaveValidator.validate` |
| SAV-07 | P1 | Floor transition full flush | **FINISHED** — `request_autosave`, `set_active_run(..., flush)` |
| SAV-08 | P1 | Schema v1 mismatch | **FINISHED** — `character-state.v2.json`, fixture, validate.mjs mapping |
| SAV-09 | P1 | Nil `accountId` | **FINISHED** — `_resolve_account_id()` |
| SAV-10 | P2 | Character id collisions | **FINISHED** — collision-checked `_generate_character_id()` |
| SAV-11 | P2 | Dead `recipes` array | **FINISHED** — `BlacksmithService.unlock_recipe` → `LocalSave.add_recipe` |
| SAV-12 | P2 | `lastHubMessage` in save | **FINISHED** — removed from `_default_character()` |

## Target design

### One write path, one backup rule
`_write_save` stops branching on storage layout and delegates to a single resolved target:

```gdscript
func _active_save_path() -> String:
    if _active_character_id != "":
        return _character_path(_active_character_id)
    return SAVE_PATH

func _write_save(data: Dictionary, rotate_backups: bool = true) -> bool
```

`_rotate_backups()` becomes parameterised and namespaced per character so slots never collide:

```gdscript
func _rotating_backup_path(index: int, character_id: String = "") -> String:
    if character_id == "":
        return "%saumbrye_save_%d.json" % [BACKUP_DIR, index]
    return "%s%s_%d.json" % [BACKUP_DIR, character_id, index]

func _rotate_backups(source_path: String, character_id: String = "") -> void
```

`list_backups()` and `restore_backup()` take an optional `character_id` defaulting to `_active_character_id`, so the continue menu lists the backups of the slot the player is looking at. Writes become atomic: write `<path>.tmp`, verify it reparses to a Dictionary that passes `_validate_save`, then `DirAccess.rename_absolute` over the real path. A power loss can therefore destroy the temp file but never the last good save.

Chosen over "keep two layouts and add a second rotation": one resolved path removes the whole class of bug where a hardening step silently applies to only one layout.

### One load path
`load_into_services()` and `load_character()` collapse into a private `_load_document(path, character_id)` used by both, so quarantine and recovery are impossible to skip:

```gdscript
func _load_document(path: String, character_id: String = "") -> bool:
    var raw := _read_raw_text(path)
    if raw.strip_edges().is_empty():
        return _recover_from_corruption(path, character_id, "empty_file")
    var parsed = JSON.parse_string(raw)
    if not parsed is Dictionary:
        return _recover_from_corruption(path, character_id, "corrupt_json")
    var data: Dictionary = SaveMigrator.migrate(parsed)
    if data.get("migrationFailed", false):
        return _recover_from_corruption(path, character_id, str(data.get("migrationReason", "migration_failed")))
    var problems := SaveValidator.validate(data)
    if not problems.is_empty():
        return _recover_from_corruption(path, character_id, "corrupt_schema: %s" % ", ".join(problems))
    _apply_save_data(data)
    save_loaded.emit()
    return true

func _recover_from_corruption(path: String, character_id: String, reason: String) -> bool
```

`_recover_from_corruption` quarantines to `<path>.corrupt_<timestamp>.json`, walks that character's backups newest-first, emits `save_failed(reason)`, and only calls `_reset_to_defaults()` when every backup fails. `backup_restored(index)` is emitted on success so the continue menu can tell the player which snapshot they are on.

### Deep validation as its own unit
Extract validation into `apps/game/client/scripts/save/save_validator.gd` so it is testable without file IO and returns *what* failed:

```gdscript
class_name SaveValidator
extends RefCounted

const REQUIRED_TOP_LEVEL: Array[String] = [
    "schemaVersion", "character", "currencies", "inventory", "talents", "flags",
]

## Returns an array of human-readable problems; empty means valid.
static func validate(data: Dictionary) -> Array[String]
```

Checks, each contributing one problem string: `schemaVersion` is an int in `1..SaveMigrator.CURRENT_VERSION`; every `REQUIRED_TOP_LEVEL` key present with the right container type; `inventory.schemaVersion == 1`; `inventory.gridWidth`/`gridHeight` are ints `>= 1`; `inventory.slots` is an Array whose entries are Dictionaries with an `itemId` String and an int `quantity >= 1`; `inventory.equipped` is a Dictionary whose keys are all in `Equipment.SLOT_ORDER`; `talents` values are ints `>= 0`; `character.level` is an int `>= 1` and `character.xp` an int `>= 0`; `currencies.gold` is a number `>= 0`. Unknown extra keys are allowed — forward compatibility matters more than strictness for a local file.

### Retire `itemInstances`, or make it real
The affix payload already round-trips on inventory slots and equipped instances, and that is the design the game actually uses. Rather than leaving a key that three layers disagree about, `itemInstances` becomes a derived index rebuilt on save and never treated as the source of truth:

```gdscript
func _build_item_instances() -> Dictionary:
    var out: Dictionary = {}
    for slot in InventoryService.inventory.slots:
        _index_instance(out, slot)
    for slot_name in InventoryService.inventory.equipped:
        _index_instance(out, InventoryService.inventory.equipped[slot_name])
    for slot in StorageService.storage.slots:
        _index_instance(out, slot)
    return out
```

`_index_instance` writes one entry keyed by `instanceId` containing `schemaVersion: 1`, `instanceId`, `itemDefId` (from `itemId`), `rarity`, `affixes`, `rollSeed`, and `durability` when present — matching the `rolledItemInstance` shape the backend and schema already expect. On load, `itemInstances` is read for *reconciliation only*: any slot missing `affixes` but whose `instanceId` is present in `itemInstances` recovers them, which is exactly the repair a cloud round-trip through the backend needs. Nothing reads stats from it.

Rejected alternative: deleting the key. The backend writes it (`CharacterStateService.cs:158-160`) and the schema requires it, so deleting it client-side guarantees a cloud round-trip drops data.

### Cloud conflict backup
`_backup_local_save()` copies the resolved active path and names the artefact after the character:

```gdscript
func _backup_local_save() -> String:
    var source := _active_save_path()
    if not FileAccess.file_exists(source):
        return ""
    var target := "%s%s.conflict_%s.json" % [
        BACKUP_DIR,
        _active_character_id if _active_character_id != "" else "legacy",
        Time.get_datetime_string_from_system().replace(":", "-"),
    ]
    DirAccess.copy_absolute(source, target)
    return target
```

The returned path is included in the `push_to_cloud` result so the UI can tell the player where their pre-conflict save went. The single-slot `BACKUP_PATH` constant is removed.

### Autosave throttling
Splitting the record from the payload removes the expensive part of a floor transition:

```gdscript
func set_active_run(data: Dictionary, flush: bool = true) -> void
func request_autosave() -> void   # coalesces to at most one write per AUTOSAVE_MIN_INTERVAL
const AUTOSAVE_MIN_INTERVAL := 2.0
```

`request_autosave` starts a one-shot timer; repeated calls inside the window collapse into one write. `autosave()` stays as the immediate, unconditional flush used at run boundaries and on `NOTIFICATION_WM_CLOSE_REQUEST`. `run_flow.gd:590-607` calls `set_active_run(active, false)` during a floor transition and `autosave()` once at the end.

### Schema alignment
`content/schemas/character-state.v1.json` is bumped to a v2 document that describes what the client actually writes. See the data section.

### Identity
`accountId` is written from `ApiConfig` when a session exists and otherwise from a locally generated v4 UUID stored once in the roster, so a save is traceable without pretending to be authenticated:

```gdscript
func _resolve_account_id() -> String
```

`_generate_character_id()` appends a roster-collision check and retries with an incrementing suffix. `character.lastHubMessage` is dropped from `_default_character()`; the hub already owns `RunFlow.last_hub_message` for the current session.

## Work plan

1. **Extract `SaveValidator`** — new file `apps/game/client/scripts/save/save_validator.gd`; `local_save.gd:616-625` delegates to it and keeps returning bool for now. Closes SAV-06.
2. **Resolve one save path and make writes atomic** — `local_save.gd:681-700`: add `_active_save_path()`, remove the early return, write through a `.tmp` + validate + rename sequence. Game runnable, backups still legacy-only.
3. **Per-character rotating backups** — `local_save.gd:740-762`: parameterise `_rotate_backups` and `_rotating_backup_path` by `character_id`; thread the id through `list_backups`, `restore_backup`, `delete_character_slot`. Closes SAV-01.
4. **Collapse the two load paths** — `local_save.gd:23-44` and `242-264` become `_load_document`; add `_recover_from_corruption` with per-character quarantine and backup walk. Closes SAV-02.
5. **Migrate and validate the warm load** — `local_save.gd:59-73`: route the `_ready` read through `SaveMigrator.migrate` + `SaveValidator.validate`, and on failure leave `_cached_state` empty rather than half-loaded. Closes SAV-03.
6. **Make `itemInstances` a derived index with load-time reconciliation** — `local_save.gd:562-600` builds it from live inventory/storage; `_apply_save_data` reconciles missing `affixes` from it. Closes SAV-04.
7. **Cloud conflict backup by character** — `local_save.gd:666-669`, and the two call sites at `479` and `498`; return the artefact path in the `push_to_cloud` / `sync_from_cloud` results. Closes SAV-05.
8. **Autosave coalescing** — `local_save.gd`: add `AUTOSAVE_MIN_INTERVAL`, `request_autosave()`, and the `flush` parameter on `set_active_run` / `set_waves_active_run`; convert the high-frequency callers (`character_service.gd` gold/flags, `inventory_service.gd`, `run_flow.gd` transitions) to `request_autosave`. Closes SAV-07.
9. **Identity and coupling cleanup** — `_resolve_account_id()`, collision-checked `_generate_character_id()`, drop `lastHubMessage` from `_default_character()`. Closes SAV-09, SAV-10, SAV-12.
10. **Retire the dead `recipes` array or wire it** — decide in favour of wiring: `BlacksmithService` records unlocked recipe ids into `_cached_state.recipes` and `RecipeCatalog.get_upgrade_recipes` filters by them, so `content/recipes/unlock_guard_spear.json` and `unlock_hunter_bow.json` become reachable. Closes SAV-11.
11. **Ship the schema v2** — new `content/schemas/character-state.v2.json`, `validate.mjs` mapping, new fixture. Closes SAV-08.

## Data and schema changes

### `content/schemas/character-state.v2.json` (new)
Replaces the v1 document as the descriptor for a real runtime save. Key differences from `character-state.v1.json`:

| Change | Reason |
|--------|--------|
| `schemaVersion` becomes `{"type": "integer", "minimum": 1, "maximum": 5}` instead of `const: 1` | Runtime writes `SaveMigrator.CURRENT_VERSION` |
| `additionalProperties: true` | Forward compatibility for a local file; unknown keys must not fail a load |
| Add `talentPointsSpent` (int >= 0), `quests` (object of string), `wavesActiveRun` (object), `meta` (object), `cloudUpdatedAt` (string) | All written by `_build_save_payload` |
| `meta` gets named sub-objects `accessibility`, `leaderboard`, `hub_tutorial`, `achievements` | Documents the four writers |
| `currencies` allows `coins` alongside `gold` | `local_save.gd:589` writes both |
| `characterProfile` adds `appearanceTheme` (int) and `appearance` (object) | `local_save.gd:571-573` |
| `characterProfile` drops `lastHubMessage` | Removed by step 9 |
| `rolledItemInstance.rarity` enum gains `aumbral` | `rarity_registry.gd:6-8` includes it; v1 stops at `mythic` |
| `rolledItemInstance.instanceId` drops `format: uuid` | `grid_inventory.gd:357` produces `"<itemId>_<seed>"` |
| `rolledItemInstance` allows `itemId` as an alias of `itemDefId` | The client writes `itemId` on slots |

`content/schemas/inventory.v1.json` is superseded by `content/schemas/inventory.v2.json`, because v1 declares `equipped` as `{"weapon": string|null}` with `additionalProperties: false` while the runtime writes all nine `Equipment.SLOT_ORDER` keys with Dictionary values, and v1's slot object forbids `rarity`, `affixes`, `rollSeed`, `upgradeLevel`, `durability`, `keyId`, `lockId`, and `keyLabel`. v2 declares the nine slot names explicitly and permits the full slot key set.

`scripts/validate-content/validate.mjs` `resolveSchemaForFile` gains mappings for `fixtures/character_state_sample.v2.json` → `character-state.v2.json` and `fixtures/inventory_sample.v2.json` → `inventory.v2.json`, and `loadSchema`'s nested-ref preload switches to `inventory.v2.json`. New fixtures `content/fixtures/character_state_sample.v2.json` and `content/fixtures/inventory_sample.v2.json` are generated from a real save containing one affixed weapon, one dungeon key, one upgraded item, and a populated `meta`.

### `save_migrator.gd` version bump
Steps 6 and 9 change the payload, so bump `CURRENT_VERSION` from `4` to `5` and add `_migrate_v4_to_v5`:

1. Set `schemaVersion = 5`.
2. Ensure `itemInstances` is a Dictionary; replace any non-Dictionary with `{}`.
3. Drop `character.lastHubMessage`.
4. Default `currencies.coins` to `currencies.gold` when absent.
5. Replace a nil-UUID `accountId` with `""` so `_resolve_account_id()` regenerates it.
6. Ensure `inventory.equipped` is a Dictionary with all nine `Equipment.SLOT_ORDER` keys, filling missing ones with `{}`, and convert a legacy `equipped.weapon` String into `{"itemId": <string>, "quantity": 1}` (the same coercion `grid_inventory.gd:373-376` performs at load).
7. Ensure `activeRun.schemaVersion = 5` when `activeRun` is present.

If [`run-flow.md`](run-flow.md) and [`world-state.md`](world-state.md) land in the same release, their v4→v5 steps merge into this one function; the version number advances once.

**Failure and recovery behaviour.** A v5 save that fails `SaveValidator.validate` is quarantined to `<path>.corrupt_<timestamp>.json`, and `_recover_from_corruption` restores the newest passing backup for that character. If all five backups fail, the character slot is reported broken through `save_failed(reason)` — the reason string names the failing fields — and the roster entry is retained so the player can delete it deliberately instead of finding a silently missing slot. `_reset_to_defaults()` is reached only for the legacy no-character path. A missing content file behind a save (an `itemId` no longer in `ItemCatalog`) is not a save error: `GridInventory.can_place` already rejects unknown definitions, so the slot is dropped on repack and one `push_warning` names the id.

## Acceptance criteria
- [x] Saving as a roster character creates `user://backups/<characterId>_0.json`, and five consecutive saves produce indices 0-4 with 0 the newest. (SAV-01)
- [x] Truncating an active character file to `{` and booting `CONTINUE_CHARACTER` quarantines the file, restores backup 0, and emits `save_failed` then `backup_restored(0)`. (SAV-02)
- [x] A v1 character file on disk is migrated before any `LocalSave` getter returns data, verified by `get_level()` reading the migrated value at `_ready`. (SAV-03)
- [x] Saving with one affixed weapon equipped and one in the grid produces two `itemInstances` entries whose `affixes` match the slots; deleting `affixes` from a slot and reloading recovers them from `itemInstances`. (SAV-04)
- [x] A cloud conflict as a roster character writes `user://backups/<characterId>.conflict_<timestamp>.json` and returns its path in the result. (SAV-05)
- [x] `SaveValidator.validate` rejects a save missing `character`, one with `inventory.equipped` as an Array, and one with a negative `character.level`, naming each failing field. (SAV-06)
- [x] Ten `request_autosave()` calls within two seconds produce exactly one file write. (SAV-07)
- [x] `npm run validate` in `scripts/validate-content` passes for `content/fixtures/character_state_sample.v2.json` generated from a real save. (SAV-08)
- [x] A save created with no API session has a non-nil `accountId` that is stable across restarts. (SAV-09)
- [x] Creating two characters in a loop with no frame gap produces two distinct files. (SAV-10)
- [x] Unlocking `guard_spear` at the blacksmith adds its recipe id to `recipes` and the id survives a save/load cycle. (SAV-11)
- [x] No save written by the new build contains `character.lastHubMessage`. (SAV-12)

## Validation
Extend `apps/game/client/scripts/validation/suites/save_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `save.backup.per_character_rotation` | Five writes as a roster character produce five indexed backups under that character's prefix |
| `save.backup.atomic_write_survives_bad_payload` | A payload that fails `SaveValidator` leaves the previous file byte-identical and writes no `.tmp` residue |
| `save.load.character_corruption_recovers` | Corrupt character file → quarantine artefact exists, backup 0 applied, `save_failed` and `backup_restored` both emitted |
| `save.load.warm_load_is_migrated` | v1 file on disk; after `_ready` the cached `schemaVersion` is `SaveMigrator.CURRENT_VERSION` |
| `save.validate.reports_named_problems` | `SaveValidator.validate` on five malformed documents returns the expected problem strings |
| `save.instances.round_trip` | Affixed grid slot + affixed equipped slot → two `itemInstances`; slot-level `affixes` deletion is repaired on load |
| `save.autosave.coalesces` | Ten `request_autosave()` calls inside `AUTOSAVE_MIN_INTERVAL` cause one write, measured by file modification time |
| `save.cloud.conflict_backup_named` | Conflict path produces a character-named artefact and returns its path |
| `save.migrate.v4_to_v5_equipped_legacy_string` | v4 save with `equipped.weapon` as a String migrates to the instance Dictionary shape |
| `save.migrate.v4_to_v5_account_id_reset` | Nil-UUID `accountId` becomes `""` and is regenerated on the next write |
| `save.identity.character_id_unique` | Two immediate `_generate_character_id()` calls with a seeded roster do not collide |

Extend `apps/game/client/scripts/validation/suites/content_suite.gd` with `content.schema.character_state_v2_matches_runtime`, which builds a payload through `LocalSave._build_save_payload()` and asserts every top-level key it produces is described by `content/schemas/character-state.v2.json`. This is the assertion that would have caught SAV-08.

Manual checklist (genuinely not automatable): kill the process with the OS task manager during a floor transition, relaunch, and confirm the run continues from the last flushed snapshot with no `.tmp` file left behind.

## Related
- Existing state: [`../existing_codebase/local-save.md`](../existing_codebase/local-save.md)
- [`save-migrator.md`](save-migrator.md), [`character-service.md`](character-service.md), [`inventory-service.md`](inventory-service.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`content-catalog.md`](content-catalog.md), [`run-flow.md`](run-flow.md)
- Owned elsewhere: [`backend-api.md`](backend-api.md), [`ui/continue_menu.md`](ui/continue_menu.md)
