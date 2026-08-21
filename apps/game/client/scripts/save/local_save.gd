extends Node

## Autoload — local JSON save + cloud cache (SAVE-4.1).

const SAVE_PATH := "user://aumbrye_save.json"
const STEAM_CLOUD_SAVE_NAME := "aumbrye_save.json"
const ROSTER_PATH := "user://character_roster.json"
const ACCOUNT_PATH := "user://account.json"
const ACCOUNT_SCHEMA_VERSION := 1
const MAX_CHARACTER_SLOTS := 5
const CHARACTERS_DIR := "user://characters/"
const BACKUP_DIR := "user://backups/"
const BACKUP_COUNT := 5

## C-232: backup depth used to be measured in *writes*, and 56 call sites reach `autosave()`
## immediately — including display mode, key rebinding, locale, audio, accessibility and privacy
## settings. Opening the options screen and changing a handful of them cycled the whole five-deep
## history without a second of play, leaving five backups all stamped within the same minute.
## Rotation is now gated on the age of the newest backup, so the history spans real time.
## `autosave_checkpoint()` bypasses the gate for run-boundary saves, which are the states a player
## actually wants to return to.
const BACKUP_MIN_INTERVAL_SEC := 300
const SAVE_SCHEMA_VERSION := SaveMigrator.CURRENT_VERSION
const AUTOSAVE_MIN_INTERVAL := 2.0

signal save_loaded
signal save_failed(reason: String)
signal cloud_sync_completed(server_won: bool)
signal backup_restored(index: int)

## C-233: a save could not be read and every backup failed with it. Carries the reason and the path
## the unreadable file was quarantined to, so the player can be told where their data went before
## anything is discarded.
signal save_recovery_required(reason: String, quarantine_path: String)

enum SavePriority { IMMEDIATE, DEFERRED }

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
var _autosave_pending := false
var _force_backup_rotation := false

## C-233: set when a load failed past every recovery route and the player has not yet chosen what to
## do. Read by the title screen; nothing is reset while it stands.
var recovery_required := false
var recovery_reason := ""
var recovery_quarantine_path := ""
var _last_quarantine_path := ""
var _autosave_timer: Timer
var _character_id_counter := 0


func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH)


## Loads the legacy single-save document at `SAVE_PATH`.
##
## This is *not* the right entry point once a roster exists — each character has its own document
## under `characters/`, and `SAVE_PATH` is only the pre-roster file kept for migration. Use
## `reload_active_into_services()` unless you specifically mean the legacy path.
func load_into_services() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	return _load_document(SAVE_PATH)


## Reloads whichever document is authoritative for the active character.
##
## The same rule `_ready()` and `execute_boot()`'s CONTINUE_MAIN branch already apply: the active
## character's own document when there is one, and only otherwise the legacy save.
##
## `Hub._boot_save_and_services` used to call `load_into_services()` directly, which meant that
## after character creation the hub re-read a stale `aumbrye_save.json` belonging to nobody — so
## `CharacterService.class_id` came back empty, the hub's own guard fired, and the player was sent
## straight back to the main menu holding a character that had in fact been created and written to
## disk correctly. That is the "Begin sends me to the menu" bug.
## The roster id of the character currently loaded, or "" before one is chosen.
func get_active_character_id() -> String:
	return _active_character_id


func reload_active_into_services() -> bool:
	if _active_character_id != "" and FileAccess.file_exists(_character_path(_active_character_id)):
		return load_character(_active_character_id)
	return load_into_services()


func _ready() -> void:
	_ensure_backup_dir()
	_ensure_characters_dir()
	_load_roster()
	_load_account()
	_migrate_legacy_save_if_needed()
	_try_adopt_steam_cloud_save()
	if _active_character_id != "" and FileAccess.file_exists(_character_path(_active_character_id)):
		_warm_load_path(_character_path(_active_character_id))
	elif FileAccess.file_exists(SAVE_PATH):
		_warm_load_path(SAVE_PATH)


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


