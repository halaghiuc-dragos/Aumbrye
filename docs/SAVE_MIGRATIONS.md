# Save migrations

Version history for `SaveMigrator` (`apps/game/client/scripts/save/save_migrator.gd`).
`CURRENT_VERSION` is **12**. Each row matches one entry in `SaveMigrator.STEPS`.

| From | To | Summary | Keys added | Keys removed |
|------|-----|---------|------------|--------------|
| 1 | 2 | activeRun floor fields | `activeRun.currentFloor`, `activeRun.maxFloors`, `activeRun.floorDefinitions` | — |
| 2 | 3 | activeRun.runMode; drop floorDefinitions | `activeRun.runMode` | `activeRun.floorDefinitions` |
| 3 | 4 | lastCheckpoint; snapshot.worldFlags | `activeRun.lastCheckpoint`, `activeRun.snapshot.worldFlags`, `activeRun.schemaVersion` | — |
| 4 | 5 | typed sections; equipped instances; accountId reset | `character.appearance`, `character.appearanceTheme`, `currencies.coins`, `inventory.equipped.<slot>`, `inventory.slots[*].instanceId`, `activeRun.clearedFloors`, `activeRun.schemaVersion` | `character.lastHubMessage`, `activeRun.playerDead`, `activeRun.floorDefinitions` |
| 5 | 6 | `mythic_loot` achievement renamed to `aumbral_loot` | `meta.achievements.aumbral_loot` | `meta.achievements.mythic_loot` |
| 6 | 7 | dungeon unlock count and per-dungeon difficulty tiers | `flags.dungeon_unlocked_count`, `flags.dungeon_tier_<id>` | — |
| 7 | 8 | accessibility camera defaults | `meta.accessibility.cameraMouseSensitivity`, `.cameraStickSensitivity`, `.cameraInvertY`, `.cameraFov`, `.cameraStickCurve`, `.cameraStickDeadzone` | — |
| 8 | 9 | display block; `ui_scale` moved out of accessibility | `meta.display.window_mode`, `.window_size`, `.monitor_index`, `.vsync_mode`, `.max_fps`, `.ui_scale`, `.hud_safe_area` | — |
| 9 | 10 | quick slots keyed by instance id instead of slot index | `inventory.quickSlotInstances` (4 entries) | `inventory.quickSlots` |
| 10 | 11 | `currencies.coins` collapsed into `currencies.gold` | `currencies.gold` | `currencies.coins` |
| 11 | 12 | account scope block; talent ids revalidated against the grown tree | `account.storage`, `account.flags`, `account.endlessBestFloor`, `account.descentTokens` | — |

Unless noted, a failed step quarantines the file and retains a pre-migration artefact at
`user://backups/<characterId>.premigrate_v<n>_<timestamp>.json`. The v4→v5 step is the exception: a
`playerDead` flag with a checkpoint restores the snapshot, and without one drops `activeRun` only,
preserving every other section.

## SY-06: fields the MVP depth plan introduced, and why none needed v13

`docs/MVP_DEPTH_PLAN.md`'s SY-06 asked for a running list of the plan's new persisted fields, bundled
into one migration step per phase rather than one per feature. Checked against the actual
implementation, none of the plan's additions ended up needing a new schema version:

- **RG-02 quiver charges** — `PlayerArrows.current_arrows`/`max_arrows` are never written to the save
  at all, matching `PlayerHeal.current_charges` (the pattern it mirrors): both are pure run-session
  state that resets to full on load, not persisted state. No new key.
- **IV-02 set bonuses** — computed at runtime from each equipped item's own `setId` (a content field,
  `content/items/equipment/*.json`) and `content/items/sets.json`. Nothing new to save; the existing
  `inventory.equipped.<slot>` instance already carries everything needed.
- **IV-03 keystone talents** — reuses the existing `talents.<nodeId>` rank storage the v5 step already
  normalizes; a keystone is just a talent node whose rank is 0 or 1, not a new shape.
- **RM-09 secrets-found counter** and **AD-07 tutorial-seen flags** — both go through
  `CharacterService.set_flag()`/`WorldState.set_flag()` into the existing generic `flags` dictionary,
  which the v5 step already declares schema-open ("bool / int / float / String values only", no fixed
  key list). An old save simply has no entry for a new flag key until it is first set, and every
  reader already calls `get_flag(key, default)` with a safe default — no backfill required.

`SaveMigrator.CURRENT_VERSION` is still correctly **12** as of this note. The next genuinely
structural addition (a new required section, a renamed/removed key, or a value that needs
transformation rather than a default) is what should bump it to 13 — not these.

## v12 guarantees

`account` is a copy of the parts of a save that belong to the player rather than to one
warden: the stash (`account.storage`) and the flags that record what the world itself has
given up — dungeon clears (`theme_*_cleared`), lore read (`lore_*_read`), bestiary counters,
and the dungeon unlock count. `LocalSave` adopts that block into `user://account.json` the
first time it sees it and hands the shared copy back to every character afterwards, so a
second warden inherits the stash and the unlocked world. The character document keeps its own
copy of both, so the step is lossless and idempotent: a save that already carries `account`
passes through with only its talent ids revalidated against the grown tree.

## v10 guarantees

`inventory.quickSlotInstances` is a four-element array of item instance ids (empty string for an unused
slot), derived from the legacy `inventory.quickSlots` index array by resolving each index against
`inventory.slots[*].instanceId`. Indices outside the slot array are dropped. The migration is idempotent:
a save that already has `quickSlotInstances` passes through untouched
(`save_migrator.gd:739-762`).

## v5 guarantees

After migration to version 5 these sections are normalized:

- **character** — `name`, `classId`, `level`, `xp`, `appearanceTheme`, `appearance`; `lastHubMessage` removed
- **currencies** — `gold` and `coins` as ints `>= 0`
- **inventory** / **storage** — `schemaVersion: 1`, grid dimensions, slot instances with `itemId`,
  `quantity`, `instanceId`, normalized `rarity` and `affixes`; `equipped` has all nine
  `Equipment.SLOT_ORDER` keys
- **talents** — int ranks `>= 0`; `talentPointsSpent` clamped to the reachable total
- **flags** — bool / int / float / String values only
- **quests** — string states; `<id>_progress` as dictionaries
- **itemInstances** — dictionary of dictionaries
- **meta** — dictionary; known sub-keys are dictionaries when present
- **activeRun** — `schemaVersion: 5`, `clearedFloors` as int array, namespaced `worldFlags`, no `playerDead`

## Newer builds

A save whose `schemaVersion` exceeds `CURRENT_VERSION` is refused **without** quarantine.
`SaveMigrator.classify()` returns the newer-build result, `LocalSave` emits
`save_failed("save_from_newer_build")` (`local_save.gd:816`, `:825`) and the file is left untouched on disk.

A save with no `schemaVersion` at all is classified `RESULT_UNKNOWN` and routed through
`LocalSave._recover_from_corruption()`.

## Maintenance note

`STEPS` in `save_migrator.gd` is the single source of truth for the migration chain. A parallel
`STEPS_DOC` table used to duplicate it for documentation; nothing read it, it drifted out of sync,
and it has been removed. Document steps here instead.

## Related

- [`ARCHITECTURE.md`](ARCHITECTURE.md) — content and save pipeline in context
- [`remaining_points.md`](remaining_points.md) — open items across the stacks
