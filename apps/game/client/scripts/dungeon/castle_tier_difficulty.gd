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
	var tier := clampi(difficulty_tier, 1, max_tier)
	var completed_blocks := RunFloorConfig.block_index(floor_index)
	var block_ratio := clampf(
		float(completed_blocks) / float(maxi(1, tier - 1)), 0.0, 1.0
	)
	var chapter_ratio := float(RunFloorConfig.floor_within_block(floor_index) - 1) / float(
		maxi(1, RunFloorConfig.FLOORS_PER_BLOCK - 1)
	)
	var tier_ratio := float(tier - 1) / float(maxi(1, max_tier - 1))
	return clampf(tier_ratio * 0.45 + block_ratio * 0.25 + chapter_ratio * 0.3, 0.0, 1.0)
