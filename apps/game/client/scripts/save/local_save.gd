extends Node


const DEFAULT_SAVE_ROOT := "user://"
## Diagnostics keep their saves here instead of in the player's folder.
const AUDIT_SAVE_ROOT := "user://audit/"
const ACCOUNT_SCHEMA_VERSION := 1
const MAX_CHARACTER_SLOTS := 5
const BACKUP_COUNT := 5

const BACKUP_MIN_INTERVAL_SEC := 300
const SAVE_SCHEMA_VERSION := SaveMigrator.CURRENT_VERSION
const AUTOSAVE_MIN_INTERVAL := 2.0

signal save_loaded
signal save_failed(reason: String)
signal cloud_sync_completed(server_won: bool)
signal backup_restored(index: int)

signal save_recovery_required(reason: String, quarantine_path: String)

enum SavePriority { IMMEDIATE, DEFERRED }

## Where every save file lives. A diagnostic run moves it under `AUDIT_SAVE_ROOT`, so no audit can
## ever create characters in, or change, the player's real saves.
var _root := DEFAULT_SAVE_ROOT
var _cached_state: Dictionary = {}
var _cloud_updated_at: String = ""

enum BootMode { NONE, NEW_GAME, CONTINUE_MAIN, CONTINUE_BACKUP, CONTINUE_CHARACTER }
var _boot_mode: BootMode = BootMode.NONE
var _boot_backup_index: int = -1
var _boot_character_id: String = ""
var _pending_new_game: Dictionary = {}
var _roster: Dictionary = {"characters": [], "activeId": "", "localAccountId": ""}
var _account: Dictionary = {}
var _active_character_id: String = ""
var _character_loaded := false
var _autosave_pending := false
var _force_backup_rotation := false

## Set when a backup replaced an unreadable save; the hub tells the player once, then clears it.
var restore_notice := ""
var recovery_required := false
var recovery_character_id := ""
var recovery_reason := ""
var recovery_quarantine_path := ""
var _last_quarantine_path := ""
var _autosave_timer: Timer
## The deferred save a worker is serialising right now (empty when none).
var _async_write: Dictionary = {}
var _character_id_counter := 0


func _save_path() -> String:
	return _root + "aumbrye_save.json"


func _roster_path() -> String:
	return _root + "character_roster.json"


func _account_path() -> String:
	return _root + "account.json"


func _journal_path() -> String:
	return _root + "save_set_journal.json"


func _characters_dir() -> String:
	return _root + "characters/"


func _backup_dir() -> String:
	return _root + "backups/"


## Empties a diagnostic save root. Refuses any path outside `AUDIT_SAVE_ROOT`.
static func _wipe_isolated_root(root: String) -> void:
	if not root.begins_with(AUDIT_SAVE_ROOT):
		return
	var dir := DirAccess.open(root)
	if dir == null:
		return
	for sub_dir in dir.get_directories():
		_wipe_isolated_root("%s%s/" % [root, sub_dir])
		DirAccess.remove_absolute("%s%s" % [root, sub_dir])
	for file_name in dir.get_files():
		DirAccess.remove_absolute("%s%s" % [root, file_name])


## A `scenes/debug/` scene launched from the command line is a diagnostic: its saves are its own.
static func _diagnostic_scene_name() -> String:
	for arg in OS.get_cmdline_args():
		if str(arg).begins_with("res://scenes/debug/"):
			return str(arg).get_file().get_basename()
	return ""


func has_save() -> bool:
	return FileAccess.file_exists(_save_path())


func load_into_services() -> bool:
	if not FileAccess.file_exists(_save_path()):
		return false
	return _load_document(_save_path())


func is_character_loaded() -> bool:
	return _character_loaded and not _cached_state.is_empty()


func get_active_character_id() -> String:
	return _active_character_id


## Anything queued on the deferred timer is written first: the file on disk is older than memory
## until then, and reading it back would throw the change away.
func reload_active_into_services() -> bool:
	if _autosave_pending:
		autosave()
	if _active_character_id != "" and FileAccess.file_exists(_character_path(_active_character_id)):
		return load_character(_active_character_id)
	return load_into_services()


func _ready() -> void:
	var diagnostic := _diagnostic_scene_name()
	if diagnostic != "":
		_root = "%s%s/" % [AUDIT_SAVE_ROOT, diagnostic]
		_wipe_isolated_root(_root)
		DirAccess.make_dir_recursive_absolute(_root)
	_ensure_backup_dir()
	_ensure_characters_dir()
	_recover_save_set_journal()
	_load_roster()
	_load_account()
	_migrate_legacy_save_if_needed()
	if _active_character_id != "" and FileAccess.file_exists(_character_path(_active_character_id)):
		_warm_load_path(_character_path(_active_character_id))
	elif FileAccess.file_exists(_save_path()):
		_warm_load_path(_save_path())


func is_first_person_camera() -> bool:
	return bool(_character().get("firstPersonCamera", false))


func set_first_person_camera(enabled: bool) -> void:
	var character := _character()
	if bool(character.get("firstPersonCamera", false)) == enabled:
		return
	character["firstPersonCamera"] = enabled
	autosave()


func get_level() -> int:
	if is_instance_valid(ProgressionService):
		return ProgressionService.level
	return int(_character().get("level", 1))


func get_character_name() -> String:
	return str(_character().get("name", "Wanderer"))


func get_character_display_name() -> String:
	var base := get_character_name()
	var title_id := str(get_appearance_profile().get("title", ""))
	if title_id == "":
		return base
	var label := AppearanceCatalog.title_label(title_id)
	return "%s %s" % [base, label] if label != "" else base


func set_character_profile(character_name: String, class_id: String = "") -> void:
	var character := _character()
	if character.is_empty():
		character = _default_character()
	character["name"] = character_name
	if class_id != "":
		character["classId"] = class_id
	_cached_state["character"] = character
	autosave()


func set_appearance_profile(profile: Dictionary) -> bool:
	if not CharacterAppearance.is_valid(profile):
		push_warning("LocalSave.set_appearance_profile: invalid appearance profile rejected")
		return false
	var clean := CharacterAppearance.sanitize(profile)
	var character := _character()
	if character.is_empty():
		character = _default_character()
	character["appearanceTheme"] = int(clean.get("theme", 0))
	character["appearance"] = clean.duplicate()
	_cached_state["character"] = character
	CharacterAppearance.apply_to_service(clean)
	autosave()
	return true


func get_appearance_profile() -> Dictionary:
	return CharacterAppearance.from_character_dict(_character())


const PLAYTIME_FLUSH_SECONDS := 45.0

var _playtime_flush := PLAYTIME_FLUSH_SECONDS


func _notification(what: int) -> void:
	if what != NOTIFICATION_WM_CLOSE_REQUEST and what != NOTIFICATION_EXIT_TREE:
		return
	if _character_loaded and not _cached_state.is_empty():
		autosave_checkpoint()


func get_playtime_seconds() -> float:
	return float(_character().get("playtimeSeconds", 0.0))


func format_playtime(seconds: float) -> String:
	var total := maxi(0, int(seconds))
	@warning_ignore("integer_division")
	var hours := total / 3600
	@warning_ignore("integer_division")
	var minutes := (total % 3600) / 60
	var secs := total % 60
	if hours > 0:
		return "%d:%02d:%02d" % [hours, minutes, secs]
	return "%02d:%02d" % [minutes, secs]


