class_name RoomGraphConfig
extends RefCounted

## Tunable parameters for grid-based room-graph generation.

var grid_width: int = 9
var grid_height: int = 9
var min_rooms: int = 8
var max_rooms: int = 14
var max_generation_attempts: int = 100
var max_walk_attempts: int = 4096
var boss_min_distance: int = 4
var min_dead_ends: int = 2
var max_secrets: int = 2
var loop_budget: int = 2
var branch_max_depth: int = 4
var allow_2x2_blocks: bool = false
var continue_probability_base: float = 0.92
var continue_decay_rate: float = 0.14
var max_neighbor_count: int = 3
var fill_bounding_box: bool = true
var debug_ascii: bool = false


static func from_biome(biome: Dictionary) -> RoomGraphConfig:
	var config := RoomGraphConfig.new()
	var room_count: Dictionary = biome.get("roomCount", {})
	config.min_rooms = int(room_count.get("min", 18))
	config.max_rooms = int(room_count.get("max", 22))
	config.grid_width = maxi(13, int(ceil(sqrt(float(config.max_rooms))) + 6))
	config.grid_height = config.grid_width
	config.boss_min_distance = clampi(int(config.min_rooms / 4.0), 4, 6)
	config.min_dead_ends = 2 if bool(biome.get("requiresSecret", false)) else 1
	if config.min_rooms >= 16:
		config.branch_max_depth = 8
		config.max_neighbor_count = 4
		config.loop_budget = 4
		config.max_generation_attempts = 256
		config.max_walk_attempts = 8192
		config.allow_2x2_blocks = true
	return config


func grid_center() -> Vector2i:
	return Vector2i(int(grid_width / 2.0), int(grid_height / 2.0))
