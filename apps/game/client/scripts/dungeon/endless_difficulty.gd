extends RefCounted
class_name EndlessDifficulty

## Scaling for Umbral Endless floors (tier = floor_index / 10).

const HP_BASE_PER_TIER := 0.12
const HP_HEAVY_AFTER_FLOOR := 10
const HP_HEAVY_BONUS := 0.35
const DAMAGE_BASE_PER_TIER := 0.10
const DAMAGE_HEAVY_BONUS := 0.25


static func floor_tier(floor_index: int) -> int:
	return int(maxi(0, floor_index) / 10.0)


static func hp_multiplier(floor_index: int) -> float:
	var tier := floor_tier(floor_index)
	var mult := 1.0 + tier * HP_BASE_PER_TIER
	if floor_index > HP_HEAVY_AFTER_FLOOR:
		var heavy_tiers := floor_tier(floor_index) - floor_tier(HP_HEAVY_AFTER_FLOOR)
		mult += heavy_tiers * HP_HEAVY_BONUS
	return mult


static func damage_multiplier(floor_index: int) -> float:
	var tier := floor_tier(floor_index)
	var mult := 1.0 + tier * DAMAGE_BASE_PER_TIER
	if floor_index > HP_HEAVY_AFTER_FLOOR:
		var heavy_tiers := floor_tier(floor_index) - floor_tier(HP_HEAVY_AFTER_FLOOR)
		mult += heavy_tiers * DAMAGE_HEAVY_BONUS
	return mult


static func rare_drop_bonus(floor_index: int) -> float:
	var tier := floor_tier(floor_index)
	return minf(tier * RunFloorConfig.DROP_RATE_BONUS_PER_TIER, RunFloorConfig.DROP_RATE_BONUS_CAP)
