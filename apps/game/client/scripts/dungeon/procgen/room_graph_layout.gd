class_name RoomGraphLayout
extends RefCounted

## Places every room of a floor on a shared lattice of 4-unit cells.
##
## The layout this replaced resolved a room's world position by walking the graph and adding half
## extents as it went, which made the position a function of whichever path arrived first. That is
## only consistent on a tree. Every biome runs `loopBudget` 3-4, and going around a loop the half
## extents have to cancel exactly -- with eleven different room footprints they almost never do, so
## the constraint system was over-determined and unsatisfiable for roughly three seeds in four. The
## generator then threw the layout away, and a floor that could not be laid out was a floor the
## player could not enter.
##
## Two things make it satisfiable here. Rooms reserve whole cells out of one occupancy grid, so two
## rooms can never be handed the same space no matter what order they are placed in. And a door is
## no longer pinned to the centre of its wall: a child slides along the wall it shares with its
## parent until it finds free cells, and the door is cut wherever the two rooms actually overlap.
## Removing that centre-alignment constraint is what lets rooms of different sizes sit next to each
## other at all.
##
## Every room footprint in `RoomTemplateCatalog` is already an exact multiple of `CELL`, so the
## lattice tiles them without gaps and without any change to the room art.

const CELL := 4.0

## A door needs `CastleRoomConstants.DOOR_WIDTH` (3.0) of shared wall, so one 4-unit cell of overlap
## is enough to cut one. Asking for two would reject a great many otherwise sound placements.
const DOOR_OVERLAP_CELLS := 1

const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

const DIR_NORTH := Vector2i(0, -1)
const DIR_EAST := Vector2i(1, 0)
const DIR_SOUTH := Vector2i(0, 1)
const DIR_WEST := Vector2i(-1, 0)


static func directions() -> Array[Vector2i]:
	return [DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST]


static func dir_name(dir: Vector2i) -> String:
	if dir == DIR_NORTH:
		return "north"
	if dir == DIR_EAST:
		return "east"
	if dir == DIR_SOUTH:
		return "south"
	return "west"


static func footprint_cells(template_id: String, yaw_rad: float) -> Vector2i:
	var spec := RoomTemplateCatalogScript.get_spec(template_id)
	var w := RoomTemplateCatalogScript.half_extent_x(spec, yaw_rad) * 2.0
	var d := RoomTemplateCatalogScript.half_extent_z(spec, yaw_rad) * 2.0
	return Vector2i(maxi(1, int(round(w / CELL))), maxi(1, int(round(d / CELL))))


## The world-space centre of a reserved rectangle.
static func rect_center(origin: Vector2i, size: Vector2i) -> Vector2:
	return Vector2((origin.x + size.x * 0.5) * CELL, (origin.y + size.y * 0.5) * CELL)


class Placement:
	extends RefCounted

	var origin: Vector2i
	var size: Vector2i
	var yaw: float = 0.0
	## Lateral door offsets in world units, keyed by "north"/"east"/"south"/"west". Measured from
	## the centre of that wall, positive towards +x on north/south walls and +z on east/west.
	var door_offsets: Dictionary = {}

	func _init(p_origin: Vector2i, p_size: Vector2i, p_yaw: float) -> void:
		origin = p_origin
		size = p_size
		yaw = p_yaw

	func center() -> Vector2:
		return Vector2((origin.x + size.x * 0.5) * CELL, (origin.y + size.y * 0.5) * CELL)


## Reserves cells and answers whether a rectangle is free.
class Occupancy:
	extends RefCounted

	var _cells: Dictionary = {}

	func is_free(origin: Vector2i, size: Vector2i) -> bool:
		for x in range(origin.x, origin.x + size.x):
			for y in range(origin.y, origin.y + size.y):
				if _cells.has(Vector2i(x, y)):
					return false
		return true

	func reserve(origin: Vector2i, size: Vector2i, owner_id: String) -> void:
		for x in range(origin.x, origin.x + size.x):
			for y in range(origin.y, origin.y + size.y):
				_cells[Vector2i(x, y)] = owner_id

	func release(origin: Vector2i, size: Vector2i) -> void:
		for x in range(origin.x, origin.x + size.x):
			for y in range(origin.y, origin.y + size.y):
				_cells.erase(Vector2i(x, y))

	func owner_at(cell: Vector2i) -> String:
		return str(_cells.get(cell, ""))


