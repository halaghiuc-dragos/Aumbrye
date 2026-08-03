extends RefCounted
class_name CastleTierDifficulty

## Client scaling for Aumbrye Dungeons progression tiers (separate from Umbral Endless floor tiers).

const HP_PER_TIER := 0.15
const DAMAGE_PER_TIER := 0.08
const LOOT_BONUS_PER_TIER := 0.05


static func hp_multiplier(tier: int) -> float:
	return 1.0 + maxf(0.0, float(tier - 1)) * HP_PER_TIER


static func damage_multiplier(tier: int) -> float:
	return 1.0 + maxf(0.0, float(tier - 1)) * DAMAGE_PER_TIER


static func loot_bonus(tier: int) -> float:
	return maxf(0.0, float(tier - 1)) * LOOT_BONUS_PER_TIER
