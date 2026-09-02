extends RefCounted
class_name RunFloorConfig


## Floors in a tier-1 run, and the size of one seed block.
##
## A tier is made of blocks of this many floors: tier 1 is one block, tier 10 is ten, so the climb
## runs 10 floors to 100. Each block carries its own seed and ends with a boss, which makes a block
## the unit a player actually experiences -- nine floors and a fight -- and keeps tier 10 at ten
## bosses rather than a hundred.
const FLOORS_PER_BLOCK := 10

## Retained as the tier-1 floor count, which is what every legacy caller meant by it.
const MAX_FLOORS := FLOORS_PER_BLOCK
const MAX_TIER := 10
const ENDLESS_MAX_FLOORS := 999999
const DROP_RATE_BONUS_PER_TIER := 0.02
const DROP_RATE_BONUS_CAP := 0.30

const FloorSeedMixScript := preload("res://scripts/dungeon/floor_seed_mix.gd")


static func mix_seed(run_seed: int, floor_index: int) -> int:
	return FloorSeedMixScript.mix(run_seed, floor_index)


## How many floors a tier holds. Tier 1 is ten, tier 10 is a hundred.
static func floors_for_tier(tier: int) -> int:
	return clampi(tier, 1, MAX_TIER) * FLOORS_PER_BLOCK


## Which block of ten a floor sits in, counting from zero. The seed unit.
static func block_index(floor_index: int) -> int:
	@warning_ignore("integer_division")
	return maxi(0, (maxi(1, floor_index) - 1) / FLOORS_PER_BLOCK)


## Position within the block, 1..FLOORS_PER_BLOCK.
static func floor_within_block(floor_index: int) -> int:
	return ((maxi(1, floor_index) - 1) % FLOORS_PER_BLOCK) + 1


## The last floor of a block, where that block's boss waits.
static func is_block_boss_floor(floor_index: int) -> bool:
	return floor_within_block(floor_index) == FLOORS_PER_BLOCK


static func clamp_floor(floor_index: int, run_mode: String = "castle", tier: int = 1) -> int:
	if run_mode == "endless":
		return maxi(1, int(floor_index))
	return clampi(floor_index, 1, floors_for_tier(tier))


## The tier finale: the last floor of the last block of the tier.
static func is_final_floor(floor_index: int, run_mode: String = "castle", tier: int = 1) -> bool:
	if run_mode == "endless":
		return false
	return clamp_floor(floor_index, run_mode, tier) >= floors_for_tier(tier)


static func max_floors_for_mode(run_mode: String, tier: int = 1) -> int:
	if run_mode == "endless":
		return ENDLESS_MAX_FLOORS
	return floors_for_tier(tier)


static func count_secrets(definition: Dictionary) -> int:
	var count := 0
	for room in definition.get("rooms", []):
		if room is Dictionary and room.get("type", "") == "secret":
			count += 1
	return count


static func is_stairs_room(room: Dictionary) -> bool:
	var kind := str(room.get("kind", ""))
	if kind != "":
		return kind == "stairs"
	var tid := str(room.get("templateId", room.get("template_id", "")))
	return tid.ends_with("_stairs")


static func find_stairs_room_id(definition: Dictionary) -> String:
	for room in definition.get("rooms", []):
		if room is Dictionary and is_stairs_room(room):
			return str(room.get("id", "stairs"))
	return "stairs"


static func stairs_spawn_facing_y(stair_room: RoomTemplate) -> float:
	if stair_room == null:
		return 0.0
	var south_socket := stair_room.find_socket(CastleRoomConstants.Direction.SOUTH)
	if south_socket:
		return south_socket.global_rotation.y + PI
	return stair_room.global_rotation.y + PI
