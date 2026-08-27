extends RefCounted
class_name SkipFloorService


const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")

const SKIP_ITEMS: Dictionary = {
	"skip_10_floors": 11,
	"skip_50_floors": 51,
	"skip_100_floors": 101,
	"skip_250_floors": 251,
	"skip_500_floors": 501,
}


static func get_available_skips(inventory: GridInventory) -> Array[Dictionary]:
	var found: Array[Dictionary] = []
	for item_id in SKIP_ITEMS:
		var qty := inventory.count_by_id(item_id)
		if qty > 0:
			(
				found
				. append(
					{
						"itemId": item_id,
						"startFloor": int(SKIP_ITEMS[item_id]),
						"quantity": qty,
					}
				)
			)
	found.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("startFloor", 0)) > int(b.get("startFloor", 0))
	)
	return found


static func has_skip(inventory: GridInventory, item_id: String) -> bool:
	if not SKIP_ITEMS.has(item_id):
		return false
	if not ItemCatalog.has_item(item_id):
		push_warning("SkipFloorService: unknown skip item '%s'" % item_id)
		return false
	return inventory.count_by_id(item_id) > 0


static func consume_skip(inventory: GridInventory, item_id: String) -> bool:
	if not SKIP_ITEMS.has(item_id):
		return false
	if not ItemCatalog.has_item(item_id):
		push_warning("SkipFloorService: unknown skip item '%s'" % item_id)
		return false
	return inventory.remove_items_by_id(item_id, 1) > 0


static func start_floor_for_item(item_id: String) -> int:
	return int(SKIP_ITEMS.get(item_id, 1))


static func describe_skip(item_id: String, run_seed: int) -> Dictionary:
	var start_floor := start_floor_for_item(item_id)
	var definition := ItemCatalog.get_definition(item_id)
	var segment := BiomeRegistry.segment_for_floor(run_seed, start_floor)
	var biome_id := str(segment.get("biomeId", ""))
	return {
		"itemId": item_id,
		"itemName": str(definition.get("name", item_id)),
		"startFloor": start_floor,
		"biomeId": biome_id,
		"biomeName": BiomeRegistry.get_display_name(biome_id),
		"hpMultiplier": EndlessDifficultyScript.hp_multiplier(start_floor),
		"damageMultiplier": EndlessDifficultyScript.damage_multiplier(start_floor),
		"bestFloor": ProgressionService.get_endless_best_floor(),
	}


static func describe_stake(item_id: String, run_seed: int) -> String:
	var info := describe_skip(item_id, run_seed)
	var lines: Array[String] = []
	lines.append(
		"Floor %d — %s" % [int(info.get("startFloor", 1)), str(info.get("biomeName", ""))]
	)
	lines.append(
		(
			"Enemies at x%.2f health and x%.2f harm."
			% [float(info.get("hpMultiplier", 1.0)), float(info.get("damageMultiplier", 1.0))]
		)
	)
	var best := int(info.get("bestFloor", 0))
	if best > 0:
		lines.append("Your deepest was floor %d." % best)
	else:
		lines.append("You have no record to measure this against.")
	lines.append("You begin with nothing this run has earned. That is the trade.")
	return "\n".join(lines)


static func conversion_recipes() -> Array:
	var data := ProgressionService.get_endless_depth_data()
	var ladder: Variant = data.get("skipLadder", [])
	return ladder if ladder is Array else []


static func available_conversions(inventory: GridInventory) -> Array[Dictionary]:
	var offers: Array[Dictionary] = []
	for recipe in conversion_recipes():
		if not recipe is Dictionary:
			continue
		var from_id := str((recipe as Dictionary).get("from", ""))
		var to_id := str((recipe as Dictionary).get("to", ""))
		var cost := int((recipe as Dictionary).get("cost", 0))
		if from_id == "" or to_id == "" or cost <= 0:
			continue
		var held := inventory.count_by_id(from_id)
		(
			offers
			. append(
				{
					"from": from_id,
					"to": to_id,
					"cost": cost,
					"held": held,
					"affordable": held >= cost,
					"fromName": str(ItemCatalog.get_definition(from_id).get("name", from_id)),
					"toName": str(ItemCatalog.get_definition(to_id).get("name", to_id)),
				}
			)
		)
	return offers


static func convert(inventory: GridInventory, from_id: String, to_id: String) -> bool:
	for recipe in conversion_recipes():
		if not recipe is Dictionary:
			continue
		if str((recipe as Dictionary).get("from", "")) != from_id:
			continue
		if str((recipe as Dictionary).get("to", "")) != to_id:
			continue
		var cost := int((recipe as Dictionary).get("cost", 0))
		if cost <= 0 or inventory.count_by_id(from_id) < cost:
			return false
		if not ItemCatalog.has_item(to_id):
			push_warning("SkipFloorService: unknown skip item '%s'" % to_id)
			return false
		if inventory.remove_items_by_id(from_id, cost) < cost:
			return false
		InventoryService.add_loot(to_id)
		return true
	return false
