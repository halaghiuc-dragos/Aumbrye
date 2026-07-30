extends RefCounted
class_name ItemCatalog

## Single source of truth for item content paths and definitions.

const CATEGORY_DIRS: Array[String] = [
	"content/items/equipment",
	"content/items/consumables",
	"content/items/materials",
]

static var _definitions: Dictionary = {}


static func get_definition(item_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(item_id, {})


static func get_content_path(item_id: String) -> String:
	var def := get_definition(item_id)
	return def.get("content_path", "")


static func has_item(item_id: String) -> bool:
	_ensure_loaded()
	return _definitions.has(item_id)


static func get_loot_value(item_id: String) -> int:
	var def := get_definition(item_id)
	if def.is_empty():
		return 1
	if def.has("lootValue"):
		return int(def.get("lootValue", 1))
	return int(def.get("value", 1))


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	for relative_dir in CATEGORY_DIRS:
		_load_directory(relative_dir)


static func _load_directory(relative_dir: String) -> void:
	var abs_dir := ContentLoader.content_path(relative_dir)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("ItemCatalog: missing directory %s" % abs_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var relative := "%s/%s" % [relative_dir, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var item_id: String = data.get("id", "")
			if item_id.is_empty():
				push_warning("ItemCatalog: skipping %s (missing id)" % relative)
			else:
				data["content_path"] = relative
				_definitions[item_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
