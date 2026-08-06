# Run flow

`RunFlow` is the autoload that owns the whole play path: hub entry, dungeon generation, floor transitions, death/escape/retreat resolution, results assembly, and the `activeRun` save record. It is on the live play path — every scene change between hub, dungeon, arena, results, and main menu goes through it.

## Files
| Path | Role |
|------|------|
| `apps/game/client/scripts/app/run_flow.gd` | Autoload `RunFlow` (~1100 lines). Run state, entry points, floor cache, outcome resolution |
| `apps/game/client/scripts/app/run_lifecycle.gd` | `RunLifecycle.build_results` — shared results dictionary builder |
| `apps/game/client/scripts/app/run_mode_config.gd` | `RunModeConfig` — mode ids `castle` / `endless` / `waves` and predicates |
| `apps/game/client/scripts/app/run_scene_router.gd` | `RunSceneRouter` — scene path constants and the deferred `change_scene_to_file` call |
| `apps/game/client/scripts/app/game_facade.gd` | `GameFacade` — dictionary accessors grouping autoloads; `run()` returns `RunFlow`, `WavesRunService`, `DungeonTierService` |
| `apps/game/client/scripts/dungeon/run_floor_config.gd` | `RunFloorConfig` — `MAX_FLOORS := 10`, `ENDLESS_MAX_FLOORS := 999999` |
| `apps/game/client/scripts/dungeon/skip_floor_service.gd` | `SkipFloorService` — endless start-floor consumables |

## How it works

### Constants
`run_flow.gd:9-26`:

| Constant | Value |
|----------|-------|
| `HUB_SCENE` | `res://scenes/hub/hub.tscn` (via `RunSceneRouter`) |
| `CASTLE_RUN_SCENE` | `res://scenes/dungeon/castle_run.tscn` |
| `WAVES_RUN_SCENE` | `res://scenes/dungeon/waves_run.tscn` |
| `ARENA_SCENE` | `res://scenes/debug/combat_arena.tscn` |
| `RESULTS_SCENE` | `res://scenes/ui/results_screen.tscn` |
| `MAIN_MENU_SCENE` | `res://scenes/ui/main_menu.tscn` |
| `TOWER_DISPLAY_NAME` | `Aumbrye Tower` |
| `DEFAULT_BIOME` | `forgotten_castle` |
| `USE_ONLINE_PROCgen` | `false` |
| `SPEED_CLEAR_MAX_SECONDS` | `900.0` |
| `WAVES_COMPLETION_XP` | `500` |
| `MAX_CACHED_FLOORS` | `3` |
| `XP_SHARD_FLAG` | `recoverable_xp_shard` |

### Online generation is compiled off
`_generate_dungeon()` (`run_flow.gd:180-192`) guards the online branch with `if USE_ONLINE_PROCgen and ApiConfig.get_base_url() != "":`. Because `USE_ONLINE_PROCgen := false` (`run_flow.gd:17`), `_try_online_generate()` (`run_flow.gd:195-215`) is unreachable, and with it `ApiClient.create_run` and `ApiClient.get_dungeon`. Every generation call in the live path is `LocalProcgen.generate(biome_id, run_seed, floor_index, run_mode, current_dungeon_tier, ProgressionService.level)` (`run_flow.gd:185-192`).

`ApiClient` is still reached after a run ends, from `_cloud_finalize_run()` (`run_flow.gd:736-755`): `ApiClient.complete_run(...)` when `run_id != ""`, then `LocalSave.push_to_cloud()`. Both failures are downgraded to `push_warning` and the error string `"auth failed"` is silenced entirely.

