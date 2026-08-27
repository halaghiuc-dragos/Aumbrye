extends RefCounted
class_name ForgeService


const EquipmentScript := preload("res://scripts/items/equipment.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const BlacksmithServiceScript := preload("res://scripts/hub/blacksmith_service.gd")

const RECIPE_SALVAGE := "forge_salvage"
const RECIPE_REROLL := "forge_reroll_affix"
const RECIPE_TRANSMUTE := "forge_transmute_rarity"
const RECIPE_TRANSFER := "forge_transfer_rule"

const INFUSION_RECIPES: Dictionary = {
	"fire": "forge_infuse_fire",
	"frost": "forge_infuse_frost",
	"poison": "forge_infuse_poison",
	"arcane": "forge_infuse_arcane",
	"lightning": "forge_infuse_lightning",
}

const CONVERSION_RECIPE_IDS: Array[String] = [
	"forge_convert_cinder_to_glimmer",
	"forge_convert_glimmer_to_sable",
	"forge_convert_sable_to_storm",
	"forge_convert_storm_to_tear",
]

const SALVAGE_YIELD: Dictionary = {
	"common": {"cinder_dust": 2},
	"magic": {"cinder_dust": 2, "glimmer_ash": 1},
	"rare": {"glimmer_ash": 2, "sable_grain": 1},
	"epic": {"sable_grain": 2, "storm_salt": 1},
	"legendary": {"storm_salt": 2, "aumbral_tear": 1},
	"aumbral": {"storm_salt": 3, "aumbral_tear": 3},
}


static func upgrade_paths() -> Array[String]:
	var paths: Array[String] = []
	for path in EquipmentScript.UPGRADE_PATHS:
		paths.append(str(path))
	return paths


static func infusions() -> Array[String]:
	var elements: Array[String] = []
	for element in EquipmentScript.INFUSIONS:
		elements.append(str(element))
	return elements


static func get_recipe(recipe_id: String) -> Dictionary:
	return RecipeCatalog.get_unlock_recipe(recipe_id)


static func can_afford_recipe(recipe: Dictionary) -> bool:
	if recipe.is_empty():
		return false
	if not CharacterService.can_afford(int(recipe.get("goldCost", 0))):
		return false
	for entry in recipe.get("materials", []):
		if not entry is Dictionary:
			continue
		var needed := int((entry as Dictionary).get("quantity", 0))
		if InventoryService.count_item(str((entry as Dictionary).get("itemId", ""))) < needed:
			return false
	return true


static func salvage_preview(slot: Dictionary) -> Dictionary:
	var rarity := RarityRegistryScript.normalize(str(slot.get("rarity", "common")))
	var yields: Dictionary = (SALVAGE_YIELD.get(rarity, SALVAGE_YIELD["common"]) as Dictionary).duplicate()
	var upgrade_level := BlacksmithServiceScript.get_slot_upgrade_level(slot)
	if upgrade_level > 0:
		yields["iron_scrap"] = int(yields.get("iron_scrap", 0)) + upgrade_level
	return yields


static func salvage(inv_index: Variant) -> Dictionary:
	if BlacksmithServiceScript.is_equipment_slot(inv_index):
		return {"ok": false, "error": "unequip first"}
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var slot: Dictionary = inv.slots[inv_index]
	var def := ItemCatalog.get_definition(str(slot.get("itemId", "")))
	if def.get("itemType", "") not in BlacksmithServiceScript.UPGRADEABLE_TYPES:
		return {"ok": false, "error": "not salvageable"}
	var yields := salvage_preview(slot)
	if inv.remove_at(inv_index).is_empty():
		return {"ok": false, "error": "invalid slot"}
	var granted: Dictionary = {}
	var lost: Dictionary = {}
	for material_id in yields:
		var amount := int(yields[material_id])
		if amount <= 0:
			continue
		if InventoryService.add_item(str(material_id), amount):
			granted[material_id] = amount
		else:
			lost[material_id] = amount
	if LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "materials": granted, "lost": lost}


static func can_reroll(inv_index: Variant) -> bool:
	var slot := _slot_at(inv_index)
	if slot.is_empty():
		return false
	var affixes: Variant = slot.get("affixes", [])
	if not affixes is Array or (affixes as Array).is_empty():
		return false
	return can_afford_recipe(get_recipe(RECIPE_REROLL))


