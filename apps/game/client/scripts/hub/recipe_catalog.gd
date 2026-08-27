extends RefCounted
class_name RecipeCatalog


const RECIPE_DIR := "content/recipes"

static var _definitions: Array[Dictionary] = []
static var _loaded := false


static func get_upgrade_recipes(item_id: String, current_level: int) -> Array[Dictionary]:
	_ensure_loaded()
	if not _is_item_unlocked(item_id):
		return []
	var result: Array[Dictionary] = []
	for recipe in _definitions:
		if recipe.get("type", "") != "upgrade":
			continue
		if recipe.get("itemId", "") != item_id:
			continue
		if int(recipe.get("fromLevel", 0)) == current_level:
			result.append(recipe)
	return result


static func get_unlock_recipes() -> Array[Dictionary]:
	_ensure_loaded()
	var result: Array[Dictionary] = []
	for recipe in _definitions:
		if recipe.get("type", "") != "unlock":
			continue
		result.append(recipe)
	return result


static func get_unlock_recipe(recipe_id: String) -> Dictionary:
	_ensure_loaded()
	for recipe in _definitions:
		if str(recipe.get("id", "")) == recipe_id:
			return recipe
	return {}


static func get_unlock_recipe_for_item(item_id: String) -> Dictionary:
	_ensure_loaded()
	for recipe in _definitions:
		if recipe.get("type", "") != "unlock":
			continue
		if str(recipe.get("itemId", "")) == item_id:
			return recipe
	return {}


static func upgrade_stat_bonus(item_id: String, to_level: int) -> Dictionary:
	_ensure_loaded()
	var result: Dictionary = {}
	for recipe in _definitions:
		if recipe.get("type", "") != "upgrade":
			continue
		if str(recipe.get("itemId", "")) != item_id:
			continue
		if int(recipe.get("toLevel", 0)) > to_level:
			continue
		var bonus: Variant = recipe.get("statBonus", {})
		if not bonus is Dictionary:
			continue
		for key in bonus:
			result[key] = float(result.get(key, 0.0)) + float(bonus[key])
	return result


static func _is_item_unlocked(item_id: String) -> bool:
	var recipe := get_unlock_recipe_for_item(item_id)
	if recipe.is_empty():
		return true
	if LocalSave and LocalSave.has_recipe(str(recipe.get("id", ""))):
		return true
	var flag_id := str(recipe.get("unlockFlag", ""))
	return flag_id != "" and CharacterService.is_flag_truthy(flag_id)


static func get_repair_recipe(item_id: String) -> Dictionary:
	_ensure_loaded()
	for recipe in _definitions:
		if recipe.get("type", "") == "repair" and recipe.get("itemId", "") == item_id:
			return recipe
	return {}


static func reload() -> void:
	_definitions.clear()
	_loaded = false
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var abs_dir := ContentLoader.content_path(RECIPE_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("RecipeCatalog: missing directory %s" % abs_dir)
		_loaded = true
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
	_loaded = true
