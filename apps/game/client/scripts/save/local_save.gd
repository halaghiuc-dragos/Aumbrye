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
	save_loaded.emit()
	return true


func autosave() -> void:
	var data := {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"character": _build_character_state(),
		"inventory": InventoryService.get_save_inventory(),
	}
	_write_save(data)


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)


func _build_character_state() -> Dictionary:
	return {
		"name": "Wanderer",
		"level": 1,
		"lastHubMessage": RunFlow.last_hub_message,
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
