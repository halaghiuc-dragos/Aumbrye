# Achievements and meta — improvement plan

## Status: FINISHED

## Current state
`AchievementService` loads `content/achievements/catalog.json` and `content/achievements/hooks.json`, exposes `notify(event, context)`, persists unlocks under `meta.achievements`, shows toasts, syncs to Steam on load when non-stub, and unlocks escape-meta achievements from `RunFlow._handle_escape_meta`. All 26 catalog ids are covered by event hooks or `manualUnlock`. See [`../existing_codebase/achievements-meta.md`](../existing_codebase/achievements-meta.md).

## Gaps
| ID | Sev | Gap | Status |
|----|-----|-----|--------|
| ACH-01 | P0 | 19 catalog achievements had zero unlock call sites | FINISHED — `notify()` wired for combat, loot, hub, and progression events |
| ACH-02 | P0 | Catalog `mythic_loot` vs runtime `aumbral` rarity | FINISHED — renamed to `aumbral_loot`; save migrator v5→v6 maps legacy key |
| ACH-03 | P1 | `SteamService.sync_achievements` never ran after load | FINISHED — `_sync_steam_on_load()` in `AchievementService._load_from_save`; Settings shows stub label |
| ACH-04 | P1 | Leaderboard submit required API `ok`; no offline feedback | FINISHED — attempt-based unlock when opted in; results screen shows failure line |
| ACH-05 | P2 | No achievements UI beyond toast | FINISHED — `achievements_ui.gd` in pause menu and settings |

## Target design

### Event-driven unlock registry
`AchievementService.notify(event, context)` maps catalog ids to predicates in `content/achievements/hooks.json`. Counters persist in `CharacterService.flags` under `ach_ctr_*`. Escape-meta ids (`boss_slayer`, biome clears, `speed_clear`, `ten_floor_clear`, `leaderboard_submit`, `all_biomes`) remain in `manualUnlock` and are unlocked from `RunFlow._handle_escape_meta` / `unlock_for_biome_clear`.

### Steam honesty
On `_load_from_save`, when `SteamService.is_available()` and not stub, `SteamService.sync_achievements(get_unlocked_ids())` runs. Settings Platform section labels stub mode as "Steam: unavailable (dev stub)".

### Rarity rename
`aumbral_loot` replaces `mythic_loot` in catalog. `SaveMigrator` v5→v6 maps `meta.achievements.mythic_loot` → `aumbral_loot`.

### Leaderboard
`leaderboard_submit` unlocks on submit attempt while opted in. Results screen appends failure text when `leaderboard_submit_ok` is false.

## Work plan

1. **Audit catalog vs call sites** — `AchievementService.validate_catalog_coverage()`; `ach.catalog.every_id_has_hook` in `achievements_suite.gd`. Closes ACH-01 discovery.
2. **Add `notify` + counter flags + wire first_blood / loot rarities / full_equip / talent_spender** — `achievement_service.gd`, `hooks.json`, `inventory_service.gd`, `progression_service.gd`. Closes ACH-01 subset; ACH-02 rename.
3. **Wire hub and combat counters** — merchant, blacksmith, quests, parry, dodge, statuses, arena, no-damage boss. Remaining ACH-01.
4. **Steam sync on load + Settings stub label** — `achievement_service.gd`, `settings_ui.gd`. Closes ACH-03.
5. **Leaderboard failure feedback + attempt unlock** — `run_flow.gd`, `results_screen.gd`. Closes ACH-04.
6. **Achievements panel in pause/settings** — `achievements_ui.gd`, `pause_menu.gd`, `player_controls.gd`. Closes ACH-05.

## Data and schema changes

- `content/achievements/hooks.json` + `content/schemas/achievement-hooks.v1.json`
- `catalog.json`: `mythic_loot` → `aumbral_loot`
- Save: `SaveMigrator` v5→v6 maps `meta.achievements.mythic_loot`; documented in `docs/SAVE_MIGRATIONS.md`

## Acceptance criteria
- [x] Every id in `catalog.json` has either a `notify` predicate or an explicit `manualUnlock` entry; CI fails otherwise. (ACH-01)
- [x] Obtaining an `aumbral` rarity instance unlocks `aumbral_loot`; `mythic_loot` is absent from catalog. (ACH-02)
- [x] With Steam non-stub, loading a save that already has `boss_slayer` calls `sync_achievements` with that id. (ACH-03)
- [x] Failed leaderboard submit shows a results or hub message when opted in. (ACH-04)
- [x] Pause or settings lists all non-hidden achievements with locked/unlocked state. (ACH-05)

## Validation
`achievements_suite.gd` (registered in `validation_runner.gd`):

| Assertion id | Checks |
|--------------|--------|
| `ach.catalog.every_id_has_hook` | Each catalog id ∈ notify map or manual allowlist |
| `ach.catalog.no_mythic_loot` | `mythic_loot` absent from catalog |
| `ach.unlock.first_blood` | Simulate one kill event → `is_unlocked("first_blood")` |
| `ach.unlock.aumbral_loot` | Notify item rarity aumbral → unlocked |
| `ach.steam.sync_on_load` | After seeding unlocks, sync callable (stub mock) |

## Related
- Existing state: [`../existing_codebase/achievements-meta.md`](../existing_codebase/achievements-meta.md)
- [`run-flow.md`](run-flow.md), [`loot-and-equipment.md`](loot-and-equipment.md), [`platform-and-net.md`](platform-and-net.md)
