extends RefCounted
class_name ItemCatalog


const CATEGORY_DIRS: Array[String] = [
	"content/items/equipment",
	"content/items/consumables",
	"content/items/materials",
	"content/items/quest",
]

const CATALOG_PATH := "content/items/catalog.json"
const STRICT_SETTING := "aumbrye/strict_item_catalog"

static var _definitions: Dictionary = {}
static var _load_attempted := false


static func get_definition(item_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(item_id, {})


static func get_content_path(item_id: String) -> String:
	var def := get_definition(item_id)
	return def.get("content_path", "")


static func has_item(item_id: String) -> bool:
	_ensure_loaded()
	return _definitions.has(item_id)


static func get_items_by_type(item_type: String) -> Array[String]:
	_ensure_loaded()
	var out: Array[String] = []
	for item_id in _definitions:
		var def: Dictionary = _definitions[item_id]
		if str(def.get("itemType", "")) == item_type:
			out.append(str(item_id))
	out.sort()
	return out


static func get_loot_value(item_id: String) -> int:
	var def := get_definition(item_id)
	if def.is_empty():
		return 1
	if def.has("lootValue"):
		return int(def.get("lootValue", 1))
	return int(def.get("value", 1))


static func clear_cache() -> void:
	_definitions.clear()
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	var loaded := ContentDirLoader.load_id_map(CATEGORY_DIRS, "id", "ItemCatalog", true, true)
	if _is_strict():
		loaded = _apply_strict_allowlist(loaded)
	_definitions = _flatten_footprints(loaded)
	if _definitions.is_empty():
		push_error("ItemCatalog: no item definitions loaded from %s" % str(CATEGORY_DIRS))


## Every item occupies exactly one cell.
##
## The grid is a plain slot list, not a Diablo-style packing puzzle, so the `gridWidth`/`gridHeight`
## fields the content files still carry are collapsed here rather than at each of the half-dozen
## places that read them. Doing it once on load also means a new content file cannot reintroduce a
## multi-cell item by accident.
static func _flatten_footprints(defs: Dictionary) -> Dictionary:
	for item_id in defs:
		var def: Dictionary = defs[item_id]
		def["gridWidth"] = 1
		def["gridHeight"] = 1
	return defs


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