## Candidate origins for `size` placed flush against `anchor` on the `dir` side.
##
## Ordered so the most centred option is tried first: a floor whose rooms all line up through the
## middle reads as deliberate, and sliding is only worth doing when the centred placement is taken.
static func candidate_origins(
	anchor_origin: Vector2i, anchor_size: Vector2i, size: Vector2i, dir: Vector2i
) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	if dir == DIR_NORTH or dir == DIR_SOUTH:
		var y := anchor_origin.y - size.y if dir == DIR_NORTH else anchor_origin.y + anchor_size.y
		var lo := anchor_origin.x - size.x + DOOR_OVERLAP_CELLS
		var hi := anchor_origin.x + anchor_size.x - DOOR_OVERLAP_CELLS
		var centered := anchor_origin.x + int(floor((anchor_size.x - size.x) * 0.5))
		for x in _ordered_span(lo, hi, centered):
			out.append(Vector2i(x, y))
		return out
	var x_edge := anchor_origin.x - size.x if dir == DIR_WEST else anchor_origin.x + anchor_size.x
	var lo_y := anchor_origin.y - size.y + DOOR_OVERLAP_CELLS
	var hi_y := anchor_origin.y + anchor_size.y - DOOR_OVERLAP_CELLS
	var centered_y := anchor_origin.y + int(floor((anchor_size.y - size.y) * 0.5))
	for y in _ordered_span(lo_y, hi_y, centered_y):
		out.append(Vector2i(x_edge, y))
	return out


## `lo`..`hi` inclusive, emitted nearest-first around `preferred`.
static func _ordered_span(lo: int, hi: int, preferred: int) -> Array[int]:
	var out: Array[int] = []
	if hi < lo:
		return out
	var start := clampi(preferred, lo, hi)
	out.append(start)
	var step := 1
	while true:
		var added := false
		var down := start - step
		if down >= lo:
			out.append(down)
			added = true
		var up := start + step
		if up <= hi:
			out.append(up)
			added = true
		if not added:
			break
		step += 1
	return out


## The shared wall between two placed rectangles, as a door offset for each side.
##
## Returns an empty dictionary when the two rooms do not actually share `DOOR_OVERLAP_CELLS` of
## wall in `dir` -- which is how a loop edge that the lattice could not honour gets discovered and
## downgraded instead of corrupting the floor.
static func door_offsets_between(
	a: Placement, b: Placement, dir: Vector2i
) -> Dictionary:
	var overlap_lo := 0
	var overlap_hi := 0
	if dir == DIR_NORTH or dir == DIR_SOUTH:
		var a_edge := a.origin.y if dir == DIR_NORTH else a.origin.y + a.size.y
		var b_edge := b.origin.y + b.size.y if dir == DIR_NORTH else b.origin.y
		if a_edge != b_edge:
			return {}
		overlap_lo = maxi(a.origin.x, b.origin.x)
		overlap_hi = mini(a.origin.x + a.size.x, b.origin.x + b.size.x)
	else:
		var a_edge_x := a.origin.x if dir == DIR_WEST else a.origin.x + a.size.x
		var b_edge_x := b.origin.x + b.size.x if dir == DIR_WEST else b.origin.x
		if a_edge_x != b_edge_x:
			return {}
		overlap_lo = maxi(a.origin.y, b.origin.y)
		overlap_hi = mini(a.origin.y + a.size.y, b.origin.y + b.size.y)
	if overlap_hi - overlap_lo < DOOR_OVERLAP_CELLS:
		return {}
	var door_along := (overlap_lo + overlap_hi) * 0.5 * CELL
	var a_center := a.center()
	var b_center := b.center()
	# The wall the two rooms share, in world space. `along` runs down the wall; `across` is the
	# shared edge itself, which both rooms sit flush against.
	if dir == DIR_NORTH or dir == DIR_SOUTH:
		var edge_z := float(a.origin.y if dir == DIR_NORTH else a.origin.y + a.size.y) * CELL
		return {
			"a": door_along - a_center.x,
			"b": door_along - b_center.x,
			"world": Vector2(door_along, edge_z),
		}
	var edge_x := float(a.origin.x if dir == DIR_WEST else a.origin.x + a.size.x) * CELL
	return {
		"a": door_along - a_center.y,
		"b": door_along - b_center.y,
		"world": Vector2(edge_x, door_along),
	}


