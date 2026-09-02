extends RefCounted
class_name DungeonSeedService


const TIER_SEED_MULTIPLIER := 104729


static func derive_tier_seed(base_seed: int, tier: int) -> int:
	var normalized_seed := maxi(1, int(base_seed))
	var t := clampi(tier, 1, DungeonCatalog.count())
	if t <= 1:
		return normalized_seed
	var mixed: int = normalized_seed ^ (t * TIER_SEED_MULTIPLIER)
	return maxi(1, mixed)


## The seed for a floor, derived through its block.
##
## A block of ten floors is the addressable unit: the block gets its own seed off the tier seed, and
## each floor is mixed from that. Floors inside a block still differ from one another, but the thing
## a seed names is the block -- so sharing a seed shares a stretch of ten floors, not one layout and
## not a whole hundred-floor tier.
static func mix_floor_seed(tier_seed: int, floor_index: int) -> int:
	var block_seed := RunFloorConfig.mix_seed(tier_seed, RunFloorConfig.block_index(floor_index) + 1)
	return RunFloorConfig.mix_seed(block_seed, RunFloorConfig.floor_within_block(floor_index))


static func generation_seed(base_seed: int, tier: int, floor_index: int) -> int:
	return mix_floor_seed(derive_tier_seed(base_seed, tier), floor_index)


static func can_access_tier(tier: int) -> bool:
	return tier <= DungeonTierService.get_max_unlocked_tier()


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
