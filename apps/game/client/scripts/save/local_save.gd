extends Node

## Autoload — local JSON save + cloud cache (SAVE-4.1).

const SAVE_PATH := "user://aumbrye_save.json"
const BACKUP_PATH := "user://aumbrye_save.conflict_backup.json"
const BACKUP_DIR := "user://backups/"
const BACKUP_COUNT := 5
const SAVE_SCHEMA_VERSION := 1

signal save_loaded
signal save_failed(reason: String)
signal cloud_sync_completed(server_won: bool)
signal backup_restored(index: int)


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


func load_into_services() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var raw_text := _read_raw_text(SAVE_PATH)
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
	_apply_save_data(data)
	save_loaded.emit()
	return true


var _cached_state: Dictionary = {}
var _cloud_updated_at: String = ""


func _ready() -> void:
	_ensure_backup_dir()
	if FileAccess.file_exists(SAVE_PATH):
		var parsed = JSON.parse_string(_read_raw_text(SAVE_PATH))
		if parsed is Dictionary:
			_cached_state = parsed
			_cloud_updated_at = str(parsed.get("cloudUpdatedAt", ""))


func is_first_person_camera() -> bool:
	return bool(_character().get("firstPersonCamera", false))


func set_first_person_camera(enabled: bool) -> void:
	var character := _character()
	if bool(character.get("firstPersonCamera", false)) == enabled:
		return
	character["firstPersonCamera"] = enabled
	autosave()


func get_level() -> int:
	return int(_character().get("level", 1))


func get_xp() -> int:
	return int(_character().get("xp", 0))


func get_talents() -> Dictionary:
	if ProgressionService:
		return ProgressionService.talents.duplicate()
	var talents: Variant = _cached_state.get("talents", {})
	return talents if talents is Dictionary else {}


func list_backups() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	for i in BACKUP_COUNT:
		var path := _rotating_backup_path(i)
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(_read_raw_text(path))
		if parsed is Dictionary:
			entries.append({
				"index": i,
				"path": path,
				"savedAt": parsed.get("cloudUpdatedAt", parsed.get("savedAt", "")),
				"level": int(parsed.get("character", {}).get("level", 1)),
			})
	return entries


func restore_backup(index: int) -> bool:
	if index < 0 or index >= BACKUP_COUNT:
		return false
	var path := _rotating_backup_path(index)
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(_read_raw_text(path))
	if not parsed is Dictionary or not _validate_save(parsed):
		return false
	_rotate_backups()
	_apply_save_data(parsed)
	_write_save(_build_save_payload(), false)
	backup_restored.emit(index)
	return true


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
	var active: Variant = _cached_state.get("activeRun", {})
	return active if active is Dictionary else {}


func set_active_run(data: Dictionary) -> void:
	_cached_state["activeRun"] = data.duplicate(true)
	autosave()


func clear_active_run() -> void:
	if not _cached_state.has("activeRun"):
		return
	_cached_state.erase("activeRun")
	autosave()


func autosave() -> void:
	_write_save(_build_save_payload())


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	_cached_state.clear()
	_cloud_updated_at = ""


## Pull cloud save; server wins on conflict (local backed up first).
func sync_from_cloud() -> bool:
	if ApiConfig.access_token == "":
		if not await ApiClient.ensure_dev_session():
			return false
	var result := await ApiClient.get_save()
	if not result.get("ok", false):
		push_warning("LocalSave: cloud sync failed — %s" % result.get("error", "unknown"))
		return false
	var server_json: String = str(result.get("stateJson", ""))
	var server_updated: String = str(result.get("updatedAt", ""))
	if server_json.is_empty():
		return false
	var parsed = JSON.parse_string(server_json)
	if not parsed is Dictionary:
		return false
	if _cloud_updated_at != "" and server_updated != "" and _cloud_updated_at != server_updated:
		_backup_local_save()
	_apply_save_data(parsed)
	_cloud_updated_at = server_updated
	_cached_state["cloudUpdatedAt"] = server_updated
	_write_save(_build_save_payload())
	cloud_sync_completed.emit(true)
	return true


## Push local save to cloud; returns false on conflict (server state in result).
func push_to_cloud() -> Dictionary:
	if ApiConfig.access_token == "":
		if not await ApiClient.ensure_dev_session():
			return {"ok": false, "error": "auth failed"}
	var payload := _build_save_payload()
	var client_updated: Variant = null
	if _cloud_updated_at != "":
		client_updated = _cloud_updated_at
	var result := await ApiClient.put_save(JSON.stringify(payload), client_updated)
	if result.get("conflict", false):
		_backup_local_save()
		var server_state: String = str(result.get("stateJson", ""))
		if not server_state.is_empty():
			var parsed = JSON.parse_string(server_state)
			if parsed is Dictionary:
				_apply_save_data(parsed)
				_cloud_updated_at = str(result.get("updatedAt", ""))
				_cached_state["cloudUpdatedAt"] = _cloud_updated_at
				_write_save(_build_save_payload())
		cloud_sync_completed.emit(true)
		return {"ok": false, "conflict": true}
	if result.get("ok", false):
		_cloud_updated_at = str(result.get("updatedAt", ""))
		_cached_state["cloudUpdatedAt"] = _cloud_updated_at
		_write_save(_build_save_payload())
		return {"ok": true}
	return result


func _character() -> Dictionary:
	var character: Variant = _cached_state.get("character", {})
	if character is Dictionary:
		return character
	return {}