func get_xp() -> int:
	return int(_character().get("xp", 0))


func get_character_name() -> String:
	return str(_character().get("name", "Wanderer"))


## Name plus the earned title the player picked in character creation, e.g. "Isolde the Oathkept".
##
## The Title row wrote its choice into the appearance profile and the profile was saved and
## reloaded faithfully, but nothing in the game ever read it back — the title could be chosen and
## then never appeared anywhere. This is the accessor screens use when they name the warden.
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


## The stash, the bestiary and everything the world itself learned live once per
## account, which is the whole reason a second warden is worth starting.
func get_account_data() -> Dictionary:
	return _account.duplicate(true)


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
	if not FileAccess.file_exists(ACCOUNT_PATH):
		_account = _default_account()
		return
	var parsed = JSON.parse_string(_read_raw_text(ACCOUNT_PATH))
	if parsed is Dictionary:
		_account = _default_account()
		for key in parsed as Dictionary:
			_account[str(key)] = (parsed as Dictionary)[key]
		_account["schemaVersion"] = ACCOUNT_SCHEMA_VERSION
	else:
		_account = _default_account()


func _save_account() -> void:
	var file := FileAccess.open(ACCOUNT_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(_account, "\t"))
	file.close()


## An account flag never regresses when a second character has seen less of the world
## than the first: booleans latch true, counters keep the higher value, dictionaries merge.
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


## Adopts whatever the document carries into the account layer the first time it is
## seen, then hands the account copy back so every character shares one stash and one
## record of what the world has already given up.
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
					"label":
					(
						"%s — %s (Lv%d)"
						% [
							entry.get("name", "Warden"),
							class_id,
							int(entry.get("level", 1)),
						]
					),
					"detail":
					(
						"Class: %s\nLast played: %s"
						% [
							class_id,
							entry.get("savedAt", "unknown"),
						]
					),
				}
			)
		)
	return slots


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
	set_meta_data(meta)


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


## Why the last `execute_boot()` returned false, as a translation key. Empty when it succeeded.
##
## The call used to return a bare bool, so `LoadingScreen` showed "Could not load save" for every
## cause — including a full character roster, which is not a load failure at all and which the
## player can actually do something about.
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
	return _load_document(path, character_id)


func get_recipes() -> Array:
	var recipes: Variant = _cached_state.get("recipes", [])
	return recipes.duplicate() if recipes is Array else []


func get_owned_recipes() -> Array:
	return get_recipes()


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
	if is_instance_valid(ProgressionService):
		return ProgressionService.talents.duplicate()
	var talents: Variant = _cached_state.get("talents", {})
	return talents if talents is Dictionary else {}


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


## C-233: extracted from `restore_backup` so the premigrate artefacts can be recovered through the
## identical migrate/validate path. Returns false without side effects if the file is missing,
## unparseable, fails migration or fails validation.
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
	var target_path := _active_save_path(character_id)
	if character_id != "":
		_active_character_id = character_id
		_roster["activeId"] = character_id
		_save_roster()
	if FileAccess.file_exists(target_path):
		_rotate_backups(target_path, character_id)
	_apply_save_data(data)
	_write_save(_build_save_payload(), false)
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


## Forces a backup generation regardless of how recently the last one was taken. For run-boundary
## saves — floor transition, bonfire rest, death, escape, retreat — where the pre-transition state
## is worth keeping even if the player just changed a setting.
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
	if _write_save(_build_save_payload(), true, priority):
		return

	# A full disk or an antivirus lock used to fail here in total silence — save_failed only ever
	# fired for load problems, so a player could keep going for hours believing they were saved.
	# Retry once shortly after, in case the lock was transient, then tell the player.
	_retry_failed_autosave(priority)


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
	_roster = {
		"characters": [], "activeId": "", "localAccountId": str(_roster.get("localAccountId", ""))
	}
	_save_roster()


func delete_character(character_id: String) -> bool:
	if character_id == "":
		return false
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
	var path := _rotating_backup_path(backup_index, _active_character_id)
	if not FileAccess.file_exists(path):
		return false
	DirAccess.remove_absolute(path)
	return true


