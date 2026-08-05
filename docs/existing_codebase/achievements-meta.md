# Achievements and meta

`AchievementService` is an autoload that loads `content/achievements/catalog.json`, persists unlocks under LocalSave meta `achievements`, shows a toast, and optionally forwards to `SteamService.unlock_achievement`. Only six catalog ids are unlocked from gameplay (biome clears, boss, ten floors, speed clear, leaderboard submit). Nineteen catalog entries have no unlock call site. `LeaderboardSettings` is a separate opt-in flag used only on escape meta.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/meta/achievement_service.gd` | Autoload — catalog, unlock, toast, Steam hook |
| `apps/game/client/scripts/meta/leaderboard_settings.gd` | `LeaderboardSettings` — `opt_in` bool under meta `leaderboard` |
| `apps/game/client/scripts/platform/steam_service.gd` | Steam or stub; `unlock_achievement`, `sync_achievements` |
| `apps/game/client/scenes/ui/achievement_toast.tscn` | Toast scene preloaded at `achievement_service.gd:8` |
| `content/achievements/catalog.json` | 26 achievement definitions |
| `apps/game/client/scripts/app/run_flow.gd` | Sole gameplay unlock caller (`_handle_escape_meta`) |
| `apps/game/client/scripts/ui/settings_ui.gd` | Leaderboard opt-in checkbox |

## How it works

### Catalog
`CATALOG_PATH := "content/achievements/catalog.json"` (`achievement_service.gd:7`). `_load_catalog` stores `data.achievements` into `_definitions` (`achievement_service.gd:19-21`). Each entry has `id`, `name`, `description`, `category`, optional `hidden`.

Catalog ids (26): `first_blood`, `castle_clear`, `crystal_clear`, `swamp_clear`, `frozen_clear`, `cathedral_clear`, `boss_slayer`, `all_biomes`, `no_damage_boss`, `speed_clear`, `epic_loot`, `legendary_loot`, `mythic_loot`, `full_equip`, `talent_spender`, `merchant_friend`, `blacksmith_patron`, `quest_complete`, `arena_victor`, `parry_master`, `dodge_artist`, `status_applier`, `freeze_master`, `poison_master`, `leaderboard_submit`, `ten_floor_clear`.

### Unlock path
`unlock(id)` (`achievement_service.gd:35-45`): returns false if already unlocked; sets `_unlocked[id] = true`; `_persist()`; if `SteamService` exists and `not SteamService.is_stub_mode`, calls `SteamService.unlock_achievement(id)`; emits `achievement_unlocked`; `_show_toast(display_name)`.

`unlock_for_biome_clear(biome_id)` (`achievement_service.gd:48-70`) maps five EA biomes plus five alias biomes onto the five `*_clear` achievements, then `_check_all_biomes()` unlocks `all_biomes` when all five clears are owned (`achievement_service.gd:88-95`).

### What actually unlocks
Only `_handle_escape_meta` in `run_flow.gd:758-774` (requires `boss_defeated`):

| Condition | Achievement |
|-----------|-------------|
| Always when boss defeated on escape | `boss_slayer` |
| Biome id match | `*_clear` via `unlock_for_biome_clear` |
| `max_floors >= 10` and `current_floor >= max_floors` | `ten_floor_clear` |
| `elapsed < SPEED_CLEAR_MAX_SECONDS` (900.0) | `speed_clear` |
| `LeaderboardSettings.opt_in` and `ApiClient.submit_leaderboard` returns `ok` | `leaderboard_submit` |

Grep for `AchievementService.unlock` / `unlock_for_biome_clear` under `apps/game/client/scripts/` finds **no other callers**. The remaining 19 catalog ids are never unlocked.

### Steam sync
`SteamService` defaults to stub mode (`steam_service.gd:11`, `_init_stub` at `63-69`). In stub mode `unlock_achievement` returns `true` without calling Steam (`steam_service.gd:77-81`). Real path uses `setAchievement` + `storeStats` when the GodotSteam singleton exists (`steam_service.gd:82-87`).

`sync_achievements(unlocked_ids)` (`steam_service.gd:91-98`) re-pushes a list. It is **not** called from `AchievementService._ready` / `_load_from_save` — only from `m7_suite.gd:392`. Reinstalling Steam after local unlocks does not backfill.

### Leaderboard opt-in
`LeaderboardSettings.SAVE_KEY := "leaderboard"` (`leaderboard_settings.gd:6`). Default `opt_in = false`. Loaded/saved via LocalSave meta. Settings checkbox at `settings_ui.gd:126-132`. Consumed only in `run_flow.gd:768-774` before `ApiClient.submit_leaderboard`.

### Toast
`_show_toast` instantiates `achievement_toast.tscn` on the root and calls `show_achievement(display_name)` if present (`achievement_service.gd:110-114`).

## Contracts

**Signals emitted:** `achievement_unlocked(achievement_id, display_name)`.

**Save keys:** `meta.achievements` (Dictionary id → bool); `meta.leaderboard.opt_in`.

**Autoloads:** `AchievementService`, `SteamService`, `LocalSave`, `ContentLoader`; `RunFlow` / `ApiClient` / `LeaderboardSettings` on the escape path.

**Biome aliases:** vault→castle, prism→crystal, mire→swamp, hollow→frozen, umbral→cathedral (`achievement_service.gd:60-69`).

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Local unlock + toast + persist | IMPLEMENTED | `achievement_service.gd:35-45`, `110-114` |
| Escape meta unlocks (boss/biome/speed/10-floor/leaderboard) | IMPLEMENTED | `run_flow.gd:758-774` |
| `all_biomes` composite | IMPLEMENTED | `achievement_service.gd:88-95` |
| Catalog entries without unlock sites (19 ids) | FAKE | Catalog lists them; no `AchievementService.unlock("first_blood")` etc. anywhere under `scripts/` |
| Steam unlock in shipping builds | PARTIAL | Real path exists (`steam_service.gd:82-87`); stub is default (`is_stub_mode := true` at line 11) |
| Steam backfill via `sync_achievements` | STUB | Defined `steam_service.gd:91-98`; no call from `AchievementService` |
| `mythic_loot` vs rarity rename `aumbral` | FAKE | Catalog still says mythic (`catalog.json:16`); `RarityRegistry` maps mythic→aumbral |
| Leaderboard opt-in gate | IMPLEMENTED | `leaderboard_settings.gd`, `run_flow.gd:768-774` |
| In-game achievement browser / list UI | ABSENT | Searched `scripts/ui/` for achievement list — toast only |

## Related
- Improvement plan: [`../actual_improvements/achievements-meta.md`](../actual_improvements/achievements-meta.md)
- [`run-flow.md`](run-flow.md), [`platform-and-net.md`](platform-and-net.md), [`ui/settings.md`](ui/settings.md), [`loot-and-equipment.md`](loot-and-equipment.md)
