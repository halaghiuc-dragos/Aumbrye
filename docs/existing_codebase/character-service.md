# Character service

`CharacterService` is the autoload holding per-character currency, class id, appearance, and the two general-purpose dictionaries `flags` and `quests`. It is 179 lines and does not own level or XP — those live in `ProgressionService` and are proxied. Every mutator calls `LocalSave.autosave()`, which makes this the busiest write trigger in the game.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/save/character_service.gd` | The autoload |
| `apps/game/client/scripts/save/local_save.gd` | Serialises it into `currencies`, `flags`, `quests`, and `character.classId` / `character.appearance*` |
| `apps/game/client/scripts/save/character_appearance.gd` | Writes `appearance_theme` / `appearance_profile` directly (`character_appearance.gd:76-77`) |
| `apps/game/client/scripts/progression/progression_service.gd` | Real owner of `level`; source of the `level_changed` re-emit |
| `apps/game/client/scripts/dungeon/dungeon_tier_service.gd` | Stores `dungeon_max_tier` in `flags` |
| `apps/game/client/scripts/quests/quest_service.gd` | Sole writer of `quests` in normal play |

## How it works

### State
| Member | Type | Default | Line |
|--------|------|---------|------|
| `gold` | int | `DEFAULT_GOLD` = 100 | 11, 14 |
| `coins` | int | 100 | 15 |
| `class_id` | String | `""` | 16 |
| `appearance_theme` | int | 0 | 17 |
| `appearance_profile` | Dictionary | `CharacterAppearance.default_profile()` | 18 |
| `flags` | Dictionary | `{}` | 19 |
| `quests` | Dictionary | `{}` | 20 |
| `level` | int (read-only property) | delegates to `get_level()` | 23-25 |

`gold` and `coins` are the same number by construction: `add_gold` and `spend_gold` both assign `coins = gold` (`character_service.gd:78`, `88`), and `add_coins` / `spend_coins` / `can_afford_coins` are thin forwards (lines 62-71). Both are persisted.

`level` is a getter over `ProgressionService.level` (`character_service.gd:34-37`), falling back to `DEFAULT_LEVEL` = 1 when the autoload is missing. `set_level(_new_level)` (lines 99-101) ignores its argument entirely and only re-emits — it exists for legacy callers. `_ready` connects `ProgressionService.progression_changed` to re-emit `level_changed` (lines 30-31) and sets `process_mode = PROCESS_MODE_ALWAYS`.

### Currency rules
- `add_gold(amount)` returns early when `amount <= 0` (lines 75-76), so a zero-value sale is a silent no-op.
- `spend_gold(amount)` returns `false` for a negative amount or insufficient funds (line 85) and only then debits; it is the only guard against overdraft.
- `can_afford(amount)` is `gold >= amount` (line 96).

### Flags
`flags` is an untyped `String -> Variant` map with no registry, no namespace, and no schema. `get_flag(id, default = false)`, `set_flag(id, value = true)`, `has_flag(id)` = `bool(flags.get(id, false))`.

Every flag id written anywhere in the codebase:

| Flag id | Written at | Read at |
|---------|-----------|---------|
| `deaths` (int counter) | `run_flow.gd:412`, `run_flow.gd:826` | `dialogue_conditions.gd:53` (`minDeaths`) |
| `runs_started` (int counter) | `run_flow.gd:886` | `dialogue_conditions.gd:50` (`minRuns`) |
| `recoverable_xp_shard` (Dictionary) | `run_flow.gd:794`, cleared at `run_flow.gd:812` | `run_flow.gd:805` |
| `story_completed` (bool) | `castle_run.gd:478` | `results_screen.gd:47` |
| `dungeon_max_tier` (int) | `dungeon_tier_service.gd:33` | `dungeon_tier_service.gd:17` |
| `heard_castle_lore` (bool) | `content/dialogue/mira_greeting.json:26` via `dialogue_runner.gd:127` | same dialogue, lines 13 and 18 |
| `met_dungeon_npc` (bool) | `content/dialogue/dungeon_npc_stranded.json:8` | No reader found — searched `apps/` and `content/` |
| `theme_forgotten_castle_cleared` | No writer found — searched `apps/` and `content/` | `loadout_ui.gd:80` (unlocks `guard_spear`) |
| `theme_crystal_caverns_cleared` | No writer found | `loadout_ui.gd:82` (unlocks `hunter_bow`) |
| arbitrary ids | `dialogue_runner.gd:127` (`set_flag` action, id taken from content) | `dialogue_conditions.gd:33` |

Note the type mixing: `deaths` and `dungeon_max_tier` hold ints, `recoverable_xp_shard` holds a Dictionary, the rest hold bools, all in one bag. `has_flag` therefore means different things per flag — for `deaths` it is "has died at least once", for `recoverable_xp_shard` it is "a shard record is non-empty" — and there is nothing in the API that tells a caller which.

### Quests
`quests` is a single Dictionary holding two different kinds of entry:
- `quests[quest_id]` -> a state String; `get_quest_state` returns `"inactive"` when absent (line 105).
- `quests[quest_id + "_progress"]` -> a Dictionary; `get_quest_progress` returns `{}` when the value is not a Dictionary (lines 114-116).

`set_quest_progress` deep-ish copies with `progress.duplicate()` (line 120, shallow — nested dictionaries are shared).

### Serialisation
`to_save_dict()` (lines 134-143) emits `gold`, `coins`, `classId`, `appearanceTheme`, `appearance`, `flags`, `quests`. **`LocalSave` does not call it.** `LocalSave._build_save_payload` reads the fields directly instead: `currencies` at `local_save.gd:589`, `flags` at `590`, `quests` at `591`, `character.classId` at `570`, `character.appearanceTheme` / `character.appearance` at `572-573`.

`from_save_dict(data)` (lines 146-165) is called by `local_save.gd:542-550` with a hand-built dictionary. It prefers `coins` over `gold` (line 147), sanitises `appearance` through `CharacterAppearance.sanitize`, re-reads `theme` back out of the sanitised profile (line 154), shallow-copies `flags` and `quests` when they are Dictionaries, and emits `gold_changed`, `coins_changed`, `level_changed` — but not `flags_changed` or `quests_changed`.

`reset_to_defaults()` (lines 168-178) restores 100 gold, empty class id, theme 0, the default appearance profile, and clears both dictionaries; it emits the same three signals and again omits `flags_changed` / `quests_changed`. It is called from `local_save.gd:644` (`_reset_to_defaults`), `progression_suite.gd:129`/`140`, and `m5_suite.gd:334`/`375`/`421`/`452`.

### Autosave coupling
Six mutators call `LocalSave.autosave()`: `set_flag` (51), `add_gold` (81), `spend_gold` (91), `set_quest_state` (111), `set_quest_progress` (122), `set_class_id` (131). Because `castle_enemy_base.gd:336-339` awards coins on every enemy death, one full save serialisation and write happens per kill.

## Contracts
**Signals emitted:** `gold_changed(int)`, `coins_changed(int)`, `level_changed(int)`, `flags_changed`, `quests_changed`.

**Signal consumers:** `gold_changed` -> `merchant_ui.gd:32`. `coins_changed` -> `blacksmith_ui.gd:33`. `level_changed`, `flags_changed`, `quests_changed` -> none outside this file.

**Signals consumed:** `ProgressionService.progression_changed` (`character_service.gd:31`).

**Autoload dependencies:** `ProgressionService`, `LocalSave`, `CharacterAppearance` (static class), `ClassCatalog` indirectly through consumers.

**Save keys written through it:** `currencies.gold`, `currencies.coins`, `flags`, `quests`, `character.classId`, `character.appearanceTheme`, `character.appearance`.

**Callers of `spend_gold` / `spend_coins`:** `merchant_service.gd:52`, `blacksmith_service.gd:68`, `blacksmith_service.gd:110`, `blacksmith_service.gd:136`.
**Callers of `add_gold` / `add_coins`:** `merchant_service.gd:71` (sell), `quest_service.gd:130` (quest reward), `dialogue_runner.gd:129` (dialogue reward), `castle_enemy_base.gd:339` (kill reward).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Gold add / spend / affordability | IMPLEMENTED | `character_service.gd:74-96`; consumed by merchant and blacksmith |
| Flag get / set / has | IMPLEMENTED | `character_service.gd:44-55` |
| Quest state and progress storage | IMPLEMENTED | `character_service.gd:104-122` |
| Level proxy to `ProgressionService` | IMPLEMENTED | `character_service.gd:23-37` |
| Appearance persistence | IMPLEMENTED | `character_service.gd:150-154`, `local_save.gd:572-573` |
| `to_save_dict()` | FAKE | Defined at `character_service.gd:134-143` and never called; `local_save.gd:589-591` duplicates the logic and omits nothing but is a second source of truth |
| `set_level(int)` | STUB | `character_service.gd:99-101` discards its argument |
| `coins` as a distinct currency | FAKE | Always assigned `= gold` (`character_service.gd:78`, `88`) yet persisted as a separate key (`local_save.gd:589`) |
| `flags_changed` / `quests_changed` signals | FAKE | Emitted at lines 50, 110, 121; zero consumers anywhere in `apps/` |
| `level_changed` signal | FAKE | Emitted at 41, 101, 165, 178; zero consumers |
| Flag emission after load / reset | BROKEN | `from_save_dict` (163-165) and `reset_to_defaults` (176-178) mutate `flags` and `quests` without emitting their change signals |
| Flag id registry or namespace | ABSENT | No constant table anywhere; ids are bare strings written at `run_flow.gd:412`, `castle_run.gd:478`, `dungeon_tier_service.gd:33`, and from arbitrary content at `dialogue_runner.gd:127` |
| `theme_forgotten_castle_cleared` / `theme_crystal_caverns_cleared` unlocks | BROKEN | Read at `loadout_ui.gd:80-82` to unlock the `guard_spear` and `hunter_bow` weapons — despite the `theme_` prefix these gate weapons, not appearance themes; no writer exists, so only the `level >= 5` / `level >= 8` branch can ever fire |
| `met_dungeon_npc` | PARTIAL | Written by `content/dialogue/dungeon_npc_stranded.json:8`; no reader |
| Quest state / progress key namespace | BROKEN | Both live in one Dictionary (`character_service.gd:109`, `120`), so a quest id ending in `_progress` overwrites another quest's progress, and any iteration over `quests` sees progress rows as quest ids |
| Autosave per mutation | PARTIAL | Six call sites (51, 81, 91, 111, 122, 131); `castle_enemy_base.gd:339` makes this one full write per enemy killed |
| New-game starting gold | PARTIAL | `local_save.gd:634` seeds `currencies.gold = 0` while `reset_to_defaults` sets 100; the service value wins because `local_save.gd:589` overwrites `currencies` on every write |
| Flag / quest value validation | ABSENT | `set_flag` accepts any Variant; nothing rejects a Node, Object, or nested Array that JSON cannot round-trip |

## Related
- Improvement plan: [`../actual_improvements/character-service.md`](../actual_improvements/character-service.md)
- [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`character-appearance.md`](character-appearance.md), [`progression-service.md`](progression-service.md), [`dialogue-quests.md`](dialogue-quests.md), [`npc-hub-services.md`](npc-hub-services.md), [`world-state.md`](world-state.md)
