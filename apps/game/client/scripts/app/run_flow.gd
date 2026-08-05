extends Node

## Autoload — hub ↔ dungeon ↔ results flow (FLOW-2.1 / FLOW-4.1).

signal run_started
signal run_ended(results: Dictionary)
signal returned_to_hub(message: String)

const HUB_SCENE := RunSceneRouter.HUB_SCENE
const TOWER_DISPLAY_NAME := "Aumbrye Tower"
const CASTLE_RUN_SCENE := RunSceneRouter.CASTLE_RUN_SCENE
const WAVES_RUN_SCENE := RunSceneRouter.WAVES_RUN_SCENE
const ARENA_SCENE := RunSceneRouter.ARENA_SCENE
const RESULTS_SCENE := RunSceneRouter.RESULTS_SCENE
const DEFAULT_BIOME := "forgotten_castle"
const USE_ONLINE_PROCgen := false

## Achievement / progression tuning
const SPEED_CLEAR_MAX_SECONDS := 900.0
const WAVES_COMPLETION_XP := 500
const MAX_CACHED_FLOORS := 3

const RM := preload("res://scripts/app/run_mode_config.gd")
const SkipFloorSvc := preload("res://scripts/dungeon/skip_floor_service.gd")
const XP_SHARD_FLAG := "recoverable_xp_shard"

var run_mode: String = "castle"

var current_biome_id: String = DEFAULT_BIOME
var current_dungeon_id: String = DungeonCatalog.DEFAULT_DUNGEON_ID
var current_dungeon_tier: int = 1
var current_floor: int = 1
var max_floors: int = RunFloorConfig.MAX_FLOORS
## Chunking: only the active floor definition is kept in memory (not all floors).
var floor_definitions: Dictionary = {}

var last_hub_message := ""
var last_run_results: Dictionary = {}
var current_run_id: String = ""
var current_dungeon_definition: Dictionary = {}
var current_seed: int = 0
var _run_active := false
var _run_start_time := 0.0
var _kill_count := 0
var _boss_defeated := false
var _loot_collected: Array[String] = []
var _loot_claimed_instance_ids: Array[String] = []
var _pending_snapshot: Dictionary = {}
var _is_continue := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	PixelDioramaBootstrap.prime()


func start_new_castle_run() -> void:
	start_new_run(DungeonCatalog.DEFAULT_DUNGEON_ID)


func start_endless_run(start_floor: int = 1, skip_item_id: String = "") -> void:
	if skip_item_id != "":
		SkipFloorSvc.consume_skip(InventoryService.inventory, skip_item_id)
		start_floor = SkipFloorSvc.start_floor_for_item(skip_item_id)
	await _start_mode_run(RM.MODE_ENDLESS, BiomeRegistry.BIOME_UMBRAL, null, start_floor)


func start_waves_run() -> void:
	_start_waves_run(false)


func continue_waves_run() -> void:
	_start_waves_run(true)


func start_new_run(dungeon_id: String, run_seed: Variant = null) -> void:
	var resolved_id := _resolve_dungeon_id(dungeon_id)
	if not DungeonTierService.is_dungeon_unlocked(resolved_id):
		last_hub_message = "That dungeon is not unlocked yet."
		return
	var tier := DungeonCatalog.get_tier_for_dungeon(resolved_id)
	if run_seed != null and not DungeonSeedService.can_access_tier(tier):
		last_hub_message = "Tier %d is locked — you cannot use a seed for that tier yet." % tier
		return
	current_dungeon_id = resolved_id
	current_biome_id = DungeonCatalog.get_biome_id(resolved_id)
	current_dungeon_tier = tier
	await _start_mode_run(RM.MODE_CASTLE, current_biome_id, run_seed, 1)


func start_castle_run_with_seed(run_seed_value: int) -> void:
	start_run_with_seed(DungeonCatalog.DEFAULT_DUNGEON_ID, run_seed_value)


func start_run_with_seed(dungeon_id: String, run_seed_value: int) -> void:
	await start_new_run(dungeon_id, run_seed_value)


func continue_castle_run() -> void:
	var saved := LocalSave.get_active_run()
	if not LocalSave.has_continuable_run():
		last_hub_message = "No saved castle run to continue."
		return
	var mode := str(saved.get("runMode", RM.MODE_CASTLE))
	if mode != RM.MODE_CASTLE and mode != "":
		last_hub_message = "Saved run is not a castle run — use the correct portal."
		return
	_is_continue = true
	_pending_snapshot = saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
	_restore_castle_run(saved)


