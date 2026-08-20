extends RefCounted
class_name BlacksmithService

## Upgrade and repair logic for hub blacksmith (HUB-4.2).

const DEFAULT_MAX_DURABILITY := 100
const DEATH_DURABILITY_LOSS := 15
const UPGRADEABLE_TYPES: Array[String] = ["weapon", "armor", "accessory"]
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")


## C-237: durability is lost only by *equipped* gear (`InventoryService.apply_death_durability_loss`
## walks `inventory.equipped`), while every service entry point below indexed `inventory.slots` —
## and `equip_from_index` removes an item from `slots` when it is equipped. The set of damaged items
## and the set the blacksmith could act on were therefore disjoint: after five deaths the repair
## list contained none of the player's damaged gear.
##
## `resolve_target()` accepts either an int grid index or an equipment slot name ("weapon",
## "chest", …) and returns the live slot dictionary in both cases, so repairs and upgrades mutate
## the real instance either way.
static func resolve_target(target: Variant) -> Dictionary:
	var inv := InventoryService.inventory
	if target is String:
		var slot_name := str(target)
		var equipped: Dictionary = inv.equipped.get(slot_name, {})
		return equipped
	var index := int(target)
	if index < 0 or index >= inv.slots.size():
		return {}
	return inv.slots[index]


static func is_equipment_slot(target: Variant) -> bool:
	return target is String


static func get_slot_upgrade_level(slot: Dictionary) -> int:
	return int(slot.get("upgradeLevel", 0))


static func get_slot_durability(slot: Dictionary) -> int:
	if slot.has("durability"):
		return int(slot.get("durability", DEFAULT_MAX_DURABILITY))
	return DEFAULT_MAX_DURABILITY


static func get_max_durability(item_id: String) -> int:
	var def := ItemCatalog.get_definition(item_id)
	return int(def.get("maxDurability", DEFAULT_MAX_DURABILITY))


static func get_max_upgrade_level_for_slot(slot: Dictionary) -> int:
	var item_id: String = slot.get("itemId", "")
	var def := ItemCatalog.get_definition(item_id)
	var base_rarity := str(def.get("rarity", "common"))
	if slot.has("rarity"):
		base_rarity = str(slot.get("rarity", base_rarity))
	return RarityRegistryScript.max_upgrade_level(base_rarity)


static func get_upgrade_cost(item_id: String, current_level: int) -> int:
	var recipes := RecipeCatalog.get_upgrade_recipes(item_id, current_level)
	if not recipes.is_empty():
		return int(recipes[0].get("goldCost", recipes[0].get("coinCost", 0)))
	return 25 + current_level * 15


static func can_upgrade(target: Variant) -> bool:
	var slot := resolve_target(target)
	if slot.is_empty():
		return false
	var item_id: String = slot.get("itemId", "")
	var def := ItemCatalog.get_definition(item_id)
	var item_type: String = def.get("itemType", "")
	if item_type not in UPGRADEABLE_TYPES:
		return false
	var level := get_slot_upgrade_level(slot)
	if level >= get_max_upgrade_level_for_slot(slot):
		return false
	return CharacterService.can_afford(get_upgrade_cost(item_id, level))


static func upgrade_item(target: Variant) -> Dictionary:
	var inv := InventoryService.inventory
	var slot := resolve_target(target)
	if slot.is_empty():
		return {"ok": false, "error": "invalid slot"}
	var item_id: String = slot.get("itemId", "")
	var level := get_slot_upgrade_level(slot)
	if level >= get_max_upgrade_level_for_slot(slot):
		return {"ok": false, "error": "max level"}
	var cost := get_upgrade_cost(item_id, level)
	if not CharacterService.spend_gold(cost):
		return {"ok": false, "error": "not enough coins"}
	slot["upgradeLevel"] = level + 1
	inv.changed.emit()
	LocalSave.request_autosave()
	if AchievementService:
		AchievementService.notify("blacksmith_craft")
	return {"ok": true, "newLevel": slot["upgradeLevel"]}


static func is_unlocked(item_id: String) -> bool:
	var recipe := RecipeCatalog.get_unlock_recipe_for_item(item_id)
	if recipe.is_empty():
		return ItemCatalog.has_item(item_id)
	if LocalSave.has_recipe(str(recipe.get("id", ""))):
		return true
	var flag_id := str(recipe.get("unlockFlag", ""))
	return flag_id != "" and CharacterService.is_flag_truthy(flag_id)


static func get_available_unlocks() -> Array[Dictionary]:
	var rows: Array[Dictionary] = []
	for recipe in RecipeCatalog.get_unlock_recipes():
		var item_id := str(recipe.get("itemId", ""))
		if item_id == "" or not ItemCatalog.has_item(item_id):
			if item_id != "":
				push_warning(
					"BlacksmithService: unlock recipe references missing item %s" % item_id
				)
			continue
		(
			rows
			. append(
				{
					"itemId": item_id,
					"recipeId": str(recipe.get("id", "")),
					"goldCost": int(recipe.get("goldCost", recipe.get("coinCost", 0))),
					"requiredLevel": int(recipe.get("requiredLevel", 1)),
					"owned": is_unlocked(item_id),
				}
			)
		)
	return rows


