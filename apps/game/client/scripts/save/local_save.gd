extends Node

## Autoload — local JSON save + cloud cache (SAVE-4.1).

const SAVE_PATH := "user://aumbrye_save.json"
const ROSTER_PATH := "user://character_roster.json"
const CHARACTERS_DIR := "user://characters/"
const BACKUP_PATH := "user://aumbrye_save.conflict_backup.json"
const BACKUP_DIR := "user://backups/"
const BACKUP_COUNT := 5
const SAVE_SCHEMA_VERSION := SaveMigrator.CURRENT_VERSION

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
	data = SaveMigrator.migrate(data)
	if data.get("migrationFailed", false):
		_handle_corrupt_save(str(data.get("migrationReason", "migration_failed")))
		return false
	if not _validate_save(data):
		_handle_corrupt_save("corrupt_schema")
		return false
	_apply_save_data(data)
	save_loaded.emit()
	return true


var _cached_state: Dictionary = {}
var _cloud_updated_at: String = ""

enum BootMode { NONE, NEW_GAME, CONTINUE_MAIN, CONTINUE_BACKUP, CONTINUE_CHARACTER }
var _boot_mode: BootMode = BootMode.NONE
var _boot_backup_index: int = -1
var _boot_character_id: String = ""
var _pending_new_game: Dictionary = {}
var _roster: Dictionary = {"characters": [], "activeId": ""}
var _active_character_id: String = ""


func _ready() -> void:
	_ensure_backup_dir()
	_ensure_characters_dir()
	_load_roster()
	_migrate_legacy_save_if_needed()
	if _active_character_id != "" and FileAccess.file_exists(_character_path(_active_character_id)):
		var parsed = JSON.parse_string(_read_raw_text(_character_path(_active_character_id)))
		if parsed is Dictionary:
			_cached_state = parsed
			_cloud_updated_at = str(parsed.get("cloudUpdatedAt", ""))
	elif FileAccess.file_exists(SAVE_PATH):
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
	if ProgressionService:
		return ProgressionService.level
	return int(_character().get("level", 1))


func get_xp() -> int:
	return int(_character().get("xp", 0))


func get_character_name() -> String:
	return str(_character().get("name", "Wanderer"))


func set_character_profile(character_name: String, class_id: String = "") -> void:
	var character := _character()
	if character.is_empty():
		character = _default_character()
	character["name"] = character_name
	if class_id != "":
		character["classId"] = class_id
	_cached_state["character"] = character
	autosave()


func set_appearance_theme(theme: int) -> void:
	set_appearance_profile({"theme": theme})


func set_appearance_profile(profile: Dictionary) -> void:
	var clean := CharacterAppearance.sanitize(profile)
	var character := _character()
	if character.is_empty():
		character = _default_character()
	character["appearanceTheme"] = int(clean.get("theme", 0))
	character["appearance"] = clean.duplicate()
	_cached_state["character"] = character
	if CharacterService:
		CharacterService.appearance_theme = int(clean.get("theme", 0))
		CharacterService.appearance_profile = clean.duplicate()
	autosave()


func get_appearance_profile() -> Dictionary:
	return CharacterAppearance.from_character_dict(_character())


func get_appearance_theme() -> int:
	return int(_character().get("appearanceTheme", CharacterService.appearance_theme if CharacterService else 0))


func has_playable_character() -> bool:
	return not list_character_slots().is_empty()


func list_character_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for entry in _roster.get("characters", []):
		if not entry is Dictionary:
			continue
		var class_id: String = str(entry.get("classId", ""))
		if class_id == "":
			continue
		slots.append({
			"characterId": str(entry.get("id", "")),
			"label": "%s — %s (Lv%d)" % [
				entry.get("name", "Warden"),
				class_id,
				int(entry.get("level", 1)),
			],
			"detail": "Class: %s\nLast played: %s" % [
				class_id,
				entry.get("savedAt", "unknown"),
			],
		})
	return slots


func queue_boot_new_game(class_id: String, character_name: String, appearance: Dictionary) -> void:
	var profile := CharacterAppearance.sanitize(appearance)
	_pending_new_game = {
		"classId": class_id,
		"name": character_name,
		"appearanceTheme": int(profile.get("theme", 0)),
		"appearance": profile,
	}
	_boot_mode = BootMode.NEW_GAME
	_boot_backup_index = -1


func queue_boot_continue_main() -> void:
	_boot_mode = BootMode.CONTINUE_MAIN
	_boot_backup_index = -1
	_boot_character_id = ""


func queue_boot_continue_character(character_id: String) -> void:
	_boot_mode = BootMode.CONTINUE_CHARACTER
	_boot_character_id = character_id
	_boot_backup_index = -1


