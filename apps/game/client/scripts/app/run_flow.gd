extends Node

## Autoload — hub ↔ dungeon ↔ results flow (FLOW-2.1 / FLOW-4.1).

signal run_started
signal run_ended(results: Dictionary)
signal returned_to_hub(message: String)

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const CASTLE_RUN_SCENE := "res://scenes/dungeon/castle_run.tscn"
const WAVES_RUN_SCENE := "res://scenes/dungeon/waves_run.tscn"
const ARENA_SCENE := "res://scenes/debug/combat_arena.tscn"
const RESULTS_SCENE := "res://scenes/ui/results_screen.tscn"
const DEFAULT_BIOME := "forgotten_castle"
const USE_ONLINE_PROCgen := false

const RM := preload("res://scripts/app/run_mode_config.gd")
const SkipFloorSvc := preload("res://scripts/dungeon/skip_floor_service.gd")

var run_mode: String = "castle"

var current_biome_id: String = DEFAULT_BIOME
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


func start_new_castle_run() -> void:
	start_new_run(DEFAULT_BIOME)


func start_endless_run(start_floor: int = 1, skip_item_id: String = "") -> void:
	if skip_item_id != "":
		SkipFloorSvc.consume_skip(InventoryService.inventory, skip_item_id)
		start_floor = SkipFloorSvc.start_floor_for_item(skip_item_id)
	await _start_mode_run(RM.MODE_ENDLESS, DEFAULT_BIOME, null, start_floor)


func start_waves_run() -> void:
	_start_waves_run(false)


func continue_waves_run() -> void:
	_start_waves_run(true)


func start_new_run(biome_id: String, run_seed: Variant = null) -> void:
	await _start_mode_run(RM.MODE_CASTLE, biome_id, run_seed, 1)


func start_castle_run_with_seed(run_seed_value: int) -> void:
	start_run_with_seed(DEFAULT_BIOME, run_seed_value)


func start_run_with_seed(biome_id: String, run_seed_value: int) -> void:
	await _start_mode_run(RM.MODE_CASTLE, biome_id, run_seed_value, 1)


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
		current_seed = int(run_seed)
	else:
		current_seed = int(gen.get("generation_seed", gen.get("input_seed", 0)))
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
	return LocalProcgen.generate(biome_id, run_seed, floor_index, run_mode)


func _try_online_generate(biome_id: String, run_seed: Variant) -> Dictionary:
	var create := await ApiClient.create_run(biome_id, run_seed)
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
		"currentFloor": current_floor,
		"maxFloors": max_floors,
		"dungeonDefinition": definition_copy,
	}
	if _is_continue and not _pending_snapshot.is_empty():
		active_run["snapshot"] = _pending_snapshot.duplicate(true)
	LocalSave.set_active_run(active_run)

	_run_active = true
	_run_start_time = Time.get_ticks_msec() / 1000.0
	_goto_scene(CASTLE_RUN_SCENE)
	run_started.emit()


func go_to_arena() -> void:
	_goto_scene(ARENA_SCENE)


func return_to_hub(message: String = "") -> void:
	_run_active = false
	last_hub_message = message
	_clear_run_meta()
	LocalSave.autosave()
	_goto_scene(HUB_SCENE)
	returned_to_hub.emit(message)


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
	last_run_results = {
		"outcome": "escaped",
		"time_seconds": elapsed,
		"kills": _kill_count,
		"loot": _loot_collected.duplicate(),
		"xp_gained": xp_result.get("gained", 0),
		"levels_gained": xp_result.get("levels_gained", 0),
		"loot_kept": true,
		"run_relics_lost": false,
		"rules_summary": _escape_rules_summary(),
	}
	var run_id := current_run_id
	var loot_instance_ids := _loot_claimed_instance_ids.duplicate()
	var boss := _boss_defeated
	LocalSave.clear_active_run()
	LocalSave.autosave()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_clear_run_meta()
	_handle_escape_meta(elapsed, boss)
	_cloud_finalize_run(run_id, "escaped", elapsed, boss, loot_instance_ids)
	_goto_scene(RESULTS_SCENE)


