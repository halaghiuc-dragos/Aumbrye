extends RefCounted
class_name EndlessDifficulty

## Bounded scaling for Umbral Endless floors (DCT-04, DCT-08).

const HP_SOFT_CAP := 25.0
const HP_GROWTH := 0.14
const HP_KNEE_TIER := 12
const DAMAGE_SOFT_CAP := 12.0
const DAMAGE_GROWTH := 0.11
const DAMAGE_KNEE_TIER := 12


static func floor_tier(floor_index: int) -> int:
	return int(maxi(0, floor_index) / 10.0)


static func hp_multiplier(floor_index: int) -> float:
	var tier := floor_tier(floor_index)
	if tier <= HP_KNEE_TIER:
		return 1.0 + tier * HP_GROWTH
	var knee := 1.0 + HP_KNEE_TIER * HP_GROWTH
	return minf(HP_SOFT_CAP, knee + log(float(tier - HP_KNEE_TIER) + 1.0) * 2.5)


static func damage_multiplier(floor_index: int) -> float:
	var tier := floor_tier(floor_index)
	if tier <= DAMAGE_KNEE_TIER:
		return 1.0 + tier * DAMAGE_GROWTH
	var knee := 1.0 + DAMAGE_KNEE_TIER * DAMAGE_GROWTH
	return minf(DAMAGE_SOFT_CAP, knee + log(float(tier - DAMAGE_KNEE_TIER) + 1.0) * 2.0)


static func rare_drop_bonus(floor_index: int) -> float:
	var tier := floor_tier(floor_index)
	return minf(tier * RunFloorConfig.DROP_RATE_BONUS_PER_TIER, RunFloorConfig.DROP_RATE_BONUS_CAP)
