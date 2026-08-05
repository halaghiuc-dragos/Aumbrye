class_name RoomGraph
extends RefCounted

## Validated abstract layout graph produced by Phase 1.

var slots: Dictionary = {} # Vector2i -> RoomGraphSlot
var start_id: String = ""
var boss_id: String = ""
var secret_ids: Array[String] = []
var treasure_id: String = ""
var stairs_id: String = ""
var walk_edges: Array = [] # [{a: Vector2i, b: Vector2i}, ...] spanning-tree edges
var config: RoomGraphConfig


func get_slot(slot_id: String) -> RoomGraphSlot:
	for cell in slots:
		var slot: RoomGraphSlot = slots[cell]
		if slot.slot_id == slot_id:
			return slot
	return null


func get_slot_at(cell: Vector2i) -> RoomGraphSlot:
	return slots.get(cell) as RoomGraphSlot


func occupied_cells() -> Array[Vector2i]:
	var cells: Array[Vector2i] = []
	for cell in slots:
		cells.append(cell)
	cells.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
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