func continue_endless_run() -> void:
	var saved := LocalSave.get_active_run()
	if not LocalSave.has_continuable_run():
		last_hub_message = "No saved endless run to continue."
		return
	if str(saved.get("runMode", "")) != RM.MODE_ENDLESS:
		last_hub_message = "Saved run is not an endless run."
		return
	_is_continue = true
	_pending_snapshot = saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
	_restore_castle_run(saved)


func start_castle_run() -> void:
	start_new_castle_run()


func _start_mode_run(
	mode: String,
	biome_id: String,
	run_seed: Variant,
	start_floor: int
) -> void:
	run_mode = mode
	_is_continue = false
	_pending_snapshot.clear()
	_reset_run_stats()
	max_floors = RunFloorConfig.max_floors_for_mode(run_mode)
	current_dungeon_definition = {}
	current_run_id = ""
	current_seed = 0
	current_biome_id = biome_id
	current_floor = maxi(1, start_floor)
	_clear_floor_cache()

	var gen := await _generate_dungeon(biome_id, run_seed, current_floor)
	if not gen.get("ok", false):
		last_hub_message = "Could not generate dungeon: %s" % gen.get("error", "unknown error")
		push_error("RunFlow: %s" % last_hub_message)
		return

	current_dungeon_definition = gen.get("definition", {})
	current_run_id = str(gen.get("run_id", ""))
	if run_seed != null:
		current_seed = maxi(1, int(run_seed))
	else:
		current_seed = maxi(1, int(gen.get("input_seed", gen.get("generation_seed", 0))))
	_set_current_floor_cache(current_dungeon_definition)

	if current_dungeon_definition.is_empty():
		last_hub_message = "Failed to load dungeon definition."
		return_to_hub(last_hub_message)
		return

	_enter_run()


func _start_run(biome_id: String, run_seed: Variant) -> void:
	await _start_mode_run(RM.MODE_CASTLE, biome_id, run_seed, 1)


func _generate_dungeon(biome_id: String, run_seed: Variant, floor_index: int = 1) -> Dictionary:
	if USE_ONLINE_PROCgen and ApiConfig.get_base_url() != "":
		var online := await _try_online_generate(biome_id, run_seed)
		if online.get("ok", false):
			return online
	return LocalProcgen.generate(
		biome_id,
		run_seed,
		floor_index,
		run_mode,
		current_dungeon_tier,
		ProgressionService.level if ProgressionService else 1
	)


func _try_online_generate(biome_id: String, run_seed: Variant) -> Dictionary:
	var create := await ApiClient.create_run(biome_id, run_seed, current_dungeon_tier)
	if not create.get("ok", false):
		return {"ok": false, "error": create.get("error", "online create failed")}
	var body: Dictionary = create.get("body", {})
	var run_id: String = str(body.get("runId", body.get("id", "")))
	if run_id == "":
		return {"ok": false, "error": "online run missing id"}
	var dungeon := await ApiClient.get_dungeon(run_id)
	if not dungeon.get("ok", false):
		return {"ok": false, "error": dungeon.get("error", "dungeon fetch failed")}
	var definition: Dictionary = dungeon.get("definition", {})
	if definition.is_empty():
		return {"ok": false, "error": "empty dungeon definition from API"}
	return {
		"ok": true,
		"definition": definition,
		"run_id": run_id,
		"input_seed": int(definition.get("seed", 0)),
		"generation_seed": int(definition.get("seed", 0)),
	}


