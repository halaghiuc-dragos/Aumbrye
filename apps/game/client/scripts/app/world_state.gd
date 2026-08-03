extends Node

## Run-scoped flags for dungeon locks, levers, keys, and room content (not persisted).

signal flag_changed(flag_id: String, value: Variant)

var _flags: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RunFlow.run_started.connect(_on_run_started)
	RunFlow.run_ended.connect(_on_run_ended)


func reset() -> void:
	_flags.clear()


func set_flag(flag_id: String, value: Variant = true) -> void:
	_flags[flag_id] = value
	flag_changed.emit(flag_id, value)


func has_flag(flag_id: String) -> bool:
	return bool(_flags.get(flag_id, false))


func get_flag(flag_id: String, default_value: Variant = false) -> Variant:
	return _flags.get(flag_id, default_value)


func all_flags() -> Dictionary:
	return _flags.duplicate()


func _on_run_started() -> void:
	reset()
	InventoryService.clear_dungeon_keys()


func _on_run_ended(_results: Dictionary) -> void:
	reset()
