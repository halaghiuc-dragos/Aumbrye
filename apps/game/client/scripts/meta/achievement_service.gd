extends Node

## M6 achievement service — unlock tracking, toasts, cloud sync.

signal achievement_unlocked(achievement_id: String, display_name: String)

const CATALOG_PATH := "content/achievements/catalog.json"
const HOOKS_PATH := "content/achievements/hooks.json"
const TOAST_SCENE: PackedScene = preload("res://scenes/ui/achievement_toast.tscn")
const COUNTER_PREFIX := "ach_ctr_"

var _unlocked: Dictionary = {}
var _definitions: Array = []
var _hooks: Array = []
var _manual_unlocks: Array[String] = []


func _ready() -> void:
	_load_catalog()
	_load_hooks()
	_load_from_save()
	if SteamService:
		if SteamService.is_available():
			_sync_steam_on_load()
		elif not SteamService.steam_ready.is_connected(_sync_steam_on_load):
			SteamService.steam_ready.connect(_sync_steam_on_load, CONNECT_ONE_SHOT)


func _load_catalog() -> void:
	var data: Dictionary = ContentLoader.load_json(CATALOG_PATH)
	_definitions = data.get("achievements", [])


func _load_hooks() -> void:
	var data: Dictionary = ContentLoader.load_json(HOOKS_PATH)
	_hooks = data.get("hooks", [])
	_manual_unlocks.clear()
	for entry in data.get("manualUnlock", []):
		_manual_unlocks.append(str(entry))


func _load_from_save() -> void:
	var save_data := LocalSave.get_meta_data()
	var achievements: Variant = save_data.get("achievements", {})
	if achievements is Dictionary:
		_unlocked = achievements.duplicate()
	_sync_steam_on_load()


func _sync_steam_on_load() -> void:
	if SteamService and SteamService.is_available():
		SteamService.sync_achievements(get_unlocked_ids())


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.get(achievement_id, false)


func unlock(achievement_id: String) -> bool:
	if is_unlocked(achievement_id):
		return false
	_unlocked[achievement_id] = true
	_persist()
	if SteamService:
		SteamService.unlock_achievement(achievement_id)
	var display_name := _get_display_name(achievement_id)
	achievement_unlocked.emit(achievement_id, display_name)
	_show_toast(display_name)
	return true


func notify(event: String, context: Dictionary = {}) -> void:
	for hook in _hooks:
		if not hook is Dictionary:
			continue
		if str(hook.get("event", "")) != event:
			continue
		var achievement_id: String = str(hook.get("achievementId", ""))
		if achievement_id == "":
			continue
		if hook.has("contextKey"):
			if str(context.get(hook.get("contextKey"), "")) != str(hook.get("contextValue", "")):
				continue
		if hook.has("threshold"):
			var counter_key: String = str(hook.get("counterKey", event))
			var increment := 1
			var increment_key: String = str(hook.get("incrementKey", ""))
			if increment_key != "":
				increment = int(context.get(increment_key, increment))
			var flag_key := COUNTER_PREFIX + counter_key
			var count := int(CharacterService.get_flag(flag_key, 0)) + increment
			CharacterService.set_flag(flag_key, count)
			if count < int(hook.get("threshold", 1)):
				continue
		unlock(achievement_id)


func unlock_for_biome_clear(biome_id: String) -> void:
	match biome_id:
		BiomeRegistry.BIOME_CASTLE:
			unlock("castle_clear")
		BiomeRegistry.BIOME_CRYSTAL:
			unlock("crystal_clear")
		BiomeRegistry.BIOME_SWAMP:
			unlock("swamp_clear")
		BiomeRegistry.BIOME_FROZEN:
			unlock("frozen_clear")
		BiomeRegistry.BIOME_CATHEDRAL:
			unlock("cathedral_clear")
		BiomeRegistry.BIOME_VAULT:
			unlock("castle_clear")
		BiomeRegistry.BIOME_PRISM:
			unlock("crystal_clear")
		BiomeRegistry.BIOME_MIRE:
			unlock("swamp_clear")
		BiomeRegistry.BIOME_HOLLOW:
			unlock("frozen_clear")
		BiomeRegistry.BIOME_UMBRAL:
			unlock("cathedral_clear")
	_check_all_biomes()


func get_unlocked_ids() -> Array[String]:
	var ids: Array[String] = []
	for key in _unlocked.keys():
		if _unlocked[key]:
			ids.append(str(key))
	return ids


func get_definition(achievement_id: String) -> Dictionary:
	for def in _definitions:
		if def.get("id", "") == achievement_id:
			return def
	return {}


func get_all_definitions() -> Array:
	return _definitions.duplicate()


func is_manual_unlock(achievement_id: String) -> bool:
	return achievement_id in _manual_unlocks


func get_hooked_achievement_ids() -> Array[String]:
	var ids: Array[String] = []
	for hook in _hooks:
		if hook is Dictionary:
			var hook_id: String = str(hook.get("achievementId", ""))
			if hook_id != "":
				ids.append(hook_id)
	return ids


func validate_catalog_coverage() -> Dictionary:
	var missing: PackedStringArray = []
	for def in _definitions:
		if not def is Dictionary:
			continue
		var id: String = str(def.get("id", ""))
		if id == "":
			continue
		if is_manual_unlock(id):
			continue
		var hooked := false
		for hook_id in get_hooked_achievement_ids():
			if hook_id == id:
				hooked = true
				break
		if not hooked:
			missing.append(id)
	return {"ok": missing.is_empty(), "missing": missing}


func _check_all_biomes() -> void:
	var required := [
		"castle_clear",
		"crystal_clear",
		"swamp_clear",
		"frozen_clear",
		"cathedral_clear",
	]
	for id in required:
		if not is_unlocked(id):
			return
	unlock("all_biomes")


func _get_display_name(achievement_id: String) -> String:
	var def := get_definition(achievement_id)
	return def.get("name", achievement_id)


func _persist() -> void:
	var save_data := LocalSave.get_meta_data()
	save_data["achievements"] = _unlocked.duplicate()
	LocalSave.set_meta_data(save_data)
	LocalSave.autosave()


func _show_toast(display_name: String) -> void:
	var toast := TOAST_SCENE.instantiate()
	if toast.has_method("show_achievement"):
		get_tree().root.add_child(toast)
		toast.show_achievement(display_name)