### Entry points
| Function | Line | Behaviour |
|----------|------|-----------|
| `start_new_castle_run()` | 59 | `start_new_run(DungeonCatalog.DEFAULT_DUNGEON_ID)` |
| `start_castle_run()` | 128 | alias of `start_new_castle_run()` |
| `start_new_run(dungeon_id, run_seed = null)` | 78 | resolves the dungeon id, refuses if `DungeonTierService.is_dungeon_unlocked()` is false, refuses a seed if `DungeonSeedService.can_access_tier(tier)` is false, then `_start_mode_run(MODE_CASTLE, ...)` |
| `start_castle_run_with_seed(v)` / `start_run_with_seed(id, v)` | 93 / 97 | seeded castle runs |
| `start_endless_run(start_floor = 1, skip_item_id = "")` | 63 | consumes the skip item via `SkipFloorService.consume_skip`, sets `start_floor` from `SkipFloorService.start_floor_for_item`, then `_start_mode_run(MODE_ENDLESS, BiomeRegistry.BIOME_UMBRAL, null, start_floor)` |
| `continue_castle_run()` | 101 | requires `LocalSave.has_continuable_run()` and `runMode == "castle"`; sets `_is_continue = true` and calls `_restore_castle_run(saved)` |
| `continue_endless_run()` | 115 | same, requiring `runMode == "endless"` |
| `start_waves_run()` / `continue_waves_run()` | 70 / 74 | `_start_waves_run(bool)` |
| `go_to_arena()` | 328 | `_goto_scene(ARENA_SCENE)` |
| `return_to_main_menu()` | 697 | flushes the snapshot, unpauses, `AudioDirector.stop_all(0.35)` + `play_menu_music()`, goes to the main menu |

Refusals set `last_hub_message` and return; the hub prints it through `_refresh_hub_message()`.

### Start path (`_start_mode_run`, lines 132-173)
1. Sets `run_mode`, clears `_is_continue` and `_pending_snapshot`.
2. Preserves `current_dungeon_tier` and `current_dungeon_id` across `_reset_run_stats()` (which zeroes `_kill_count`, `_boss_defeated`, `_cleared_floors`, `_loot_collected`, `_loot_claimed_instance_ids`, sets `current_floor = 1`, clears the floor cache).
3. `max_floors = RunFloorConfig.max_floors_for_mode(run_mode)` — 10 for castle, 999999 for endless.
4. `current_floor = maxi(1, start_floor)`, then `_generate_dungeon(...)`.
5. On `ok == false`, sets `last_hub_message = "Could not generate dungeon: %s"`, `push_error`, and returns without a scene change.
6. `current_seed` is the explicit seed if given, otherwise `maxi(1, int(gen.input_seed or gen.generation_seed))`.
7. `_enter_run()`.

### `_enter_run` (lines 289-325)
Writes six root metas consumed by `castle_run.tscn` and `DungeonBuilder`:

| Meta | Value |
|------|-------|
| `dungeon_definition` | deep copy of `current_dungeon_definition` |
| `run_seed` | `current_seed` |
| `tier_generation_seed` | `DungeonSeedService.generation_seed(current_seed, current_dungeon_tier, current_floor)` |
| `run_id` | `current_run_id` |
| `run_snapshot` | `_pending_snapshot` when continuing; removed otherwise |

Then writes `activeRun` through `LocalSave.set_active_run()` with keys `schemaVersion` (`SaveMigrator.CURRENT_VERSION`), `runMode`, `runId`, `seed`, `biomeId`, `dungeonId`, `dungeonTier`, `currentFloor`, `maxFloors`, `dungeonDefinition`, `clearedFloors`, plus `snapshot` when continuing. Sets `_run_active = true`, stamps `_run_start_time` from `Time.get_ticks_msec() / 1000.0`, increments the `runs_started` character flag (`_register_run_started`), routes to `CASTLE_RUN_SCENE`, and emits `run_started`.

Waves never uses `_enter_run`: `_start_waves_run()` (line 907) sets `_run_active` itself, calls `WavesRunService.begin_new_run()` or `restore_from_save()`, routes to `WAVES_RUN_SCENE`, and emits `run_started`.

### Continue path (`_restore_castle_run`, lines 218-286)
Reads `runId`, `biomeId`, `seed`, `runMode`, `currentFloor`, `maxFloors`, `dungeonTier`, `dungeonId` from the saved record. Repairs an invalid `dungeonId` by falling back to `biomeId` then `DungeonCatalog.DEFAULT_DUNGEON_ID`. If `dungeonDefinition` is missing it regenerates from `current_seed`. Four bail-outs each clear the active run and return to the hub with a message:

