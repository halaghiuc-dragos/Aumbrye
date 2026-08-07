extends RefCounted
class_name SkipFloorService

## Rare skip-floor consumables for Umbral Endless starts.

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
		var qty := _count_item(inventory, item_id)
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


static func consume_skip(inventory: GridInventory, item_id: String) -> bool:
	if not SKIP_ITEMS.has(item_id):
		return false
	if not ItemCatalog.has_item(item_id):
		push_warning("SkipFloorService: unknown skip item '%s'" % item_id)
		return false
	return inventory.remove_items_by_id(item_id, 1) > 0


static func _count_item(inventory: GridInventory, item_id: String) -> int:
	var total := 0
	for slot in inventory.slots:
		if slot.get("itemId", "") == item_id:
			total += int(slot.get("quantity", 1))
	return total


static func start_floor_for_item(item_id: String) -> int:
	return int(SKIP_ITEMS.get(item_id, 1))
