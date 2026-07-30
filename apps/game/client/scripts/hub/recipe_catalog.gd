extends RefCounted
class_name RecipeCatalog

## Blacksmith upgrade/repair recipes from content/recipes/ (HUB-4.2).

const RECIPE_DIR := "content/recipes"

static var _definitions: Array[Dictionary] = []


static func get_upgrade_recipes(item_id: String, current_level: int) -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for recipe in _definitions:
		if recipe.get("type", "") != "upgrade":
			continue
		if recipe.get("itemId", "") != item_id:
			continue
		if int(recipe.get("fromLevel", 0)) == current_level:
			result.append(recipe)
	return result


static func get_repair_recipe(item_id: String) -> Dictionary:
	_ensure_loaded()
	for recipe in _definitions:
		if recipe.get("type", "") == "repair" and recipe.get("itemId", "") == item_id:
			return recipe
	return {}


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	var abs_dir := ContentLoader.content_path(RECIPE_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("RecipeCatalog: missing directory %s" % abs_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var data: Dictionary = ContentLoader.load_json("%s/%s" % [RECIPE_DIR, file_name])
			if not data.is_empty():
				_definitions.append(data)
		file_name = dir.get_next()
	dir.list_dir_end()