| Condition | Message |
|-----------|---------|
| definition still empty | `Saved run data was invalid.` |
| `dungeonTier > DungeonTierService.get_max_unlocked_tier()` | `That dungeon tier is locked — continue from the hub portal.` |
| `not DungeonTierService.is_dungeon_unlocked(current_dungeon_id)` | `That dungeon is not unlocked yet.` |
| `current_floor > _max_cleared_floor() + 1` | clamps the floor and sets `Saved floor was ahead of progression — restored to floor %d.` (does not abort) |

Then restores `_kill_count`, `_boss_defeated`, `_loot_collected`, `_loot_claimed_instance_ids` from `_pending_snapshot`, and forces `_boss_defeated = false` if the current floor is not in `_cleared_floors`.

### Floor transitions
`ascend_floor()` (524) requires `_run_active`, `_boss_defeated`, and `current_floor` present in `_cleared_floors`; castle mode additionally refuses at `current_floor >= max_floors`. `descend_floor()` (537) refuses at floor 1 and in endless mode. Both stash the current definition and call `_transition_floor(ascending)`.

`_transition_floor()` (548-574) clears `current_dungeon_definition`, prefers `_get_cached_floor_definition(current_floor)` (in-memory `floor_definitions` keyed by `str(floor)`, else `DungeonBuilder.get_floor_cache`), otherwise regenerates. It sets root metas `dungeon_definition`, `floor_transition` (`{"ascending": bool, "floor": int}`) and `run_snapshot` (`_build_floor_transition_snapshot`, line 577: `floorTransition`, `ascending`, `currentFloor`, `bossDefeated`, `clearedFloors`, `killCount`, `lootCollected`, `lootClaimedInstanceIds`), calls `_persist_active_run()`, and reloads `CASTLE_RUN_SCENE`.

Floor cache trimming: `_trim_floor_cache()` keeps at most `MAX_CACHED_FLOORS` entries and evicts floors farthest from `current_floor` (integer keys, not string sort).

### Outcomes

**Escape — `complete_run_via_portal()` (355-392).** Refused when not active, in endless mode, when `can_escape_run()` is false (`_boss_defeated and is_final_floor()`, line 479), or when `current_floor < max_floors`. Grants `ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, true)` with reason `"escape"`, clears `RunBuffs`, builds results via `RunLifecycle.build_escape_results`, clears the active run, autosaves, emits `run_ended`, sets root meta `run_results`, runs `_handle_escape_meta`, fires `_cloud_finalize_run(run_id, "escaped", ...)`, calls `DungeonTierService.on_dungeon_cleared(cleared_dungeon)` for castle mode, and routes to `RESULTS_SCENE`.

**Death — `on_player_died()`.** Returns immediately if a node is in group `training_arena`. If `activeRun.lastCheckpoint` is non-empty, diverts to `_bonfire_death_respawn(checkpoint)` (respawn flow with `run_respawn_results` meta). Otherwise grants death XP fraction, stores recoverable shard, strips run loot, builds results via `RunLifecycle.build_results(OUTCOME_DIED)`, calls `QuestService.register_run_outcome`, clears the active run, sets `run_results` meta, and routes to `RESULTS_SCENE`.

**Bonfire respawn — `_bonfire_death_respawn()`.** Grants death XP, stores shard, strips loot since checkpoint, restores checkpoint state, builds `OUTCOME_RESPAWNED` results, erases stale `playerDead` from `activeRun`, autosaves, sets `run_respawn_results` + `run_snapshot` metas, and reloads `CASTLE_RUN_SCENE`.

**Retreat — `retreat_to_hub()` (491-509).** Allowed only when `can_retreat_to_hub()` (485) is true: active run, `_boss_defeated`, and mode `castle` or `endless`. Calls `castle_run._persist_snapshot()`, refreshes `currentFloor` / `dungeonTier` / `dungeonId` / `dungeonDefinition` in `activeRun`, and returns to the hub with `Retreated to Aumbrye Tower. Continue from the portal.`

**Abandon — `abandon_active_run()` (344-352).** Removes run loot, clears `RunBuffs`, clears the active run, and returns to the hub with `Run abandoned. Loot from this run was lost.`