func queue_boot_continue_backup(index: int) -> void:
	_boot_mode = BootMode.CONTINUE_BACKUP
	_boot_backup_index = index


func execute_boot() -> bool:
	match _boot_mode:
		BootMode.NEW_GAME:
			return _apply_new_game_boot()
		BootMode.CONTINUE_CHARACTER:
			var character_id := _boot_character_id
			_boot_character_id = ""
			_boot_mode = BootMode.NONE
			return load_character(character_id)
		BootMode.CONTINUE_MAIN:
			_boot_mode = BootMode.NONE
			if _active_character_id != "":
				return load_character(_active_character_id)
			return load_into_services()
		BootMode.CONTINUE_BACKUP:
			var index := _boot_backup_index
			_boot_mode = BootMode.NONE
			_boot_backup_index = -1
			return restore_backup(index)
		_:
			return load_into_services() if has_save() else false


func _apply_new_game_boot() -> bool:
	var data: Dictionary = _pending_new_game.duplicate()
	_pending_new_game.clear()
	_boot_mode = BootMode.NONE
	var character_id := _generate_character_id()
	_active_character_id = character_id
	_reset_to_defaults()
	var class_id: String = str(data.get("classId", ""))
	var character_name: String = str(data.get("name", "Warden"))
	var appearance: Dictionary = CharacterAppearance.sanitize(
		data.get("appearance", {"theme": data.get("appearanceTheme", 0)})
	)
	set_character_profile(character_name, class_id)
	set_appearance_profile(appearance)
	if CharacterService:
		CharacterService.set_class_id(class_id)
	var starter_weapon := ClassCatalog.get_starting_weapon_item_id(class_id)
	InventoryService.inventory.add_item(starter_weapon, 1)
	_equip_weapon_item(starter_weapon)
	_add_roster_entry(character_id, character_name, class_id)
	autosave()
	return true


func load_character(character_id: String) -> bool:
	if character_id == "":
		return false
	var path := _character_path(character_id)
	if not FileAccess.file_exists(path):
		return false
	var raw_text := _read_raw_text(path)
	if raw_text.strip_edges().is_empty():
		return false
	var parsed = JSON.parse_string(raw_text)
	if parsed == null or not parsed is Dictionary:
		return false
	var data: Dictionary = SaveMigrator.migrate(parsed)
	if data.get("migrationFailed", false):
		return false
	if not _validate_save(data):
		return false
	_active_character_id = character_id
	_roster["activeId"] = character_id
	_save_roster()
	_apply_save_data(data)
	save_loaded.emit()
	return true


func _equip_weapon_item(item_id: String) -> void:
	var grid := InventoryService.inventory
	for i in grid.slots.size():
		if grid.slots[i].get("itemId", "") == item_id:
			grid.equip_weapon(i)
			return
	if grid.add_item(item_id, 1):
		grid.equip_weapon(grid.slots.size() - 1)


