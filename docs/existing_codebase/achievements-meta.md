# Achievements and meta

`AchievementService` is an autoload that loads `content/achievements/catalog.json` and `content/achievements/hooks.json`, persists unlocks under `meta.achievements`, routes gameplay events through `notify(event, context)`, shows a toast, syncs to Steam on load when non-stub, and unlocks escape-meta achievements from `RunFlow._handle_escape_meta`. `LeaderboardSettings.opt_in` gates leaderboard submit on escape; `leaderboard_submit` unlocks on attempt while opted in.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/meta/achievement_service.gd` | Autoload â€” catalog, hooks, `notify`, unlock, toast, Steam sync on load |
| `apps/game/client/scripts/meta/leaderboard_settings.gd` | `LeaderboardSettings` â€” `opt_in` bool under meta `leaderboard` |
| `apps/game/client/scripts/platform/steam_service.gd` | Steam or stub; `unlock_achievement`, `sync_achievements` |
| `apps/game/client/scripts/ui/achievements_ui.gd` | Achievement browser â€” locked/unlocked list from catalog |
| `apps/game/client/scenes/ui/achievement_toast.tscn` | Toast scene preloaded at `achievement_service.gd:9` |
| `content/achievements/catalog.json` | 26 achievement definitions |
| `content/achievements/hooks.json` | Event â†’ achievement id map + `manualUnlock` allowlist |
| `content/schemas/achievement-hooks.v1.json` | Schema for hooks file |
| `apps/game/client/scripts/app/run_flow.gd` | Escape-meta unlocks; boss-fight damage tracking; leaderboard attempt |
| `apps/game/client/scripts/ui/settings_ui.gd` | Leaderboard opt-in; Steam stub label; achievements button |
| `apps/game/client/scripts/ui/pause_menu.gd` | Achievements menu entry |
| `apps/game/client/scripts/validation/suites/achievements_suite.gd` | Catalog coverage and unlock assertions |

## How it works

### Catalog
`CATALOG_PATH := "content/achievements/catalog.json"` (`achievement_service.gd:7`). `_load_catalog` stores `data.achievements` into `_definitions` (`achievement_service.gd:24-26`). Each entry has `id`, `name`, `description`, `category`, optional `hidden`.

Catalog ids (26): `first_blood`, `castle_clear`, `crystal_clear`, `swamp_clear`, `frozen_clear`, `cathedral_clear`, `boss_slayer`, `all_biomes`, `no_damage_boss`, `speed_clear`, `epic_loot`, `legendary_loot`, `aumbral_loot`, `full_equip`, `talent_spender`, `merchant_friend`, `blacksmith_patron`, `quest_complete`, `arena_victor`, `parry_master`, `dodge_artist`, `status_applier`, `freeze_master`, `poison_master`, `leaderboard_submit`, `ten_floor_clear`.

### Hooks and notify
`HOOKS_PATH := "content/achievements/hooks.json"` (`achievement_service.gd:8`). `notify(event, context)` matches hooks by `event` and optional `contextKey`/`contextValue`; threshold hooks increment `CharacterService.flags` keys prefixed `ach_ctr_` (`achievement_service.gd:68-93`). `manualUnlock` lists escape-meta ids unlocked directly from `RunFlow`.

| Event | Achievement ids | Wired from |
|-------|-----------------|------------|
| `enemy_killed` | `first_blood` | `run_flow.gd:register_kill` |
| `item_obtained` + rarity | `epic_loot`, `legendary_loot`, `aumbral_loot` | `inventory_service.gd:add_item` |
| `equipment_full` | `full_equip` | `inventory_service.gd:_check_full_equip_achievement` |
| `talent_points_spent` | `talent_spender` | `progression_service.gd:unlock_talent` |
| `merchant_buy` | `merchant_friend` | `merchant_service.gd:buy_item` |
| `blacksmith_craft` | `blacksmith_patron` | `blacksmith_service.gd:upgrade_item`, `unlock_recipe` |
| `quest_completed` | `quest_complete` | `quest_service.gd:complete_quest` |
| `parry` | `parry_master` | `hit_feedback.gd:_on_parry_success` |
| `dodge` | `dodge_artist` | `hit_feedback.gd:on_dodge_iframe` |
| `status_applied` | `status_applier`, `freeze_master`, `poison_master` | `hurtbox.gd:_notify_player_status_applied` |
| `boss_defeated_no_damage` | `no_damage_boss` | `run_flow.gd:register_boss_defeated` |
| `arena_won` | `arena_victor` | `combat_arena.gd:_on_dummy_died` |

### Unlock path
`unlock(id)` (`achievement_service.gd:54-64`): returns false if already unlocked; sets `_unlocked[id] = true`; `_persist()`; if `SteamService` exists and `not SteamService.is_stub_mode`, calls `SteamService.unlock_achievement(id)`; emits `achievement_unlocked`; `_show_toast(display_name)`.

`unlock_for_biome_clear(biome_id)` (`achievement_service.gd:96-113`) maps five EA biomes plus five alias biomes onto the five `*_clear` achievements, then `_check_all_biomes()` unlocks `all_biomes` when all five clears are owned (`achievement_service.gd:168-177`).

### Escape meta unlocks
`_handle_escape_meta` in `run_flow.gd:826-844` (requires `boss_defeated`):

| Condition | Achievement |
|-----------|-------------|
| Always when boss defeated on escape | `boss_slayer` |
| Biome id match | `*_clear` via `unlock_for_biome_clear` |
| `max_floors >= 10` and `current_floor >= max_floors` | `ten_floor_clear` |
| `elapsed < SPEED_CLEAR_MAX_SECONDS` (900.0) | `speed_clear` |
| `LeaderboardSettings.opt_in` (submit attempted) | `leaderboard_submit` |

### Steam sync
`SteamService` defaults to stub mode (`steam_service.gd:11`). `_sync_steam_on_load()` (`achievement_service.gd:40-43`) calls `sync_achievements(get_unlocked_ids())` when Steam is available and not stub.

### Leaderboard opt-in
`LeaderboardSettings.SAVE_KEY := "leaderboard"` (`leaderboard_settings.gd:6`). Default `opt_in = false`. Settings checkbox at `settings_ui.gd:141-148`. On failed submit, `results_screen.gd` appends "Leaderboard submit failed â€” clear time saved locally only."

### Achievements UI
`achievements_ui.gd` lists non-hidden catalog entries with `[Locked]` / `[Unlocked]` prefix. Opened from pause menu (`pause_menu.gd`) and settings Platform section (`settings_ui.gd`).

### Toast
`_show_toast` instantiates `achievement_toast.tscn` on the root and calls `show_achievement(display_name)` if present (`achievement_service.gd:193-197`).

## Contracts

**Signals emitted:** `achievement_unlocked(achievement_id, display_name)`.

**Save keys:** `meta.achievements` (Dictionary id â†’ bool); `meta.leaderboard.opt_in`; `CharacterService.flags` keys `ach_ctr_*` for counters.

**Autoloads:** `AchievementService`, `SteamService`, `LocalSave`, `ContentLoader`, `CharacterService`; `RunFlow` / `ApiClient` / `LeaderboardSettings` on the escape path.

**Biome aliases:** vaultâ†’castle, prismâ†’crystal, mireâ†’swamp, hollowâ†’frozen, umbralâ†’cathedral (`achievement_service.gd:104-112`).

**Save migration:** `SaveMigrator` v5â†’v6 renames `meta.achievements.mythic_loot` to `aumbral_loot`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Local unlock + toast + persist | IMPLEMENTED | `achievement_service.gd:54-64`, `193-197` |
| Event-driven `notify` hooks | IMPLEMENTED | `hooks.json`, `achievement_service.gd:68-93` |
| Escape meta unlocks (boss/biome/speed/10-floor/leaderboard) | IMPLEMENTED | `run_flow.gd:826-844` |
| `all_biomes` composite | IMPLEMENTED | `achievement_service.gd:168-177` |
| Catalog coverage validation | IMPLEMENTED | `achievements_suite.gd`, `validate_catalog_coverage()` |
| Steam unlock in shipping builds | PARTIAL | Real path exists (`steam_service.gd:82-87`); stub is default (`is_stub_mode := true` at line 11) |
| Steam backfill via `sync_achievements` on load | IMPLEMENTED | `achievement_service.gd:40-43` |
| `aumbral_loot` rarity alignment | IMPLEMENTED | `catalog.json`, `hooks.json`, migrator v5â†’v6 |
| Leaderboard opt-in + attempt unlock | IMPLEMENTED | `leaderboard_settings.gd`, `run_flow.gd:836-844` |
| Leaderboard failure feedback | IMPLEMENTED | `results_screen.gd` |
| In-game achievement browser | IMPLEMENTED | `achievements_ui.gd`, `pause_menu.gd`, `settings_ui.gd` |

## Related
- Improvement plan: [`../actual_improvements/achievements-meta.md`](../actual_improvements/achievements-meta.md) - **FINISHED**
- [`run-flow.md`](run-flow.md), [`platform-and-net.md`](platform-and-net.md), [`ui/settings.md`](ui/settings.md), [`loot-and-equipment.md`](loot-and-equipment.md)
