class_name RoomContentConfig
extends RefCounted

## Configurable weights for post-layout room content assignment.

var weight_combat := 0.55
var weight_empty := 0.20
var weight_trap := 0.10
var weight_hazard := 0.08
var weight_puzzle := 0.0
var weight_npc_quest := 0.0
var weight_locked_vault := 0.07
var max_assignment_attempts := 48
var min_off_path_distance := 2
var enable_locked_door := true
var enable_npc_quest := false
var min_locks_per_floor := 1
var max_locks_per_floor := 3


static func default() -> RoomContentConfig:
	return RoomContentConfig.new()
