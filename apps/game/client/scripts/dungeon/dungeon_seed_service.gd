extends RefCounted
class_name DungeonSeedService

## Base run seed → per-tier generation seeds. Tier 1 uses base seed X; tier 2+ derives Y.

const TIER_SEED_MULTIPLIER := 104729


static func derive_tier_seed(base_seed: int, tier: int) -> int:
	var normalized_seed := maxi(1, int(base_seed))
	var t := clampi(tier, 1, DungeonCatalog.count())
	if t <= 1:
		return normalized_seed
	var mixed: int = normalized_seed ^ (t * TIER_SEED_MULTIPLIER)
	return maxi(1, mixed)


static func mix_floor_seed(tier_seed: int, floor_index: int) -> int:
	return RunFloorConfig.mix_seed(tier_seed, floor_index)


static func generation_seed(base_seed: int, tier: int, floor_index: int) -> int:
	return mix_floor_seed(derive_tier_seed(base_seed, tier), floor_index)


static func can_access_tier(tier: int) -> bool:
	return tier <= DungeonTierService.get_max_unlocked_tier()


static func can_access_dungeon(dungeon_id: String) -> bool:
	return DungeonTierService.is_dungeon_unlocked(dungeon_id)


static func tier_for_dungeon(dungeon_id: String) -> int:
	return DungeonCatalog.get_tier_for_dungeon(dungeon_id)


static func describe_tier_seed(base_seed: int, tier: int) -> String:
	var tier_seed := derive_tier_seed(base_seed, tier)
	if tier <= 1:
		return "Base seed %d" % base_seed
	return "Base seed %d → Tier %d seed %d" % [base_seed, tier, tier_seed]


static func parse_run_seed(text: String) -> Variant:
	var trimmed := text.strip_edges()
	if trimmed == "" or not trimmed.is_valid_int():
		return null
	var value := int(trimmed)
	if value < 1:
		return null
	return value