static func reroll_affixes(inv_index: Variant) -> Dictionary:
	if not can_reroll(inv_index):
		return {"ok": false, "error": "cannot reroll"}
	var recipe := get_recipe(RECIPE_REROLL)
	if not _spend(recipe):
		return {"ok": false, "error": "not enough materials"}
	var inv := InventoryService.inventory
	var slot: Dictionary = _slot_at(inv_index)
	if slot.is_empty():
		return {"ok": false, "error": "invalid slot"}
	var attempt := int(slot.get("rerollCount", 0)) + 1
	slot["rerollCount"] = attempt
	var rarity := RarityRegistryScript.normalize(str(slot.get("rarity", "common")))
	slot["affixes"] = AffixRoller.reroll_affixes(
		slot.get("affixes", []), rarity, _derive_seed(slot, attempt)
	)
	inv.changed.emit()
	if LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "affixes": slot["affixes"]}


static func can_transmute(inv_index: Variant) -> bool:
	var slot := _slot_at(inv_index)
	if slot.is_empty():
		return false
	var rarity := RarityRegistryScript.normalize(str(slot.get("rarity", "common")))
	if RarityRegistryScript.tier_index(rarity) >= RarityRegistryScript.TIER_ORDER.size() - 1:
		return false
	return can_afford_recipe(get_recipe(RECIPE_TRANSMUTE))


static func transmute_rarity(inv_index: Variant) -> Dictionary:
	if not can_transmute(inv_index):
		return {"ok": false, "error": "cannot transmute"}
	var recipe := get_recipe(RECIPE_TRANSMUTE)
	if not _spend(recipe):
		return {"ok": false, "error": "not enough materials"}
	var inv := InventoryService.inventory
	var slot: Dictionary = _slot_at(inv_index)
	if slot.is_empty():
		return {"ok": false, "error": "invalid slot"}
	var rarity := RarityRegistryScript.normalize(str(slot.get("rarity", "common")))
	var next_index := RarityRegistryScript.tier_index(rarity) + 1
	var next_rarity: String = RarityRegistryScript.TIER_ORDER[next_index]
	slot["rarity"] = next_rarity
	var attempt := int(slot.get("rerollCount", 0)) + 1
	slot["rerollCount"] = attempt
	slot["affixes"] = AffixRoller.reroll_affixes(
		slot.get("affixes", []), next_rarity, _derive_seed(slot, attempt)
	)
	inv.changed.emit()
	if LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "rarity": next_rarity}


static func can_infuse(inv_index: Variant, element: String) -> bool:
	if not EquipmentScript.INFUSIONS.has(element):
		return false
	var slot := _slot_at(inv_index)
	if slot.is_empty():
		return false
	if str(slot.get("infusion", "")) == element:
		return false
	var def := ItemCatalog.get_definition(str(slot.get("itemId", "")))
	if def.get("itemType", "") != "weapon":
		return false
	return can_afford_recipe(get_recipe(str(INFUSION_RECIPES.get(element, ""))))


static func infuse(inv_index: Variant, element: String) -> Dictionary:
	if not can_infuse(inv_index, element):
		return {"ok": false, "error": "cannot infuse"}
	var recipe := get_recipe(str(INFUSION_RECIPES.get(element, "")))
	if not _spend(recipe):
		return {"ok": false, "error": "not enough materials"}
	var inv := InventoryService.inventory
	var slot: Dictionary = _slot_at(inv_index)
	if slot.is_empty():
		return {"ok": false, "error": "invalid slot"}
	slot["infusion"] = element
	inv.changed.emit()
	if LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "infusion": element}


static func can_set_upgrade_path(inv_index: Variant, path: String) -> bool:
	if not EquipmentScript.UPGRADE_PATHS.has(path):
		return false
	var slot := _slot_at(inv_index)
	if slot.is_empty():
		return false
	if EquipmentScript.normalize_upgrade_path(str(slot.get("upgradePath", ""))) == path:
		return false
	return BlacksmithServiceScript.get_slot_upgrade_level(slot) <= 0