func _restore_castle_run(saved: Dictionary) -> void:
	current_run_id = str(saved.get("runId", ""))
	current_biome_id = str(saved.get("biomeId", DEFAULT_BIOME))
	current_seed = int(saved.get("seed", 0))
	run_mode = str(saved.get("runMode", RM.MODE_CASTLE))
	current_floor = int(saved.get("currentFloor", 1))
	max_floors = int(saved.get("maxFloors", RunFloorConfig.max_floors_for_mode(run_mode)))
	current_dungeon_tier = int(saved.get("dungeonTier", 1))
	current_dungeon_id = str(saved.get("dungeonId", DungeonCatalog.DEFAULT_DUNGEON_ID))
	if not DungeonCatalog.is_valid(current_dungeon_id):
		if DungeonCatalog.is_valid(current_biome_id):
			current_dungeon_id = current_biome_id
		else:
			current_dungeon_id = DungeonCatalog.DEFAULT_DUNGEON_ID
	current_biome_id = DungeonCatalog.get_biome_id(current_dungeon_id)
	_clear_floor_cache()
	var def: Variant = saved.get("dungeonDefinition", {})
	current_dungeon_definition = def if def is Dictionary else {}
	if current_dungeon_definition.is_empty():
		var regen := await _generate_dungeon(current_biome_id, current_seed, current_floor)
		if regen.get("ok", false):
			current_dungeon_definition = regen.get("definition", {})
	if not current_dungeon_definition.is_empty():
		_set_current_floor_cache(current_dungeon_definition)

	if current_dungeon_definition.is_empty():
		_is_continue = false
		_pending_snapshot.clear()
		LocalSave.clear_active_run()
		last_hub_message = "Saved run data was invalid."
		return_to_hub(last_hub_message)
		return

	_kill_count = int(_pending_snapshot.get("killCount", 0))
	_boss_defeated = bool(_pending_snapshot.get("bossDefeated", false))
	_loot_collected.clear()
	_loot_claimed_instance_ids.clear()
	for item in _pending_snapshot.get("lootCollected", []):
		_loot_collected.append(str(item))
	for inst_id in _pending_snapshot.get("lootClaimedInstanceIds", []):
		_loot_claimed_instance_ids.append(str(inst_id))

	_enter_run()


func _enter_run() -> void:
	var root := get_tree().root
	var definition_copy := current_dungeon_definition.duplicate(true)
	root.set_meta("dungeon_definition", definition_copy)
	root.set_meta("run_seed", current_seed)
	root.set_meta(
		"tier_generation_seed",
		DungeonSeedService.generation_seed(current_seed, current_dungeon_tier, current_floor)
	)
	root.set_meta("run_id", current_run_id)
	if _is_continue and not _pending_snapshot.is_empty():
		root.set_meta("run_snapshot", _pending_snapshot.duplicate(true))
	elif root.has_meta("run_snapshot"):
		root.remove_meta("run_snapshot")

	var active_run := {
		"schemaVersion": 4,
		"runMode": run_mode,
		"runId": current_run_id,
		"seed": current_seed,
		"biomeId": current_biome_id,
		"dungeonId": current_dungeon_id,
		"dungeonTier": current_dungeon_tier,
		"currentFloor": current_floor,
		"maxFloors": max_floors,
		"dungeonDefinition": definition_copy,
	}
	if _is_continue and not _pending_snapshot.is_empty():
		active_run["snapshot"] = _pending_snapshot.duplicate(true)
	LocalSave.set_active_run(active_run)

	_run_active = true
	_run_start_time = Time.get_ticks_msec() / 1000.0
	_register_run_started()
	_goto_scene(CASTLE_RUN_SCENE)
	run_started.emit()


func go_to_arena() -> void:
	_goto_scene(ARENA_SCENE)


func return_to_hub(message: String = "") -> void:
	if run_mode == RM.MODE_WAVES and _run_active:
		LocalSave.clear_waves_active_run()
		WavesRunService.begin_new_run()
	_run_active = false
	last_hub_message = message
	_clear_run_meta()
	LocalSave.autosave()
	_goto_scene(HUB_SCENE)
	returned_to_hub.emit(message)


func abandon_active_run() -> void:
	if not _run_active:
		return_to_hub("Returned to Aumbrye Tower.")
		return
	InventoryService.remove_run_loot(_loot_collected)
	RunBuffs.clear_all()
	LocalSave.clear_active_run()
	_run_active = false
	return_to_hub("Run abandoned. Loot from this run was lost.")