static func can_unlock(item_id: String) -> bool:
	if is_unlocked(item_id):
		return false
	var recipe := RecipeCatalog.get_unlock_recipe_for_item(item_id)
	if recipe.is_empty():
		return false
	if ProgressionService and ProgressionService.level < int(recipe.get("requiredLevel", 1)):
		return false
	var cost := int(recipe.get("goldCost", recipe.get("coinCost", 0)))
	return CharacterService.can_afford(cost)


## BUG-43: validate space before spending, and only record the recipe as owned after the item
## has actually been granted. The old order spent gold, granted the permanent recipe unlock, and
## only then checked inventory space — so a full bag on a failed unlock refunded the gold (with
## the BUG-42 goldFind bonus stacked on top) but kept the recipe, leaving is_unlocked() true for
## an item the player never received and can no longer buy through this path.
static func unlock_item(item_id: String) -> Dictionary:
	if not can_unlock(item_id):
		return {"ok": false, "error": "cannot unlock"}
	var recipe := RecipeCatalog.get_unlock_recipe_for_item(item_id)
	var recipe_id := str(recipe.get("id", ""))
	var cost := int(recipe.get("goldCost", recipe.get("coinCost", 0)))
	if not InventoryService.inventory.has_space_for(item_id):
		return {"ok": false, "error": "inventory full"}
	if not CharacterService.spend_gold(cost):
		return {"ok": false, "error": "not enough coins"}
	if not InventoryService.add_item(item_id, 1):
		CharacterService.add_gold(cost, false)
		return {"ok": false, "error": "inventory full"}
	LocalSave.add_owned_recipe(recipe_id)
	if AchievementService:
		AchievementService.notify("blacksmith_craft")
	return {"ok": true, "recipeId": recipe_id}


static func can_unlock_recipe(recipe_id: String) -> bool:
	var recipe := RecipeCatalog.get_unlock_recipe(recipe_id)
	if recipe.is_empty():
		return false
	return can_unlock(str(recipe.get("itemId", "")))


static func unlock_recipe(recipe_id: String) -> Dictionary:
	var recipe := RecipeCatalog.get_unlock_recipe(recipe_id)
	if recipe.is_empty():
		return {"ok": false, "error": "cannot unlock"}
	return unlock_item(str(recipe.get("itemId", "")))


static func can_repair(target: Variant) -> bool:
	var slot := resolve_target(target)
	if slot.is_empty():
		return false
	var item_id: String = slot.get("itemId", "")
	var def := ItemCatalog.get_definition(item_id)
	if def.get("itemType", "") not in UPGRADEABLE_TYPES:
		return false
	var current := get_slot_durability(slot)
	var max_dur := get_max_durability(item_id)
	if current >= max_dur:
		return false
	var recipe := RecipeCatalog.get_repair_recipe(item_id)
	if recipe.is_empty():
		var repair_cost := maxi(1, int((max_dur - current) / 2.0))
		return CharacterService.can_afford(repair_cost)
	return CharacterService.can_afford(int(recipe.get("goldCost", recipe.get("coinCost", 10))))


const RESPEC_COST := 250


static func can_respec_talents() -> bool:
	if ProgressionService == null:
		return false
	if ProgressionService.talent_points_spent <= 0:
		return false
	return CharacterService.can_afford(RESPEC_COST)


static func respec_talents() -> Dictionary:
	if not can_respec_talents():
		return {"ok": false, "error": "cannot respec"}
	if not CharacterService.spend_gold(RESPEC_COST):
		return {"ok": false, "error": "not enough coins"}
	ProgressionService.respec_talents()
	InventoryService.apply_equipment_to_player_node(
		InventoryService.get_tree().get_first_node_in_group("player")
	)
	LocalSave.autosave()
	return {"ok": true}


static func repair_item(target: Variant) -> Dictionary:
	var inv := InventoryService.inventory
	var slot := resolve_target(target)
	if slot.is_empty():
		return {"ok": false, "error": "invalid slot"}
	var item_id: String = slot.get("itemId", "")
	var max_dur := get_max_durability(item_id)
	var current := get_slot_durability(slot)
	if current >= max_dur:
		return {"ok": false, "error": "already full"}
	var recipe := RecipeCatalog.get_repair_recipe(item_id)
	var cost: int
	if recipe.is_empty():
		cost = maxi(1, int((max_dur - current) / 2.0))
	else:
		cost = int(recipe.get("goldCost", recipe.get("coinCost", 10)))
	if not CharacterService.spend_gold(cost):
		return {"ok": false, "error": "not enough coins"}
	slot["durability"] = max_dur
	inv.changed.emit()
	LocalSave.autosave()
	return {"ok": true, "durability": max_dur}