## Pull cloud save; server wins on conflict (local backed up first).
func sync_from_cloud() -> Dictionary:
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


## Push local save to cloud; returns false on conflict (server state in result).
func push_to_cloud() -> Dictionary:
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
		# BUG-18: persist the instance-id high-water mark so a fresh session cannot mint an id
		# that collides with one already on disk from a prior session.
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
	if character_id != "":
		_active_character_id = character_id
		_roster["activeId"] = character_id
		_save_roster()
	_apply_save_data(data)
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
			BACKUP_DIR,
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
	var dir := DirAccess.open(BACKUP_DIR)
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
		DirAccess.remove_absolute("%s%s" % [BACKUP_DIR, oldest])


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
	# C-233: this emitted the raw reason, which `combat_hud._on_save_failed` renders through its
	# default arm as "Saving failed (corrupt_schema: ...)" — wrong verb for a *load* failure, and
	# no mention of the quarantine copy. Load failures now carry their own reason so the message
	# can name the file that was kept.
	save_failed.emit("load_failed")
	for backup in list_backups(character_id):
		var index: int = int(backup.get("index", 0))
		if restore_backup(index, character_id):
			return true
	# C-233: a bug in any migration step fails identically on the live save and on all five rotating
	# backups, because they are documents of the same vintage. The premigrate artefacts are the only
	# copies a later build could still read, so they are tried after the backups rather than not at
	# all.
	if _restore_from_premigrate(character_id):
		return true
	if character_id == "":
		# C-233 (fix 1): this used to call `_reset_to_defaults()` immediately — a silent, automatic
		# wipe of the player's progress, announced only through a message that said "Saving failed".
		# The data is not gone (it is quarantined next to the save), but nothing told the player
		# that, and nothing gave them the choice.
		#
		# Nothing is reset here now. The failure is published with the quarantine path, and
		# `recovery_required` holds until someone resolves it — the title screen offers the choice
		# and calls `resolve_recovery_start_fresh()` or `resolve_recovery_dismiss()`. If no UI is
		# listening the game still boots on defaults (`_state` was never populated), so this cannot
		# soft-lock a build that has not wired the screen; it just stops the wipe being silent.
		print_verbose("LocalSave: %s — awaiting player recovery decision" % reason)
		recovery_required = true
		recovery_reason = reason
		recovery_quarantine_path = _last_quarantine_path
		save_recovery_required.emit(reason, _last_quarantine_path)
	return false


## C-233: the player's answer to the recovery prompt — discard the unreadable save and begin again.
func resolve_recovery_start_fresh() -> void:
	if not recovery_required:
		return
	recovery_required = false
	_reset_to_defaults()
	_write_save(_build_save_payload(), false)
	save_loaded.emit()


## C-233: the player's answer to the recovery prompt — leave the quarantined file alone and carry on
## with an empty profile, so a later build with a fixed migrator can still read it.
func resolve_recovery_dismiss() -> void:
	recovery_required = false


## Newest premigrate snapshot first. These are pre-migration documents, so they are only useful
## when the live save and every rotating backup died in the migrator itself.
func _restore_from_premigrate(character_id: String) -> bool:
	var prefix := character_id if character_id != "" else "legacy"
	var matches: Array[String] = []
	var dir := DirAccess.open(BACKUP_DIR)
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
		if _adopt_document_file("%s%s" % [BACKUP_DIR, roster_name], character_id):
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
			BACKUP_DIR,
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
	return SAVE_PATH



