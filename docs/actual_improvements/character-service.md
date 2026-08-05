# Character service — improvement plan

## Current state
`CharacterService` (`apps/game/client/scripts/save/character_service.gd`, 179 lines) holds gold, class id, appearance, and two untyped Dictionaries named `flags` and `quests`. See [`../existing_codebase/character-service.md`](../existing_codebase/character-service.md). Gold works and is consumed by the merchant and blacksmith. Everything around it is loose: `coins` is a duplicate of `gold` that is persisted separately, `to_save_dict()` is dead code while `LocalSave` reimplements the same mapping inline, three of the five signals have no consumers, `flags` and `quests` share no registry and no value validation, quest state and quest progress live in the same Dictionary under colliding key names, two theme-unlock flags are read but never written, and six mutators each trigger a full `LocalSave.autosave()` — including the per-enemy coin reward, so a normal floor produces dozens of full save writes.

## Gaps
| ID | Sev | Gap | Evidence |
|----|-----|-----|----------|
| CHS-01 | P0 | Quest state and quest progress share one Dictionary keyed `id` and `id + "_progress"`, so a quest id ending in `_progress` silently overwrites another quest's progress and any iteration over `quests` treats progress rows as quest ids | `character_service.gd:109`, `character_service.gd:115`, `character_service.gd:120` |
| CHS-02 | P0 | `loadout_ui.gd` gates the `guard_spear` and `hunter_bow` weapons on `theme_forgotten_castle_cleared` and `theme_crystal_caverns_cleared`, and nothing in `apps/` or `content/` ever sets them; the flag half of both unlocks is dead, leaving only the level gate | `loadout_ui.gd:80-82`; no `set_flag` for either id in `apps/` or `content/` |
| CHS-03 | P0 | `flags` and `quests` are mutated by `from_save_dict` and `reset_to_defaults` without emitting `flags_changed` / `quests_changed`, so any future reactive UI is wrong immediately after a load or a character switch | `character_service.gd:155-165`, `character_service.gd:174-178` |
| CHS-04 | P1 | Every enemy kill awards coins, and `add_gold` autosaves, so clearing a floor writes the full save document once per enemy | `castle_enemy_base.gd:336-339` -> `character_service.gd:81` |
| CHS-05 | P1 | `to_save_dict()` is never called; `local_save.gd:589-591` and `569-573` reimplement the mapping, so the two can diverge without a compile error | `character_service.gd:134-143` vs `local_save.gd:569-591` |
| CHS-06 | P1 | `flags` accepts any Variant with no validation; a value JSON cannot serialise reaches `_write_save` and produces a corrupt document | `character_service.gd:48-51`, no type check before `local_save.gd:590` |
| CHS-07 | P1 | No flag id registry; ids are bare literals across `run_flow.gd`, `castle_run.gd`, `dungeon_tier_service.gd`, and arbitrary content strings from `dialogue_runner.gd`, so a typo is undetectable | `run_flow.gd:412`, `castle_run.gd:478`, `dungeon_tier_service.gd:33`, `dialogue_runner.gd:127` |
| CHS-08 | P2 | `coins` is always assigned `= gold` yet stored as a separate save key; a save with divergent values silently keeps `coins` and discards `gold` | `character_service.gd:78`, `88`; `local_save.gd:589`; `character_service.gd:147` |
| CHS-09 | P2 | `set_level(int)` discards its argument and only re-emits | `character_service.gd:99-101` |
| CHS-10 | P2 | `level_changed`, `flags_changed`, `quests_changed` have zero consumers, so the observable surface is decorative | Grep of `apps/` finds only the emitters in `character_service.gd` |
| CHS-11 | P2 | `_reset_to_defaults` seeds `currencies.gold = 0` while `reset_to_defaults` seeds 100; the disagreement is invisible only because the write path overwrites the cached value | `local_save.gd:634` vs `character_service.gd:169` |
| CHS-12 | P2 | `set_quest_progress` uses a shallow `duplicate()`, so a nested Dictionary passed by a caller stays aliased into save state | `character_service.gd:120` |

## Target design

### Separate quest state from quest progress
The single `quests` bag becomes two typed maps, which removes the key collision and makes iteration meaningful:

