extends RefCounted
class_name RunFloorConfig

## Multi-floor dungeon run constants and seed mixing (FLOOR-7.x).

const MAX_FLOORS := 10
const ENDLESS_MAX_FLOORS := 999999
const DROP_RATE_BONUS_PER_TIER := 0.02
const DROP_RATE_BONUS_CAP := 0.30

const FloorSeedMixScript := preload("res://scripts/dungeon/floor_seed_mix.gd")


static func mix_seed(run_seed: int, floor_index: int) -> int:
	return FloorSeedMixScript.mix(run_seed, floor_index)


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


static func max_secrets_for_biome(biome_id: String) -> int:
	var biome: Dictionary = ContentLoader.load_json("content/biomes/%s.json" % biome_id)
	return int(biome.get("maxSecrets", 2))


static func is_stairs_room(room: Dictionary) -> bool:
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