## C-238: shared adoption gate for documents of unknown provenance.
##
## `_load_document` ran classify -> premigrate snapshot -> migrate -> validate before applying a
## disk save. `sync_from_cloud` and `push_to_cloud`'s conflict branch applied the server document
## straight to services with none of it, then wrote it back stamped with the *current*
## schemaVersion — permanently disqualifying the migrator from ever repairing it.
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
	var normalized := _normalize_save_integers(data.duplicate(true))
	normalized["itemInstances"] = _build_item_instances()
	normalized["accountId"] = _resolve_account_id()
	_cached_state = normalized
	if _active_character_id != "":
		_update_roster_entry_metadata(normalized)
		_save_roster()
	var target_path := _active_save_path()
	var temp_path := "%s.tmp" % target_path
	var file := FileAccess.open(temp_path, FileAccess.WRITE)
	if not file:
		if CrashLogger:
			CrashLogger.log_error("local_save.write_failed", {"path": temp_path})
		else:
			push_warning("LocalSave: could not write %s" % temp_path)
		return false
	var json_text := (
		JSON.stringify(normalized, "\t") if OS.is_debug_build() else JSON.stringify(normalized)
	)
	file.store_string(json_text)
	file.close()
	if priority == SavePriority.IMMEDIATE:
		# Read back through a fresh handle and re-parse — the strongest corruption guard, worth
		# the cost for a save the caller is treating as urgent (e.g. before quitting).
		var verified = JSON.parse_string(_read_raw_text(temp_path))
		if not verified is Dictionary:
			if CrashLogger:
				CrashLogger.log_error(
					"local_save.readback_unparseable", {"path": temp_path}
				)
			DirAccess.remove_absolute(temp_path)
			return false
		# Log WHICH invariant the round-tripped save broke. Deleting the temp file silently made
		# corruption sources undiagnosable.
		var problems := SaveValidator.validate(verified)
		if not problems.is_empty():
			if CrashLogger:
				CrashLogger.log_error(
					"local_save.readback_validate_failed",
					{"path": temp_path, "problems": ", ".join(problems)}
				)
			else:
				push_error("LocalSave: read-back validation failed — %s" % ", ".join(problems))
			DirAccess.remove_absolute(temp_path)
			return false
	else:
		# Deferred autosaves validate the in-memory payload that was just serialized instead of
		# reading the file back — the write handle is already flushed and closed above, so the
		# on-disk bytes match `normalized`; this is the expensive re-read/re-parse round trip
		# a background autosave does not need to pay for.
		var deferred_problems := SaveValidator.validate(normalized)
		if not deferred_problems.is_empty():
			DirAccess.remove_absolute(temp_path)
			if CrashLogger:
				CrashLogger.log_error(
					"local_save.deferred_validate_failed",
					{"path": temp_path, "problems": ", ".join(deferred_problems)}
				)
			else:
				push_error(
					"LocalSave: deferred validation failed — %s" % ", ".join(deferred_problems)
				)
			return false
	# C-231: rotation happens here — after the temp file exists and has validated, immediately
	# before the commit. It used to run *before* the write, so a failed write (full disk, AV lock)
	# still consumed a backup generation and duplicated the current save into slot 0. Three failures
	# collapsed the whole five-slot history, precisely when a player would want to roll back.
	if rotate_backups and FileAccess.file_exists(target_path):
		if _force_backup_rotation or _backup_slot_is_stale(_active_character_id):
			_rotate_backups(target_path, _active_character_id)
	_force_backup_rotation = false
	if DirAccess.rename_absolute(temp_path, target_path) != OK:
		DirAccess.remove_absolute(temp_path)
		if CrashLogger:
			CrashLogger.log_error("local_save.rename_failed", {"path": target_path})
		return false
	_mirror_to_steam_cloud(normalized)
	return true


## Current time as an ISO-8601 UTC instant.
##
## Save timestamps are compared against `cloudUpdatedAt`, which the backend writes in UTC. Stamping
## local time here meant any player east of UTC produced strings that sorted ahead of newer cloud
## saves, so adoption silently kept the older copy.
func _utc_now_iso() -> String:
	return Time.get_datetime_string_from_system(true) + "Z"


## Parses a save timestamp to a unix time, or 0 when it cannot be trusted.
##
## Legacy saves carry local-time strings with no offset suffix; those are indistinguishable from
## UTC once written, so a parse that succeeds is taken at face value and a parse that fails is
## reported as unknown for the caller to handle conservatively.
func _save_stamp_unix(stamp: String) -> int:
	if stamp.strip_edges().is_empty():
		return 0
	return int(Time.get_unix_time_from_datetime_string(stamp))


