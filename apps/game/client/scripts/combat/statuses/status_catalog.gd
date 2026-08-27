extends RefCounted
class_name StatusCatalog

static var _definitions: Dictionary = {}


static func get_definition(status_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(status_id, {})


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var abs_dir := ContentLoader.content_path("content/statuses")
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Dictionary = ContentLoader.load_json("content/statuses/%s" % file_name)
			var status_id: String = data.get("id", "")
			if status_id != "":
				_definitions[status_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
