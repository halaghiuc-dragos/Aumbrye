class_name RoomContentConfig
extends RefCounted

## Configurable weights for post-layout room content assignment (normalized off-path table).

var weight_combat := 0.45
var weight_empty := 0.14
var weight_trap := 0.09
var weight_hazard := 0.07
var weight_reward := 0.06
var weight_lore := 0.06
var weight_rest := 0.05
var weight_puzzle := 0.05
var weight_npc_quest := 0.02
var weight_merchant := 0.01
var max_assignment_attempts := 48
var min_off_path_distance := 2
var enable_locked_door := true
var enable_npc_quest := true
var min_locks_per_floor := 1
var max_locks_per_floor := 3


static func default() -> RoomContentConfig:
	return RoomContentConfig.new()
