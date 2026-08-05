class_name ProcgenLootTables
extends RefCounted

## Theme loot/trap tables (mirrors C# ThemeLootTables).


static func treasure_loot(biome_id: String) -> Array:
	match biome_id:
		"crystal_caverns", "prism_depths":
			return [_item("health_potion", 2), _item("wind_relic_charm", 1)]
		"poison_swamp", "venom_mire":
			return [_item("health_potion", 2), _item("poison_relic_vial", 1)]
		"frozen_fortress", "glacial_hollow":
			return [_item("health_potion", 2), _item("frost_relic_shard", 1)]
		"dark_cathedral", "umbral_chapel":
			return [_item("health_potion", 2), _item("shadow_relic_veil", 1)]
		"iron_vault":
			return [_item("health_potion", 2), _item("stone_relic_heart", 1)]
		_:
			return [_item("health_potion", 2), _item("bloodlust_charm", 1)]


static func secret_loot(biome_id: String) -> Array:
	match biome_id:
		"crystal_caverns", "prism_depths":
			return [_item("wind_relic_charm", 1), _item("health_potion", 3)]
		"poison_swamp", "venom_mire":
			return [_item("poison_relic_vial", 1), _item("health_potion", 3)]
		"frozen_fortress", "glacial_hollow":
			return [_item("frost_relic_shard", 1), _item("health_potion", 3)]
		"dark_cathedral", "umbral_chapel":
			return [_item("shadow_relic_veil", 1), _item("health_potion", 3)]
		"iron_vault":
			return [_item("stone_relic_heart", 1), _item("health_potion", 4)]
		_:
			return [_item("knight_relic", 1), _item("health_potion", 3)]


static func side_loot(biome_id: String) -> Array:
	match biome_id:
		"crystal_caverns", "prism_depths":
			return [_item("crystal_shard_blade", 1), _item("flame_relic_core", 1)]
		"poison_swamp", "venom_mire":
			return [_item("swamp_bog_boots", 1), _item("blood_relic_stone", 1)]
		"frozen_fortress", "glacial_hollow":
			return [_item("frost_raider_boots", 1), _item("frost_relic_shard", 1)]
		"dark_cathedral", "umbral_chapel":
			return [_item("cathedral_warden_helm", 1), _item("sun_relic_medallion", 1)]
		"iron_vault":
			return [_item("castle_gauntlets", 1), _item("swift_step_charm", 1)]
		_:
			return [_item("iron_scrap", 2), _item("bloodlust_charm", 1)]


static func armory_loot(biome_id: String) -> Array:
	match biome_id:
		"crystal_caverns", "prism_depths":
			return [_item("crystal_shard_blade", 1)]
		"poison_swamp", "venom_mire":
			return [_item("swamp_toxin_dagger", 1)]
		"frozen_fortress", "glacial_hollow":
			return [_item("frost_glacier_sword", 1)]
		"dark_cathedral", "umbral_chapel":
			return [_item("cathedral_arcane_staff", 1)]
		"iron_vault":
			return [_item("war_hammer", 1)]
		_:
			return [_item("castle_sword", 1)]


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


static func _item(item_id: String, quantity: int) -> Dictionary:
	return {"itemId": item_id, "quantity": quantity}