func _apply_save_data(data: Dictionary) -> void:
	_cached_state = data.duplicate(true)
	InventoryService.apply_save_inventory(data.get("inventory", {}))
	var character: Dictionary = _character()
	if character.is_empty():
		character = _default_character()
		_cached_state["character"] = character
	if ProgressionService:
		ProgressionService.from_save_dict({
			"level": character.get("level", 1),
			"xp": character.get("xp", 0),
			"talentPointsSpent": data.get("talentPointsSpent", 0),
			"talents": data.get("talents", {}),
		})
	if CharacterService:
		CharacterService.from_save_dict({
			"gold": data.get("currencies", {}).get("gold", CharacterService.DEFAULT_GOLD),
			"level": character.get("level", 1),
			"flags": data.get("flags", {}),
			"quests": data.get("quests", {}),
		})
	if RunBuffs:
		RunBuffs.from_save_array(data.get("runRelics", []))


func _build_save_payload() -> Dictionary:
	var character := _character()
	if character.is_empty():
		character = _default_character()
	if ProgressionService:
		character["level"] = ProgressionService.level
		character["xp"] = ProgressionService.xp
	var data := {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"accountId": _cached_state.get("accountId", "00000000-0000-4000-8000-000000000000"),
		"character": character,
		"currencies": _cached_state.get("currencies", {"gold": 0}),
		"inventory": InventoryService.get_save_inventory(),
		"itemInstances": _cached_state.get("itemInstances", {}),
		"talents": ProgressionService.talents.duplicate() if ProgressionService else _cached_state.get("talents", {}),
		"talentPointsSpent": ProgressionService.talent_points_spent if ProgressionService else 0,
		"flags": _cached_state.get("flags", {}),
		"recipes": _cached_state.get("recipes", []),
		"runRelics": RunBuffs.to_save_array() if RunBuffs else _cached_state.get("runRelics", []),
	}
	if CharacterService:
		data["currencies"] = {"gold": CharacterService.gold}
		data["flags"] = CharacterService.flags.duplicate()
		data["quests"] = CharacterService.quests.duplicate()
	if _cached_state.has("activeRun"):
		data["activeRun"] = _cached_state["activeRun"]
	if _cloud_updated_at != "":
		data["cloudUpdatedAt"] = _cloud_updated_at
	return data


func _default_character() -> Dictionary:
	return {
		"name": "Wanderer",
		"level": 1,
		"xp": 0,
		"lastHubMessage": RunFlow.last_hub_message,
		"firstPersonCamera": false,
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
	_cached_state = {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"character": _default_character(),
		"currencies": {"gold": 0},
		"talents": {},
		"itemInstances": {},
		"flags": {},
		"recipes": [],
		"runRelics": [],
	}
	if ProgressionService:
		ProgressionService.from_save_dict({})
	if CharacterService:
		CharacterService.reset_to_defaults()
	if RunBuffs:
		RunBuffs.clear_all()


func _handle_corrupt_save(reason: String) -> void:
	save_failed.emit(reason)
	push_warning("LocalSave: %s — starting fresh" % reason)
	_reset_to_defaults()


func _backup_local_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, BACKUP_PATH)
		push_warning("LocalSave: conflict — local save backed up to %s" % BACKUP_PATH)


func _read_raw_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	return file.get_as_text()


func _write_save(data: Dictionary, rotate_backups: bool = true) -> void:
	if rotate_backups and FileAccess.file_exists(SAVE_PATH):
		_rotate_backups()
	var normalized := _normalize_save_integers(data.duplicate(true))
	_cached_state = normalized
	var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if not file:
		push_warning("LocalSave: could not write %s" % SAVE_PATH)
		return
	file.store_string(JSON.stringify(normalized, "\t"))


func _normalize_save_integers(data: Dictionary) -> Dictionary:
	var inv: Variant = data.get("inventory", {})
	if inv is Dictionary:
		var inv_copy: Dictionary = inv.duplicate(true)
		for dim_key in ["gridWidth", "gridHeight", "schemaVersion"]:
			if inv_copy.has(dim_key):
				inv_copy[dim_key] = int(inv_copy[dim_key])
		var slots: Array = inv_copy.get("slots", [])
		for i in slots.size():
			if slots[i] is Dictionary:
				slots[i] = _normalize_slot_integers(slots[i])
		inv_copy["slots"] = slots
		var equipped: Variant = inv_copy.get("equipped", {})
		if equipped is Dictionary:
			for slot_name in equipped:
				if equipped[slot_name] is Dictionary and not equipped[slot_name].is_empty():
					equipped[slot_name] = _normalize_slot_integers(equipped[slot_name])
			inv_copy["equipped"] = equipped
		data["inventory"] = inv_copy
	if data.has("talentPointsSpent"):
		data["talentPointsSpent"] = int(data["talentPointsSpent"])
	var instances: Variant = data.get("itemInstances", {})
	if instances is Dictionary:
		for instance_id in instances:
			if instances[instance_id] is Dictionary:
				instances[instance_id] = _normalize_slot_integers(instances[instance_id])
		data["itemInstances"] = instances
	return data


func _normalize_slot_integers(slot: Dictionary) -> Dictionary:
	for key in ["quantity", "x", "y", "rollSeed"]:
		if slot.has(key):
			slot[key] = int(slot[key])
	return slot


func _rotate_backups() -> void:
	_ensure_backup_dir()
	for i in range(BACKUP_COUNT - 1, 0, -1):
		var from_path := _rotating_backup_path(i - 1)
		var to_path := _rotating_backup_path(i)
		if FileAccess.file_exists(from_path):
			DirAccess.rename_absolute(from_path, to_path)
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.copy_absolute(SAVE_PATH, _rotating_backup_path(0))


func _rotating_backup_path(index: int) -> String:
	return "%saumbrye_save_%d.json" % [BACKUP_DIR, index]


func _ensure_backup_dir() -> void:
	if not DirAccess.dir_exists_absolute(BACKUP_DIR):
		DirAccess.make_dir_recursive_absolute(BACKUP_DIR)
