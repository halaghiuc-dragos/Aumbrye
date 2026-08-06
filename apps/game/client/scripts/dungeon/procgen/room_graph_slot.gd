class_name RoomGraphSlot
extends RefCounted

## One cell in the abstract room-graph grid (Phase 1).

enum SlotType {
	EMPTY,
	START,
	NORMAL,
	BOSS,
	TREASURE,
	SHOP,
	SECRET,
	STAIRS,
	OBSTACLE,
}

const DOOR_NORTH := 1
const DOOR_EAST := 2
const DOOR_SOUTH := 4
const DOOR_WEST := 8

var grid_pos: Vector2i = Vector2i.ZERO
var slot_id: String = ""
var slot_type: SlotType = SlotType.EMPTY
var door_mask: int = 0
var graph_distance: int = -1
var secret_parent_id: String = ""
var secret_mechanism: String = ""  # illusory_wall | hidden_lever
var is_filler: bool = false
var on_critical_path: bool = false
var height_level: int = 0


func is_occupied() -> bool:
	return slot_type != SlotType.EMPTY


func connection_count() -> int:
	var count := 0
	if door_mask & DOOR_NORTH:
		count += 1
	if door_mask & DOOR_EAST:
		count += 1
	if door_mask & DOOR_SOUTH:
		count += 1
	if door_mask & DOOR_WEST:
		count += 1
	return count


func is_dead_end() -> bool:
	return is_occupied() and connection_count() == 1


func type_letter() -> String:
	match slot_type:
		SlotType.START:
			return "S"
		SlotType.BOSS:
			return "B"
		SlotType.TREASURE:
			return "T"
		SlotType.SHOP:
			return "$"
		SlotType.SECRET:
			return "?"
		SlotType.STAIRS:
			return "#"
		SlotType.OBSTACLE:
			return "O"
		SlotType.NORMAL:
			return "."
		_:
			return " "
