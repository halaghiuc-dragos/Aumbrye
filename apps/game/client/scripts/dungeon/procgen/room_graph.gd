class_name RoomGraph
extends RefCounted

## Validated abstract layout graph produced by Phase 1.

var slots: Dictionary = {}  # Vector2i -> RoomGraphSlot
var _index: Dictionary = {}  # slot_id -> Vector2i
var start_id: String = ""
var boss_id: String = ""
var secret_ids: Array[String] = []
var treasure_id: String = ""
var stairs_id: String = ""
var shop_id: String = ""
var walk_edges: Array = []  # [{a: Vector2i, b: Vector2i}, ...] spanning-tree edges
var config: RoomGraphConfig


func add_slot(cell: Vector2i, slot: RoomGraphSlot) -> void:
	slots[cell] = slot
	_index[slot.slot_id] = cell


func remove_slot(cell: Vector2i) -> void:
	var slot: RoomGraphSlot = slots.get(cell) as RoomGraphSlot
	if slot != null:
		_index.erase(slot.slot_id)
	slots.erase(cell)


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


func occupied_ids() -> Array[String]:
	var ids: Array[String] = []
	for cell in occupied_cells():
		var slot: RoomGraphSlot = slots[cell]
		ids.append(slot.slot_id)
	return ids


func main_slot_count() -> int:
	var count := 0
	for cell in slots:
		var slot: RoomGraphSlot = slots[cell]
		if slot.slot_type != RoomGraphSlot.SlotType.SECRET:
			count += 1
	return count
