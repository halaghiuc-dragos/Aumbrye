extends RefCounted
class_name ItemSetCatalog

## IV-02: content/items/sets.json keyed by setId -> {name, bonuses: {"2": [rules], "4": [...], ...}}.

const SETS_PATH := "content/items/sets.json"

static var _definitions: Dictionary = {}
static var _load_attempted := false


static func get_definition(set_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(set_id, {})


static func clear_cache() -> void:
	_definitions.clear()
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	_definitions = ContentLoader.load_json(SETS_PATH)
