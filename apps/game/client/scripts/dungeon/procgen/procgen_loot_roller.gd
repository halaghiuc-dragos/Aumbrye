class_name ProcgenLootRoller
extends RefCounted

## Rolls chest contents from biome loot tables with tier-scaled budget (PLC-01, PLC-03, PLC-12).

const ROLE_SHARES := {
	"treasure": 0.35,
	"secret": 0.25,
	"armory": 0.25,
	"side": 0.15,
}


static func roll_chest(
	biome: Dictionary, role: String, tier: int, rng: RandomNumberGenerator
) -> Array:
	var tables: Dictionary = biome.get("lootTables", {})
	var table: Array = tables.get(role, [])
	if table.is_empty():
		return []
	var budgets: Dictionary = biome.get("budgets", {})
	var total_budget := float(budgets.get("baseLootValue", 80)) + float(
		budgets.get("lootPerTier", 14)
	) * float(tier - 1)
	var share := total_budget * float(ROLE_SHARES.get(role, 0.15))
	return _fill_share(table, tier, share, rng)


static func estimate_loot_value(loot: Array) -> float:
	var total := 0.0
	for chest in loot:
		for item in chest.get("items", []):
			var item_id: String = str(item.get("itemId", ""))
			var qty := int(item.get("quantity", 1))
			total += float(ItemCatalog.get_loot_value(item_id) * qty)
	return total


static func _fill_share(table: Array, tier: int, share: float, rng: RandomNumberGenerator) -> Array:
	var items: Array = []
	var remaining := maxf(share, 1.0)
	for _attempt in 4:
		if remaining <= 0.0:
			break
		var entry := _pick_weighted(table, tier, rng)
		if entry.is_empty():
			break
		var item_id: String = str(entry.get("itemId", ""))
		if item_id.is_empty():
			continue
		var min_q: int = _quantity_range(entry)[0]
		var max_q: int = _quantity_range(entry)[1]
		var quantity := rng.randi_range(mini(min_q, max_q), maxi(min_q, max_q))
		var value := float(ItemCatalog.get_loot_value(item_id) * quantity)
		if value > remaining and not items.is_empty():
			break
		items.append({"itemId": item_id, "quantity": quantity})
		remaining -= value
	if items.is_empty():
		var fallback := _pick_weighted(table, tier, rng)
		if not fallback.is_empty():
			var item_id: String = str(fallback.get("itemId", ""))
			items.append({"itemId": item_id, "quantity": _quantity_range(fallback)[0]})
	return items


static func _quantity_range(entry: Dictionary) -> Array:
	var qty: Variant = entry.get("quantity", 1)
	if qty is Array:
		if qty.size() >= 2:
			return [int(qty[0]), int(qty[1])]
		if qty.size() == 1:
			return [int(qty[0]), int(qty[0])]
		return [1, 1]
	return [int(qty), int(qty)]


static func _pick_weighted(table: Array, tier: int, rng: RandomNumberGenerator) -> Dictionary:
	var eligible: Array = []
	for entry in table:
		var min_tier := int(entry.get("minTier", 1))
		if min_tier <= tier:
			eligible.append(entry)
	if eligible.is_empty():
		return {}
	var total := 0
	for entry in eligible:
		total += int(entry.get("weight", 1))
	if total <= 0:
		return eligible[0]
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for entry in eligible:
		acc += int(entry.get("weight", 1))
		if roll < acc:
			return entry
	return eligible[eligible.size() - 1]