```gdscript
## Persisted as save["quests"] = {"states": {...}, "progress": {...}}
var quest_states: Dictionary = {}     ## quest_id -> String state
var quest_progress: Dictionary = {}   ## quest_id -> Dictionary

func get_quest_state(quest_id: String) -> String
func set_quest_state(quest_id: String, state: String) -> void
func get_quest_progress(quest_id: String) -> Dictionary
func set_quest_progress(quest_id: String, progress: Dictionary) -> void
func active_quest_ids() -> Array[String]
func clear_quest(quest_id: String) -> void
```

`set_quest_state` validates against the state set owned by `QuestService` (`inactive`, `active`, `completed`, `turned_in`; see [`dialogue-quests.md`](dialogue-quests.md)) and pushes a warning plus a no-op for anything else, so a typo in a dialogue action cannot park a quest in an unreachable state. `set_quest_progress` uses `progress.duplicate(true)`. `active_quest_ids()` gives the quest board and the HUD a real list instead of filtering a mixed bag.

### Registered, typed flags
Flags stop being an open bag. A declared table gives every flag a type, a default, and a scope:

```gdscript
## apps/game/client/scripts/save/character_flags.gd (new)
class_name CharacterFlags
extends RefCounted

enum Kind { BOOL, INT, STRING, DICT }

const REGISTRY: Dictionary = {
    "deaths":                         {"kind": Kind.INT,  "default": 0},
    "runs_started":                   {"kind": Kind.INT,  "default": 0},
    "dungeon_max_tier":               {"kind": Kind.INT,  "default": 1},
    "story_completed":                {"kind": Kind.BOOL, "default": false},
    "recoverable_xp_shard":           {"kind": Kind.DICT, "default": {}},
    "theme_forgotten_castle_cleared": {"kind": Kind.BOOL, "default": false},
    "theme_crystal_caverns_cleared":  {"kind": Kind.BOOL, "default": false},
    "heard_castle_lore":              {"kind": Kind.BOOL, "default": false},
    "met_dungeon_npc":                {"kind": Kind.BOOL, "default": false},
}

static func is_registered(flag_id: String) -> bool
static func coerce(flag_id: String, value: Variant) -> Variant
static func default_for(flag_id: String) -> Variant
static func content_writable_ids() -> PackedStringArray
```

`CharacterService.set_flag(flag_id, value)` coerces through `CharacterFlags.coerce`, which drops anything JSON cannot represent (Object, Node, Callable, RID) with a `push_warning` naming the flag. Unregistered ids are still accepted at runtime — content authors add flags faster than code does — but they are recorded so validation can flag them:

```gdscript
func set_flag(flag_id: String, value: Variant = true) -> void
func get_flag(flag_id: String, default_value: Variant = null) -> Variant   ## null -> registry default
func has_flag(flag_id: String) -> bool
func is_flag_truthy(flag_id: String) -> bool   ## explicit replacement for the current bool() coercion
func unregistered_flag_ids() -> PackedStringArray
```

`get_flag` with no explicit default returns the registry default rather than `false`, so `get_flag("dungeon_max_tier")` yields `1` instead of `false` and `int(false)` cannot leak a tier 0 into `dungeon_tier_service.gd:17`.

Content-side enforcement lives in the validator: every `set_flag` action and every `flag` condition in `content/dialogue/*.json` and `content/quests/*.json` must name a `CharacterFlags.REGISTRY` id. That closes the typo class from CHS-07 without preventing content authors from working.

Chosen over an enum-only design: the flag bag is written from JSON content, so a GDScript enum cannot cover it. A registry keyed by String is checkable from both sides.

### Make the dungeon-clear unlocks real
`theme_forgotten_castle_cleared` and `theme_crystal_caverns_cleared` need writers. Despite their `theme_` prefix they unlock the `guard_spear` and `hunter_bow` weapons at `loadout_ui.gd:80-82`. The event that should set them is a dungeon clear, which `RunFlow` already knows about at the escape and boss paths:

```gdscript
## dungeon_catalog.gd — one new key per ENTRIES row
{"id": "forgotten_castle", "name": "Forgotten Castle", "biomeId": "forgotten_castle",
 "clearFlag": "theme_forgotten_castle_cleared"},

static func get_clear_flag(dungeon_id: String) -> String

## run_flow.gd — called from _handle_escape_meta and the boss-defeat path
func _mark_dungeon_cleared(dungeon_id: String) -> void:
    var flag_id := DungeonCatalog.get_clear_flag(dungeon_id)
    if flag_id != "":
        CharacterService.set_flag(flag_id, true)
```

