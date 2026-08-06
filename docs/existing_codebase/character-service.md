# Character service

`CharacterService` is the autoload holding per-character currency, class id, appearance, registered flags, and split quest state/progress maps. It does not own level or XP â€” those live in `ProgressionService` and are proxied. Currency, flag, and quest mutations request deferred autosave; `spend_gold` requests immediate autosave.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/save/character_service.gd` | The autoload |
| `apps/game/client/scripts/save/character_flags.gd` | Flag registry, coercion, and JSON-safety |
| `apps/game/client/scripts/save/local_save.gd` | Calls `to_save_dict()` in `_build_save_payload`; loads via `from_save_dict` |
| `apps/game/client/scripts/save/character_appearance.gd` | Writes `appearance_theme` / `appearance_profile` directly (`character_appearance.gd:76-77`) |
| `apps/game/client/scripts/progression/progression_service.gd` | Real owner of `level`; source of the `level_changed` re-emit |
| `apps/game/client/scripts/dungeon/dungeon_tier_service.gd` | Stores `dungeon_max_tier` in `flags` |
| `apps/game/client/scripts/dungeon/dungeon_catalog.gd` | `clearFlag` per dungeon row; read by `RunFlow._mark_dungeon_cleared` |
| `apps/game/client/scripts/quests/quest_service.gd` | Sole writer of quest state/progress in normal play |

## How it works

### State
| Member | Type | Default | Line |
|--------|------|---------|------|
| `gold` | int | `DEFAULT_GOLD` = 100 | 11, 20 |
| `class_id` | String | `""` | 21 |
| `appearance_theme` | int | 0 | 22 |
| `appearance_profile` | Dictionary | `CharacterAppearance.default_profile()` | 23 |
| `flags` | Dictionary | `{}` | 24 |
| `quest_states` | Dictionary | `{}` | 25 |
| `quest_progress` | Dictionary | `{}` | 26 |
| `level` | int (read-only property) | delegates to `get_level()` | 30-32 |

`get_coins()` returns `gold`. `add_coins`, `spend_coins`, and `can_afford_coins` forward to the gold API and emit both `gold_changed` and `coins_changed`.

`level` is a getter over `ProgressionService.level` (`character_service.gd:40-43`), falling back to `DEFAULT_LEVEL` = 1 when the autoload is missing. `_ready` connects `ProgressionService.progression_changed` to re-emit `level_changed` (`character_service.gd:36-37`).

### Currency rules
- `add_gold(amount)` returns early when `amount <= 0` (lines 99-101) and requests `LocalSave.SavePriority.DEFERRED`.
- `spend_gold(amount)` returns `false` for a negative amount or insufficient funds (line 109) and requests `LocalSave.SavePriority.IMMEDIATE`.
- `can_afford(amount)` is `gold >= amount` (line 119).

### Flags
`CharacterFlags.REGISTRY` (`character_flags.gd:8-26`) declares every known flag id with `Kind` (BOOL, INT, STRING, DICT) and a typed default. `set_flag` coerces through `CharacterFlags.coerce`, records unregistered ids in `_unregistered_flag_ids`, and requests deferred autosave. `get_flag(id)` returns the stored value, an explicit default when provided, or the registry default when absent. `has_flag` / `is_flag_truthy` use type-aware truthiness.

Registered flag ids and writers:

| Flag id | Written at | Read at |
|---------|-----------|---------|
| `deaths` (int) | `run_flow.gd` | `dialogue_conditions.gd:53` (`minDeaths`) |
| `runs_started` (int) | `run_flow.gd` | `dialogue_conditions.gd:50` (`minRuns`) |
| `recoverable_xp_shard` (dict) | `run_flow.gd` | `run_flow.gd` |
| `story_completed` (bool) | `castle_run.gd:478` | `results_screen.gd:47` |
| `dungeon_max_tier` (int) | `dungeon_tier_service.gd:33` | `dungeon_tier_service.gd:17` |
| `heard_castle_lore` (bool) | `content/dialogue/mira_greeting.json:26` | same dialogue |
| `met_dungeon_npc` (bool) | `content/dialogue/dungeon_npc_stranded.json:8` | No reader found |
| `theme_*_cleared` (bool, 10 ids) | `run_flow.gd:_mark_dungeon_cleared` | `loadout_ui.gd:80-87` (two weapon unlocks) |

### Quests
Quest state and progress are separate maps persisted as `save["quests"] = {"states": {...}, "progress": {...}}`.

- `quest_states[quest_id]` -> state String (`inactive`, `active`, `completed`, `turned_in`); unknown states are rejected with `push_warning`.
- `quest_progress[quest_id]` -> Dictionary; `set_quest_progress` deep-copies with `duplicate(true)`.
- `active_quest_ids()` returns ids whose state is `active`.
- `clear_quest(quest_id)` removes both maps entries.

`from_save_dict` and `SaveMigrator._normalize_quests` split legacy flat keys (`id` + `id + "_progress"`) into the two maps.

### Serialisation
`to_save_dict()` (`character_service.gd:169-181`) is the only mapping from service state to save keys. `LocalSave._build_save_payload` (`local_save.gd:676-683`) splices `currencies.gold`, `flags`, `quests`, and `character.classId` / `character.appearance*` from its result.

`from_save_dict(data)` (`character_service.gd:184-199`) folds legacy `coins` into `gold` via `maxi`, coerces flags through `CharacterFlags.coerce_all`, loads split or legacy quest payloads, and emits `gold_changed`, `coins_changed`, `level_changed`, `flags_changed`, and `quests_changed`.

`reset_to_defaults()` (`character_service.gd:202-216`) restores 100 gold, empty class id, theme 0, the default appearance profile, and clears flags and both quest maps; it emits all five signals. `local_save.gd:_reset_to_defaults` seeds `currencies.gold` to `CharacterService.DEFAULT_GOLD` (`local_save.gd:717`).

### Autosave coupling
Deferred autosave: `set_flag`, `add_gold`, `set_quest_state`, `set_quest_progress`, `clear_quest`, `set_class_id`. Immediate autosave: `spend_gold` (merchant and blacksmith purchases). Kill coin rewards accumulate in memory and flush on the next deferred interval or floor transition.

## Contracts
**Signals emitted:** `gold_changed(int)`, `coins_changed(int)`, `level_changed(int)`, `flags_changed`, `quests_changed`.

**Signal consumers:** `gold_changed` -> `merchant_ui.gd:32`. `coins_changed` -> `blacksmith_ui.gd:33`. `quests_changed` -> `quest_board_ui.gd:26`. `flags_changed` -> none outside quest board load path yet.

**Signals consumed:** `ProgressionService.progression_changed` (`character_service.gd:37`).

**Autoload dependencies:** `ProgressionService`, `LocalSave`, `CharacterAppearance`, `CharacterFlags`, `ClassCatalog` indirectly through consumers.

**Save keys written through it:** `currencies.gold`, `flags`, `quests` (`states` + `progress`), `character.classId`, `character.appearanceTheme`, `character.appearance`.

**Callers of `spend_gold` / `spend_coins`:** `merchant_service.gd:52`, `blacksmith_service.gd:68`, `blacksmith_service.gd:110`, `blacksmith_service.gd:136`.
**Callers of `add_gold` / `add_coins`:** `merchant_service.gd:71` (sell), `quest_service.gd:140` (quest reward), `dialogue_runner.gd:129` (dialogue reward), `castle_enemy_base.gd:339` (kill reward).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Gold add / spend / affordability | IMPLEMENTED | `character_service.gd:99-119`; deferred vs immediate autosave |
| Flag registry and coercion | IMPLEMENTED | `character_flags.gd`; `character_service.gd:50-75` |
| Quest state / progress split | IMPLEMENTED | `character_service.gd:122-158`; migration at `save_migrator.gd:_normalize_quests` |
| Level proxy to `ProgressionService` | IMPLEMENTED | `character_service.gd:30-43` |
| Appearance persistence | IMPLEMENTED | `character_service.gd:187-192`, `local_save.gd:676-683` |
| `to_save_dict()` single mapping | IMPLEMENTED | `character_service.gd:169-181`; consumed by `local_save.gd:676-683` |
| `coins` alias | IMPLEMENTED | `get_coins()` returns `gold`; no separate persisted field |
| Dungeon clear weapon unlocks | IMPLEMENTED | `run_flow.gd:_mark_dungeon_cleared`; `dungeon_catalog.gd` `clearFlag` rows |
| Flag / quest signals on load / reset | IMPLEMENTED | `character_service.gd:196-199`, `213-215` |
| `met_dungeon_npc` | PARTIAL | Written by dialogue; no reader |
| Content flag validation | IMPLEMENTED | `content_suite.gd` registry checks |

## Related
- Improvement plan: [`../actual_improvements/character-service.md`](../actual_improvements/character-service.md) - **FINISHED**
- [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`character-appearance.md`](character-appearance.md), [`progression-service.md`](progression-service.md), [`dialogue-quests.md`](dialogue-quests.md), [`npc-hub-services.md`](npc-hub-services.md), [`world-state.md`](world-state.md)