func complete_run_via_portal() -> void:
	if not _run_active:
		return
	if run_mode == RM.MODE_ENDLESS:
		push_warning("RunFlow: endless runs have no exit portal")
		return
	if current_floor < max_floors:
		push_warning("RunFlow: escape blocked until final floor is cleared")
		return
	_run_active = false
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, true)
	var xp_result := ProgressionService.grant_xp(full_xp, "escape")
	RunBuffs.clear_all()
	last_run_results = RunLifecycle.build_escape_results(
		elapsed,
		_kill_count,
		_loot_collected,
		xp_result,
		_escape_rules_summary()
	)
	var run_id := current_run_id
	var loot_instance_ids := _loot_claimed_instance_ids.duplicate()
	var boss := _boss_defeated
	var cleared_dungeon := current_dungeon_id
	LocalSave.clear_active_run()
	LocalSave.autosave()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_clear_run_meta()
	_handle_escape_meta(elapsed, boss)
	_cloud_finalize_run(run_id, "escaped", elapsed, boss, loot_instance_ids)
	if run_mode == RM.MODE_CASTLE:
		DungeonTierService.on_dungeon_cleared(cleared_dungeon)
	_goto_scene(RESULTS_SCENE)


func on_player_died() -> void:
	if get_tree().get_first_node_in_group("training_arena"):
		return
	var elapsed := 0.0
	if _run_start_time > 0.0:
		elapsed = (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, false)
	var death_xp := ProgressionService.apply_death_xp_fraction(full_xp)
	var xp_result := ProgressionService.grant_xp(death_xp, "death")
	_store_recoverable_xp_shard_from_active_run(full_xp - death_xp)
	InventoryService.remove_run_loot(_loot_collected)
	RunBuffs.clear_all()
	CharacterService.set_flag("deaths", int(CharacterService.get_flag("deaths", 0)) + 1)
	last_run_results = RunLifecycle.build_death_results(
		elapsed,
		_kill_count,
		_loot_collected,
		xp_result,
		full_xp,
		_death_rules_summary()
	)
	var run_id := current_run_id
	var loot_instance_ids := _loot_claimed_instance_ids.duplicate()
	var boss := _boss_defeated
	LocalSave.clear_active_run()
	LocalSave.autosave()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_run_active = false
	_clear_run_meta()
	_cloud_finalize_run(run_id, "died", elapsed, boss, loot_instance_ids)
	_goto_scene(RESULTS_SCENE)


func register_kill(enemy_id: String = "") -> void:
	_kill_count += 1
	QuestService.register_kill(enemy_id)


func register_boss_defeated() -> void:
	_boss_defeated = true


func rest_at_bonfire(player: Node = null) -> void:
	if player == null:
		player = get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var health := player.get_node_or_null("Health") as Health
	if health:
		health.reset_health()
	var stamina := player.get_node_or_null("Stamina") as Stamina
	if stamina:
		stamina.reset_stamina()
	var heal := player.get_node_or_null("PlayerHeal")
	if heal and heal.has_method("refill_charges"):
		heal.call("refill_charges")
	for enemy in get_tree().get_nodes_in_group("enemy"):
		if enemy.has_method("respawn_at_rest"):
			enemy.call("respawn_at_rest")


func get_current_floor() -> int:
	return current_floor


func get_max_floors() -> int:
	return max_floors


func is_final_floor() -> bool:
	return RunFloorConfig.is_final_floor(current_floor, run_mode)


func can_escape_run() -> bool:
	if run_mode == RM.MODE_ENDLESS:
		return false
	return _boss_defeated and is_final_floor()


func can_retreat_to_hub() -> bool:
	if not _run_active or not _boss_defeated:
		return false
	return run_mode == RM.MODE_ENDLESS or run_mode == RM.MODE_CASTLE


func retreat_to_hub() -> void:
	if not can_retreat_to_hub():
		return
	var castle := get_tree().get_first_node_in_group("castle_run")
	if castle and castle.has_method("_persist_snapshot"):
		castle.call("_persist_snapshot")
	var active := LocalSave.get_active_run()
	if not active.is_empty():
		active["currentFloor"] = current_floor
		active["dungeonTier"] = current_dungeon_tier
		active["dungeonId"] = current_dungeon_id
		active["dungeonDefinition"] = current_dungeon_definition.duplicate(true)
		LocalSave.set_active_run(active)
	_run_active = false
	last_hub_message = "Retreated to %s. Continue from the portal." % TOWER_DISPLAY_NAME
	_clear_run_meta()
	LocalSave.autosave()
	_goto_scene(HUB_SCENE)
	returned_to_hub.emit(last_hub_message)


func get_dungeon_tier() -> int:
	return current_dungeon_tier


func get_dungeon_id() -> String:
	return current_dungeon_id


func get_run_mode() -> String:
	return run_mode