`DungeonCatalog.ENTRIES` (`dungeon_catalog.gd:8-19`) is a hardcoded ten-row table, not content-driven, so the mapping goes there as a fourth key per row and `_mark_dungeon_cleared` reads it through a new `DungeonCatalog.get_clear_flag(dungeon_id) -> String`. `loadout_ui.gd:80-82` keeps its existing `level >= N or flag` shape, and the flag branch becomes reachable. Earning a weapon by clearing the dungeon it belongs to is the honest reward: the flag names already promise it. All ten dungeons get a `clearFlag`, so the other eight are available for future unlocks without another code change.

### One serialisation path
`to_save_dict()` becomes the only mapping and `LocalSave` calls it:

```gdscript
func to_save_dict() -> Dictionary:
    return {
        "gold": gold,
        "classId": class_id,
        "appearanceTheme": appearance_theme,
        "appearance": appearance_profile.duplicate(true),
        "flags": flags.duplicate(true),
        "quests": {
            "states": quest_states.duplicate(true),
            "progress": quest_progress.duplicate(true),
        },
    }
```

`local_save.gd:_build_save_payload` splices the result into `currencies`, `flags`, `quests`, and the three `character.*` keys instead of reading fields. `coins` disappears from the payload; `from_save_dict` keeps accepting it for one version so v4 saves still load, and `_migrate_v4_to_v5` folds `currencies.coins` into `currencies.gold` by taking the maximum of the two, which cannot cost a player money.

`coins` stays on the *API* — `add_coins`, `spend_coins`, `can_afford_coins`, `get_coins` have four external call sites in `blacksmith_service.gd` and `blacksmith_ui.gd` — but is documented as an alias and no longer a separate field. `coins_changed` continues to fire alongside `gold_changed`.

### Emit on every mutation
`from_save_dict` and `reset_to_defaults` gain `flags_changed.emit()` and `quests_changed.emit()`. `blacksmith_ui`, `merchant_ui`, and the quest board then have a correct refresh trigger after a character switch. `quest_board_ui.gd:63` moves from polling `get_quest_progress` on open to reacting to `quests_changed`.

### Batched autosave
Currency, flag, and quest mutations request a save instead of performing one, using the throttle introduced in [`local-save.md`](local-save.md):

```gdscript
LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)
```

`DEFERRED` coalesces to at most one write per 5 s of wall clock and one immediate write on the run-boundary events `RunFlow` already emits. Currency changes from a merchant transaction stay `IMMEDIATE`, because losing a purchase is worse than losing kill coins, and a purchase is a discrete player action rather than a per-frame event. Kill coins accumulate in memory and land with the next deferred flush or the floor transition, whichever comes first.

## Work plan

1. **Add `character_flags.gd` with `REGISTRY`, `coerce`, `default_for`, `is_registered`** — new file next to `character_service.gd`. Closes CHS-06 groundwork.
2. **Route `set_flag` / `get_flag` through the registry, add `is_flag_truthy` and `unregistered_flag_ids`** — `character_service.gd:44-55`. Update `dungeon_tier_service.gd:17` to drop its `clampi` fallback now that the default is typed. Closes CHS-06, CHS-07.
3. **Split `quests` into `quest_states` and `quest_progress`, add `active_quest_ids` and `clear_quest`, validate state strings, deep-copy progress** — `character_service.gd:104-122`. Update `quest_service.gd:23-130` and `quest_board_ui.gd:63`. Closes CHS-01, CHS-12.
4. **Add `clearFlag` to all ten `DungeonCatalog.ENTRIES` rows plus `get_clear_flag`, and call `_mark_dungeon_cleared` from `RunFlow`** — `dungeon_catalog.gd:8-19`, `run_flow.gd:758-776` and the boss-defeat path at `run_flow.gd:439-443`. Closes CHS-02.
5. **Emit `flags_changed` and `quests_changed` from `from_save_dict` and `reset_to_defaults`; subscribe `quest_board_ui`** — `character_service.gd:155-178`. Closes CHS-03, CHS-10.
6. **Make `to_save_dict` the single mapping and call it from `LocalSave`; fold `coins` into `gold`** — `character_service.gd:134-143`, `local_save.gd:569-591`, `local_save.gd:542-550`. Closes CHS-05, CHS-08.
7. **Replace the six `LocalSave.autosave()` calls with `request_autosave` priorities** — `character_service.gd:51`, `81`, `91`, `111`, `122`, `131`; keep merchant and blacksmith paths immediate. Depends on the throttle from [`local-save.md`](local-save.md). Closes CHS-04.
8. **Delete `set_level` and fix `_reset_to_defaults` seeding** — `character_service.gd:99-101`, `local_save.gd:634` becomes `{"gold": CharacterService.DEFAULT_GOLD}`. Closes CHS-09, CHS-11.

