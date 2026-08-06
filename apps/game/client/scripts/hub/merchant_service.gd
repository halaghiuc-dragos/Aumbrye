extends RefCounted
class_name MerchantService

## Buy/sell consumables from merchant stock data (HUB-4.3).

const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const EquipmentScript := preload("res://scripts/items/equipment.gd")

static var _warned_missing_items: Dictionary = {}


static func get_buy_price(item_id: String, merchant_id: String = "hub_merchant") -> int:
	for entry in MerchantCatalog.get_stock(merchant_id):
		if entry is Dictionary and entry.get("itemId", "") == item_id:
			return int(entry.get("price", ItemCatalog.get_definition(item_id).get("value", 10)))
	return int(ItemCatalog.get_definition(item_id).get("value", 10))


static func get_sell_price(item_id: String) -> int:
	return get_slot_unit_sell_price({"itemId": item_id, "quantity": 1})


static func get_slot_unit_sell_price(slot: Dictionary) -> int:
	var item_id: String = slot.get("itemId", "")
	var base := maxi(1, ItemCatalog.get_loot_value(item_id))
	var rarity := str(
		slot.get("rarity", ItemCatalog.get_definition(item_id).get("rarity", "common"))
	)
	var price := int(round(float(base) * RarityRegistryScript.sell_multiplier(rarity)))
	price = int(
		round(float(price) * EquipmentScript.upgrade_multiplier(int(slot.get("upgradeLevel", 0))))
	)
	for affix in slot.get("affixes", []):
		if affix is Dictionary:
			price += int(round(float(affix.get("value", 0.0))))
	return maxi(1, price)


static func get_slot_sell_price(slot: Dictionary) -> int:
	var qty := maxi(1, int(slot.get("quantity", 1)))
	return get_slot_unit_sell_price(slot) * qty


static func get_purchased(merchant_id: String) -> Dictionary:
	return LocalSave.get_merchant_purchased(merchant_id)


static func restock(merchant_id: String) -> void:
	LocalSave.clear_merchant_purchased(merchant_id)


static func restock_all() -> void:
	LocalSave.clear_all_merchant_purchases()


static func get_available_stock(merchant_id: String = "hub_merchant") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var purchased := get_purchased(merchant_id)
	for entry in MerchantCatalog.get_stock(merchant_id):
		if not entry is Dictionary:
			continue
		var item_id: String = entry.get("itemId", "")
		if not ItemCatalog.has_item(item_id):
			if not _warned_missing_items.has(item_id):
				_warned_missing_items[item_id] = true
				push_warning("MerchantService: dropping unknown stock item %s" % item_id)
			continue
		var stock: int = int(entry.get("stock", 99))
		var bought: int = int(purchased.get(item_id, 0))
		if stock - bought <= 0:
			continue
		var row: Dictionary = entry.duplicate()
		row["remaining"] = stock - bought
		result.append(row)
	return result


## BUG-43: validate everything, then commit — never spend and refund. Stock, affordability and
## inventory space are all checked before CharacterService.spend_gold() runs, so the common
## failure paths no longer need a refund at all. add_loot() can still fail after the space check
## (a stack/placement edge case) — that residual path still refunds, and BUG-42 makes sure the
## refund does not also apply the goldFind bonus.
static func buy_item(item_id: String, merchant_id: String = "hub_merchant") -> Dictionary:
	var found_entry: Dictionary = {}
	for entry in MerchantCatalog.get_stock(merchant_id):
		if entry is Dictionary and entry.get("itemId", "") == item_id:
			found_entry = entry
			break
	if found_entry.is_empty():
		return {"ok": false, "error": "item not sold here"}
	var stock: int = int(found_entry.get("stock", 99))
	var bought: int = int(get_purchased(merchant_id).get(item_id, 0))
	if bought >= stock:
		return {"ok": false, "error": "out of stock"}
	var price := get_buy_price(item_id, merchant_id)
	if not CharacterService.can_afford(price):
		return {"ok": false, "error": "not enough gold"}
	if not InventoryService.inventory.has_space_for(item_id):
		return {"ok": false, "error": "inventory full"}
	if not CharacterService.spend_gold(price):
		return {"ok": false, "error": "not enough gold"}
	if not InventoryService.add_loot(item_id, {"quantity": 1}):
		CharacterService.add_gold(price, false)
		return {"ok": false, "error": "inventory full"}
	LocalSave.increment_merchant_purchase(merchant_id, item_id)
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)
	if AchievementService:
		AchievementService.notify("merchant_buy")
	return {"ok": true}


static func sell_item(inv_index: int, quantity: int = -1) -> Dictionary:
	var inv := InventoryService.inventory
	if inv_index < 0 or inv_index >= inv.slots.size():
		return {"ok": false, "error": "invalid slot"}
	var slot: Dictionary = inv.slots[inv_index]
	var item_id: String = slot.get("itemId", "")
	var def := ItemCatalog.get_definition(item_id)
	if def.is_empty():
		return {"ok": false, "error": "unknown item"}
	var slot_qty := maxi(1, int(slot.get("quantity", 1)))
	var sell_qty := slot_qty if quantity < 0 else mini(quantity, slot_qty)
	if sell_qty <= 0:
		return {"ok": false, "error": "invalid quantity"}
	var unit_price := get_slot_unit_sell_price(slot)
	var total_price := unit_price * sell_qty
	if sell_qty >= slot_qty:
		inv.remove_at(inv_index)
	else:
		slot["quantity"] = slot_qty - sell_qty
		inv.changed.emit()
	CharacterService.add_gold(total_price)
	LocalSave.request_autosave(LocalSave.SavePriority.DEFERRED)
	return {"ok": true, "gold": total_price, "quantity": sell_qty}