func _process(delta: float) -> void:
	if not _async_write.is_empty() and WorkerThreadPool.is_task_completed(int(_async_write["task"])):
		_finish_async_write()
	if not _character_loaded or _cached_state.is_empty():
		return
	var character: Dictionary = _character()
	if character.is_empty():
		return
	character["playtimeSeconds"] = float(character.get("playtimeSeconds", 0.0)) + delta
	_cached_state["character"] = character
	_playtime_flush -= delta
	if _playtime_flush <= 0.0:
		_playtime_flush = PLAYTIME_FLUSH_SECONDS
		autosave_checkpoint()


func has_playable_character() -> bool:
	return not list_character_slots().is_empty()


func character_slot_limit() -> int:
	return MAX_CHARACTER_SLOTS


func used_character_slots() -> int:
	var used := 0
	for entry in _roster.get("characters", []):
		if entry is Dictionary and str(entry.get("classId", "")) != "":
			used += 1
	return used


func can_create_character() -> bool:
	return used_character_slots() < MAX_CHARACTER_SLOTS


func get_account_flags() -> Dictionary:
	var flags: Variant = _account.get("flags", {})
	return (flags as Dictionary).duplicate(true) if flags is Dictionary else {}


func _default_account() -> Dictionary:
	return {
		"schemaVersion": ACCOUNT_SCHEMA_VERSION,
		"storage": {},
		"flags": {},
		"endlessBestFloor": 0,
		"descentTokens": 0,
	}


func _load_account() -> void:
	if not FileAccess.file_exists(_account_path()):
		_account = _default_account()
		return
	var parsed = JSON.parse_string(_read_raw_text(_account_path()))
	if parsed is Dictionary:
		_account = _default_account()
		for key in parsed as Dictionary:
			_account[str(key)] = (parsed as Dictionary)[key]
		_account["schemaVersion"] = ACCOUNT_SCHEMA_VERSION
	else:
		_account = _default_account()


func _save_account() -> void:
	_write_json_atomic(_account_path(), _account)


func _merge_account_flag(flag_id: String, value: Variant) -> void:
	var flags: Dictionary = _account.get("flags", {})
	if not flags.has(flag_id):
		flags[flag_id] = value
		_account["flags"] = flags
		return
	var current: Variant = flags[flag_id]
	if current is bool or value is bool:
		flags[flag_id] = bool(current) or bool(value)
	elif current is Dictionary and value is Dictionary:
		var merged: Dictionary = (current as Dictionary).duplicate(true)
		for key in value as Dictionary:
			var incoming: Variant = (value as Dictionary)[key]
			if merged.has(key) and not (incoming is Dictionary):
				merged[key] = maxf(float(merged[key]), float(incoming))
			else:
				merged[key] = incoming
		flags[flag_id] = merged
	elif (current is int or current is float) and (value is int or value is float):
		flags[flag_id] = maxi(int(current), int(value))
	else:
		flags[flag_id] = value
	_account["flags"] = flags


func _harvest_account_scope(data: Dictionary) -> void:
	var storage: Variant = data.get("storage", {})
	if storage is Dictionary:
		_account["storage"] = (storage as Dictionary).duplicate(true)
	var flags: Variant = data.get("flags", {})
	if flags is Dictionary:
		for flag_id in flags as Dictionary:
			if SaveMigrator.is_account_scope_flag(str(flag_id)):
				_merge_account_flag(str(flag_id), (flags as Dictionary)[flag_id])
	if is_instance_valid(ProgressionService):
		_account["endlessBestFloor"] = maxi(
			int(_account.get("endlessBestFloor", 0)), ProgressionService.endless_best_floor
		)
	_save_account()


func _apply_account_scope(working: Dictionary) -> void:
	var adopted: Variant = working.get("account", {})
	if adopted is Dictionary and not (adopted as Dictionary).is_empty():
		var account_storage: Variant = (adopted as Dictionary).get("storage", {})
		var own_storage: Variant = _account.get("storage", {})
		if (
			account_storage is Dictionary
			and not (account_storage as Dictionary).is_empty()
			and (not own_storage is Dictionary or (own_storage as Dictionary).is_empty())
		):
			_account["storage"] = (account_storage as Dictionary).duplicate(true)
		var account_flags: Variant = (adopted as Dictionary).get("flags", {})
		if account_flags is Dictionary:
			for flag_id in account_flags as Dictionary:
				_merge_account_flag(str(flag_id), (account_flags as Dictionary)[flag_id])
	var own: Variant = _account.get("storage", {})
	if own is Dictionary and (own as Dictionary).is_empty():
		var doc_storage: Variant = working.get("storage", {})
		if doc_storage is Dictionary:
			_account["storage"] = (doc_storage as Dictionary).duplicate(true)
	var shared: Variant = _account.get("storage", {})
	if shared is Dictionary and not (shared as Dictionary).is_empty():
		working["storage"] = (shared as Dictionary).duplicate(true)
	var flags: Variant = working.get("flags", {})
	if flags is Dictionary:
		var merged: Dictionary = (flags as Dictionary)
		var account_scope := get_account_flags()
		for flag_id in account_scope:
			if not merged.has(flag_id):
				merged[flag_id] = account_scope[flag_id]
		working["flags"] = merged
	_save_account()


func list_character_slots() -> Array[Dictionary]:
	var slots: Array[Dictionary] = []
	for entry in _roster.get("characters", []):
		if not entry is Dictionary:
			continue
		var class_id: String = str(entry.get("classId", ""))
		if class_id == "":
			continue
		(
			slots
			. append(
				{
					"characterId": str(entry.get("id", "")),
					"playtime": format_playtime(float(entry.get("playtimeSeconds", 0.0))),
					"label":
					_slot_label(
						(
							"%s — %s (Lv%d)"
							% [
								entry.get("name", "Warden"),
								class_display_name(class_id),
								int(entry.get("level", 1)),
							]
						),
						format_playtime(float(entry.get("playtimeSeconds", 0.0)))
					),
					"detail":
					(
						"Class: %s     Last played: %s"
						% [
							class_display_name(class_id),
							format_save_stamp(str(entry.get("savedAt", ""))),
						]
					),
				}
			)
		)
	return slots


const SLOT_LABEL_WIDTH := 46


func class_display_name(class_id: String) -> String:
	if class_id.strip_edges().is_empty():
		return "Unknown"
	var display := str(ClassCatalog.get_definition(class_id).get("name", ""))
	return display if display != "" else class_id.capitalize()


func format_save_stamp(stamp: String) -> String:
	var unix := _save_stamp_unix(stamp)
	if unix <= 0:
		return "unknown"
	var local := Time.get_datetime_dict_from_unix_time(
		unix + Time.get_time_zone_from_system().get("bias", 0) * 60
	)
	return "%d %s %d, %02d:%02d" % [
		int(local["day"]),
		MONTH_NAMES[clampi(int(local["month"]) - 1, 0, 11)],
		int(local["year"]),
		int(local["hour"]),
		int(local["minute"]),
	]


const MONTH_NAMES: Array[String] = [
	"Jan", "Feb", "Mar", "Apr", "May", "Jun", "Jul", "Aug", "Sep", "Oct", "Nov", "Dec"
]


func _slot_label(left: String, right: String) -> String:
	var gap := SLOT_LABEL_WIDTH - left.length() - right.length()
	if gap < 2:
		gap = 2
	return left + " ".repeat(gap) + right


func list_warden_names() -> PackedStringArray:
	var names: PackedStringArray = []
	for entry in _roster.get("characters", []):
		if entry is Dictionary:
			names.append(str(entry.get("name", "")))
	return names


func get_last_creation_profile() -> Dictionary:
	var meta := get_meta_data()
	var profile: Variant = meta.get("lastCreationProfile", {})
	return profile if profile is Dictionary else {}


