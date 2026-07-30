extends RefCounted
class_name BlacksmithService

## Upgrade and repair logic for hub blacksmith (HUB-4.2).

const DEFAULT_MAX_DURABILITY := 100


static func get_slot_upgrade_level(slot: Dictionary) -> int:
	return int(slot.get("upgradeLevel", 0))


static func get_slot_durability(slot: Dictionary) -> int:
	if slot.has("durability"):
		return int(slot.get("durability", DEFAULT_MAX_DURABILITY))
	return DEFAULT_MAX_DURABILITY


static func get_max_durability(item_id: String) -> int:
	var def := ItemCatalog.get_definition(item_id)
	return int(def.get("maxDurability", DEFAULT_MAX_DURABILITY))


static func can_upgrade(inv_index: int) -> bool:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return false
	var slot: Dictionary = inv.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var def := ItemCatalog.get_definition(item_id)
	if def.get("itemType", "") != "weapon":
		return false
	var level := get_slot_upgrade_level(slot)
	var recipes := RecipeCatalog.get_upgrade_recipes(item_id, level)
	if recipes.is_empty():
		return false
	var recipe: Dictionary = recipes[0]
	return CharacterService.can_afford(int(recipe.get("goldCost", 0)))


static func upgrade_item(inv_index: int) -> Dictionary:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var slot: Dictionary = inv.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var level := get_slot_upgrade_level(slot)
	var recipes := RecipeCatalog.get_upgrade_recipes(item_id, level)
	if recipes.is_empty():
		return {"ok": false, "error": "no recipe"}
	var recipe: Dictionary = recipes[0]
	var cost: int = int(recipe.get("goldCost", 0))
	if not CharacterService.spend_gold(cost):
		return {"ok": false, "error": "not enough gold"}
	slot["upgradeLevel"] = int(recipe.get("toLevel", level + 1))
	inv.changed.emit()
	LocalSave.autosave()
	return {"ok": true, "newLevel": slot["upgradeLevel"]}


static func can_repair(inv_index: int) -> bool:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return false
	var slot: Dictionary = inv.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var def := ItemCatalog.get_definition(item_id)
	if def.get("itemType", "") != "weapon":
		return false
	var current := get_slot_durability(slot)
	var max_dur := get_max_durability(item_id)
	if current >= max_dur:
		return false
	var recipe := RecipeCatalog.get_repair_recipe(item_id)
	if recipe.is_empty():
		var repair_cost := maxi(1, (max_dur - current) / 2)
		return CharacterService.can_afford(repair_cost)
	return CharacterService.can_afford(int(recipe.get("goldCost", 10)))


static func repair_item(inv_index: int) -> Dictionary:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var slot: Dictionary = inv.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var max_dur := get_max_durability(item_id)
	var current := get_slot_durability(slot)
	if current >= max_dur:
		return {"ok": false, "error": "already full"}
	var recipe := RecipeCatalog.get_repair_recipe(item_id)
	var cost: int
	if recipe.is_empty():
		cost = maxi(1, (max_dur - current) / 2)
	else:
		cost = int(recipe.get("goldCost", 10))
	if not CharacterService.spend_gold(cost):
		return {"ok": false, "error": "not enough gold"}
	slot["durability"] = max_dur
	inv.changed.emit()
	LocalSave.autosave()
	return {"ok": true, "durability": max_dur}
