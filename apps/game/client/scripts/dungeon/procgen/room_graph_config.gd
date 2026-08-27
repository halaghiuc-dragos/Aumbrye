class_name RoomGraphConfig
extends RefCounted


var grid_width: int = 9
var grid_height: int = 9
var min_rooms: int = 18
var max_rooms: int = 22
var max_generation_attempts: int = 256
var max_walk_attempts: int = 8192
var boss_min_distance: int = 4
var min_dead_ends: int = 2
var max_secrets: int = 2
var loop_budget: int = 3

var loop_min_detour: int = 5

var loop_fallback_detour: int = 3

var min_loops: int = 1
var branch_max_depth: int = 8
var allow_2x2_blocks: bool = true
var max_neighbor_count: int = 4
var fill_bounding_box: bool = true
var max_height_level: int = 0
var debug_ascii: bool = false


static func from_biome(biome: Dictionary) -> RoomGraphConfig:
	var config := RoomGraphConfig.new()
	var room_count: Dictionary = biome.get("roomCount", {})
	config.min_rooms = int(room_count.get("min", 18))
	config.max_rooms = int(room_count.get("max", 22))
	config.grid_width = maxi(13, int(ceil(sqrt(float(config.max_rooms))) + 6))
	config.grid_height = config.grid_width
	var generator: Dictionary = biome.get("generator", {})
	config.boss_min_distance = int(
		generator.get("bossMinDistance", clampi(int(config.min_rooms / 4.0), 4, 6))
	)
	var default_dead_ends := 3 if bool(biome.get("requiresSecret", false)) else 2
	config.min_dead_ends = int(generator.get("minDeadEnds", default_dead_ends))
	config.min_dead_ends = mini(config.min_dead_ends, maxi(2, config.min_rooms - 2))
	config.max_secrets = int(biome.get("maxSecrets", 2))
	config.branch_max_depth = int(generator.get("branchMaxDepth", config.branch_max_depth))
	config.max_neighbor_count = int(generator.get("maxNeighborCount", config.max_neighbor_count))
	config.loop_budget = int(generator.get("loopBudget", config.loop_budget))
	config.loop_min_detour = maxi(3, int(generator.get("loopMinDetour", config.loop_min_detour)))
	config.loop_fallback_detour = clampi(
		int(generator.get("loopFallbackDetour", config.loop_fallback_detour)),
		3,
		config.loop_min_detour
	)
	config.min_loops = clampi(
		int(generator.get("minLoops", config.min_loops)), 0, maxi(0, config.loop_budget)
	)
	config.max_generation_attempts = int(
		generator.get("maxGenerationAttempts", config.max_generation_attempts)
	)
	config.max_walk_attempts = int(generator.get("maxWalkAttempts", config.max_walk_attempts))
	config.allow_2x2_blocks = bool(generator.get("allow2x2Blocks", config.allow_2x2_blocks))
	config.fill_bounding_box = bool(generator.get("fillBoundingBox", config.fill_bounding_box))
	config.max_height_level = int(biome.get("maxHeightLevel", 0))
	return config


func grid_center() -> Vector2i:
	return Vector2i(int(grid_width / 2.0), int(grid_height / 2.0))