## Lays every room of a floor onto the lattice.
##
## Returns `{placements, dropped, realised_edges}`. It does not have a failure mode: rooms that
## cannot be fitted are reported in `dropped` rather than sinking the floor, and the rooms a floor
## cannot do without -- entrance, boss, stairs and the path between them -- fall back to a straight
## line, which always fits because it never revisits a cell.
static func solve(graph: RoomGraph, assignment: Dictionary) -> Dictionary:
	var rooms_by_layout := {}
	for room in assignment.get("rooms", []):
		rooms_by_layout[str(room.get("layout_id", ""))] = room
	var entrance_id := str(assignment.get("entrance_layout_id", graph.start_id))
	if not rooms_by_layout.has(entrance_id):
		return {"placements": {}, "dropped": [], "realised_edges": {}, "ok": false}

	var order := _bfs_order(graph, rooms_by_layout, entrance_id)
	var attempt := 0
	while attempt < 4:
		var result := _try_layout(graph, rooms_by_layout, entrance_id, order, attempt)
		if _has_required_rooms(graph, rooms_by_layout, result["placements"]):
			_place_secrets(graph, rooms_by_layout, result)
			result["realised_edges"] = _realised_edges(
				graph, result["placements"], result["tree_edges"]
			)
			result["ok"] = true
			return result
		attempt += 1
	var fallback := _straight_line_layout(graph, rooms_by_layout, entrance_id, order)
	_place_secrets(graph, rooms_by_layout, fallback)
	fallback["realised_edges"] = _realised_edges(
		graph, fallback["placements"], fallback["tree_edges"]
	)
	fallback["ok"] = true
	return fallback


## Whether a layout seated everything a floor cannot be played without.
##
## `_try_layout` reports a critical room it failed to place, but it cannot report one it was never
## offered: a boss whose door mask leaves it outside the breadth-first walk is simply absent, and
## the pass would otherwise be judged a success and go on to have the boss pruned out from under it.
static func _has_required_rooms(
	graph: RoomGraph, rooms_by_layout: Dictionary, placements: Dictionary
) -> bool:
	for required_id in [graph.start_id, graph.boss_id, graph.stairs_id]:
		if required_id == "" or not rooms_by_layout.has(required_id):
			continue
		if not placements.has(required_id):
			return false
	return true


## Secrets hang off an already-placed room rather than taking part in the breadth-first walk.
##
## A secret prefers the parent the graph chose for it, but will accept any placed room with a free
## side. `RunFloorConfig` wants one or two on every floor, and refusing to relocate a secret whose
## nominated parent happens to be boxed in is the main way a floor ends up with none.
static func _place_secrets(
	graph: RoomGraph, rooms_by_layout: Dictionary, state: Dictionary
) -> void:
	var placements: Dictionary = state["placements"]
	var occupancy := Occupancy.new()
	for layout_id in placements:
		var p: Placement = placements[layout_id]
		occupancy.reserve(p.origin, p.size, layout_id)
	for secret_id in graph.secret_ids:
		if placements.has(secret_id) or not rooms_by_layout.has(secret_id):
			continue
		var size := footprint_cells(str(rooms_by_layout[secret_id]["template_id"]), 0.0)
		var slot := graph.get_slot(secret_id)
		var preferred := slot.secret_parent_id if slot != null else ""
		var hosts: Array = []
		if preferred != "" and placements.has(preferred):
			hosts.append(preferred)
		for layout_id in placements:
			if layout_id != preferred:
				hosts.append(layout_id)
		var seated := false
		for host_id in hosts:
			var host: Placement = placements[host_id]
			for dir in directions():
				var chosen: Variant = _first_free(
					occupancy, candidate_origins(host.origin, host.size, size, dir), size, 0
				)
				if chosen == null:
					continue
				occupancy.reserve(chosen, size, secret_id)
				placements[secret_id] = Placement.new(chosen, size, 0.0)
				if slot != null:
					slot.secret_parent_id = host_id
					# Recorded rather than re-derived: a rehomed secret no longer sits one graph
					# cell from its parent, so this is the only place the shared wall is known.
					slot.secret_parent_dir = dir
				seated = true
				break
			if seated:
				break


