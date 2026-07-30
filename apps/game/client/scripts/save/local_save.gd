extends Node

## Autoload — local JSON save to user:// (SAVE-2.1).

const SAVE_PATH := "user://aumbrye_save.json"
const SAVE_SCHEMA_VERSION := 1

signal save_loaded
signal save_failed(reason: String)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_into_services() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var raw_text := _read_raw_text()
	if raw_text.strip_edges().is_empty():
		_handle_corrupt_save("empty_file")
		return false
	var parsed = JSON.parse_string(raw_text)
	if parsed == null or not parsed is Dictionary:
		_handle_corrupt_save("corrupt_json")
		return false
	var data: Dictionary = parsed
	if not _validate_save(data):
		_handle_corrupt_save("corrupt_schema")
		return false
	InventoryService.apply_save_inventory(data.get("inventory", {}))
	_apply_character_preferences(data.get("character", {}))
	var active: Variant = data.get("activeRun", {})
	_cached_active_run = active if active is Dictionary else {}
	save_loaded.emit()
	return true


var _cached_active_run: Dictionary = {}
var _first_person_camera := false


func _ready() -> void:
	_load_preferences_from_disk()


func is_first_person_camera() -> bool:
	return _first_person_camera


func set_first_person_camera(enabled: bool) -> void:
	if _first_person_camera == enabled:
		return
	_first_person_camera = enabled
	autosave()


func _load_preferences_from_disk() -> void:
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var parsed = JSON.parse_string(_read_raw_text())
	if parsed is Dictionary:
		_apply_character_preferences(parsed.get("character", {}))


func _apply_character_preferences(character: Variant) -> void:
	if character is Dictionary:
		_first_person_camera = bool(character.get("firstPersonCamera", false))


func has_continuable_run() -> bool:
	var run := get_active_run()
	if run.is_empty():
		return false
	if run.get("playerDead", false):
		return false
	var snapshot: Variant = run.get("snapshot", {})
	if not snapshot is Dictionary or snapshot.is_empty():
		return false
	var player_state: Dictionary = snapshot.get("player", {})
	if player_state.has("health") and float(player_state.get("health", 1.0)) <= 0.0:
		return false
	return true


func get_active_run() -> Dictionary:
	return _cached_active_run.duplicate(true)


func set_active_run(data: Dictionary) -> void:
	_cached_active_run = data.duplicate(true)
	autosave()


func clear_active_run() -> void:
	if _cached_active_run.is_empty():
		return
	_cached_active_run.clear()
	autosave()


func autosave() -> void:
	var data := {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"character": _build_character_state(),
		"inventory": InventoryService.get_save_inventory(),
	}
	if not _cached_active_run.is_empty():
		data["activeRun"] = _cached_active_run.duplicate(true)
	_write_save(data)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _build_character_state() -> Dictionary:
	return {
		"name": "Wanderer",
		"level": 1,
		"lastHubMessage": RunFlow.last_hub_message,
		"firstPersonCamera": _first_person_camera,
	}


func _validate_save(data: Dictionary) -> bool:
	if data.get("schemaVersion", 0) != SAVE_SCHEMA_VERSION:
		return false
	if not data.has("inventory"):
		return false
	var inv: Dictionary = data.get("inventory", {})
	if inv.get("schemaVersion", 0) != 1:
		return false
	return true


func _reset_to_defaults() -> void:
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("castle_sword", 1)
	_cached_active_run.clear()


func _handle_corrupt_save(reason: String) -> void:
	save_failed.emit(reason)
	push_warning("LocalSave: %s — starting fresh" % reason)
	_reset_to_defaults()


func _read_raw_text() -> String:
	if not FileAccess.file_exists(SAVE_PATH):
		return ""
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if not file:
		return ""
	return file.get_as_text()


func _write_save(data: Dictionary) -> void:
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_warning("LocalSave: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(data, "\t"))
