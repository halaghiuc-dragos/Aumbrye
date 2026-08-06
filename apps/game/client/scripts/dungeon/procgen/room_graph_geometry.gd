class_name RoomGraphGeometry
extends RefCounted

## Phase 2 — socket-aligned world positions from the validated graph.

const HEIGHT_STEP := 3.0


static func build_rooms(graph: RoomGraph, assignment: Dictionary) -> Array:
	var rooms_by_layout := {}
	for room in assignment.get("rooms", []):
		rooms_by_layout[room["layout_id"]] = room
	var positions := {}
	var yaws := {}
	var visited := {}
	var entrance_id: String = assignment.get("entrance_layout_id", graph.start_id)
	positions[entrance_id] = Vector2.ZERO
	yaws[entrance_id] = RoomTemplateCatalog.yaw_rad_for_entrance(
		rooms_by_layout[entrance_id]["template_id"], graph.get_slot(entrance_id).door_mask
	)
	visited[entrance_id] = true
	var queue: Array[String] = [entrance_id]
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current_slot := graph.get_slot(current_id)
		var current_room: Dictionary = rooms_by_layout[current_id]
		var current_pos: Vector2 = positions[current_id]
		var parent_yaw: float = yaws[current_id]
		var parent_spec := RoomTemplateCatalog.get_spec(current_room["template_id"])
		for dir in _directions():
			var neighbor_cell: Vector2i = current_slot.grid_pos + dir
			var neighbor_slot: RoomGraphSlot = graph.slots.get(neighbor_cell) as RoomGraphSlot
			if neighbor_slot == null:
				continue
			if neighbor_slot.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			if not (current_slot.door_mask & _dir_to_door(dir)):
				continue
			var neighbor_id := neighbor_slot.slot_id
			if visited.has(neighbor_id):
				continue
			var neighbor_room: Dictionary = rooms_by_layout[neighbor_id]
			var child_spec := RoomTemplateCatalog.get_spec(neighbor_room["template_id"])
			var dx := neighbor_slot.grid_pos.x - current_slot.grid_pos.x
			var dz := neighbor_slot.grid_pos.y - current_slot.grid_pos.y
			var door_pair := RoomTemplateCatalog.doors_for_step(dx, dz)
			var incoming_door: int = int(door_pair[1])
			var child_yaw := RoomTemplateCatalog.yaw_rad_for_incoming_door(
				neighbor_room["template_id"], incoming_door
			)
			if not _doors_aligned(
				current_room, neighbor_room, door_pair, parent_yaw, child_yaw, dx, dz
			):
				push_error(
					(
						"Door mismatch %s→%s on step (%d,%d)"
						% [current_room["template_id"], neighbor_room["template_id"], dx, dz]
					)
				)
			var next_pos := current_pos
			if dz == -1:
				next_pos.y -= (
					RoomTemplateCatalog.half_extent_z(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_z(child_spec, child_yaw)
				)
			elif dz == 1:
				next_pos.y += (
					RoomTemplateCatalog.half_extent_z(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_z(child_spec, child_yaw)
				)
			elif dx == 1:
				next_pos.x += (
					RoomTemplateCatalog.half_extent_x(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_x(child_spec, child_yaw)
				)
			elif dx == -1:
				next_pos.x -= (
					RoomTemplateCatalog.half_extent_x(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_x(child_spec, child_yaw)
				)
			positions[neighbor_id] = next_pos
			yaws[neighbor_id] = child_yaw
			visited[neighbor_id] = true
			queue.append(neighbor_id)
	_place_secret_rooms(graph, assignment, rooms_by_layout, positions, yaws, visited)
	var built: Array = []
	for room in assignment.get("rooms", []):
		var layout_id: String = room["layout_id"]
		if not positions.has(layout_id):
			push_error("Room '%s' has no world position" % layout_id)
			continue
		var pos: Vector2 = positions[layout_id]
		var yaw_rad: float = yaws.get(layout_id, 0.0)
		var slot := graph.get_slot(layout_id)
		var height_y := 0.0
		if slot != null:
			height_y = float(slot.height_level) * HEIGHT_STEP
		var spec := RoomTemplateCatalog.get_spec(room["template_id"])
		var half_x := RoomTemplateCatalog.half_extent_x(spec, yaw_rad)
		var half_z := RoomTemplateCatalog.half_extent_z(spec, yaw_rad)
		(
			built
			. append(
				{
					"id": room["semantic_id"],
					"templateId": room["template_id"],
					"type": room["type"],
					"transform":
					{"x": pos.x, "y": height_y, "z": pos.y, "yaw": rad_to_deg(yaw_rad)},
					"tags": room.get("tags", []),
					"heightLevel": slot.height_level if slot != null else 0,
					"size": {"x": half_x * 2.0, "z": half_z * 2.0},
					"kind": _minimap_kind_for_semantic(str(room["semantic_id"]), str(room["type"])),
				}
			)
		)
	built.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return built


static func build_edges(graph: RoomGraph, assignment: Dictionary) -> Array:
	var semantic_by_layout := {}
	for room in assignment.get("rooms", []):
		semantic_by_layout[room["layout_id"]] = room["semantic_id"]
	var type_by_layout := {}
	for room in assignment.get("rooms", []):
		type_by_layout[room["layout_id"]] = room["type"]
	var edges: Array = []
	var seen := {}
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlot.SlotType.SECRET:
			continue
		for dir in _directions():
			if not (slot.door_mask & _dir_to_door(dir)):
				continue
			var neighbor: RoomGraphSlot = graph.slots.get(cell + dir) as RoomGraphSlot
			if neighbor == null or neighbor.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			var from_id: String = semantic_by_layout.get(slot.slot_id, slot.slot_id)
			var to_id: String = semantic_by_layout.get(neighbor.slot_id, neighbor.slot_id)
			var pair := [from_id, to_id]
			pair.sort()
			var key := "%s>%s" % [pair[0], pair[1]]
			if seen.has(key):
				continue
			seen[key] = true
			var kind := "door"
			if (
				type_by_layout.get(slot.slot_id, "") == "corridor"
				or type_by_layout.get(neighbor.slot_id, "") == "corridor"
			):
				kind = "corridor"
			elif not _is_spanning_edge(graph, cell, cell + dir):
				kind = "shortcut"
			edges.append({"from": from_id, "to": to_id, "kind": kind})
	for secret_id in graph.secret_ids:
		var secret_slot := graph.get_slot(secret_id)
		if secret_slot == null or secret_slot.secret_parent_id == "":
			continue
		var from_semantic: String = semantic_by_layout.get(
			secret_slot.secret_parent_id, secret_slot.secret_parent_id
		)
		var to_semantic: String = semantic_by_layout.get(secret_id, secret_id)
		edges.append({"from": from_semantic, "to": to_semantic, "kind": "secret"})
	edges.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ak := "%s>%s" % [a.get("from", ""), a.get("to", "")]
			var bk := "%s>%s" % [b.get("from", ""), b.get("to", "")]
			return ak < bk
	)
	return edges


static func validate_door_topology(graph: RoomGraph, assignment: Dictionary) -> Dictionary:
	var rooms_by_layout := {}
	for room in assignment.get("rooms", []):
		rooms_by_layout[room["layout_id"]] = room
	var positions := {}
	var yaws := {}
	var visited := {}
	var entrance_id: String = assignment.get("entrance_layout_id", graph.start_id)
	positions[entrance_id] = Vector2.ZERO
	yaws[entrance_id] = RoomTemplateCatalog.yaw_rad_for_entrance(
		rooms_by_layout[entrance_id]["template_id"], graph.get_slot(entrance_id).door_mask
	)
	visited[entrance_id] = true
	var queue: Array[String] = [entrance_id]
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current_slot := graph.get_slot(current_id)
		var current_room: Dictionary = rooms_by_layout[current_id]
		var current_pos: Vector2 = positions[current_id]
		var parent_yaw: float = yaws[current_id]
		var parent_spec := RoomTemplateCatalog.get_spec(current_room["template_id"])
		for dir in _directions():
			var neighbor_cell: Vector2i = current_slot.grid_pos + dir
			var neighbor_slot: RoomGraphSlot = graph.slots.get(neighbor_cell) as RoomGraphSlot
			if neighbor_slot == null:
				continue
			if neighbor_slot.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			if not (current_slot.door_mask & _dir_to_door(dir)):
				continue
			var neighbor_id := neighbor_slot.slot_id
			if visited.has(neighbor_id):
				continue
			var neighbor_room: Dictionary = rooms_by_layout[neighbor_id]
			var child_spec := RoomTemplateCatalog.get_spec(neighbor_room["template_id"])
			var dx := neighbor_slot.grid_pos.x - current_slot.grid_pos.x
			var dz := neighbor_slot.grid_pos.y - current_slot.grid_pos.y
			var door_pair := RoomTemplateCatalog.doors_for_step(dx, dz)
			var incoming_door: int = int(door_pair[1])
			var child_yaw := RoomTemplateCatalog.yaw_rad_for_incoming_door(
				neighbor_room["template_id"], incoming_door
			)
			if not _doors_aligned(
				current_room, neighbor_room, door_pair, parent_yaw, child_yaw, dx, dz
			):
				return {
					"ok": false,
					"reason":
					(
						"Door mismatch %s→%s on step (%d,%d)"
						% [current_room["template_id"], neighbor_room["template_id"], dx, dz]
					),
				}
			var next_pos := current_pos
			if dz == -1:
				next_pos.y -= (
					RoomTemplateCatalog.half_extent_z(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_z(child_spec, child_yaw)
				)
			elif dz == 1:
				next_pos.y += (
					RoomTemplateCatalog.half_extent_z(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_z(child_spec, child_yaw)
				)
			elif dx == 1:
				next_pos.x += (
					RoomTemplateCatalog.half_extent_x(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_x(child_spec, child_yaw)
				)
			elif dx == -1:
				next_pos.x -= (
					RoomTemplateCatalog.half_extent_x(parent_spec, parent_yaw)
					+ RoomTemplateCatalog.half_extent_x(child_spec, child_yaw)
				)
			positions[neighbor_id] = next_pos
			yaws[neighbor_id] = child_yaw
			visited[neighbor_id] = true
			queue.append(neighbor_id)
	return {"ok": true}


static func _is_spanning_edge(graph: RoomGraph, cell_a: Vector2i, cell_b: Vector2i) -> bool:
	var key := _edge_key(cell_a, cell_b)
	for edge in graph.walk_edges:
		if edge.get("key", "") == key:
			return true
	return false


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


static func _place_secret_rooms(
	graph: RoomGraph,
	_assignment: Dictionary,
	rooms_by_layout: Dictionary,
	positions: Dictionary,
	yaws: Dictionary,
	visited: Dictionary
) -> void:
	for secret_id in graph.secret_ids:
		var secret_slot := graph.get_slot(secret_id)
		if secret_slot == null or secret_slot.secret_parent_id == "":
			continue
		var parent_id := secret_slot.secret_parent_id
		if not positions.has(parent_id):
			continue
		var parent_slot := graph.get_slot(parent_id)
		var parent_room: Dictionary = rooms_by_layout[parent_id]
		var secret_room: Dictionary = rooms_by_layout[secret_id]
		var parent_pos: Vector2 = positions[parent_id]
		var parent_yaw: float = yaws.get(parent_id, 0.0)
		var parent_spec := RoomTemplateCatalog.get_spec(parent_room["template_id"])
		var secret_spec := RoomTemplateCatalog.get_spec(secret_room["template_id"])
		var dx := secret_slot.grid_pos.x - parent_slot.grid_pos.x
		var dz := secret_slot.grid_pos.y - parent_slot.grid_pos.y
		var door_pair := RoomTemplateCatalog.doors_for_step(dx, dz)
		var secret_yaw := RoomTemplateCatalog.yaw_rad_for_incoming_door(
			secret_room["template_id"], int(door_pair[1])
		)
		var next_pos := parent_pos
		if dz == -1:
			next_pos.y -= (
				RoomTemplateCatalog.half_extent_z(parent_spec, parent_yaw)
				+ RoomTemplateCatalog.half_extent_z(secret_spec, secret_yaw)
			)
		elif dz == 1:
			next_pos.y += (
				RoomTemplateCatalog.half_extent_z(parent_spec, parent_yaw)
				+ RoomTemplateCatalog.half_extent_z(secret_spec, secret_yaw)
			)
		elif dx == 1:
			next_pos.x += (
				RoomTemplateCatalog.half_extent_x(parent_spec, parent_yaw)
				+ RoomTemplateCatalog.half_extent_x(secret_spec, secret_yaw)
			)
		elif dx == -1:
			next_pos.x -= (
				RoomTemplateCatalog.half_extent_x(parent_spec, parent_yaw)
				+ RoomTemplateCatalog.half_extent_x(secret_spec, secret_yaw)
			)
		positions[secret_id] = next_pos
		yaws[secret_id] = secret_yaw
		visited[secret_id] = true


static func _doors_aligned(
	current_room: Dictionary,
	neighbor_room: Dictionary,
	door_pair: Array,
	parent_yaw: float,
	child_yaw: float,
	_dx: int,
	_dz: int
) -> bool:
	var parent_out: int = int(door_pair[0])
	var child_in: int = int(door_pair[1])
	if not _door_satisfied(current_room["template_id"], parent_out, parent_yaw):
		return false
	if not _door_satisfied(neighbor_room["template_id"], child_in, child_yaw):
		return false
	return true


static func _door_satisfied(template_id: String, door_mask: int, yaw_rad: float) -> bool:
	if RoomTemplateCatalog.has_door(template_id, door_mask):
		return true
	var primary: int = RoomTemplateCatalog.primary_door_mask(
		int(RoomTemplateCatalog.get_spec(template_id)["doors"])
	)
	if primary == 0:
		return false
	var aligned := RoomTemplateCatalog.yaw_to_align_doors(primary, door_mask)
	return is_equal_approx(aligned, yaw_rad)


static func _directions() -> Array[Vector2i]:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func _dir_to_door(dir: Vector2i) -> int:
	if dir == Vector2i(0, -1):
		return RoomGraphSlot.DOOR_NORTH
	if dir == Vector2i(1, 0):
		return RoomGraphSlot.DOOR_EAST
	if dir == Vector2i(0, 1):
		return RoomGraphSlot.DOOR_SOUTH
	return RoomGraphSlot.DOOR_WEST


static func _minimap_kind_for_semantic(semantic_id: String, room_type: String) -> String:
	match semantic_id:
		"entrance":
			return "entrance"
		"boss":
			return "boss"
		"treasure":
			return "treasure"
		"shop":
			return "shop"
		"stairs":
			return "stairs"
		_:
			if room_type == "combat":
				return "combat"
			return "unknown"
