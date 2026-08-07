extends RefCounted
class_name QuestCatalog

## Quest definitions from content/quests/ (QUEST-4.1).

const QUEST_DIR := "content/quests"

static var _definitions: Dictionary = {}
static var _load_attempted := false


static func get_definition(quest_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(quest_id, {})


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key in _definitions.keys():
		ids.append(str(key))
	return ids


static func clear_cache() -> void:
	_definitions.clear()
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	_definitions = ContentDirLoader.load_id_map([QUEST_DIR], "id", "QuestCatalog", false, true)