## Data and schema changes

**Save version bump: `save_migrator.gd` `CURRENT_VERSION` 4 -> 5.** This is the same single bump shared with [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`run-flow.md`](run-flow.md), and [`world-state.md`](world-state.md).

`_migrate_v4_to_v5` additions owned by this topic:

```gdscript
## currencies: fold coins into gold, never reduce the player's money
var currencies: Dictionary = copy.get("currencies", {})
var gold := int(currencies.get("gold", 0))
var coins := int(currencies.get("coins", gold))
currencies["gold"] = maxi(gold, coins)
currencies.erase("coins")
copy["currencies"] = currencies

## quests: {"kill_grunts": "active", "kill_grunts_progress": {...}}
##      -> {"states": {"kill_grunts": "active"}, "progress": {"kill_grunts": {...}}}
var legacy: Dictionary = copy.get("quests", {})
var states := {}
var progress := {}
for key in legacy.keys():
    var k := str(key)
    if k.ends_with("_progress"):
        var owner_id := k.substr(0, k.length() - 9)
        if legacy[key] is Dictionary:
            progress[owner_id] = (legacy[key] as Dictionary).duplicate(true)
    else:
        states[k] = str(legacy[key])
copy["quests"] = {"states": states, "progress": progress}

## flags: coerce through the registry, drop unserialisable values with a warning
copy["flags"] = CharacterFlags.coerce_all(copy.get("flags", {}))
```

The `_progress` split is ambiguous for a quest literally named `x_progress`; no such id exists in `content/quests/` today, and the validator gains an assertion forbidding the suffix so it never appears.

**Schema files:**
- `content/schemas/character-state.v2.json` (new, defined in [`local-save.md`](local-save.md)) describes `currencies` with `gold` only, `flags` as an object with `boolean | integer | string | object` values, and `quests` as `{"states": {additionalProperties: {"enum": [...]}}, "progress": {additionalProperties: object}}`.
- `content/schemas/dialogue-definition.v1.json` and `content/schemas/quest-definition.v1.json` keep `flag` as a free string in JSON Schema; the registry check happens in the GDScript validation suite, which can see `CharacterFlags.REGISTRY`.
- No schema change is needed for `clearFlag`: `DungeonCatalog.ENTRIES` is a GDScript constant table (`dungeon_catalog.gd:8-19`), not a content file. See [`dungeon-catalog-tiers.md`](dungeon-catalog-tiers.md) for the case for moving it into `content/`.

**Failure and recovery behaviour:**

| Situation | Behaviour |
|-----------|-----------|
| Corrupt save reaches `from_save_dict` with `flags` not a Dictionary | Already handled at `character_service.gd:156-158`; keep, and add `push_warning` naming the observed type |
| `quests` is a legacy flat Dictionary at runtime (a v4 file loaded by a build that skipped migration) | `from_save_dict` detects the absence of `states` / `progress` keys and applies the same split inline, so the service never sees a mixed bag |
| A flag value fails `CharacterFlags.coerce` | Flag is set to the registry default, one `push_warning` names the id and the rejected type, load continues |
| Content names an unregistered flag | Load continues, id recorded in `unregistered_flag_ids()`, validation suite reports it as a failure so it is caught before ship |
| A dungeon has no `clearFlag` | `_mark_biome_cleared` is a no-op; no theme unlock, no error |
| `spend_gold` called with a value above `gold` | Returns `false` before any mutation (`character_service.gd:85`), unchanged |