func ascend_floor() -> void:
	if not _run_active or not _boss_defeated:
		return
	if run_mode == RM.MODE_CASTLE and current_floor >= max_floors:
		return
	_stash_current_floor_in_cache()
	current_floor += 1
	_boss_defeated = false
	await _transition_floor(true)


func descend_floor() -> void:
	if not _run_active or current_floor <= 1:
		return
	if run_mode == RM.MODE_ENDLESS:
		return
	_stash_current_floor_in_cache()
	current_floor -= 1
	_boss_defeated = true
	await _transition_floor(false)


func _transition_floor(ascending: bool) -> void:
	current_dungeon_definition = {}
	var cached := _get_cached_floor_definition(current_floor)
	if not cached.is_empty():
		current_dungeon_definition = cached
	else:
		var gen := await _generate_dungeon(current_biome_id, current_seed, current_floor)
		if gen.get("ok", false):
			current_dungeon_definition = gen.get("definition", {})
		else:
			last_hub_message = "Could not generate floor %d." % current_floor
			if ascending:
				current_floor -= 1
			else:
				current_floor += 1
			return
	_set_current_floor_cache(current_dungeon_definition)

	var root := get_tree().root
	root.set_meta("dungeon_definition", current_dungeon_definition.duplicate(true))
	root.set_meta("floor_transition", {
		"ascending": ascending,
		"floor": current_floor,
	})
	root.set_meta("run_snapshot", _build_floor_transition_snapshot(ascending))
	_persist_active_run()
	_goto_scene(CASTLE_RUN_SCENE)


func _build_floor_transition_snapshot(ascending: bool) -> Dictionary:
	return {
		"floorTransition": true,
		"ascending": ascending,
		"currentFloor": current_floor,
		"bossDefeated": _boss_defeated,
		"killCount": _kill_count,
		"lootCollected": _loot_collected.duplicate(),
		"lootClaimedInstanceIds": _loot_claimed_instance_ids.duplicate(),
	}


func _persist_active_run() -> void:
	var active := LocalSave.get_active_run()
	if active.is_empty():
		active = {
			"schemaVersion": 4,
			"runMode": run_mode,
			"runId": current_run_id,
			"seed": current_seed,
			"biomeId": current_biome_id,
		}
	active["runMode"] = run_mode
	active["currentFloor"] = current_floor
	active["dungeonTier"] = current_dungeon_tier
	active["dungeonId"] = current_dungeon_id
	active["maxFloors"] = max_floors
	active["dungeonDefinition"] = current_dungeon_definition.duplicate(true)
	LocalSave.set_active_run(active)


func _clear_floor_cache() -> void:
	floor_definitions.clear()
	DungeonBuilder.clear_floor_cache()


func _stash_current_floor_in_cache() -> void:
	if current_dungeon_definition.is_empty():
		return
	floor_definitions[str(current_floor)] = current_dungeon_definition.duplicate(true)
	DungeonBuilder.store_floor_cache(current_floor, current_dungeon_definition)
	_trim_floor_cache()


func _get_cached_floor_definition(floor_index: int) -> Dictionary:
	var key := str(floor_index)
	if floor_definitions.has(key):
		return floor_definitions[key].duplicate(true)
	return DungeonBuilder.get_floor_cache(floor_index)


func _trim_floor_cache() -> void:
	if floor_definitions.size() <= MAX_CACHED_FLOORS:
		return
	var keys: Array = floor_definitions.keys()
	keys.sort()
	while floor_definitions.size() > MAX_CACHED_FLOORS:
		var drop_key: String = keys[0]
		floor_definitions.erase(drop_key)
		keys.remove_at(0)


func _set_current_floor_cache(definition: Dictionary) -> void:
	if definition.is_empty():
		return
	floor_definitions[str(current_floor)] = definition.duplicate(true)
	DungeonBuilder.store_floor_cache(current_floor, definition)
	_trim_floor_cache()


func _unload_current_floor_chunk() -> void:
	current_dungeon_definition = {}
	var root := get_tree().root
	if root.has_meta("dungeon_definition"):
		root.remove_meta("dungeon_definition")


func register_loot(item_id: String, instance_id: String = "") -> void:
	if item_id not in _loot_collected:
		_loot_collected.append(item_id)
	if instance_id != "" and instance_id not in _loot_claimed_instance_ids:
		_loot_claimed_instance_ids.append(instance_id)