func _read_character_summary(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		return {"hasCharacter": false}
	var parsed = JSON.parse_string(_read_raw_text(path))
	if not parsed is Dictionary:
		return {"hasCharacter": false}
	var character: Dictionary = parsed.get("character", {})
	var class_id: String = str(character.get("classId", ""))
	return {
		"hasCharacter": class_id != "",
		"name": str(character.get("name", "Warden")),
		"classId": class_id,
		"level": int(character.get("level", 1)),
		"savedAt": str(parsed.get("cloudUpdatedAt", parsed.get("savedAt", ""))),
	}


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


func get_waves_active_run() -> Dictionary:
	var active: Variant = _cached_state.get("wavesActiveRun", {})
	return active if active is Dictionary else {}


func set_waves_active_run(data: Dictionary) -> void:
	_cached_state["wavesActiveRun"] = data.duplicate(true)
	autosave()


func clear_waves_active_run() -> void:
	if not _cached_state.has("wavesActiveRun"):
		return
	_cached_state.erase("wavesActiveRun")
	autosave()


func has_continuable_waves_run() -> bool:
	var run := get_waves_active_run()
	if run.is_empty():
		return false
	var snapshot: Variant = run.get("snapshot", {})
	if not snapshot is Dictionary or snapshot.is_empty():
		return false
	var player_state: Dictionary = snapshot.get("player", {})
	if player_state.has("health") and float(player_state.get("health", 1.0)) <= 0.0:
		return false
	return int(run.get("currentWave", 0)) >= 0


func get_meta_data() -> Dictionary:
	var meta: Variant = _cached_state.get("meta", {})
	return meta if meta is Dictionary else {}


func set_meta_data(meta: Dictionary) -> void:
	_cached_state["meta"] = meta.duplicate(true)
	autosave()


func autosave() -> void:
	_write_save(_build_save_payload())


func delete_save() -> void:
	if FileAccess.file_exists(SAVE_PATH):
		DirAccess.remove_absolute(SAVE_PATH)
	if _active_character_id != "":
		var char_path := _character_path(_active_character_id)
		if FileAccess.file_exists(char_path):
			DirAccess.remove_absolute(char_path)
	_cached_state.clear()
	_cloud_updated_at = ""
	_active_character_id = ""
	_roster = {"characters": [], "activeId": ""}
	_save_roster()


func delete_character(character_id: String) -> bool:
	if character_id == "":
		return false
	var path := _character_path(character_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var characters: Array = _roster.get("characters", [])
	for i in characters.size():
		if str((characters[i] as Dictionary).get("id", "")) == character_id:
			characters.remove_at(i)
			break
	_roster["characters"] = characters
	if str(_roster.get("activeId", "")) == character_id:
		_roster["activeId"] = ""
		_active_character_id = ""
		_cached_state.clear()
	_save_roster()
	return true


func delete_character_slot(backup_index: int) -> bool:
	if backup_index < 0:
		if _active_character_id != "":
			return delete_character(_active_character_id)
		delete_save()
		return true
	if backup_index >= BACKUP_COUNT:
		return false
	var path := _rotating_backup_path(backup_index)
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	return true


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
	if not get_active_run().is_empty():
		push_warning("LocalSave: keeping local active run — skipping cloud overwrite")
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
	if StorageService:
		StorageService.apply_save_storage(data.get("storage", {}))
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
			"gold": data.get("currencies", {}).get("gold", data.get("currencies", {}).get("coins", CharacterService.DEFAULT_GOLD)),
			"coins": data.get("currencies", {}).get("coins", data.get("currencies", {}).get("gold", CharacterService.DEFAULT_GOLD)),
			"classId": character.get("classId", ""),
			"appearanceTheme": character.get("appearanceTheme", 0),
			"appearance": character.get("appearance", {}),
			"flags": data.get("flags", {}),
			"quests": data.get("quests", {}),
		})
	if RunBuffs:
		RunBuffs.from_save_array(data.get("runRelics", []))
	var waves_run: Variant = data.get("wavesActiveRun", {})
	if waves_run is Dictionary and not waves_run.is_empty():
		_cached_state["wavesActiveRun"] = waves_run.duplicate(true)
		if WavesRunService:
			WavesRunService.restore_from_save(waves_run)
	elif _cached_state.has("wavesActiveRun"):
		_cached_state.erase("wavesActiveRun")


func _build_save_payload() -> Dictionary:
	var character := _character()
	if character.is_empty():
		character = _default_character()
	if ProgressionService:
		character["level"] = ProgressionService.level
		character["xp"] = ProgressionService.xp
	if CharacterService and CharacterService.class_id != "":
		character["classId"] = CharacterService.class_id
	if CharacterService:
		character["appearanceTheme"] = CharacterService.appearance_theme
		character["appearance"] = CharacterService.appearance_profile.duplicate()
	var data := {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"accountId": _cached_state.get("accountId", "00000000-0000-4000-8000-000000000000"),
		"character": character,
		"currencies": _cached_state.get("currencies", {"gold": 0}),
		"inventory": InventoryService.get_save_inventory(),
		"storage": StorageService.get_save_storage() if StorageService else _cached_state.get("storage", {}),
		"itemInstances": _cached_state.get("itemInstances", {}),
		"talents": ProgressionService.talents.duplicate() if ProgressionService else _cached_state.get("talents", {}),
		"talentPointsSpent": ProgressionService.talent_points_spent if ProgressionService else 0,
		"flags": _cached_state.get("flags", {}),
		"recipes": _cached_state.get("recipes", []),
		"runRelics": RunBuffs.to_save_array() if RunBuffs else _cached_state.get("runRelics", []),
	}
	if CharacterService:
		data["currencies"] = {"gold": CharacterService.gold, "coins": CharacterService.get_coins()}
		data["flags"] = CharacterService.flags.duplicate()
		data["quests"] = CharacterService.quests.duplicate()
	if _cached_state.has("activeRun"):
		data["activeRun"] = _cached_state["activeRun"]
	if _cached_state.has("wavesActiveRun"):
		data["wavesActiveRun"] = _cached_state["wavesActiveRun"]
	if _cached_state.has("meta"):
		data["meta"] = _cached_state["meta"]
	if _cloud_updated_at != "":
		data["cloudUpdatedAt"] = _cloud_updated_at
	return data


func _default_character() -> Dictionary:
	return {
		"name": "Wanderer",
		"classId": "",
		"level": 1,
		"xp": 0,
		"appearanceTheme": 0,
		"appearance": CharacterAppearance.default_profile(),
		"lastHubMessage": RunFlow.last_hub_message,
		"firstPersonCamera": false,
	}


