class_name RoomGraph
extends RefCounted


var slots: Dictionary = {}
var _index: Dictionary = {}

var _block_counts: Dictionary = {}
var start_id: String = ""
var boss_id: String = ""
var secret_ids: Array[String] = []
var treasure_id: String = ""
var stairs_id: String = ""
var walk_edges: Array = []

var loop_edges: Array = []
var config: RoomGraphConfig


func add_slot(cell: Vector2i, slot: RoomGraphSlot) -> void:
	slots[cell] = slot
	_index[slot.slot_id] = cell
	if _is_block_eligible(slot):
		_adjust_block_counts(cell, 1)


func remove_slot(cell: Vector2i) -> void:
	var slot: RoomGraphSlot = slots.get(cell) as RoomGraphSlot
	if slot != null:
		_index.erase(slot.slot_id)
		if _is_block_eligible(slot):
			_adjust_block_counts(cell, -1)
	slots.erase(cell)


func block_count_at(anchor: Vector2i) -> int:
	return int(_block_counts.get(anchor, 0))


func _is_block_eligible(slot: RoomGraphSlot) -> bool:
	return not slot.is_filler and slot.slot_type != RoomGraphSlot.SlotType.SECRET


func _adjust_block_counts(cell: Vector2i, delta: int) -> void:
	for ox in 2:
		for oy in 2:
			var anchor := cell + Vector2i(-ox, -oy)
			var count := int(_block_counts.get(anchor, 0)) + delta
			if count <= 0:
				_block_counts.erase(anchor)
			else:
				_block_counts[anchor] = count


func get_slot(slot_id: String) -> RoomGraphSlot:
	var cell: Variant = _index.get(slot_id)
	if cell == null:
		return null
	return slots.get(cell) as RoomGraphSlot


func get_slot_at(cell: Vector2i) -> RoomGraphSlot:
	return slots.get(cell) as RoomGraphSlot


func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in slots:
		cells.append(cell)
	cells.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if a.x == b.x:
				return a.y < b.y
			return a.x < b.x
	)
	return cells


func main_slot_count() -> int:
	var count := 0
	for cell in slots:
		var slot: RoomGraphSlot = slots[cell]
		if slot.slot_type != RoomGraphSlot.SlotType.SECRET:
			count += 1
	return count