func get_loot_claimed_instance_ids() -> Array[String]:
	return _loot_claimed_instance_ids.duplicate()


func get_kill_count() -> int:
	return _kill_count


func get_loot_collected() -> Array[String]:
	return _loot_collected.duplicate()


func is_run_active() -> bool:
	return _run_active


func is_continue_restore() -> bool:
	return _is_continue


func clear_continue_restore() -> void:
	_is_continue = false
	_pending_snapshot.clear()


func _resolve_dungeon_id(dungeon_id: String) -> String:
	if DungeonCatalog.is_valid(dungeon_id):
		return dungeon_id
	for entry in DungeonCatalog.ENTRIES:
		if str(entry.get("biomeId", "")) == dungeon_id:
			return str(entry.get("id", ""))
	return DungeonCatalog.DEFAULT_DUNGEON_ID


func _reset_run_stats() -> void:
	_kill_count = 0
	_boss_defeated = false
	_loot_collected.clear()
	_loot_claimed_instance_ids.clear()
	current_floor = 1
	current_dungeon_tier = 1
	current_dungeon_id = DungeonCatalog.DEFAULT_DUNGEON_ID
	_clear_floor_cache()


func _cloud_finalize_run(
	run_id: String,
	outcome: String,
	elapsed: float,
	boss_defeated: bool,
	loot_instance_ids: Array
) -> void:
	if run_id != "":
		var result := await ApiClient.complete_run(
			run_id, outcome, elapsed, boss_defeated, loot_instance_ids
		)
		if not result.get("ok", false):
			var err := str(result.get("error", "unknown"))
			if err != "auth failed":
				push_warning("RunFlow: complete_run failed — %s" % err)
	var push := await LocalSave.push_to_cloud()
	if not push.get("ok", false) and not push.get("conflict", false):
		var push_err := str(push.get("error", "unknown"))
		if push_err != "auth failed":
			push_warning("RunFlow: cloud push failed — %s" % push_err)


func _handle_escape_meta(elapsed: float, boss_defeated: bool) -> void:
	if not boss_defeated:
		return
	if AchievementService:
		AchievementService.unlock("boss_slayer")
		AchievementService.unlock_for_biome_clear(current_biome_id)
		if max_floors >= RunFloorConfig.MAX_FLOORS and current_floor >= max_floors:
			AchievementService.unlock("ten_floor_clear")
		if elapsed < SPEED_CLEAR_MAX_SECONDS:
			AchievementService.unlock("speed_clear")
	LeaderboardSettings.load_from_save()
	if LeaderboardSettings.opt_in:
		var lb := await ApiClient.submit_leaderboard(
			current_biome_id, current_floor, elapsed, true
		)
		if lb.get("ok", false) and AchievementService:
			AchievementService.unlock("leaderboard_submit")


func _escape_rules_summary() -> String:
	return (
		"Escaped alive: kept all loot and full XP. "
		+ "The tower releases you — your echo returns to Aumbrye Tower with proof of the oath."
	)


func _death_rules_summary() -> String:
	return (
		"The tower pulls you back: 50% XP saved, the rest lingers as a recoverable echo at your death spot. "
		+ "Run loot and relics are lost. Your echo wakes in Aumbrye Tower — the ascent begins again."
	)


func store_recoverable_xp_shard(world_pos: Vector3, floor_index: int, dungeon_id: String, xp_amount: int) -> void:
	if xp_amount <= 0:
		return
	CharacterService.set_flag(XP_SHARD_FLAG, {
		"x": world_pos.x,
		"y": world_pos.y,
		"z": world_pos.z,
		"floor": floor_index,
		"dungeonId": dungeon_id,
		"xp": xp_amount,
	})


func get_recoverable_xp_shard() -> Dictionary:
	var shard: Variant = CharacterService.get_flag(XP_SHARD_FLAG, {})
	return shard if shard is Dictionary and not shard.is_empty() else {}


func clear_recoverable_xp_shard() -> void:
	if get_recoverable_xp_shard().is_empty():
		return
	CharacterService.set_flag(XP_SHARD_FLAG, {})