func set_last_creation_profile(profile: Dictionary) -> void:
	var meta := get_meta_data().duplicate(true)
	meta["lastCreationProfile"] = profile.duplicate(true)
	patch_meta(meta)
	request_autosave()


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


func queue_boot_continue_character(character_id: String) -> void:
	_boot_mode = BootMode.CONTINUE_CHARACTER
	_boot_character_id = character_id
	_boot_backup_index = -1


var last_boot_failure := ""


func execute_boot() -> bool:
	last_boot_failure = ""
	match _boot_mode:
		BootMode.NEW_GAME:
			return _apply_new_game_boot()
		BootMode.CONTINUE_CHARACTER:
			var character_id := _boot_character_id
			_boot_character_id = ""
			_boot_mode = BootMode.NONE
			if load_character(character_id):
				return true
			last_boot_failure = "LOADING_CHARACTER_MISSING"
			return false
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
			if has_save() and load_into_services():
				return true
			last_boot_failure = "LOADING_SAVE_FAILED"
			return false


func _apply_new_game_boot() -> bool:
	var data: Dictionary = _pending_new_game.duplicate()
	_pending_new_game.clear()
	_boot_mode = BootMode.NONE
	if not can_create_character():
		push_warning(
			"LocalSave: character slots full (%d of %d)"
			% [used_character_slots(), MAX_CHARACTER_SLOTS]
		)
		last_boot_failure = "LOADING_SLOTS_FULL"
		return false
	var character_id := _generate_character_id()
	_active_character_id = character_id
	_character_loaded = true
	_reset_to_defaults()
	var class_id: String = str(data.get("classId", ""))
	var character_name: String = str(data.get("name", "Warden"))
	var appearance: Dictionary = CharacterAppearance.sanitize(
		data.get("appearance", {"theme": data.get("appearanceTheme", 0)})
	)
	set_character_profile(character_name, class_id)
	set_appearance_profile(appearance)
	if is_instance_valid(CharacterService):
		CharacterService.set_class_id(class_id)
	var starter_weapon := ClassCatalog.get_starting_weapon_item_id(class_id)
	InventoryService.inventory.add_item(starter_weapon, 1)
	InventoryService.equip_weapon_item(starter_weapon)
	_add_roster_entry(character_id, character_name, class_id)
	autosave()
	return true


func load_character(character_id: String) -> bool:
	if character_id == "":
		return false
	var path := _character_path(character_id)
	if not FileAccess.file_exists(path):
		return false
	return _load_document(path, character_id)


func get_recipes() -> Array:
	var recipes: Variant = _cached_state.get("recipes", [])
	return recipes.duplicate() if recipes is Array else []


func has_recipe(recipe_id: String) -> bool:
	return recipe_id in get_recipes()


func add_recipe(recipe_id: String) -> void:
	add_owned_recipe(recipe_id)


func add_owned_recipe(recipe_id: String) -> void:
	if recipe_id == "" or has_recipe(recipe_id):
		return
	var recipes: Array = get_recipes()
	recipes.append(recipe_id)
	_cached_state["recipes"] = recipes
	request_autosave(SavePriority.DEFERRED)


func get_merchants() -> Dictionary:
	var merchants: Variant = _cached_state.get("merchants", {})
	return merchants.duplicate(true) if merchants is Dictionary else {}


func get_merchant_purchased(merchant_id: String) -> Dictionary:
	var merchants := get_merchants()
	var entry: Variant = merchants.get(merchant_id, {})
	if not entry is Dictionary:
		return {}
	var purchased: Variant = entry.get("purchased", {})
	return purchased.duplicate() if purchased is Dictionary else {}


func set_merchant_purchased(merchant_id: String, purchased: Dictionary) -> void:
	if not _cached_state.has("merchants") or not _cached_state["merchants"] is Dictionary:
		_cached_state["merchants"] = {}
	var merchants: Dictionary = _cached_state["merchants"]
	var entry: Dictionary = merchants.get(merchant_id, {})
	if not entry is Dictionary:
		entry = {}
	entry["purchased"] = purchased.duplicate()
	merchants[merchant_id] = entry
	_cached_state["merchants"] = merchants


func increment_merchant_purchase(merchant_id: String, item_id: String) -> void:
	var purchased := get_merchant_purchased(merchant_id)
	purchased[item_id] = int(purchased.get(item_id, 0)) + 1
	set_merchant_purchased(merchant_id, purchased)


func clear_merchant_purchased(merchant_id: String) -> void:
	set_merchant_purchased(merchant_id, {})


func clear_all_merchant_purchases() -> void:
	_cached_state["merchants"] = {}

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


func list_backups(character_id: String = "") -> Array[Dictionary]:
	if character_id == "":
		character_id = _active_character_id
	var entries: Array[Dictionary] = []
	for i in BACKUP_COUNT:
		var path := _rotating_backup_path(i, character_id)
		if not FileAccess.file_exists(path):
			continue
		var parsed = JSON.parse_string(_read_raw_text(path))
		if parsed is Dictionary:
			(
				entries
				. append(
					{
						"index": i,
						"path": path,
						"savedAt": parsed.get("cloudUpdatedAt", parsed.get("savedAt", "")),
						"level": int(parsed.get("character", {}).get("level", 1)),
					}
				)
			)
	return entries


func restore_backup(index: int, character_id: String = "") -> bool:
	if character_id == "":
		character_id = _active_character_id
	if index < 0 or index >= BACKUP_COUNT:
		return false
	var path := _rotating_backup_path(index, character_id)
	if not _adopt_document_file(path, character_id):
		return false
	backup_restored.emit(index)
	return true


