extends RefCounted
class_name ItemCatalog

## Single source of truth for item content paths and definitions.

const CATEGORY_DIRS: Array[String] = [
	"content/items/equipment",
	"content/items/consumables",
	"content/items/materials",
	"content/items/quest",
]

const CATALOG_PATH := "content/items/catalog.json"
const STRICT_SETTING := "aumbrye/strict_item_catalog"

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


static func clear_cache() -> void:
	_definitions.clear()


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var loaded := ContentDirLoader.load_id_map(CATEGORY_DIRS, "id", "ItemCatalog", true, true)
	if _is_strict():
		loaded = _apply_strict_allowlist(loaded)
	_definitions = loaded


static func _is_strict() -> bool:
	return bool(ProjectSettings.get_setting(STRICT_SETTING, false))


static func _apply_strict_allowlist(disk_map: Dictionary) -> Dictionary:
	var catalog := ContentLoader.load_json(CATALOG_PATH)
	var allowed := _catalog_id_set(catalog)
	var filtered: Dictionary = {}
	for item_id in disk_map:
		if allowed.has(item_id):
			filtered[item_id] = disk_map[item_id]
		else:
			push_error("ItemCatalog: strict mode rejects orphan item %s" % item_id)
	for item_id in allowed:
		if not disk_map.has(item_id):
			push_error("ItemCatalog: strict mode missing catalog item %s on disk" % item_id)
	return filtered


static func _catalog_id_set(catalog: Dictionary) -> Dictionary:
	var allowed: Dictionary = {}
	for category in ["equipment", "consumables", "materials"]:
		for item_id in catalog.get(category, []):
			allowed[str(item_id)] = true
	return allowed
