extends RefCounted
class_name DialogueCatalog

## Loads branching dialogue JSON from content/dialogue/ (DLG-4.1).

const DIALOGUE_DIR := "content/dialogue"

static var _definitions: Dictionary = {}


static func get_dialogue(dialogue_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(dialogue_id, {})


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var abs_dir := ContentLoader.content_path(DIALOGUE_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("DialogueCatalog: missing directory %s" % abs_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var relative := "%s/%s" % [DIALOGUE_DIR, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var dialogue_id: String = data.get("id", "")
			if dialogue_id.is_empty():
				push_warning("DialogueCatalog: skipping %s (missing id)" % relative)
			else:
				_definitions[dialogue_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
