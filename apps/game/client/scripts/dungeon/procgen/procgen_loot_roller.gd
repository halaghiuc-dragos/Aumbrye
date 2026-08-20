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


## C-143: the loop bound, not the item bound. Generous enough that the budget runs out first in
## normal cases.
const MAX_CHEST_ATTEMPTS := 24

## A hard ceiling on stacks so a chest of very cheap items cannot become an inventory dump.
const MAX_CHEST_STACKS := 8

## Consecutive over-budget picks tolerated before the fill gives up.
const MAX_OVERSPEND_SKIPS := 4


static func _fill_share(table: Array, tier: int, share: float, rng: RandomNumberGenerator) -> Array:
	# C-143: the fill loop ran at most 4 times, so a chest held at most four stacks whatever the
	# budget said — and the budget is real and tier-scaled (`baseLootValue` + `lootPerTier` per tier,
	# apportioned by `ROLE_SHARES`), so a tier-10 treasure share of ~52 collapsed toward the same
	# "four items" a tier-1 chest gives. Worse, the loop `break`s the moment one *randomly picked*
	# item exceeds the remaining budget instead of trying a cheaper entry, so a chest could stop at
	# two items with most of its budget unspent.
	#
	# The budget is now what bounds the chest. `MAX_CHEST_ATTEMPTS` bounds the *loop*, not the item
	# count, so an unlucky run of over-budget picks cannot spin — and an over-budget pick is skipped
	# rather than ending the fill, so the remainder gets spent on something affordable.
	var items: Array = []
	var remaining := maxf(share, 1.0)
	var overspend_skips := 0
	for _attempt in MAX_CHEST_ATTEMPTS:
		if remaining <= 0.0:
			break
		if items.size() >= MAX_CHEST_STACKS:
			break
		# C-216: the first pick is unbounded so a chest is never empty; every pick after it is drawn
		# from what the remaining budget can actually afford.
		var entry := _pick_weighted(table, tier, rng, 0.0 if items.is_empty() else remaining)
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
			# Try a cheaper entry rather than abandoning the budget; give up after a few misses so
			# a table whose cheapest item exceeds the remainder still terminates.
			overspend_skips += 1
			if overspend_skips >= MAX_OVERSPEND_SKIPS:
				break
			continue
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


## C-216: a single roll could exceed a chest's whole budget by 17x, so which item came out first
## decided the chest rather than the budget doing it — the first pick was always accepted (the
## over-budget guard only fires `if not items.is_empty()`), so a treasure share of ~52 could be
## spent entirely on one 900-value item, and the rest of the budget vanished with it.
##
## `budget_ceiling` lets the caller exclude entries it cannot afford *before* rolling, so the weights
## are applied over what is actually purchasable. Zero means no ceiling, which is what the first pick
## still uses — a chest must never come out empty, so the opening roll is deliberately unbounded.
static func _pick_weighted(
	table: Array, tier: int, rng: RandomNumberGenerator, budget_ceiling: float = 0.0
) -> Dictionary:
	var eligible: Array = []
	for entry in table:
		var min_tier := int(entry.get("minTier", 1))
		if min_tier > tier:
			continue
		if budget_ceiling > 0.0:
			var item_id := str(entry.get("itemId", ""))
			if item_id != "" and float(ItemCatalog.get_loot_value(item_id)) > budget_ceiling:
				continue
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
