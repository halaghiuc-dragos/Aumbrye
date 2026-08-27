extends RefCounted
class_name DialogueCatalog


const DIALOGUE_DIR := "content/dialogue"

static var _definitions: Dictionary = {}
static var _load_attempted := false


static func get_dialogue(dialogue_id: String) -> Dictionary:
	_ensure_loaded()
	var definition: Variant = _definitions.get(dialogue_id, {})
	return (definition as Dictionary).duplicate(true) if definition is Dictionary else {}


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