## Breadth-first over door adjacency, skipping secrets -- they hang off a parent and are placed last.
static func _bfs_order(
	graph: RoomGraph, rooms_by_layout: Dictionary, entrance_id: String
) -> Array:
	var order: Array = []
	var seen := {entrance_id: true}
	var queue: Array[String] = [entrance_id]
	order.append({"id": entrance_id, "parent": "", "dir": Vector2i.ZERO})
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var slot := graph.get_slot(current_id)
		if slot == null:
			continue
		for dir in directions():
			if not (slot.door_mask & _door_bit(dir)):
				continue
			var neighbor := graph.get_slot_at(slot.grid_pos + dir) as RoomGraphSlot
			if neighbor == null or neighbor.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			if seen.has(neighbor.slot_id) or not rooms_by_layout.has(neighbor.slot_id):
				continue
			seen[neighbor.slot_id] = true
			order.append({"id": neighbor.slot_id, "parent": current_id, "dir": dir})
			queue.append(neighbor.slot_id)
	return order


static func _door_bit(dir: Vector2i) -> int:
	if dir == DIR_NORTH:
		return RoomGraphSlot.DOOR_NORTH
	if dir == DIR_EAST:
		return RoomGraphSlot.DOOR_EAST
	if dir == DIR_SOUTH:
		return RoomGraphSlot.DOOR_SOUTH
	return RoomGraphSlot.DOOR_WEST


static func _is_critical(graph: RoomGraph, layout_id: String) -> bool:
	if layout_id == graph.start_id or layout_id == graph.boss_id or layout_id == graph.stairs_id:
		return true
	var slot := graph.get_slot(layout_id)
	return slot != null and slot.on_critical_path


static func _yaw_for(
	rooms_by_layout: Dictionary, graph: RoomGraph, layout_id: String, entry: Dictionary
) -> float:
	var room: Dictionary = rooms_by_layout[layout_id]
	var template_id := str(room.get("template_id", ""))
	var parent_id := str(entry.get("parent", ""))
	if parent_id == "":
		var slot := graph.get_slot(layout_id)
		var mask: int = slot.door_mask if slot != null else 0
		return RoomTemplateCatalogScript.yaw_rad_for_entrance(template_id, mask)
	var dir: Vector2i = entry.get("dir", Vector2i.ZERO)
	var pair := RoomTemplateCatalogScript.doors_for_step(dir.x, dir.y)
	return RoomTemplateCatalogScript.yaw_rad_for_incoming_door(template_id, int(pair[1]))


## One greedy pass. `shuffle_bias` nudges which candidate offset is preferred so a repeat attempt
## explores a different shape instead of re-deriving the same jam.
static func _try_layout(
	graph: RoomGraph,
	rooms_by_layout: Dictionary,
	entrance_id: String,
	order: Array,
	shuffle_bias: int
) -> Dictionary:
	var occupancy := Occupancy.new()
	var placements := {}
	var dropped: Array = []
	var tree_edges: Array = []
	var critical_ok := true
	for entry in order:
		var layout_id: String = str(entry["id"])
		var yaw := _yaw_for(rooms_by_layout, graph, layout_id, entry)
		var size := footprint_cells(str(rooms_by_layout[layout_id]["template_id"]), yaw)
		if layout_id == entrance_id:
			var placement := Placement.new(Vector2i.ZERO, size, yaw)
			occupancy.reserve(Vector2i.ZERO, size, layout_id)
			placements[layout_id] = placement
			continue
		var parent_id: String = str(entry["parent"])
		if not placements.has(parent_id):
			dropped.append(layout_id)
			if _is_critical(graph, layout_id):
				critical_ok = false
			continue
		var parent: Placement = placements[parent_id]
		var dir: Vector2i = entry["dir"]
		var candidates := candidate_origins(parent.origin, parent.size, size, dir)
		var chosen: Variant = _best_free(
			occupancy, candidates, size, shuffle_bias, graph, layout_id, placements
		)
		if chosen == null:
			dropped.append(layout_id)
			if _is_critical(graph, layout_id):
				critical_ok = false
			continue
		var placed := Placement.new(chosen, size, yaw)
		occupancy.reserve(chosen, size, layout_id)
		placements[layout_id] = placed
		tree_edges.append({"from": parent_id, "to": layout_id, "dir": dir})
	return {
		"placements": placements,
		"dropped": dropped,
		"tree_edges": tree_edges,
		"critical_ok": critical_ok,
	}


