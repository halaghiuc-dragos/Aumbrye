extends RefCounted
class_name DialogueCatalog

## Loads branching dialogue JSON from content/dialogue/ (DLG-4.1).

const DIALOGUE_DIR := "content/dialogue"

static var _definitions: Dictionary = {}
static var _load_attempted := false


static func get_dialogue(dialogue_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(dialogue_id, {})


static func clear_cache() -> void:
	_definitions.clear()
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	_definitions = ContentDirLoader.load_id_map(
		[DIALOGUE_DIR], "id", "DialogueCatalog", false, true
	)
