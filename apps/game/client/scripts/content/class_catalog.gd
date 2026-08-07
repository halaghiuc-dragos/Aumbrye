extends RefCounted
class_name ClassCatalog

## Loads playable class definitions from content/classes/.

const CLASSES_DIR := "content/classes"

static var _definitions: Dictionary = {}


static func get_definition(class_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(class_id, {})


static func get_all_classes() -> Array[Dictionary]:
	_ensure_loaded()
	var out: Array[Dictionary] = []
	for class_id in _definitions:
		out.append(_definitions[class_id])
	out.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("name", "")) < str(b.get("name", ""))
	)
	return out


static func has_class(class_id: String) -> bool:
	_ensure_loaded()
	return _definitions.has(class_id)


static func is_weapon_allowed(class_id: String, item_id: String) -> bool:
	var def := get_definition(class_id)
	if def.is_empty():
		return true
	var allowed: Variant = def.get("allowedWeapons", [])
	if allowed is Array and not allowed.is_empty():
		return item_id in allowed
	return true


static func get_stat_bonuses(class_id: String) -> Dictionary:
	var def := get_definition(class_id)
	var bonuses: Variant = def.get("statBonuses", {})
	return bonuses if bonuses is Dictionary else {}


static func get_starting_weapon_item_id(class_id: String) -> String:
	return str(get_definition(class_id).get("startingWeaponItemId", "castle_sword"))


static func get_perk(class_id: String) -> String:
	return str(get_definition(class_id).get("perk", ""))


static func clear_cache() -> void:
	_definitions.clear()


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	_definitions = ContentDirLoader.load_id_map([CLASSES_DIR], "id", "ClassCatalog", false, true)