## Picks a free spot, preferring one that also closes a loop.
##
## Placement is otherwise greedy and breadth-first, so a graph loop only becomes a real doorway when
## two rooms happen to land against each other. That left most floors as plain trees -- and a loop
## that does not close is downgraded to a shortcut the builder then seals, so the floor loses the
## fold-back routes a Souls-like leans on. Scoring each candidate by how many of the room's *other*
## graph neighbours it would end up sharing a wall with turns that luck into intent, at the cost of
## a handful of rectangle comparisons. Ties keep the earlier, more centred candidate.
static func _best_free(
	occupancy: Occupancy,
	candidates: Array[Vector2i],
	size: Vector2i,
	shuffle_bias: int,
	graph: RoomGraph,
	layout_id: String,
	placements: Dictionary
) -> Variant:
	var best: Variant = null
	var best_score := -1
	var count := candidates.size()
	for i in count:
		var index := (i + shuffle_bias) % count if shuffle_bias > 0 else i
		var origin: Vector2i = candidates[index]
		if not occupancy.is_free(origin, size):
			continue
		var score := _loop_score(graph, layout_id, origin, size, placements)
		if score > best_score:
			best_score = score
			best = origin
		if best_score >= 2:
			break
	return best


## How many already-placed graph neighbours this position would share a doorway with.
static func _loop_score(
	graph: RoomGraph,
	layout_id: String,
	origin: Vector2i,
	size: Vector2i,
	placements: Dictionary
) -> int:
	var slot := graph.get_slot(layout_id)
	if slot == null:
		return 0
	var probe := Placement.new(origin, size, 0.0)
	var score := 0
	for dir in directions():
		if not (slot.door_mask & _door_bit(dir)):
			continue
		var neighbor := graph.get_slot_at(slot.grid_pos + dir) as RoomGraphSlot
		if neighbor == null or not placements.has(neighbor.slot_id):
			continue
		if not door_offsets_between(probe, placements[neighbor.slot_id], dir).is_empty():
			score += 1
	return score


static func _first_free(
	occupancy: Occupancy, candidates: Array[Vector2i], size: Vector2i, shuffle_bias: int
) -> Variant:
	if candidates.is_empty():
		return null
	var count := candidates.size()
	for i in count:
		var index := (i + shuffle_bias) % count if shuffle_bias > 0 else i
		var origin: Vector2i = candidates[index]
		if occupancy.is_free(origin, size):
			return origin
	return null