static func set_upgrade_path(inv_index: Variant, path: String) -> Dictionary:
	if not can_set_upgrade_path(inv_index, path):
		return {"ok": false, "error": "cannot set path"}
	var inv := InventoryService.inventory
	var slot: Dictionary = _slot_at(inv_index)
	if slot.is_empty():
		return {"ok": false, "error": "invalid slot"}
	slot["upgradePath"] = path
	inv.changed.emit()
	if LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "upgradePath": path}


static func can_transfer_rule(source_index: int, target_index: int) -> bool:
	var source := _slot_at(source_index)
	var target := _slot_at(target_index)
	if source.is_empty() or target.is_empty() or source_index == target_index:
		return false
	var source_def := ItemCatalog.get_definition(str(source.get("itemId", "")))
	var rules: Variant = source_def.get("rules", [])
	if not rules is Array or (rules as Array).is_empty():
		return false
	if str(target.get("transferredRuleFrom", "")) != "":
		return false
	var target_def := ItemCatalog.get_definition(str(target.get("itemId", "")))
	if target_def.get("itemType", "") != source_def.get("itemType", ""):
		return false
	return can_afford_recipe(get_recipe(RECIPE_TRANSFER))


static func transfer_rule(source_index: int, target_index: int) -> Dictionary:
	if BlacksmithServiceScript.is_equipment_slot(source_index) or BlacksmithServiceScript.is_equipment_slot(target_index):
		return {"ok": false, "error": "unequip first"}
	if not can_transfer_rule(source_index, target_index):
		return {"ok": false, "error": "cannot transfer"}
	var recipe := get_recipe(RECIPE_TRANSFER)
	if not _spend(recipe):
		return {"ok": false, "error": "not enough materials"}
	var inv := InventoryService.inventory
	var source: Dictionary = inv.slots[source_index]
	var source_id := str(source.get("itemId", ""))
	if inv.remove_at(source_index).is_empty():
		return {"ok": false, "error": "invalid slot"}
	var adjusted := target_index - 1 if target_index > source_index else target_index
	if adjusted < 0 or adjusted >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var target: Dictionary = inv.slots[adjusted]
	target["transferredRuleFrom"] = source_id
	inv.changed.emit()
	if LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "sourceItemId": source_id}


static func conversion_recipes() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for recipe_id in CONVERSION_RECIPE_IDS:
		var recipe := get_recipe(recipe_id)
		if not recipe.is_empty():
			rows.append(recipe)
	return rows


static func convert_materials(recipe_id: String) -> Dictionary:
	var recipe := get_recipe(recipe_id)
	if recipe.is_empty() or str(recipe.get("type", "")) != "convert":
		return {"ok": false, "error": "unknown recipe"}
	if not can_afford_recipe(recipe):
		return {"ok": false, "error": "not enough materials"}
	var output_id := str(recipe.get("itemId", ""))
	if not InventoryService.inventory.has_space_for(output_id):
		return {"ok": false, "error": "inventory full"}
	if not _spend(recipe):
		return {"ok": false, "error": "not enough materials"}
	if not InventoryService.add_item(output_id, 1):
		return {"ok": false, "error": "inventory full"}
	if LocalSave:
		LocalSave.request_autosave()
	return {"ok": true, "itemId": output_id}


static func _slot_at(target: Variant) -> Dictionary:
	return BlacksmithServiceScript.resolve_target(target)


static func _spend(recipe: Dictionary) -> bool:
	if not can_afford_recipe(recipe):
		return false
	if not CharacterService.spend_gold(int(recipe.get("goldCost", 0))):
		return false
	for entry in recipe.get("materials", []):
		if not entry is Dictionary:
			continue
		var material_id := str((entry as Dictionary).get("itemId", ""))
		var quantity := int((entry as Dictionary).get("quantity", 0))
		InventoryService.inventory.remove_items_by_id(material_id, quantity)
	return true


static func _derive_seed(slot: Dictionary, attempt: int) -> int:
	var base := int(slot.get("rollSeed", 0))
	var identity := hash(str(slot.get("instanceId", "")))
	return absi((base ^ (identity * 2654435761) ^ (attempt * 40503))) & 0x7fffffff
