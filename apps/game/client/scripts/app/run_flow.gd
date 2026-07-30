extends Node

## Autoload — hub ↔ dungeon ↔ results flow (FLOW-2.1 / FLOW-3.1).
## Dungeon generation is fully offline via LocalProcgen + procgen-cli.

signal run_started
signal run_ended(results: Dictionary)
signal returned_to_hub(message: String)

const HUB_SCENE := "res://scenes/hub/hub_stub.tscn"
const CASTLE_RUN_SCENE := "res://scenes/dungeon/castle_run.tscn"
const ARENA_SCENE := "res://scenes/debug/combat_arena.tscn"
const RESULTS_SCENE := "res://scenes/ui/results_screen.tscn"
const DEFAULT_BIOME := "forgotten_castle"

var last_hub_message := ""
var last_run_results: Dictionary = {}
var current_run_id: String = ""
var current_dungeon_definition: Dictionary = {}
var current_seed: int = 0
var _run_active := false
var _run_start_time := 0.0
var _kill_count := 0
var _loot_collected: Array[String] = []
var _pending_snapshot: Dictionary = {}
var _is_continue := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_new_castle_run() -> void:
	_start_castle_run(null)


func start_castle_run_with_seed(run_seed_value: int) -> void:
	_start_castle_run(run_seed_value)


func continue_castle_run() -> void:
	var saved := LocalSave.get_active_run()
	if not LocalSave.has_continuable_run():
		last_hub_message = "No saved castle run to continue."
		return
	_is_continue = true
	_pending_snapshot = saved.get("snapshot", {}) if saved.get("snapshot", {}) is Dictionary else {}
	_restore_castle_run(saved)


## Back-compat alias.
func start_castle_run() -> void:
	start_new_castle_run()


func _start_castle_run(run_seed: Variant) -> void:
	_is_continue = false
	_pending_snapshot.clear()
	_reset_run_stats()
	current_dungeon_definition = {}
	current_run_id = ""
	current_seed = 0

	var gen := LocalProcgen.generate(DEFAULT_BIOME, run_seed)
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

	_enter_castle_run()


func _restore_castle_run(saved: Dictionary) -> void:
	current_run_id = str(saved.get("runId", ""))
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
	_loot_collected.clear()
	for item in _pending_snapshot.get("lootCollected", []):
		_loot_collected.append(str(item))

	_enter_castle_run()


func _enter_castle_run() -> void:
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
		"biomeId": DEFAULT_BIOME,
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
	last_run_results = {
		"time_seconds": elapsed,
		"kills": _kill_count,
		"loot": _loot_collected.duplicate(),
	}
	LocalSave.clear_active_run()
	LocalSave.autosave()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_clear_run_meta()
	_goto_scene(RESULTS_SCENE)


func on_player_died() -> void:
	LocalSave.clear_active_run()
	return_to_hub("You fell in the castle. Returned to the hub.")


func register_kill() -> void:
	_kill_count += 1


func register_loot(item_id: String) -> void:
	if item_id not in _loot_collected:
		_loot_collected.append(item_id)


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
	_loot_collected.clear()


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
