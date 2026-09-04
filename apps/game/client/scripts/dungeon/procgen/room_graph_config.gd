class_name RoomGraphConfig
extends RefCounted


var grid_width: int = 9
var grid_height: int = 9
var min_rooms: int = 22
var max_rooms: int = 28
var max_generation_attempts: int = 256
var max_walk_attempts: int = 8192
var boss_min_distance: int = 4
var min_dead_ends: int = 4
var min_secrets: int = 1
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

## RM-13: what fraction of eligible two-opposite-door NORMAL rooms become corridors (`RM-14`).
var corridor_ratio: float = 0.15
## RM-13: a multiplier on how often the assigner prefers the larger template for a kind
## (`RM-17` consumes this).
var size_bias: float = 1.0
## RM-13: how often a dead-end room gets a reward instead of a combat encounter (`RM-17`).
var dead_end_reward_ratio: float = 0.3
## RM-15: the shape `_fill_bounding_box()` fills toward instead of the whole rectangle --
## "blob" (no shape filter, the old behaviour), "cross", "ring", "spine" or "scatter".
var floor_silhouette: String = "blob"


static func from_biome(biome: Dictionary) -> RoomGraphConfig:
	var config := RoomGraphConfig.new()
	var room_count: Dictionary = biome.get("roomCount", {})
	config.min_rooms = int(room_count.get("min", 22))
	config.max_rooms = int(room_count.get("max", 28))
	config.grid_width = maxi(13, int(ceil(sqrt(float(config.max_rooms))) + 6))
	config.grid_height = config.grid_width
	var generator: Dictionary = biome.get("generator", {})
	config.boss_min_distance = int(
		generator.get("bossMinDistance", clampi(int(config.min_rooms / 4.0), 4, 6))
	)
	# At least four off-path pockets, so there is always room for a three-key ring's worth of hidden
	# key rooms plus a secret, even after two of the locks land on the same branch.
	var default_dead_ends := 5 if bool(biome.get("requiresSecret", false)) else 4
	config.min_dead_ends = int(generator.get("minDeadEnds", default_dead_ends))
	config.min_dead_ends = mini(config.min_dead_ends, maxi(4, config.min_rooms - 2))
	# Every floor gets one or two secret rooms, whatever a biome file asks for. A floor with none
	# has nothing to reward exploring, and three starts to make them feel routine rather than found.
	config.max_secrets = clampi(int(biome.get("maxSecrets", 2)), 1, 2)
	config.min_secrets = clampi(int(biome.get("minSecrets", 1)), 1, config.max_secrets)
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
	config.corridor_ratio = clampf(float(generator.get("corridorRatio", config.corridor_ratio)), 0.0, 1.0)
	config.size_bias = maxf(0.0, float(generator.get("sizeBias", config.size_bias)))
	config.dead_end_reward_ratio = clampf(
		float(generator.get("deadEndRewardRatio", config.dead_end_reward_ratio)), 0.0, 1.0
	)
	config.floor_silhouette = str(generator.get("floorSilhouette", config.floor_silhouette))
	return config


func grid_center() -> Vector2i:
	return Vector2i(int(grid_width / 2.0), int(grid_height / 2.0))