func _try_adopt_steam_cloud_save() -> void:
	if has_save() or has_playable_character():
		return
	if SteamService == null or not SteamService.cloud_enabled:
		return
	var cloud_text := SteamService.read_cloud_file(STEAM_CLOUD_SAVE_NAME)
	if cloud_text.strip_edges().is_empty():
		return
	var parsed = JSON.parse_string(cloud_text)
	if not parsed is Dictionary:
		return
	var cloud_updated := str(parsed.get("cloudUpdatedAt", parsed.get("savedAt", "")))
	var local_updated := str(_cached_state.get("cloudUpdatedAt", _cached_state.get("savedAt", "")))
	if local_updated != "":
		# Compare parsed instants, never raw strings: a lexicographic compare across two different
		# clocks is what discarded hours of progress on a fresh install with Steam Cloud enabled.
		var cloud_unix := _save_stamp_unix(cloud_updated)
		var local_unix := _save_stamp_unix(local_updated)
		if cloud_unix == 0 or local_unix == 0:
			# An untrusted stamp on either side: keep the local save, which is the copy the player
			# is definitely holding.
			push_warning(
				"LocalSave: unparseable save timestamp (cloud='%s', local='%s'); keeping local."
				% [cloud_updated, local_updated]
			)
			return
		if cloud_unix <= local_unix:
			return
	_apply_save_data(parsed)
	_cloud_updated_at = cloud_updated
	_cached_state["cloudUpdatedAt"] = cloud_updated


func _mirror_to_steam_cloud(payload: Dictionary) -> void:
	if SteamService == null or not SteamService.cloud_enabled:
		return
	var json_text := JSON.stringify(payload, "\t")
	if not SteamService.write_cloud_file(STEAM_CLOUD_SAVE_NAME, json_text) and CrashLogger:
		CrashLogger.log_warning("local_save.steam_cloud_write", {"file": STEAM_CLOUD_SAVE_NAME})


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
	if slot.has("durability"):
		entry["durability"] = slot.get("durability")
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
		return "%saumbrye_save_%d.json" % [BACKUP_DIR, index]
	return "%s%s_%d.json" % [BACKUP_DIR, character_id, index]


func _ensure_backup_dir() -> void:
	if not DirAccess.dir_exists_absolute(BACKUP_DIR):
		DirAccess.make_dir_recursive_absolute(BACKUP_DIR)


func _ensure_characters_dir() -> void:
	if not DirAccess.dir_exists_absolute(CHARACTERS_DIR):
		DirAccess.make_dir_recursive_absolute(CHARACTERS_DIR)


func _load_roster() -> void:
	if not FileAccess.file_exists(ROSTER_PATH):
		_roster = {"characters": [], "activeId": "", "localAccountId": ""}
		_active_character_id = ""
		return
	var parsed = JSON.parse_string(_read_raw_text(ROSTER_PATH))
	if parsed is Dictionary:
		_roster = parsed
		if not _roster.has("localAccountId"):
			_roster["localAccountId"] = ""
		_active_character_id = str(_roster.get("activeId", ""))
	else:
		_roster = {"characters": [], "activeId": "", "localAccountId": ""}
		_active_character_id = ""


func _save_roster() -> void:
	var file := FileAccess.open(ROSTER_PATH, FileAccess.WRITE)
	if not file:
		return
	file.store_string(JSON.stringify(_roster, "\t"))
	file.close()


func _character_path(character_id: String) -> String:
	return "%s%s.json" % [CHARACTERS_DIR, character_id]


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
		entry["classId"] = str(character.get("classId", entry.get("classId", "")))
		entry["level"] = int(character.get("level", entry.get("level", 1)))
		entry["savedAt"] = _utc_now_iso()
		characters[i] = entry
		break
	_roster["characters"] = characters
