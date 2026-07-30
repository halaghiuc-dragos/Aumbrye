extends RefCounted
class_name RelicCatalog

const RELIC_DIR := "content/relics"

static var _definitions: Dictionary = {}


static func get_definition(relic_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(relic_id, {})


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key in _definitions:
		ids.append(key)
	return ids


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var abs_dir := ContentLoader.content_path(RELIC_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("RelicCatalog: missing directory %s" % abs_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var relative := "%s/%s" % [RELIC_DIR, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var relic_id: String = data.get("id", "")
			if relic_id != "":
				_definitions[relic_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
