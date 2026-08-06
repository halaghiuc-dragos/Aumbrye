extends RefCounted
class_name DialogueCatalog

## Loads branching dialogue JSON from content/dialogue/ (DLG-4.1).

const DIALOGUE_DIR := "content/dialogue"

static var _definitions: Dictionary = {}


static func get_dialogue(dialogue_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(dialogue_id, {})


static func clear_cache() -> void:
	_definitions.clear()


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	_definitions = ContentDirLoader.load_id_map(
		[DIALOGUE_DIR], "id", "DialogueCatalog", false, true
	)
