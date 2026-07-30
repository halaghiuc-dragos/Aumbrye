extends RefCounted
class_name QuestCatalog

## Quest definitions from content/quests/ (QUEST-4.1).

const QUEST_DIR := "content/quests"

static var _definitions: Dictionary = {}


static func get_definition(quest_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(quest_id, {})


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key in _definitions.keys():
		ids.append(str(key))
	return ids


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var abs_dir := ContentLoader.content_path(QUEST_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("QuestCatalog: missing directory %s" % abs_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var relative := "%s/%s" % [QUEST_DIR, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var quest_id: String = data.get("id", "")
			if quest_id.is_empty():
				push_warning("QuestCatalog: skipping %s (missing id)" % relative)
			else:
				_definitions[quest_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
