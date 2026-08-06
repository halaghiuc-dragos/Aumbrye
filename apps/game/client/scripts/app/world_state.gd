extends Node

## Run-scoped flags for dungeon locks, levers, keys, and room content (not persisted).

signal flag_changed(flag_id: String, value: Variant)
signal namespace_changed(flag_namespace: String, flag_id: String, value: Variant)

var _flags: Dictionary = {}


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	RunFlow.run_started.connect(_on_run_started)
	RunFlow.run_ended.connect(_on_run_ended)
	RunFlow.returned_to_hub.connect(_on_returned_to_hub)


func reset() -> void:
	_flags.clear()


func set_flag(flag_id: String, value: Variant = true) -> void:
	if not WorldFlags.is_valid_id(flag_id):
		if OS.is_debug_build():
			push_error("WorldState: invalid flag id %r" % flag_id)
		else:
			push_warning("WorldState: invalid flag id %r" % flag_id)
		return
	var stored: Variant = _deep_copy_value(value)
	_flags[flag_id] = stored
	flag_changed.emit(flag_id, stored)
	namespace_changed.emit(flag_id.split(".")[0], flag_id, stored)


func has_flag(flag_id: String) -> bool:
	return _flags.has(flag_id)


func is_flag_true(flag_id: String) -> bool:
	return bool(_flags.get(flag_id, false))


func get_flag(flag_id: String, default_value: Variant = null) -> Variant:
	return _flags.get(flag_id, default_value)


func erase_flag(flag_id: String) -> bool:
	if not _flags.has(flag_id):
		return false
	_flags.erase(flag_id)
	flag_changed.emit(flag_id, null)
	namespace_changed.emit(flag_id.split(".")[0], flag_id, null)
	return true


func all_flags() -> Dictionary:
	return _flags.duplicate(true)


func restore_flags(flags: Dictionary) -> int:
	_flags.clear()
	var rejected := 0
	for flag_id in flags:
		var key := str(flag_id)
		if not WorldFlags.is_valid_id(key):
			rejected += 1
			continue
		var sanitized: Variant = _sanitize_value(flags[flag_id])
		if sanitized == null and not _is_scalar(flags[flag_id]):
			rejected += 1
			continue
		_flags[key] = sanitized
	if rejected > 0:
		push_warning("WorldState: dropped %d invalid flag(s) from snapshot" % rejected)
	return rejected


func _on_run_started() -> void:
	if RunFlow.is_continue_restore():
		return
	reset()
	InventoryService.clear_dungeon_keys()


func _on_run_ended(_results: Dictionary) -> void:
	reset()


func _on_returned_to_hub(_message: String) -> void:
	reset()


static func _is_scalar(value: Variant) -> bool:
	return value is bool or value is int or value is float or value is String


static func _sanitize_value(value: Variant) -> Variant:
	if _is_scalar(value):
		return value
	if value is Array:
		var out: Array = []
		for item in value:
			if not _is_scalar(item):
				return null
			out.append(item)
		return out
	if value is Dictionary:
		var out: Dictionary = {}
		for raw_key in value:
			var entry: Variant = value[raw_key]
			if not _is_scalar(entry):
				return null
			out[str(raw_key)] = entry
		return out
	return null


static func _deep_copy_value(value: Variant) -> Variant:
	if value is Dictionary or value is Array:
		return value.duplicate(true)
	return value
