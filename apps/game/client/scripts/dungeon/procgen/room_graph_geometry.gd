class_name RoomGraphGeometry
extends RefCounted


const HEIGHT_STEP := 3.0


static func build_rooms(graph: RoomGraph, assignment: Dictionary, layout: Dictionary) -> Array:
	var placements: Dictionary = layout["placements"]
	var realised: Dictionary = layout["realised_edges"]
	var door_offsets := _door_offsets_by_room(realised)
	var built: Array = []
	for room in assignment.get("rooms", []):
		var layout_id: String = room["layout_id"]
		if not placements.has(layout_id):
			# Dropped rather than fatal: the solver only ever discards optional rooms, so the floor
			# is still enterable and still has its boss and stairs.
			continue
		var placement: RoomGraphLayout.Placement = placements[layout_id]
		var center := placement.center()
		var slot := graph.get_slot(layout_id)
		var height_y := 0.0
		if slot != null:
			height_y = float(slot.height_level) * HEIGHT_STEP
		var size_x := float(placement.size.x) * RoomGraphLayout.CELL
		var size_z := float(placement.size.y) * RoomGraphLayout.CELL
		(
			built
			. append(
				{
					"id": room["semantic_id"],
					"templateId": room["template_id"],
					"type": room["type"],
					"transform":
					{
						"x": center.x,
						"y": height_y,
						"z": center.y,
						"yaw": rad_to_deg(placement.yaw),
					},
					"tags": room.get("tags", []),
					"heightLevel": slot.height_level if slot != null else 0,
					"size": {"x": size_x, "z": size_z},
					"doorOffsets": door_offsets.get(layout_id, {}),
					"kind": _minimap_kind_for_semantic(str(room["semantic_id"]), str(room["type"])),
					"shape": str(RoomTemplateCatalog.get_spec(str(room["template_id"])).get("shape", "rect")),
				}
			)
		)
	built.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("id", "")) < str(b.get("id", ""))
	)
	return built


## Turns the solver's per-edge offsets into a per-room map of wall name to lateral door offset.
static func _door_offsets_by_room(realised: Dictionary) -> Dictionary:
	var out := {}
	for key in realised:
		var edge: Dictionary = realised[key]
		var dir: Vector2i = edge["dir"]
		var from_id: String = edge["from"]
		var to_id: String = edge["to"]
		if not out.has(from_id):
			out[from_id] = {}
		if not out.has(to_id):
			out[to_id] = {}
		out[from_id][RoomGraphLayout.dir_name(dir)] = float(edge["from_offset"])
		out[to_id][RoomGraphLayout.dir_name(-dir)] = float(edge["to_offset"])
	return out


