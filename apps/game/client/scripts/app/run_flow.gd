extends Node

## Autoload — hub ↔ dungeon ↔ results flow (FLOW-2.1 / FLOW-4.1).

signal run_started
signal run_ended(results: Dictionary)
signal returned_to_hub(message: String)

const HUB_SCENE := "res://scenes/hub/hub.tscn"
const CASTLE_RUN_SCENE := "res://scenes/dungeon/castle_run.tscn"
const ARENA_SCENE := "res://scenes/debug/combat_arena.tscn"
const RESULTS_SCENE := "res://scenes/ui/results_screen.tscn"
const DEFAULT_BIOME := "forgotten_castle"
const USE_ONLINE_PROCgen := false

var current_biome_id: String = DEFAULT_BIOME

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


func start_new_run(biome_id: String, run_seed: Variant = null) -> void:
	_start_run(biome_id, run_seed)


func start_castle_run_with_seed(run_seed_value: int) -> void:
	start_run_with_seed(DEFAULT_BIOME, run_seed_value)


func start_run_with_seed(biome_id: String, run_seed_value: int) -> void:
	_start_run(biome_id, run_seed_value)


func continue_castle_run() -> void:
	var saved := LocalSave.get_active_run()
	if not LocalSave.has_continuable_run():
		last_hub_message = "No saved castle run to continue."
		return
	_is_continue = true
	_pending_snapshot = saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
	_restore_castle_run(saved)


func start_castle_run() -> void:
	start_new_castle_run()


func _start_run(biome_id: String, run_seed: Variant) -> void:
	_is_continue = false
	_pending_snapshot.clear()
	_reset_run_stats()
	current_dungeon_definition = {}
	current_run_id = ""
	current_seed = 0
	current_biome_id = biome_id

	var gen := await _generate_dungeon(biome_id, run_seed)
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

	if current_dungeon_definition.is_empty():
		last_hub_message = "Failed to load dungeon definition."
		return_to_hub(last_hub_message)
		return

	_enter_run()


func _generate_dungeon(biome_id: String, run_seed: Variant) -> Dictionary:
	if USE_ONLINE_PROCgen and ApiConfig.get_base_url() != "":
		var online := await _try_online_generate(biome_id, run_seed)
		if online.get("ok", false):
			return online
	return LocalProcgen.generate(biome_id, run_seed)


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
	var def: Variant = saved.get("dungeonDefinition", {})
	current_dungeon_definition = def if def is Dictionary else {}

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
		"schemaVersion": 2,
		"runId": current_run_id,
		"seed": current_seed,
		"biomeId": current_biome_id,
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
