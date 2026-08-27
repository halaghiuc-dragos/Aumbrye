extends RefCounted
class_name CastleTierDifficulty


const HP_COMBINED_CAP := 4.0
const DAMAGE_COMBINED_CAP := 2.6


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
	return minf(
		HP_COMBINED_CAP,
		hp_multiplier(dungeon_id, difficulty_tier) * floor_hp_factor(dungeon_id, floor_index)
	)


static func combined_damage_multiplier(
	dungeon_id: String, difficulty_tier: int, floor_index: int
) -> float:
	return minf(
		DAMAGE_COMBINED_CAP,
		(
			damage_multiplier(dungeon_id, difficulty_tier)
			* floor_damage_factor(dungeon_id, floor_index)
		)
	)


static func behaviour_progress(dungeon_id: String, difficulty_tier: int, floor_index: int) -> float:
	var max_tier := maxi(1, DungeonCatalog.max_difficulty_tier(dungeon_id))
	var tier_ratio := 0.0
	if max_tier > 1:
		tier_ratio = float(clampi(difficulty_tier, 1, max_tier) - 1) / float(max_tier - 1)
	var floor_ratio := clampf(
		float(maxi(1, floor_index) - 1) / float(maxi(1, RunFloorConfig.MAX_FLOORS - 1)), 0.0, 1.0
	)
	return clampf(tier_ratio * 0.8 + floor_ratio * 0.2, 0.0, 1.0)