## Emits one edge per doorway the lattice actually built, plus the graph links it could not honour.
##
## Driven by the solver rather than by graph adjacency, because the two can disagree: the
## straight-line fallback lays the critical rooms out in a run that ignores their grid positions
## entirely. Reading connectivity back off the graph there would describe a floor that is not the
## one being built, and the validator would rightly call the exit unreachable.
static func build_edges(graph: RoomGraph, assignment: Dictionary, layout: Dictionary) -> Array:
	var placements: Dictionary = layout["placements"]
	var realised: Dictionary = layout["realised_edges"]
	var semantic_by_layout := {}
	var type_by_layout := {}
	for room in assignment.get("rooms", []):
		semantic_by_layout[room["layout_id"]] = room["semantic_id"]
		type_by_layout[room["layout_id"]] = room["type"]
	var edges: Array = []
	var seen := {}
	var secret_ids := {}
	for secret_id in _placed_secret_ids(graph, assignment):
		secret_ids[str(secret_id)] = true
	var loop_layout_pairs := _loop_layout_pairs(graph)
	for key in realised:
		var realised_edge: Dictionary = realised[key]
		var from_layout := str(realised_edge["from"])
		var to_layout := str(realised_edge["to"])
		if secret_ids.has(from_layout) or secret_ids.has(to_layout):
			continue
		if not semantic_by_layout.has(from_layout) or not semantic_by_layout.has(to_layout):
			continue
		var from_id: String = semantic_by_layout[from_layout]
		var to_id: String = semantic_by_layout[to_layout]
		seen[_realised_key(from_layout, to_layout)] = true
		var kind := "door"
		if (
			type_by_layout.get(from_layout, "") == "corridor"
			or type_by_layout.get(to_layout, "") == "corridor"
		):
			kind = "corridor"
		var door_world: Vector2 = realised_edge["door_world"]
		var edge_dict := {
			"from": from_id,
			"to": to_id,
			"kind": kind,
			"dir": RoomGraphLayout.dir_name(realised_edge["dir"]),
			"door": {"x": door_world.x, "z": door_world.y},
		}
		# RM-04: a loop edge is by definition redundant -- the graph already validated as connected
		# on its walk edges alone before any loop was opened -- so marking one a one-way "down" drop
		# (no ramp, see `dungeon_builder.gd:_build_height_transitions()`) can never strand anything
		# the floor requires the way promoting a dead end to a barred gate could. No walk edge is
		# ever a candidate here.
		if _realised_key(from_layout, to_layout) in loop_layout_pairs:
			var from_slot := graph.get_slot(from_layout)
			var to_slot := graph.get_slot(to_layout)
			if from_slot != null and to_slot != null and from_slot.height_level != to_slot.height_level:
				edge_dict["oneWay"] = "down"
		edges.append(edge_dict)
	# Graph links the lattice left unrealised stay in the definition as shortcuts. The builder
	# already knows to close a shortcut whose rooms do not touch, and the minimap still draws them.
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlot.SlotType.SECRET:
			continue
		for dir in _directions():
			if not (slot.door_mask & dir_to_door(dir)):
				continue
			var neighbor: RoomGraphSlot = graph.slots.get(cell + dir) as RoomGraphSlot
			if neighbor == null or neighbor.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			if not placements.has(slot.slot_id) or not placements.has(neighbor.slot_id):
				continue
			var pair_key := _realised_key(slot.slot_id, neighbor.slot_id)
			if seen.has(pair_key):
				continue
			seen[pair_key] = true
			if not semantic_by_layout.has(slot.slot_id):
				continue
			if not semantic_by_layout.has(neighbor.slot_id):
				continue
			edges.append(
				{
					"from": semantic_by_layout[slot.slot_id],
					"to": semantic_by_layout[neighbor.slot_id],
					"kind": "shortcut",
				}
			)
	for secret_id in _placed_secret_ids(graph, assignment):
		var secret_slot := graph.get_slot(secret_id)
		if secret_slot == null or secret_slot.secret_parent_id == "":
			continue
		if not semantic_by_layout.has(secret_id):
			continue
		var parent_layout := secret_slot.secret_parent_id
		if not semantic_by_layout.has(parent_layout):
			continue
		var secret_edge := {
			"from": semantic_by_layout[parent_layout],
			"to": semantic_by_layout[secret_id],
			"kind": "secret",
		}
		# A secret is seated against its host by the solver, so it gets the same wall-and-offset
		# treatment as any other doorway. Without it the panel and the hole behind it are placed by
		# the old centre-delta guess, which for a rehomed secret names a wall at random.
		var secret_dir: Vector2i = secret_slot.secret_parent_dir
		if (
			secret_dir != Vector2i.ZERO
			and placements.has(parent_layout)
			and placements.has(secret_id)
		):
			var offsets := RoomGraphLayout.door_offsets_between(
				placements[parent_layout], placements[secret_id], secret_dir
			)
			if not offsets.is_empty():
				var door_world: Vector2 = offsets["world"]
				secret_edge["dir"] = RoomGraphLayout.dir_name(secret_dir)
				secret_edge["door"] = {"x": door_world.x, "z": door_world.y}
		edges.append(secret_edge)
	edges.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ak := "%s>%s" % [a.get("from", ""), a.get("to", "")]
			var bk := "%s>%s" % [b.get("from", ""), b.get("to", "")]
			return ak < bk
	)
	return edges


## The lattice solver has no failure mode, so this no longer rejects layouts.
##
## It used to run the walk in strict mode and refuse any floor whose doors did not line up, which is
## what turned an unsatisfiable constraint system into a floor the player could not enter. Sliding
## doors mean alignment is decided by where two rooms actually meet, so the only thing left worth
## checking is that the entrance the assigner nominated is a room that exists.
static func validate_door_topology(graph: RoomGraph, assignment: Dictionary) -> Dictionary:
	var entrance_id := str(assignment.get("entrance_layout_id", graph.start_id))
	for room in assignment.get("rooms", []):
		if str(room.get("layout_id", "")) == entrance_id:
			return {"ok": true}
	return {"ok": false, "reason": "Missing entrance room '%s'" % entrance_id}


## Loop edges are stored as grid cells; realised edges are keyed by layout id. This bridges the
## two so `build_edges()` can tell whether a given realised edge came from `graph.loop_edges` (safe
## to make one-way) or `graph.walk_edges` (load-bearing, never touched here).
static func _loop_layout_pairs(graph: RoomGraph) -> Dictionary:
	var pairs := {}
	for loop_edge in graph.loop_edges:
		var slot_a: RoomGraphSlot = graph.slots.get(loop_edge["a"])
		var slot_b: RoomGraphSlot = graph.slots.get(loop_edge["b"])
		if slot_a == null or slot_b == null:
			continue
		pairs[_realised_key(slot_a.slot_id, slot_b.slot_id)] = true
	return pairs


static func _realised_key(a: String, b: String) -> String:
	return "%s>%s" % [a, b] if a < b else "%s>%s" % [b, a]


static func _placed_secret_ids(graph: RoomGraph, assignment: Dictionary) -> Array:
	var raw: Variant = assignment.get("secret_layout_ids", null)
	var ids: Array = raw if raw is Array else graph.secret_ids
	var rooms_by_layout := {}
	for room in assignment.get("rooms", []):
		rooms_by_layout[str(room.get("layout_id", ""))] = true
	var out: Array = []
	for secret_id in ids:
		if rooms_by_layout.has(str(secret_id)):
			out.append(secret_id)
	return out


static func _directions() -> Array[Vector2i]:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


## The door slot a step in `dir` leaves through. Shared with `room_graph_paths`.
static func dir_to_door(dir: Vector2i) -> int:
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
			if room_type == "secret":
				return "secret"
			return "unknown"
