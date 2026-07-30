extends Node

## Autoload — hub ↔ dungeon ↔ results flow (FLOW-2.1).

signal run_started
signal run_ended(results: Dictionary)
signal returned_to_hub(message: String)

const HUB_SCENE := "res://scenes/hub/hub_stub.tscn"
const CASTLE_RUN_SCENE := "res://scenes/dungeon/castle_run.tscn"
const ARENA_SCENE := "res://scenes/debug/combat_arena.tscn"
const RESULTS_SCENE := "res://scenes/ui/results_screen.tscn"

var last_hub_message := ""
var last_run_results: Dictionary = {}
var _run_active := false
var _run_start_time := 0.0
var _kill_count := 0
var _loot_collected: Array[String] = []


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS


func start_castle_run() -> void:
	_reset_run_stats()
	_run_active = true
	_run_start_time = Time.get_ticks_msec() / 1000.0
	_goto_scene(CASTLE_RUN_SCENE)
	run_started.emit()


func go_to_arena() -> void:
	_goto_scene(ARENA_SCENE)


func return_to_hub(message: String = "") -> void:
	_run_active = false
	last_hub_message = message
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
	LocalSave.autosave()
	run_ended.emit(last_run_results)
	get_tree().root.set_meta("run_results", last_run_results)
	_goto_scene(RESULTS_SCENE)


func on_player_died() -> void:
	return_to_hub("You fell in the castle. Returned to the hub.")


func register_kill() -> void:
	_kill_count += 1


func register_loot(item_id: String) -> void:
	if item_id not in _loot_collected:
		_loot_collected.append(item_id)


func is_run_active() -> bool:
	return _run_active


func _reset_run_stats() -> void:
	_kill_count = 0
	_loot_collected.clear()


func _goto_scene(path: String) -> void:
	get_tree().call_deferred("change_scene_to_file", path)