## The guarantee of last resort: run the critical rooms out in one direction, then hang whatever
## optional rooms still fit off them. A straight run never revisits a cell, so it always places.
static func _straight_line_layout(
	graph: RoomGraph, rooms_by_layout: Dictionary, entrance_id: String, order: Array
) -> Dictionary:
	var occupancy := Occupancy.new()
	var placements := {}
	var dropped: Array = []
	var critical: Array = [entrance_id]
	for entry in order:
		var layout_id: String = str(entry["id"])
		if layout_id != entrance_id and _is_critical(graph, layout_id):
			critical.append(layout_id)
	# The walk may not have reached the boss or the stairs at all, which is one of the reasons this
	# fallback exists. Put them on the end of the run so the floor is at least completable.
	for required_id in [graph.boss_id, graph.stairs_id]:
		if required_id == "" or critical.has(required_id):
			continue
		if rooms_by_layout.has(required_id):
			critical.append(required_id)
	var tree_edges: Array = []
	var cursor := 0
	var previous_id := ""
	for layout_id in critical:
		# The run always steps east, so every room after the first needs its incoming door rotated
		# to face west (back toward the room before it) -- a hardcoded yaw=0.0 here left single- or
		# limited-door rooms (e.g. boss) facing whichever way their template's primary door happens
		# to point, which is only ever correct by accident.
		var yaw := 0.0
		if previous_id != "":
			yaw = RoomTemplateCatalogScript.yaw_rad_for_incoming_door(
				str(rooms_by_layout[layout_id]["template_id"]), RoomGraphSlot.DOOR_WEST
			)
		var size := footprint_cells(str(rooms_by_layout[layout_id]["template_id"]), yaw)
		var origin := Vector2i(cursor, 0)
		occupancy.reserve(origin, size, layout_id)
		placements[layout_id] = Placement.new(origin, size, yaw)
		if previous_id != "":
			# The run is laid out west to east regardless of where the graph put these cells, so the
			# connection has to be recorded from the placement rather than read back off the graph.
			tree_edges.append({"from": previous_id, "to": layout_id, "dir": DIR_EAST})
		previous_id = layout_id
		cursor += size.x
	for entry in order:
		var layout_id: String = str(entry["id"])
		if placements.has(layout_id):
			continue
		var parent_id: String = str(entry["parent"])
		if not placements.has(parent_id):
			dropped.append(layout_id)
			continue
		var parent: Placement = placements[parent_id]
		var yaw := _yaw_for(rooms_by_layout, graph, layout_id, entry)
		var size := footprint_cells(str(rooms_by_layout[layout_id]["template_id"]), yaw)
		var dir: Vector2i = entry["dir"]
		var chosen: Variant = _first_free(
			occupancy, candidate_origins(parent.origin, parent.size, size, dir), size, 0
		)
		if chosen == null:
			dropped.append(layout_id)
			continue
		occupancy.reserve(chosen, size, layout_id)
		placements[layout_id] = Placement.new(chosen, size, yaw)
		tree_edges.append({"from": parent_id, "to": layout_id, "dir": dir})
	return {
		"placements": placements,
		"dropped": dropped,
		"tree_edges": tree_edges,
		"critical_ok": true,
	}


## Which graph adjacencies the lattice actually honoured, with the door offset for each side.
##
## A loop edge only becomes a door when the two rooms genuinely ended up sharing wall. The rest are
## reported as unrealised and the definition downgrades them, which is what stops a loop the lattice
## could not close from turning into a door onto solid rock.
static func _realised_edges(
	graph: RoomGraph, placements: Dictionary, tree_edges: Array
) -> Dictionary:
	var out := {}
	# The placement tree comes first and is never questioned. Every one of its edges was created by
	# seating a room flush against its parent, so the doorway is real whatever the graph thinks the
	# two cells' relationship is -- which matters for the straight-line fallback, where the layout
	# deliberately ignores the graph's grid positions and would otherwise read as disconnected.
	for edge in tree_edges:
		var from_id := str(edge["from"])
		var to_id := str(edge["to"])
		if not placements.has(from_id) or not placements.has(to_id):
			continue
		var dir: Vector2i = edge["dir"]
		var offsets := door_offsets_between(placements[from_id], placements[to_id], dir)
		if offsets.is_empty():
			continue
		out[_pair_key(from_id, to_id)] = {
			"from": from_id,
			"to": to_id,
			"dir": dir,
			"from_offset": float(offsets["a"]),
			"to_offset": float(offsets["b"]),
			"door_world": offsets["world"],
		}
	# Then the loops: a graph edge that is not part of the tree becomes a real door only where the
	# lattice happened to leave the two rooms sharing a wall. Loops the lattice could not close are
	# simply not doors, which is what keeps a shortcut from opening onto solid rock.
	for layout_id in placements:
		var slot := graph.get_slot(layout_id)
		if slot == null:
			continue
		for dir in directions():
			if not (slot.door_mask & _door_bit(dir)):
				continue
			var neighbor := graph.get_slot_at(slot.grid_pos + dir) as RoomGraphSlot
			if neighbor == null or not placements.has(neighbor.slot_id):
				continue
			var key := _pair_key(layout_id, neighbor.slot_id)
			if out.has(key):
				continue
			var loop_offsets := door_offsets_between(
				placements[layout_id], placements[neighbor.slot_id], dir
			)
			if loop_offsets.is_empty():
				continue
			out[key] = {
				"from": layout_id,
				"to": neighbor.slot_id,
				"dir": dir,
				"from_offset": float(loop_offsets["a"]),
				"to_offset": float(loop_offsets["b"]),
				"door_world": loop_offsets["world"],
			}
	return out


static func _pair_key(a: String, b: String) -> String:
	return "%s>%s" % [a, b] if a < b else "%s>%s" % [b, a]