func _adopt_document_file(path: String, character_id: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	var parsed = JSON.parse_string(_read_raw_text(path))
	if not parsed is Dictionary:
		return false
	var data: Dictionary = SaveMigrator.migrate(parsed)
	if data.get("migrationFailed", false):
		return false
	if not _validate_save(data):
		return false
	SaveValidator.repair(data)
	var target_path := _active_save_path(character_id)
	if character_id != "":
		_active_character_id = character_id
		_roster["activeId"] = character_id
		_save_roster()
	if FileAccess.file_exists(target_path):
		_rotate_backups(target_path, character_id)
	_apply_save_data(data)
	_character_loaded = true
	_write_save(_build_save_payload(), false)
	restore_notice = tr("SAVE_RESTORED_NOTICE").format(
		{"time": str(data.get("cloudUpdatedAt", data.get("savedAt", "?")))}
	)
	return true


func has_continuable_run() -> bool:
	return run_is_continuable(get_active_run())


static func run_is_continuable(run: Dictionary) -> bool:
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


func set_active_run(data: Dictionary, flush: bool = true) -> void:
	_cached_state["activeRun"] = data.duplicate(true)
	if flush:
		autosave()
	else:
		request_autosave()


func clear_active_run() -> void:
	if not _cached_state.has("activeRun"):
		return
	_cached_state.erase("activeRun")
	autosave()


func get_waves_active_run() -> Dictionary:
	var active: Variant = _cached_state.get("wavesActiveRun", {})
	return active if active is Dictionary else {}


func set_waves_active_run(data: Dictionary, flush: bool = true) -> void:
	_cached_state["wavesActiveRun"] = data.duplicate(true)
	if flush:
		autosave()
	else:
		request_autosave()


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


func patch_meta(meta: Dictionary) -> void:
	_cached_state["meta"] = meta.duplicate(true)


func set_settlement_receipt(receipt: Dictionary) -> void:
	var meta := get_meta_data().duplicate(true)
	meta["runSettlement"] = receipt.duplicate(true)
	patch_meta(meta)
	autosave(SavePriority.IMMEDIATE)


func clear_settlement_receipt() -> void:
	var meta := get_meta_data().duplicate(true)
	if not meta.has("runSettlement"):
		return
	meta.erase("runSettlement")
	patch_meta(meta)
	autosave(SavePriority.IMMEDIATE)


func request_autosave(priority: SavePriority = SavePriority.DEFERRED) -> void:
	if priority == SavePriority.IMMEDIATE:
		autosave()
		return
	_autosave_pending = true
	if _autosave_timer == null:
		_autosave_timer = Timer.new()
		_autosave_timer.one_shot = true
		_autosave_timer.wait_time = AUTOSAVE_MIN_INTERVAL
		_autosave_timer.timeout.connect(_flush_deferred_autosave)
		add_child(_autosave_timer)
	if not _autosave_timer.is_stopped():
		return
	_autosave_timer.start()


func _flush_deferred_autosave() -> void:
	if not _autosave_pending:
		return
	_autosave_pending = false
	autosave(SavePriority.DEFERRED)


func autosave_checkpoint() -> void:
	_force_backup_rotation = true
	autosave()


func _backup_slot_is_stale(character_id: String) -> bool:
	var newest := _rotating_backup_path(0, character_id)
	if not FileAccess.file_exists(newest):
		return true
	var age := Time.get_unix_time_from_system() - float(FileAccess.get_modified_time(newest))
	return age >= float(BACKUP_MIN_INTERVAL_SEC)


func autosave(priority: SavePriority = SavePriority.IMMEDIATE) -> void:
	_autosave_pending = false
	if _autosave_timer != null and not _autosave_timer.is_stopped():
		_autosave_timer.stop()
	if not _can_write_active_document():
		return
	if _write_save(_build_save_payload(), true, priority):
		return

	_retry_failed_autosave(priority)


func _can_write_active_document() -> bool:
	return _active_character_id == "" or _character_loaded


func _retry_failed_autosave(priority: SavePriority) -> void:
	var tree := get_tree()
	if tree == null:
		save_failed.emit("write_failed")
		return
	await tree.create_timer(1.0).timeout
	if _write_save(_build_save_payload(), true, priority):
		return
	if CrashLogger:
		CrashLogger.log_error("local_save.autosave_failed", {"path": _active_save_path()})
	save_failed.emit("write_failed")


func delete_character(character_id: String) -> bool:
	if character_id == "":
		return false
	_finish_async_write()
	var path := _character_path(character_id)
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	for i in BACKUP_COUNT:
		var backup_path := _rotating_backup_path(i, character_id)
		if FileAccess.file_exists(backup_path):
			DirAccess.remove_absolute(backup_path)
	var characters: Array = _roster.get("characters", [])
	for i in characters.size():
		if str((characters[i] as Dictionary).get("id", "")) == character_id:
			characters.remove_at(i)
			break
	_roster["characters"] = characters
	if str(_roster.get("activeId", "")) == character_id:
		_roster["activeId"] = ""
		_active_character_id = ""
		_character_loaded = false
		_cached_state.clear()
	_save_roster()
	return true


func sync_from_cloud() -> Dictionary:
	if not ApiConfig.cloud_calls_enabled():
		return {"ok": false, "error": "offline"}
	if is_instance_valid(ApiConfig) and ApiConfig.access_token == "":
		if not await ApiClient.require_session():
			ApiConfig.set_cloud_state(ApiConfig.CloudState.SIGNED_OUT, "")
			return {"ok": false, "error": "not signed in"}
	var result := await ApiClient.get_save()
	if not result.get("ok", false):
		var sync_err := str(result.get("error", "unknown"))
		if CrashLogger:
			CrashLogger.log_warning("local_save.cloud_sync", {"error": sync_err})
		else:
			push_warning("LocalSave: cloud sync failed — %s" % sync_err)
		return {"ok": false, "error": sync_err}
	var server_json: String = str(result.get("stateJson", ""))
	var server_updated: String = str(result.get("updatedAt", ""))
	if server_json.is_empty():
		return {"ok": false, "error": "empty server state"}
	if not get_active_run().is_empty():
		push_warning("LocalSave: keeping local active run — skipping cloud overwrite")
		return {"ok": false, "error": "active run in progress"}
	var parsed = JSON.parse_string(server_json)
	if not parsed is Dictionary:
		return {"ok": false, "error": "invalid server json"}
	var adopted := _adopt_foreign_document(parsed, "cloud_sync")
	if adopted.is_empty():
		return {"ok": false, "error": "server state rejected"}
	var conflict_backup := ""
	if _cloud_updated_at != "" and server_updated != "" and _cloud_updated_at != server_updated:
		conflict_backup = _backup_local_save()
	_apply_save_data(adopted)
	_cloud_updated_at = server_updated
	_cached_state["cloudUpdatedAt"] = server_updated
	_write_save(_build_save_payload())
	cloud_sync_completed.emit(true)
	return {"ok": true, "conflictBackup": conflict_backup}


func push_to_cloud() -> Dictionary:
	if not ApiConfig.cloud_calls_enabled():
		return {"ok": false, "error": "offline"}
	if is_instance_valid(ApiConfig) and ApiConfig.access_token == "":
		if not await ApiClient.require_session():
			ApiConfig.set_cloud_state(ApiConfig.CloudState.SIGNED_OUT, "")
			return {"ok": false, "error": "not signed in"}
	var payload := _build_save_payload()
	var client_updated: Variant = null
	if _cloud_updated_at != "":
		client_updated = _cloud_updated_at
	var result := await ApiClient.put_save(JSON.stringify(payload), client_updated)
	if result.get("conflict", false):
		var conflict_backup := _backup_local_save()
		var server_state: String = str(result.get("stateJson", ""))
		if not server_state.is_empty():
			var parsed = JSON.parse_string(server_state)
			if parsed is Dictionary:
				var adopted := _adopt_foreign_document(parsed, "cloud_conflict")
				if adopted.is_empty():
					return {"ok": false, "conflict": true, "conflictBackup": conflict_backup}
				_apply_save_data(adopted)
				_cloud_updated_at = str(result.get("updatedAt", ""))
				_cached_state["cloudUpdatedAt"] = _cloud_updated_at
				_write_save(_build_save_payload())
		cloud_sync_completed.emit(true)
		return {"ok": false, "conflict": true, "conflictBackup": conflict_backup}
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
	var working := data.duplicate(true)
	_apply_account_scope(working)
	_reconcile_item_instances(working)
	GridInventory.seed_instance_ordinal(int(working.get("itemInstanceOrdinal", 0)))
	_cached_state = working
	if is_instance_valid(InventoryService):
		InventoryService.apply_save_inventory(working.get("inventory", {}))
	if is_instance_valid(StorageService):
		StorageService.apply_save_storage(working.get("storage", {}))
	var character: Dictionary = _character()
	if character.is_empty():
		character = _default_character()
		_cached_state["character"] = character
	if is_instance_valid(ProgressionService):
		(
			ProgressionService
			. from_save_dict(
				{
					"level": character.get("level", 1),
					"xp": character.get("xp", 0),
					"talentPointsSpent": working.get("talentPointsSpent", 0),
					"talents": working.get("talents", {}),
				}
			)
		)
	if is_instance_valid(CharacterService):
		var currencies: Variant = working.get("currencies", {})
		var cur: Dictionary = currencies if currencies is Dictionary else {}
		(
			CharacterService
			. from_save_dict(
				{
					"gold":
					cur.get("gold", cur.get("coins", CharacterService.DEFAULT_GOLD)),
					"classId": character.get("classId", ""),
					"appearanceTheme": character.get("appearanceTheme", 0),
					"appearance": character.get("appearance", {}),
					"flags": working.get("flags", {}),
					"quests": working.get("quests", {}),
				}
			)
		)
	if is_instance_valid(RunBuffs):
		RunBuffs.from_save_array(working.get("runRelics", []))
		RunBuffs.temporary_effects_from_save_array(working.get("runEffects", []))
		RunBuffs.offer_state_from_save(working.get("runRelicOffer", {}))
	var waves_run: Variant = working.get("wavesActiveRun", {})
	if waves_run is Dictionary and not waves_run.is_empty():
		_cached_state["wavesActiveRun"] = waves_run.duplicate(true)
		if is_instance_valid(WavesRunService):
			WavesRunService.restore_from_save(waves_run)
	elif _cached_state.has("wavesActiveRun"):
		_cached_state.erase("wavesActiveRun")
	_cloud_updated_at = str(working.get("cloudUpdatedAt", ""))


func _build_save_payload() -> Dictionary:
	var character := _character()
	if character.is_empty():
		character = _default_character()
	if is_instance_valid(ProgressionService):
		character["level"] = ProgressionService.level
		character["xp"] = ProgressionService.xp
	if is_instance_valid(CharacterService):
		if CharacterService.class_id != "":
			character["classId"] = CharacterService.class_id
		character["appearanceTheme"] = CharacterService.appearance_theme
		character["appearance"] = CharacterService.appearance_profile.duplicate(true)
	character.erase("lastHubMessage")
	var account_id := _resolve_account_id()
	_cached_state["accountId"] = account_id
	var data := {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"accountId": account_id,
		"character": character,
		"currencies":
		_cached_state.get(
			"currencies",
			{"gold": CharacterService.DEFAULT_GOLD if is_instance_valid(CharacterService) else 0}
		),
		"inventory":
		(
			InventoryService.get_save_inventory()
			if is_instance_valid(InventoryService)
			else _cached_state.get("inventory", {})
		),
		"storage":
		StorageService.get_save_storage() if StorageService else _cached_state.get("storage", {}),
		"itemInstances": _build_item_instances(),
		"itemInstanceOrdinal": GridInventory._next_instance_ordinal,
		"talents":
		(
			ProgressionService.talents.duplicate()
			if ProgressionService
			else _cached_state.get("talents", {})
		),
		"talentPointsSpent":
		ProgressionService.talent_points_spent if is_instance_valid(ProgressionService) else 0,
		"flags": _cached_state.get("flags", {}),
		"recipes": get_recipes(),
		"merchants": get_merchants(),
		"runRelics": RunBuffs.to_save_array() if RunBuffs else _cached_state.get("runRelics", []),
		"runEffects": RunBuffs.temporary_effects_to_save_array() if RunBuffs else _cached_state.get("runEffects", []),
		"runRelicOffer": RunBuffs.offer_state_to_save() if RunBuffs else _cached_state.get("runRelicOffer", {}),
	}
	if is_instance_valid(CharacterService):
		var char_save: Dictionary = CharacterService.to_save_dict()
		data["currencies"] = {"gold": char_save.get("gold", CharacterService.DEFAULT_GOLD)}
		data["flags"] = char_save.get("flags", {})
		data["quests"] = char_save.get("quests", {})
		character["classId"] = str(char_save.get("classId", ""))
		character["appearanceTheme"] = int(char_save.get("appearanceTheme", 0))
		character["appearance"] = char_save.get("appearance", character.get("appearance", {}))
	if _cached_state.has("activeRun"):
		data["activeRun"] = _cached_state["activeRun"]
	if _cached_state.has("wavesActiveRun"):
		data["wavesActiveRun"] = _cached_state["wavesActiveRun"]
	if _cached_state.has("meta"):
		data["meta"] = _cached_state["meta"]
	if _cloud_updated_at != "":
		data["cloudUpdatedAt"] = _cloud_updated_at
	_harvest_account_scope(data)
	data["account"] = _account.duplicate(true)
	return data


func _default_character() -> Dictionary:
	return {
		"name": "Wanderer",
		"classId": "",
		"level": 1,
		"xp": 0,
		"appearanceTheme": 0,
		"appearance": CharacterAppearance.default_profile(),
		"firstPersonCamera": false,
		"playtimeSeconds": 0.0,
	}


func _validate_save(data: Dictionary) -> bool:
	return SaveValidator.validate(data).is_empty()


func _reset_to_defaults() -> void:
	InventoryService.inventory = GridInventory.new()
	InventoryService.inventory.add_item("castle_sword", 1)
	_cached_state = {
		"schemaVersion": SAVE_SCHEMA_VERSION,
		"accountId": _resolve_account_id(),
		"character": _default_character(),
		"currencies": {"gold": CharacterService.DEFAULT_GOLD},
		"talents": {},
		"itemInstances": {},
		"flags": {},
		"recipes": [],
		"merchants": {},
		"runRelics": [],
	}
	if is_instance_valid(ProgressionService):
		ProgressionService.from_save_dict({})
	if is_instance_valid(CharacterService):
		CharacterService.reset_to_defaults()
	if is_instance_valid(RunBuffs):
		RunBuffs.clear_all()


func _load_document(path: String, character_id: String = "") -> bool:
	_finish_async_write()
	var raw := _read_raw_text(path)
	if raw.strip_edges().is_empty():
		return _recover_from_corruption(path, character_id, "empty_file")
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return _recover_from_corruption(path, character_id, "corrupt_json")
	var from_version := int(parsed.get("schemaVersion", 0))
	match SaveMigrator.classify(parsed):
		SaveMigrator.RESULT_TOO_NEW:
			save_failed.emit("save_from_newer_build")
			return false
		SaveMigrator.RESULT_UNKNOWN:
			return _recover_from_corruption(path, character_id, "missing schemaVersion")
		SaveMigrator.RESULT_MIGRATABLE:
			_snapshot_before_migration(path, from_version, character_id)
	var data: Dictionary = SaveMigrator.migrate(parsed)
	if data.get("migrationFailed", false):
		if str(data.get("migrationKind", "")) == "too_new":
			save_failed.emit("save_from_newer_build")
			return false
		return _recover_from_corruption(
			path, character_id, str(data.get("migrationReason", "migration_failed"))
		)
	var problems := SaveValidator.validate(data)
	if not problems.is_empty():
		return _recover_from_corruption(
			path, character_id, "corrupt_schema: %s" % ", ".join(problems)
		)
	# Anything smaller than that is fixed in place and logged, and the fixed file is written back.
	var repairs := SaveValidator.repair(data)
	if not repairs.is_empty():
		if CrashLogger:
			CrashLogger.log_warning("local_save.repaired", {"path": path, "repairs": "; ".join(repairs)})
		else:
			push_warning("LocalSave: repaired %s — %s" % [path, "; ".join(repairs)])
	if character_id != "":
		_active_character_id = character_id
		_roster["activeId"] = character_id
		_save_roster()
	_apply_save_data(data)
	_character_loaded = true
	if not repairs.is_empty():
		request_autosave()
	save_loaded.emit()
	return true


func _snapshot_before_migration(
	path: String, from_version: int, character_id: String = ""
) -> String:
	if character_id == "":
		character_id = _active_character_id
	var prefix := character_id if character_id != "" else "legacy"
	var target := (
		"%s%s.premigrate_v%d_%s.json"
		% [
			_backup_dir(),
			prefix,
			from_version,
			Time.get_datetime_string_from_system().replace(":", "-"),
		]
	)
	DirAccess.copy_absolute(path, target)
	_prune_premigrate_artefacts(prefix)
	return target


func _prune_premigrate_artefacts(prefix: String) -> void:
	var matches: Array[String] = []
	var dir := DirAccess.open(_backup_dir())
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("%s.premigrate_v" % prefix):
			matches.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	matches.sort()
	while matches.size() > BACKUP_COUNT:
		var oldest: String = matches.pop_front()
		DirAccess.remove_absolute("%s%s" % [_backup_dir(), oldest])


func _recover_from_corruption(path: String, character_id: String, reason: String) -> bool:
	if FileAccess.file_exists(path):
		var stamp := Time.get_datetime_string_from_system().replace(":", "-")
		var corrupt_path := "%s.corrupt_%s.json" % [path.get_basename(), stamp]
		_last_quarantine_path = corrupt_path
		DirAccess.copy_absolute(path, corrupt_path)
		DirAccess.remove_absolute(path)
		if CrashLogger:
			CrashLogger.log_error(
				"local_save.corrupt", {"reason": reason, "quarantinePath": corrupt_path}
			)
		else:
			push_error("LocalSave: corrupt save (%s) — quarantined to %s" % [reason, corrupt_path])
	save_failed.emit("load_failed")
	for backup in list_backups(character_id):
		var index: int = int(backup.get("index", 0))
		if restore_backup(index, character_id):
			return true
	if _restore_from_premigrate(character_id):
		return true
	print_verbose("LocalSave: %s — awaiting player recovery decision" % reason)
	recovery_required = true
	recovery_reason = reason
	recovery_character_id = character_id
	recovery_quarantine_path = _last_quarantine_path
	save_recovery_required.emit(reason, _last_quarantine_path)
	return false


func resolve_recovery_start_fresh() -> void:
	if not recovery_required:
		return
	recovery_required = false
	if recovery_character_id != "":
		# A warden whose file is unreadable is discarded: the file itself was kept at the
		# quarantine path, so nothing is lost that was not already unreadable.
		var discarded := recovery_character_id
		recovery_character_id = ""
		delete_character(discarded)
		return
	_reset_to_defaults()
	_write_save(_build_save_payload(), false)
	save_loaded.emit()


func resolve_recovery_dismiss() -> void:
	recovery_required = false
	recovery_character_id = ""


func _restore_from_premigrate(character_id: String) -> bool:
	var prefix := character_id if character_id != "" else "legacy"
	var matches: Array[String] = []
	var dir := DirAccess.open(_backup_dir())
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry.begins_with("%s.premigrate_v" % prefix):
			matches.append(entry)
		entry = dir.get_next()
	dir.list_dir_end()
	matches.sort()
	matches.reverse()
	for roster_name in matches:
		if _adopt_document_file("%s%s" % [_backup_dir(), roster_name], character_id):
			print_verbose("LocalSave: recovered from premigrate artefact %s" % roster_name)
			return true
	return false


func _warm_load_path(path: String) -> void:
	var raw := _read_raw_text(path)
	if raw.strip_edges().is_empty():
		return
	var parsed = JSON.parse_string(raw)
	if not parsed is Dictionary:
		return
	var data: Dictionary = SaveMigrator.migrate(parsed)
	if data.get("migrationFailed", false):
		return
	if not SaveValidator.validate(data).is_empty():
		return
	_cached_state = data
	_cloud_updated_at = str(data.get("cloudUpdatedAt", ""))


func _backup_local_save() -> String:
	var source := _active_save_path()
	if not FileAccess.file_exists(source):
		return ""
	var prefix := _active_character_id if _active_character_id != "" else "legacy"
	var target := (
		"%s%s.conflict_%s.json"
		% [
			_backup_dir(),
			prefix,
			Time.get_datetime_string_from_system().replace(":", "-"),
		]
	)
	DirAccess.copy_absolute(source, target)
	push_warning("LocalSave: conflict — local save backed up to %s" % target)
	return target


func _read_raw_text(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var file := FileAccess.open(path, FileAccess.READ)
	if not file:
		return ""
	return file.get_as_text()


func _active_save_path(character_id: String = "") -> String:
	if character_id == "":
		character_id = _active_character_id
	if character_id != "":
		return _character_path(character_id)
	return _save_path()


func _adopt_foreign_document(parsed: Dictionary, source: String) -> Dictionary:
	match SaveMigrator.classify(parsed):
		SaveMigrator.RESULT_TOO_NEW:
			save_failed.emit("save_from_newer_build")
			return {}
		SaveMigrator.RESULT_UNKNOWN:
			if CrashLogger:
				CrashLogger.log_error("local_save.foreign_unknown_version", {"source": source})
			return {}
		SaveMigrator.RESULT_MIGRATABLE:
			_snapshot_before_migration(
				_active_save_path(), int(parsed.get("schemaVersion", 0)), _active_character_id
			)
	var data: Dictionary = SaveMigrator.migrate(parsed)
	if data.get("migrationFailed", false):
		if str(data.get("migrationKind", "")) == "too_new":
			save_failed.emit("save_from_newer_build")
		elif CrashLogger:
			CrashLogger.log_error(
				"local_save.foreign_migration_failed",
				{"source": source, "reason": str(data.get("migrationReason", ""))}
			)
		return {}
	var problems := SaveValidator.validate(data)
	if not problems.is_empty():
		if CrashLogger:
			CrashLogger.log_error(
				"local_save.foreign_validate_failed",
				{"source": source, "problems": ", ".join(problems)}
			)
		return {}
	return data


func _write_save(
	data: Dictionary, rotate_backups: bool = true, priority: SavePriority = SavePriority.IMMEDIATE
) -> bool:
	# A deferred write may still be in flight; settle it so every write starts from a finished file.
	_finish_async_write()
	var normalized := _normalize_save_integers(data.duplicate(true))
	normalized["itemInstances"] = _build_item_instances()
	normalized["accountId"] = _resolve_account_id()
	_cached_state = normalized
	var roster_changed := false
	if _active_character_id != "":
		_update_roster_entry_metadata(normalized)
		roster_changed = true
	var target_path := _active_save_path()
	var temp_path := "%s.tmp" % target_path
	if priority == SavePriority.DEFERRED:
		# Serialising 120-220 KB is the expensive part, so it happens on a worker, on a copy the
		# worker owns; `_finish_async_write()` commits the verified file on the main thread.
		_start_async_write(normalized.duplicate(true), target_path, temp_path, rotate_backups, roster_changed)
		return true
	var verified := _serialise_and_verify(normalized, temp_path)
	if not bool(verified.get("ok", false)):
		_log_write_failure(temp_path, str(verified.get("reason", "unknown")))
		DirAccess.remove_absolute(temp_path)
		return false
	return _commit_written_file(
		temp_path, target_path, str(verified.get("sha", "")), rotate_backups, roster_changed
	)


## Writes `payload` to `temp_path`, reads it back and validates it. Touches no shared state, so it
## is safe on a worker thread.
static func _serialise_and_verify(payload: Dictionary, temp_path: String) -> Dictionary:
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "reason": "open_failed"}
	var json_text := (
		JSON.stringify(payload, "\t") if OS.is_debug_build() else JSON.stringify(payload)
	)
	var stored := file.store_string(json_text)
	var write_error := file.get_error()
	file.close()
	if not stored or write_error != OK:
		return {"ok": false, "reason": "write_error_%d" % write_error}
	var verified: Variant = JSON.parse_string(FileAccess.get_file_as_string(temp_path))
	if not verified is Dictionary:
		return {"ok": false, "reason": "readback_unparseable"}
	var problems := SaveValidator.validate(verified as Dictionary)
	if not problems.is_empty():
		return {"ok": false, "reason": "readback_validate_failed: %s" % ", ".join(problems)}
	return {"ok": true, "sha": json_text.sha256_text()}


func _log_write_failure(path: String, reason: String) -> void:
	if CrashLogger:
		CrashLogger.log_error("local_save.write_failed", {"path": path, "reason": reason})
	else:
		push_warning("LocalSave: could not write %s (%s)" % [path, reason])


## The half of a save that has to stay on the main thread: backups, the journal, the rename that
## makes the new file live, and the roster.
func _commit_written_file(
	temp_path: String,
	target_path: String,
	checksum: String,
	rotate_backups: bool,
	roster_changed: bool
) -> bool:
	if rotate_backups and FileAccess.file_exists(target_path):
		if _force_backup_rotation or _backup_slot_is_stale(_active_character_id):
			_rotate_backups(target_path, _active_character_id)
	_force_backup_rotation = false
	var journal: Dictionary = {}
	if roster_changed:
		journal = {
			"savePath": target_path,
			"saveChecksum": checksum,
			"roster": _roster.duplicate(true),
		}
		if not _write_json_atomic(_journal_path(), journal):
			DirAccess.remove_absolute(temp_path)
			return false
	if DirAccess.rename_absolute(temp_path, target_path) != OK:
		DirAccess.remove_absolute(temp_path)
		if not journal.is_empty():
			DirAccess.remove_absolute(_journal_path())
		if CrashLogger:
			CrashLogger.log_error("local_save.rename_failed", {"path": target_path})
		return false
	if roster_changed:
		if not _save_roster():
			return false
		DirAccess.remove_absolute(_journal_path())
	return true


func _start_async_write(
	payload: Dictionary,
	target_path: String,
	temp_path: String,
	rotate_backups: bool,
	roster_changed: bool
) -> void:
	var outcome := {}
	var task_id := WorkerThreadPool.add_task(
		func() -> void:
			outcome.merge(_serialise_and_verify(payload, temp_path))
	)
	_async_write = {
		"task": task_id,
		"outcome": outcome,
		"payload": payload,
		"target": target_path,
		"temp": temp_path,
		"rotate": rotate_backups,
		"roster": roster_changed,
	}


## Completes the in-flight deferred write, if any, waiting for the worker when it has not finished.
## A failure is reported like any other failed save and retried on the next deferred tick.
func _finish_async_write() -> void:
	if _async_write.is_empty():
		return
	var job := _async_write
	_async_write = {}
	WorkerThreadPool.wait_for_task_completion(int(job["task"]))
	var outcome: Dictionary = job["outcome"]
	var temp_path := str(job["temp"])
	if not bool(outcome.get("ok", false)):
		_log_write_failure(temp_path, str(outcome.get("reason", "unknown")))
		DirAccess.remove_absolute(temp_path)
		save_failed.emit("write_failed")
		request_autosave()
		return
	if not _commit_written_file(
		temp_path,
		str(job["target"]),
		str(outcome.get("sha", "")),
		bool(job["rotate"]),
		bool(job["roster"])
	):
		save_failed.emit("write_failed")
		request_autosave()


func _utc_now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


func _save_stamp_unix(stamp: String) -> int:
	if stamp.strip_edges().is_empty():
		return 0
	return int(Time.get_unix_time_from_datetime_string(stamp))


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


func _build_item_instances() -> Dictionary:
	var out: Dictionary = {}
	for slot in InventoryService.inventory.slots:
		_index_instance(out, slot)
	for slot_name in InventoryService.inventory.equipped:
		_index_instance(out, InventoryService.inventory.equipped[slot_name])
	if is_instance_valid(StorageService):
		for slot in StorageService.storage.slots:
			_index_instance(out, slot)
	return out


func _index_instance(out: Dictionary, slot: Variant) -> void:
	if not slot is Dictionary or slot.is_empty():
		return
	var instance_id := str(slot.get("instanceId", ""))
	if instance_id == "":
		return
	var entry := {
		"schemaVersion": 1,
		"instanceId": instance_id,
		"itemDefId": str(slot.get("itemId", "")),
		"itemId": str(slot.get("itemId", "")),
		"rarity": str(slot.get("rarity", "common")),
		"affixes": slot.get("affixes", []),
		"rollSeed": int(slot.get("rollSeed", 0)),
	}
	out[instance_id] = entry


func _reconcile_item_instances(data: Dictionary) -> void:
	var instances: Variant = data.get("itemInstances", {})
	if not instances is Dictionary:
		return
	var inv: Variant = data.get("inventory", {})
	if inv is Dictionary:
		_reconcile_slots_from_instances(inv.get("slots", []), instances)
		_reconcile_equipped_from_instances(inv.get("equipped", {}), instances)
		data["inventory"] = inv
	var storage: Variant = data.get("storage", {})
	if storage is Dictionary:
		_reconcile_slots_from_instances(storage.get("slots", []), instances)
		data["storage"] = storage


func _reconcile_slots_from_instances(slots: Variant, instances: Dictionary) -> void:
	if not slots is Array:
		return
	for i in slots.size():
		if not slots[i] is Dictionary:
			continue
		slots[i] = _reconcile_slot(slots[i], instances)


func _reconcile_equipped_from_instances(equipped: Variant, instances: Dictionary) -> void:
	if not equipped is Dictionary:
		return
	for slot_name in equipped:
		if equipped[slot_name] is Dictionary and not equipped[slot_name].is_empty():
			equipped[slot_name] = _reconcile_slot(equipped[slot_name], instances)


func _reconcile_slot(slot: Dictionary, instances: Dictionary) -> Dictionary:
	if slot.has("affixes"):
		return slot
	var instance_id := str(slot.get("instanceId", ""))
	if instance_id == "" or not instances.has(instance_id):
		return slot
	var source: Dictionary = instances[instance_id]
	var out := slot.duplicate(true)
	if source.has("affixes"):
		out["affixes"] = source.get("affixes", []).duplicate(true)
	if not out.has("rarity") and source.has("rarity"):
		out["rarity"] = source.get("rarity")
	if not out.has("rollSeed") and source.has("rollSeed"):
		out["rollSeed"] = source.get("rollSeed")
	return out


func _rotate_backups(source_path: String, character_id: String = "") -> void:
	_ensure_backup_dir()
	for i in range(BACKUP_COUNT - 1, 0, -1):
		var from_path := _rotating_backup_path(i - 1, character_id)
		var to_path := _rotating_backup_path(i, character_id)
		if FileAccess.file_exists(from_path):
			if FileAccess.file_exists(to_path):
				DirAccess.remove_absolute(to_path)
			DirAccess.rename_absolute(from_path, to_path)
	if FileAccess.file_exists(source_path):
		DirAccess.copy_absolute(source_path, _rotating_backup_path(0, character_id))


func _rotating_backup_path(index: int, character_id: String = "") -> String:
	if character_id == "":
		return "%saumbrye_save_%d.json" % [_backup_dir(), index]
	return "%s%s_%d.json" % [_backup_dir(), character_id, index]


func _ensure_backup_dir() -> void:
	if not DirAccess.dir_exists_absolute(_backup_dir()):
		DirAccess.make_dir_recursive_absolute(_backup_dir())


func _ensure_characters_dir() -> void:
	if not DirAccess.dir_exists_absolute(_characters_dir()):
		DirAccess.make_dir_recursive_absolute(_characters_dir())


func _load_roster() -> void:
	if not FileAccess.file_exists(_roster_path()):
		_roster = {"characters": [], "activeId": "", "localAccountId": ""}
		_active_character_id = ""
		_character_loaded = false
		return
	var parsed = JSON.parse_string(_read_raw_text(_roster_path()))
	if parsed is Dictionary:
		_roster = parsed
		if not _roster.has("localAccountId"):
			_roster["localAccountId"] = ""
		_active_character_id = str(_roster.get("activeId", ""))
	else:
		_roster = {"characters": [], "activeId": "", "localAccountId": ""}
		_active_character_id = ""
	_character_loaded = false
	_heal_roster_class_ids()


func _heal_roster_class_ids() -> void:
	var characters: Array = _roster.get("characters", [])
	var healed := 0
	for i in characters.size():
		var entry: Dictionary = characters[i] as Dictionary
		var character_id := str(entry.get("id", ""))
		if character_id == "":
			continue
		var path := _character_path(character_id)
		var in_roster := str(entry.get("classId", ""))
		var in_document := _class_id_in_document(path)
		if in_roster != "" and in_document != "":
			continue
		var recovered := in_roster if in_roster != "" else in_document
		if recovered == "":
			recovered = _recover_class_id(character_id)
		if recovered == "":
			continue
		if in_document == "":
			_restore_class_id_in_document(path, recovered)
		if in_roster == "":
			entry["classId"] = recovered
			characters[i] = entry
		healed += 1
	if healed <= 0:
		return
	_roster["characters"] = characters
	_save_roster()

	push_warning(
		"LocalSave: restored a blanked classId for %d character%s"
		% [healed, "" if healed == 1 else "s"]
	)


func _recover_class_id(character_id: String) -> String:
	for i in BACKUP_COUNT:
		var from_backup := _class_id_in_document(_rotating_backup_path(i, character_id))
		if from_backup != "":
			return from_backup
	return ""


func _restore_class_id_in_document(path: String, class_id: String) -> void:
	if class_id == "" or not FileAccess.file_exists(path):
		return
	var parsed = JSON.parse_string(_read_raw_text(path))
	if not parsed is Dictionary:
		return
	var data: Dictionary = parsed
	var character: Variant = data.get("character", {})
	if not character is Dictionary:
		return
	var character_dict: Dictionary = character
	if str(character_dict.get("classId", "")) != "":
		return
	character_dict["classId"] = class_id
	data["character"] = character_dict
	_write_json_atomic(path, data)


func _class_id_in_document(path: String) -> String:
	if not FileAccess.file_exists(path):
		return ""
	var parsed = JSON.parse_string(_read_raw_text(path))
	if not parsed is Dictionary:
		return ""
	var character: Variant = (parsed as Dictionary).get("character", {})
	if not character is Dictionary:
		return ""
	return str((character as Dictionary).get("classId", ""))


func _save_roster() -> bool:
	return _write_json_atomic(_roster_path(), _roster)


func _recover_save_set_journal() -> void:
	if not FileAccess.file_exists(_journal_path()):
		return
	var parsed: Variant = JSON.parse_string(_read_raw_text(_journal_path()))
	if not parsed is Dictionary:
		DirAccess.remove_absolute(_journal_path())
		return
	var journal: Dictionary = parsed
	var save_path := str(journal.get("savePath", ""))
	var expected_checksum := str(journal.get("saveChecksum", ""))
	var roster: Variant = journal.get("roster", {})
	if save_path == "" or expected_checksum == "" or not roster is Dictionary:
		DirAccess.remove_absolute(_journal_path())
		return
	if _read_raw_text(save_path).sha256_text() != expected_checksum:
		return
	if _write_json_atomic(_roster_path(), roster as Dictionary):
		DirAccess.remove_absolute(_journal_path())


func _write_json_atomic(path: String, data: Dictionary) -> bool:
	var temp_path := "%s.tmp" % path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		if CrashLogger:
			CrashLogger.log_error("local_save.sidecar_write_failed", {"path": temp_path})
		return false
	file.store_string(JSON.stringify(data, "\t"))
	file.close()
	if DirAccess.rename_absolute(temp_path, path) != OK:
		if CrashLogger:
			CrashLogger.log_error("local_save.sidecar_rename_failed", {"path": path})
		return false
	return true


func _character_path(character_id: String) -> String:
	return "%s%s.json" % [_characters_dir(), character_id]


func _generate_character_id() -> String:
	for attempt in 100:
		_character_id_counter += 1
		var suffix := (Time.get_ticks_usec() + _character_id_counter + attempt) % 1000000000
		var candidate := "warden_%d" % suffix
		if (
			not _roster_has_character_id(candidate)
			and not FileAccess.file_exists(_character_path(candidate))
		):
			return candidate
	return "warden_%d" % randi()


func _roster_has_character_id(character_id: String) -> bool:
	for entry in _roster.get("characters", []):
		if entry is Dictionary and str(entry.get("id", "")) == character_id:
			return true
	return false


func _resolve_account_id() -> String:
	if is_instance_valid(ApiConfig) and ApiConfig.access_token != "" and ApiConfig.account_id != "":
		return ApiConfig.account_id
	var cached := str(_cached_state.get("accountId", ""))
	if cached != "" and cached != SaveMigrator.NIL_ACCOUNT_ID:
		return cached
	var local_id := str(_roster.get("localAccountId", ""))
	if local_id == "":
		local_id = _generate_uuid_v4()
		_roster["localAccountId"] = local_id
		_save_roster()
	return local_id


func _generate_uuid_v4() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in 16:
		bytes[i] = randi() % 256
	bytes[6] = (bytes[6] & 0x0f) | 0x40
	bytes[8] = (bytes[8] & 0x3f) | 0x80
	var hex := ""
	for i in 16:
		hex += "%02x" % bytes[i]
	return (
		"%s-%s-%s-%s-%s"
		% [
			hex.substr(0, 8),
			hex.substr(8, 4),
			hex.substr(12, 4),
			hex.substr(16, 4),
			hex.substr(20, 12),
		]
	)


func _migrate_legacy_save_if_needed() -> void:
	var characters: Array = _roster.get("characters", [])
	if not characters.is_empty():
		return
	if not FileAccess.file_exists(_save_path()):
		return
	var summary := _read_character_summary(_save_path())
	if not bool(summary.get("hasCharacter", false)):
		return
	var character_id := _generate_character_id()
	var parsed = JSON.parse_string(_read_raw_text(_save_path()))
	if not parsed is Dictionary:
		return
	var char_file := FileAccess.open(_character_path(character_id), FileAccess.WRITE)
	if char_file:
		char_file.store_string(JSON.stringify(parsed, "\t"))
		char_file.close()
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
	(
		characters
		. append(
			{
				"id": character_id,
				"name": character_name,
				"classId": class_id,
				"level": level,
				"savedAt": saved_at if saved_at != "" else _utc_now_iso(),
			}
		)
	)
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
		var incoming_class := str(character.get("classId", ""))
		if incoming_class != "":
			entry["classId"] = incoming_class
		elif not entry.has("classId"):
			entry["classId"] = ""
		entry["level"] = int(character.get("level", entry.get("level", 1)))
		entry["playtimeSeconds"] = float(
			character.get("playtimeSeconds", entry.get("playtimeSeconds", 0.0))
		)
		entry["savedAt"] = _utc_now_iso()
		characters[i] = entry
		break
	_roster["characters"] = characters
