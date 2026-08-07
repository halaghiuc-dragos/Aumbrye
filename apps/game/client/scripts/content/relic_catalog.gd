extends RefCounted
class_name RelicCatalog

const RELIC_DIR := "content/relics"

static var _definitions: Dictionary = {}
static var _load_attempted := false


static func get_definition(relic_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(relic_id, {})


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key in _definitions:
		ids.append(key)
	return ids


static func clear_cache() -> void:
	_definitions.clear()
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	_definitions = ContentDirLoader.load_id_map([RELIC_DIR], "id", "RelicCatalog", false, false)
