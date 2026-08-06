extends RefCounted
class_name CastleTierDifficulty

## Castle-mode scaling from catalog difficulty tiers and per-floor growth (DCT-02, DCT-13).


static func hp_multiplier(dungeon_id: String, difficulty_tier: int) -> float:
	var data := DungeonCatalog.get_difficulty_tier_data(dungeon_id, difficulty_tier)
	return float(data.get("hpMult", 1.0))


static func damage_multiplier(dungeon_id: String, difficulty_tier: int) -> float:
	var data := DungeonCatalog.get_difficulty_tier_data(dungeon_id, difficulty_tier)
	return float(data.get("damageMult", 1.0))


static func loot_bonus(dungeon_id: String, difficulty_tier: int) -> float:
	var data := DungeonCatalog.get_difficulty_tier_data(dungeon_id, difficulty_tier)
	return float(data.get("lootBonus", 0.0))


static func floor_hp_factor(dungeon_id: String, floor_index: int) -> float:
	var growth := DungeonCatalog.get_floor_hp_growth(dungeon_id)
	return 1.0 + growth * maxf(0.0, float(floor_index - 1))


static func floor_damage_factor(dungeon_id: String, floor_index: int) -> float:
	var growth := DungeonCatalog.get_floor_damage_growth(dungeon_id)
	return 1.0 + growth * maxf(0.0, float(floor_index - 1))


static func combined_hp_multiplier(dungeon_id: String, difficulty_tier: int, floor_index: int) -> float:
	return hp_multiplier(dungeon_id, difficulty_tier) * floor_hp_factor(dungeon_id, floor_index)


static func combined_damage_multiplier(
	dungeon_id: String, difficulty_tier: int, floor_index: int
) -> float:
	return damage_multiplier(dungeon_id, difficulty_tier) * floor_damage_factor(
		dungeon_id, floor_index
	)
