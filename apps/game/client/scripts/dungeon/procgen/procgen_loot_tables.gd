class_name ProcgenLootTables
extends RefCounted

## Deprecated — use LootTableLoader + biome JSON. Kept for legacy call sites.

const LootTableLoaderScript := preload("res://scripts/loot/loot_table_loader.gd")


static func treasure_loot(biome_id: String) -> Array:
	return _legacy_items(biome_id, "treasure")


static func secret_loot(biome_id: String) -> Array:
	return _legacy_items(biome_id, "secret")


static func side_loot(biome_id: String) -> Array:
	return _legacy_items(biome_id, "side")


static func armory_loot(biome_id: String) -> Array:
	return _legacy_items(biome_id, "armory")


static func corridor_trap(biome_id: String) -> String:
	match biome_id:
		"poison_swamp", "venom_mire":
			return "poison_pool"
		"frozen_fortress", "glacial_hollow":
			return "frost_trap"
		"dark_cathedral", "umbral_chapel":
			return "shadow_trap"
		_:
			return "spike_trap"


static func _legacy_items(biome_id: String, role: String) -> Array:
	var tables: Dictionary = LootTableLoaderScript.load_for_biome(biome_id)
	if tables.is_empty():
		tables = BiomeRegistry.get_biome(biome_id).get("lootTables", {})
	var entries: Array = tables.get(role, [])
	var out: Array = []
	for entry in entries:
		if not entry is Dictionary:
			continue
		var qty: Variant = entry.get("quantity", 1)
		var quantity := 1
		if qty is Array and (qty as Array).size() > 0:
			quantity = int((qty as Array)[0])
		elif qty is int or qty is float:
			quantity = int(qty)
		out.append(_item(str(entry.get("itemId", "")), quantity))
	return out


static func _item(item_id: String, quantity: int) -> Dictionary:
	return {"itemId": item_id, "quantity": quantity}
