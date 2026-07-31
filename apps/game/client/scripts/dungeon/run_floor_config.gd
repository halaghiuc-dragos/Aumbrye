extends RefCounted
class_name RunFloorConfig

## Multi-floor dungeon run constants and seed mixing (FLOOR-7.x).

const MAX_FLOORS := 10
const ENDLESS_MAX_FLOORS := 999999
const MAX_SECRETS_PER_FLOOR := 2
const FLOOR_SEED_MULTIPLIER := 7919
const DROP_RATE_BONUS_PER_TIER := 0.02
const DROP_RATE_BONUS_CAP := 0.30


static func mix_seed(run_seed: int, floor_index: int) -> int:
	if floor_index <= 1:
		return maxi(1, int(run_seed))
	var mixed := int(run_seed) + int(floor_index) * FLOOR_SEED_MULTIPLIER
	return maxi(1, mixed)


static func clamp_floor(floor_index: int, run_mode: String = "castle") -> int:
	if run_mode == "endless":
		return maxi(1, int(floor_index))
	return clampi(floor_index, 1, MAX_FLOORS)


static func is_final_floor(floor_index: int, run_mode: String = "castle") -> bool:
	if run_mode == "endless":
		return false
	return clamp_floor(floor_index, run_mode) >= MAX_FLOORS


static func max_floors_for_mode(run_mode: String) -> int:
	if run_mode == "endless":
		return ENDLESS_MAX_FLOORS
	return MAX_FLOORS


static func count_secrets(definition: Dictionary) -> int:
	var count := 0
	for room in definition.get("rooms", []):
		if room is Dictionary and room.get("type", "") == "secret":
			count += 1
	return count


static func find_stairs_room_id(definition: Dictionary) -> String:
	for room in definition.get("rooms", []):
		if room is Dictionary:
			var tid: String = room.get("templateId", "")
			if tid.ends_with("_stairs") or room.get("type", "") == "corridor":
				return str(room.get("id", "stairs"))
	return "stairs"


static func stairs_spawn_facing_y(stair_room: RoomTemplate, ascending: bool) -> float:
	# Player spawns at top of stair set, facing opposite stairs (walk down into floor).
	var south_socket := stair_room.find_socket(CastleRoomConstants.Direction.SOUTH)
	if south_socket:
		return south_socket.global_rotation.y + PI
	if ascending:
		return stair_room.global_rotation.y
	return stair_room.global_rotation.y + PI