func _store_recoverable_xp_shard_from_active_run(xp_amount: int) -> void:
	if xp_amount <= 0:
		return
	var active := LocalSave.get_active_run()
	var snapshot: Variant = active.get("snapshot", {})
	if not snapshot is Dictionary:
		return
	var player: Variant = snapshot.get("player", {})
	if not player is Dictionary or player.is_empty():
		return
	store_recoverable_xp_shard(
		Vector3(
			float(player.get("x", 0.0)),
			float(player.get("y", 0.0)),
			float(player.get("z", 0.0))
		),
		current_floor,
		current_dungeon_id,
		xp_amount
	)


func _register_run_started() -> void:
	CharacterService.set_flag("runs_started", int(CharacterService.get_flag("runs_started", 0)) + 1)


func _clear_run_meta() -> void:
	var root := get_tree().root
	if root.has_meta("dungeon_definition"):
		root.remove_meta("dungeon_definition")
	if root.has_meta("run_seed"):
		root.remove_meta("run_seed")
	if root.has_meta("tier_generation_seed"):
		root.remove_meta("tier_generation_seed")
	if root.has_meta("run_id"):
		root.remove_meta("run_id")
	if root.has_meta("run_snapshot"):
		root.remove_meta("run_snapshot")


func _goto_scene(path: String) -> void:
	RunSceneRouter.goto_scene(get_tree(), path)


func _start_waves_run(is_continue: bool) -> void:
	run_mode = RM.MODE_WAVES
	_is_continue = is_continue
	_run_active = true
	_run_start_time = Time.get_ticks_msec() / 1000.0
	if is_continue:
		var saved := LocalSave.get_waves_active_run()
		_pending_snapshot = saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
		WavesRunService.restore_from_save(saved)
	else:
		_pending_snapshot.clear()
		WavesRunService.begin_new_run()
	var root := get_tree().root
	if _is_continue and not _pending_snapshot.is_empty():
		root.set_meta("run_snapshot", _pending_snapshot.duplicate(true))
	elif root.has_meta("run_snapshot"):
		root.remove_meta("run_snapshot")
	_goto_scene(WAVES_RUN_SCENE)
	_register_run_started()
	run_started.emit()


func quit_waves_run() -> void:
	if run_mode != RM.MODE_WAVES:
		return
	var wave := WavesRunService.current_wave
	var keep_fraction := WavesRunService.get_early_exit_keep_fraction()
	var kept_items: Array[String] = []
	if keep_fraction > 0.0:
		kept_items = WavesRunService.transfer_early_exit_items(keep_fraction)
	LocalSave.clear_waves_active_run()
	WavesRunService.begin_new_run()
	_run_active = false
	if keep_fraction > 0.0 and not kept_items.is_empty():
		last_hub_message = (
			"Left waves at wave %d — kept %d item(s) (%d%% milestone transfer)."
			% [wave, kept_items.size(), int(round(keep_fraction * 100.0))]
		)
	else:
		last_hub_message = "Left waves early — loadout was not kept."
	_clear_run_meta()
	return_to_hub(last_hub_message)


func complete_waves_run(rewards: Array[String]) -> void:
	_run_active = false
	var elapsed := (Time.get_ticks_msec() / 1000.0) - _run_start_time
	for item_id in rewards:
		InventoryService.add_item(item_id, 1)
	last_run_results = {
		"outcome": "waves_complete",
		"time_seconds": elapsed,
		"kills": WavesRunService.get_kill_count(),
		"loot": rewards.duplicate(),
		"xp_gained": ProgressionService.grant_xp(WAVES_COMPLETION_XP, "waves").get("gained", 0),
		"levels_gained": 0,
		"loot_kept": true,
		"run_relics_lost": false,
		"rules_summary": "Waves cleared: kept up to 3 chosen items.",
	}
	LocalSave.clear_waves_active_run()
	LocalSave.autosave()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_clear_run_meta()
	_goto_scene(RESULTS_SCENE)


func on_waves_failed() -> void:
	var elapsed := 0.0
	if _run_start_time > 0.0:
		elapsed = (Time.get_ticks_msec() / 1000.0) - _run_start_time
	last_run_results = {
		"outcome": "waves_failed",
		"time_seconds": elapsed,
		"kills": WavesRunService.get_kill_count(),
		"loot": [],
		"xp_gained": 0,
		"levels_gained": 0,
		"loot_kept": false,
		"rules_summary": "Waves failed: no items transferred to main inventory.",
	}
	LocalSave.clear_waves_active_run()
	LocalSave.autosave()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_run_active = false
	_clear_run_meta()
	_goto_scene(RESULTS_SCENE)