## Acceptance criteria
- [ ] A quest with id `relic_progress` and a quest with id `relic` keep independent state and progress. (CHS-01)
- [ ] Escaping a `forgotten_castle` run sets `theme_forgotten_castle_cleared`, and `loadout_ui` offers `guard_spear` at level 1. (CHS-02)
- [ ] Loading a second character emits `flags_changed` and `quests_changed`, and the quest board redraws without being reopened. (CHS-03)
- [ ] Killing 30 enemies on one floor produces at most one deferred save write plus the floor-transition write. (CHS-04)
- [ ] `to_save_dict()` is the only place that maps service state to save keys; grep finds no field reads of `CharacterService.flags` or `.quests` in `local_save.gd`. (CHS-05)
- [ ] `set_flag("x", Node.new())` leaves the flag at its default and emits one warning; the save file remains valid JSON. (CHS-06)
- [ ] A dialogue action naming an unregistered flag fails `content_suite`. (CHS-07)
- [ ] A v4 save with `currencies: {"gold": 40, "coins": 90}` migrates to `gold: 90` with no `coins` key. (CHS-08)
- [ ] `set_level` no longer exists and no call site references it. (CHS-09)
- [ ] `_reset_to_defaults` and `reset_to_defaults` agree on the starting gold value. (CHS-11)
- [ ] `set_quest_progress({"nested": {"count": 1}})` followed by mutating the caller's nested Dictionary does not change stored progress. (CHS-12)

## Validation
Extend `apps/game/client/scripts/validation/suites/progression_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `character.quests.state_and_progress_are_separate` | `set_quest_state("relic_progress", "active")` then `set_quest_progress("relic", {"count": 3})`; both read back intact |
| `character.quests.rejects_unknown_state` | `set_quest_state("relic", "banana")` leaves the state unchanged and warns |
| `character.quests.active_ids_excludes_progress` | `active_quest_ids()` returns only ids with state `active` |
| `character.quests.progress_is_deep_copied` | Mutating a nested Dictionary after `set_quest_progress` does not alter stored progress |
| `character.flags.registry_coerces_types` | `set_flag("deaths", "7")` stores int `7`; `set_flag("story_completed", 1)` stores bool `true` |
| `character.flags.rejects_unserialisable` | `set_flag("deaths", Callable())` leaves the registry default and emits a warning |
| `character.flags.default_from_registry` | `get_flag("dungeon_max_tier")` returns `1`, not `false` |
| `character.flags.clear_flag_set_on_escape` | A simulated `forgotten_castle` escape sets `theme_forgotten_castle_cleared` and `loadout_ui._is_weapon_unlocked("guard_spear")` is true at level 1 |
| `character.signals.emitted_on_load` | `from_save_dict` fires `flags_changed`, `quests_changed`, `gold_changed`, `coins_changed`, `level_changed` exactly once each |
| `character.signals.emitted_on_reset` | Same for `reset_to_defaults` |
| `character.save.round_trip_via_to_save_dict` | `from_save_dict(to_save_dict())` is a fixed point for gold, class id, appearance, flags, and both quest maps |
| `character.currency.coins_alias_tracks_gold` | `add_coins(10)` raises `gold` and `get_coins()` identically and fires both signals |
| `character.currency.autosave_is_deferred` | 30 `add_coins` calls produce one write; one `spend_gold` from the merchant path produces an immediate write |

Extend `apps/game/client/scripts/validation/suites/content_suite.gd`:

| Assertion id | Checks |
|--------------|--------|
| `content.dialogue.flags_are_registered` | Every `set_flag` action and `flag` condition in `content/dialogue/*.json` names a `CharacterFlags.REGISTRY` id |
| `content.quests.flags_are_registered` | Same for `content/quests/*.json` |
| `content.quests.no_progress_suffix` | No quest id ends with `_progress` |
| `content.dungeons.clear_flag_registered` | Every `clearFlag` in `DungeonCatalog.ENTRIES` is a registered flag id and all ten rows have one |

Extend `apps/game/client/scripts/validation/suites/save_suite.gd` with `save.migrate.quests_split_v4_to_v5` and `save.migrate.coins_folded_into_gold`, covering the two migration blocks above.

## Related
- Existing state: [`../existing_codebase/character-service.md`](../existing_codebase/character-service.md)
- [`local-save.md`](local-save.md), [`save-migrator.md`](save-migrator.md), [`character-appearance.md`](character-appearance.md), [`progression-service.md`](progression-service.md), [`dialogue-quests.md`](dialogue-quests.md), [`npc-hub-services.md`](npc-hub-services.md), [`world-state.md`](world-state.md), [`run-flow.md`](run-flow.md)
