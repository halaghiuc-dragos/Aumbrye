extends Node

## M6 achievement service — unlock tracking, toasts, cloud sync.

signal achievement_unlocked(achievement_id: String, display_name: String)

const CATALOG_PATH := "content/achievements/catalog.json"
const TOAST_SCENE: PackedScene = preload("res://scenes/ui/achievement_toast.tscn")

var _unlocked: Dictionary = {}
var _definitions: Array = []


func _ready() -> void:
	_load_catalog()
	_load_from_save()


func _load_catalog() -> void:
	var data: Dictionary = ContentLoader.load_json(CATALOG_PATH)
	_definitions = data.get("achievements", [])


func _load_from_save() -> void:
	var save_data := LocalSave.get_meta_data()
	var achievements: Variant = save_data.get("achievements", {})
	if achievements is Dictionary:
		_unlocked = achievements.duplicate()


func is_unlocked(achievement_id: String) -> bool:
	return _unlocked.get(achievement_id, false)


func unlock(achievement_id: String) -> bool:
	if is_unlocked(achievement_id):
		return false
	_unlocked[achievement_id] = true
	_persist()
	if SteamService and not SteamService.is_stub_mode:
		SteamService.unlock_achievement(achievement_id)
	var display_name := _get_display_name(achievement_id)
	achievement_unlocked.emit(achievement_id, display_name)
	_show_toast(display_name)
	return true


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


func _check_all_biomes() -> void:
	var required := [
		"castle_clear", "crystal_clear", "swamp_clear", "frozen_clear", "cathedral_clear",
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