**Waves.** `quit_waves_run()`, `complete_waves_run(rewards)`, and `on_waves_failed()` all assemble results through `RunLifecycle.build_results` with `xp_result.levels_gained` and `run_relics_lost` where applicable.

### Results dictionary shape
`RunLifecycle.build_results` centralizes outcome keys (`outcome`, `time_seconds`, `kills`, `loot`, `xp_gained`, `levels_gained`, `loot_kept`, `run_relics_lost`, `rules_summary`, plus per-outcome extras such as `loot_lost`, `xp_deferred`, `xp_full_would_be`).

## Contracts

**Signals emitted:** `run_started`, `run_ended(results: Dictionary)`, `returned_to_hub(message: String)`, `run_warning(message: String)`. Consumers include `WorldState`, `QuestService`, and hub UI.

**Root metas written:** `RUN_META_KEYS` — `dungeon_definition`, `run_seed`, `tier_generation_seed`, `run_id`, `run_snapshot`, `floor_transition`, `run_results`; plus `run_respawn_results` during bonfire respawn. `_clear_run_meta()` clears all `RUN_META_KEYS` and `run_respawn_results`.

**Autoloads depended on:** `LocalSave`, `ProgressionService`, `CharacterService`, `InventoryService`, `RunBuffs`, `QuestService`, `AchievementService`, `WavesRunService`, `DungeonTierService`, `AudioDirector`, `WorldState`, `PixelDioramaBootstrap`, `DungeonBuilder`, `LocalProcgen`, `ApiClient`, `LeaderboardSettings`.

**Node groups queried:** `player`, `enemy`, `castle_run`, `waves_run`, `training_arena`.

**Duck-typed calls into the run scene:** `castle_run._persist_snapshot()`, `castle_run.persist_bonfire_checkpoint()`, `waves_run._persist_waves_save()`, `enemy.respawn_at_rest()`, `player/PlayerHeal.refill_charges()`.

**Save keys written:** `activeRun.*` (see `_enter_run`), `wavesActiveRun` (cleared here, written by `WavesRunService`), and the character flags `runs_started`, `deaths`, `recoverable_xp_shard`.

## Current state
| Surface | Status | Evidence |
|---------|--------|----------|
| Castle start → floor → boss → ascend → escape → results → hub | IMPLEMENTED | `start_new_run`, `ascend_floor`, `complete_run_via_portal` |
| Online dungeon generation | STUB | `USE_ONLINE_PROCgen := false` |
| Escape-quest outcome gating | IMPLEMENTED | `QuestService.register_run_outcome` on escape/death |
| Floor-cache eviction by distance from current floor | IMPLEMENTED | `_trim_floor_cache` integer sort |
| Mid-run generation failure recovery | IMPLEMENTED | `_transition_floor` reverts floor + definition, emits `run_warning` |
| Failed dungeon start feedback | IMPLEMENTED | `run_warning` + `last_hub_message` |
| Bonfire respawn with respawn results meta | IMPLEMENTED | `_bonfire_death_respawn`, `run_respawn_results` |
| `playerDead` stale key cleanup | IMPLEMENTED | `active.erase("playerDead")` before continue |
| Waves results honesty | IMPLEMENTED | `build_results` with `xp_result.levels_gained`, `run_relics_lost` |
| Run meta hygiene | IMPLEMENTED | `_clear_run_meta` clears `RUN_META_KEYS` |
| Cloud finalize error surfacing | IMPLEMENTED | awaited `_cloud_finalize_run`; `cloud_synced` on results; offline message in `results_screen.gd` |

## Related
- Improvement plan: [`../actual_improvements/run-flow.md`](../actual_improvements/run-flow.md) — **FINISHED**
- [`world-state.md`](world-state.md), [`local-save.md`](local-save.md), [`hub.md`](hub.md), [`progression-service.md`](progression-service.md), [`achievements-meta.md`](achievements-meta.md), [`dialogue-quests.md`](dialogue-quests.md)
- Run scenes owned elsewhere: [`castle-run.md`](castle-run.md), [`waves-run.md`](waves-run.md)
- Results UI: [`ui/run_outcome.md`](ui/run_outcome.md), [`ui/run_flow_ui.md`](../actual_improvements/ui/run_flow_ui.md)
