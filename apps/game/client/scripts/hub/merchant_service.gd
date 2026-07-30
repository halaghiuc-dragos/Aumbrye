extends RefCounted
class_name MerchantService

## Buy/sell consumables from merchant stock data (HUB-4.3).

static var _purchased: Dictionary = {}


static func reset_session() -> void:
	_purchased.clear()


static func get_buy_price(item_id: String, merchant_id: String = "hub_merchant") -> int:
	for entry in MerchantCatalog.get_stock(merchant_id):
		if entry is Dictionary and entry.get("itemId", "") == item_id:
			return int(entry.get("price", ItemCatalog.get_definition(item_id).get("value", 10)))
	return int(ItemCatalog.get_definition(item_id).get("value", 10))


static func get_sell_price(item_id: String) -> int:
	return maxi(1, ItemCatalog.get_loot_value(item_id))


static func get_available_stock(merchant_id: String = "hub_merchant") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in MerchantCatalog.get_stock(merchant_id):
		if not entry is Dictionary:
			continue
		var item_id: String = entry.get("itemId", "")
		var stock: int = int(entry.get("stock", 99))
		var bought: int = int(_purchased.get(item_id, 0))
		if stock - bought <= 0:
			continue
		var row: Dictionary = entry.duplicate()
		row["remaining"] = stock - bought
		result.append(row)
	return result


static func buy_item(item_id: String, merchant_id: String = "hub_merchant") -> Dictionary:
	var price := get_buy_price(item_id, merchant_id)
	if not CharacterService.can_afford(price):
		return {"ok": false, "error": "not enough gold"}
	for entry in MerchantCatalog.get_stock(merchant_id):
		if entry is Dictionary and entry.get("itemId", "") == item_id:
			var stock: int = int(entry.get("stock", 99))
			var bought: int = int(_purchased.get(item_id, 0))
			if bought >= stock:
				return {"ok": false, "error": "out of stock"}
			if not InventoryService.add_item(item_id, 1):
				return {"ok": false, "error": "inventory full"}
			if not CharacterService.spend_gold(price):
				return {"ok": false, "error": "not enough gold"}
			_purchased[item_id] = bought + 1
			LocalSave.autosave()
			return {"ok": true}
	return {"ok": false, "error": "item not sold here"}


static func sell_item(inv_index: int) -> Dictionary:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var slot: Dictionary = inv.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var def := ItemCatalog.get_definition(item_id)
	if def.is_empty():
		return {"ok": false, "error": "unknown item"}
	var price := get_sell_price(item_id)
	inv.remove_at(inv_index)
	CharacterService.add_gold(price)
	LocalSave.autosave()
	return {"ok": true, "gold": price}