func on_player_died() -> void:
	var elapsed := 0.0
	if _run_start_time > 0.0:
		elapsed = (Time.get_ticks_msec() / 1000.0) - _run_start_time
	var full_xp := ProgressionService.calculate_run_xp(_kill_count, _boss_defeated, false)
	var death_xp := ProgressionService.apply_death_xp_fraction(full_xp)
	var xp_result := ProgressionService.grant_xp(death_xp, "death")
	InventoryService.remove_run_loot(_loot_collected)
	RunBuffs.clear_all()
	last_run_results = {
		"outcome": "died",
		"time_seconds": elapsed,
		"kills": _kill_count,
		"loot": _loot_collected.duplicate(),
		"xp_gained": xp_result.get("gained", 0),
		"xp_full_would_be": full_xp,
		"levels_gained": xp_result.get("levels_gained", 0),
		"loot_kept": false,
		"run_relics_lost": true,
		"rules_summary": _death_rules_summary(),
	}
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
		active["dungeonDefinition"] = current_dungeon_definition.duplicate(true)
		LocalSave.set_active_run(active)
	_run_active = false
	last_hub_message = "Retreated to hub. Continue from the portal."
	_clear_run_meta()
	LocalSave.autosave()
	_goto_scene(HUB_SCENE)
	returned_to_hub.emit(last_hub_message)


func get_run_mode() -> String:
	return run_mode


func ascend_floor() -> void:
	if not _run_active or not _boss_defeated:
		return
	if run_mode == RM.MODE_CASTLE and current_floor >= max_floors:
		return
	current_floor += 1
	_boss_defeated = false
	await _transition_floor(true)


func descend_floor() -> void:
	if not _run_active or current_floor <= 1:
		return
	if run_mode == RM.MODE_ENDLESS:
		return
	current_floor -= 1
	_boss_defeated = true
	await _transition_floor(false)


func _transition_floor(ascending: bool) -> void:
	_unload_current_floor_chunk()
	var floor_key := str(current_floor)
	current_dungeon_definition = {}
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
	active["maxFloors"] = max_floors
	active["dungeonDefinition"] = current_dungeon_definition.duplicate(true)
	LocalSave.set_active_run(active)


func _clear_floor_cache() -> void:
	floor_definitions.clear()


func _set_current_floor_cache(definition: Dictionary) -> void:
	_clear_floor_cache()
	if definition.is_empty():
		return
	floor_definitions[str(current_floor)] = definition.duplicate(true)


func _unload_current_floor_chunk() -> void:
	_clear_floor_cache()
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


func _reset_run_stats() -> void:
	_kill_count = 0
	_boss_defeated = false
	_loot_collected.clear()
	_loot_claimed_instance_ids.clear()
	current_floor = 1
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
			push_warning("RunFlow: complete_run failed — %s" % result.get("error", "unknown"))
	var push := await LocalSave.push_to_cloud()
	if not push.get("ok", false) and not push.get("conflict", false):
		push_warning("RunFlow: cloud push failed — %s" % push.get("error", "unknown"))


func _handle_escape_meta(elapsed: float, boss_defeated: bool) -> void:
	if not boss_defeated:
		return
	if AchievementService:
		AchievementService.unlock("boss_slayer")
		AchievementService.unlock_for_biome_clear(current_biome_id)
		if max_floors >= RunFloorConfig.MAX_FLOORS and current_floor >= max_floors:
			AchievementService.unlock("ten_floor_clear")
		if elapsed < 900.0:
			AchievementService.unlock("speed_clear")
	LeaderboardSettings.load_from_save()
	if LeaderboardSettings.opt_in:
		var lb := await ApiClient.submit_leaderboard(
			current_biome_id, current_floor, elapsed, true
		)
		if lb.get("ok", false) and AchievementService:
			AchievementService.unlock("leaderboard_submit")


func _escape_rules_summary() -> String:
	return "Escaped: kept all loot, full XP, run relics cleared."


func _death_rules_summary() -> String:
	return "Died: kept 50% XP, lost run loot & relics. Prior gear safe."


func _clear_run_meta() -> void:
	var root := get_tree().root
	if root.has_meta("dungeon_definition"):
		root.remove_meta("dungeon_definition")
	if root.has_meta("run_seed"):
		root.remove_meta("run_seed")
	if root.has_meta("run_id"):
		root.remove_meta("run_id")
	if root.has_meta("run_snapshot"):
		root.remove_meta("run_snapshot")


func _goto_scene(path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", path)


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
	_goto_scene(WAVES_RUN_SCENE)
	run_started.emit()


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
		"xp_gained": ProgressionService.grant_xp(500, "waves").get("gained", 0),
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