func _validate_save(data: Dictionary) -> bool:
	var version := int(data.get("schemaVersion", 0))
	if version < 1 or version > SAVE_SCHEMA_VERSION:
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
	if FileAccess.file_exists(SAVE_PATH):
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		var corrupt_path := "user://aumbrye_save.corrupt_%s.json" % stamp
		DirAccess.copy_absolute(SAVE_PATH, corrupt_path)
		DirAccess.remove_absolute(SAVE_PATH)
		push_error("LocalSave: corrupt save (%s) — quarantined to %s" % [reason, corrupt_path])
	for backup in list_backups():
		var index: int = int(backup.get("index", 0))
		if restore_backup(index):
			save_failed.emit(reason)
			return
	save_failed.emit(reason)
	print_verbose("LocalSave: %s — starting fresh" % reason)
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
	var normalized := _normalize_save_integers(data.duplicate(true))
	_cached_state = normalized
	if _active_character_id != "":
		_update_roster_entry_metadata(normalized)
		_save_roster()
		var char_path := _character_path(_active_character_id)
		var char_file := FileAccess.open(char_path, FileAccess.WRITE)
		if not char_file:
			push_warning("LocalSave: could not write %s" % char_path)
			return
		char_file.store_string(JSON.stringify(normalized, "\t"))
		return
	if rotate_backups and FileAccess.file_exists(SAVE_PATH):
		_rotate_backups()
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


func _ensure_characters_dir() -> void:
	if not DirAccess.dir_exists_absolute(CHARACTERS_DIR):
		DirAccess.make_dir_recursive_absolute(CHARACTERS_DIR)


func _load_roster() -> void:
	if not FileAccess.file_exists(ROSTER_PATH):
		_roster = {"characters": [], "activeId": ""}
		_active_character_id = ""
		return
	var parsed = JSON.parse_string(_read_raw_text(ROSTER_PATH))
	if parsed is Dictionary:
		_roster = parsed
		_active_character_id = str(_roster.get("activeId", ""))
	else:
		_roster = {"characters": [], "activeId": ""}
		_active_character_id = ""


func _save_roster() -> void:
	var file := FileAccess.open(ROSTER_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(_roster, "\t"))


func _character_path(character_id: String) -> String:
	return "%s%s.json" % [CHARACTERS_DIR, character_id]


func _generate_character_id() -> String:
	return "warden_%d" % (Time.get_ticks_usec() % 1000000000)


func _migrate_legacy_save_if_needed() -> void:
	var characters: Array = _roster.get("characters", [])
	if not characters.is_empty():
		return
	if not FileAccess.file_exists(SAVE_PATH):
		return
	var summary := _read_character_summary(SAVE_PATH)
	if not bool(summary.get("hasCharacter", false)):
		return
	var character_id := _generate_character_id()
	var parsed = JSON.parse_string(_read_raw_text(SAVE_PATH))
	if not parsed is Dictionary:
		return
	var char_file := FileAccess.open(_character_path(character_id), FileAccess.WRITE)
	if char_file:
		char_file.store_string(JSON.stringify(parsed, "\t"))
	_add_roster_entry(
		character_id,
		str(summary.get("name", "Warden")),
		str(summary.get("classId", "")),
		int(summary.get("level", 1)),
		str(summary.get("savedAt", ""))
	)
	_active_character_id = character_id
	_roster["activeId"] = character_id
	_save_roster()


func _add_roster_entry(
	character_id: String,
	character_name: String,
	class_id: String,
	level: int = 1,
	saved_at: String = ""
) -> void:
	var characters: Array = _roster.get("characters", [])
	characters.append({
		"id": character_id,
		"name": character_name,
		"classId": class_id,
		"level": level,
		"savedAt": saved_at if saved_at != "" else Time.get_datetime_string_from_system(),
	})
	_roster["characters"] = characters
	_roster["activeId"] = character_id


func _update_roster_entry_metadata(data: Dictionary) -> void:
	var character: Dictionary = data.get("character", {})
	var characters: Array = _roster.get("characters", [])
	for i in characters.size():
		var entry: Dictionary = characters[i] as Dictionary
		if str(entry.get("id", "")) != _active_character_id:
			continue
		entry["name"] = str(character.get("name", entry.get("name", "Warden")))
		entry["classId"] = str(character.get("classId", entry.get("classId", "")))
		entry["level"] = int(character.get("level", entry.get("level", 1)))
		entry["savedAt"] = Time.get_datetime_string_from_system()
		characters[i] = entry
		break
	_roster["characters"] = characters
