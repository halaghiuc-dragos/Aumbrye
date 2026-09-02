class_name RoomGraphGenerator
extends RefCounted


const RoomGraphSlotScript := preload("res://scripts/dungeon/procgen/room_graph_slot.gd")
const RoomGraphScript := preload("res://scripts/dungeon/procgen/room_graph.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphDebugScript := preload("res://scripts/dungeon/procgen/room_graph_debug.gd")
const RoomGraphPathsScript := preload("res://scripts/dungeon/procgen/room_graph_paths.gd")

const DIR_NORTH := Vector2i(0, -1)
const DIR_EAST := Vector2i(1, 0)
const DIR_SOUTH := Vector2i(0, 1)
const DIR_WEST := Vector2i(-1, 0)
const DIRECTIONS: Array[Vector2i] = [DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST]
const HEIGHT_RUN_LENGTH := 4

const LOOP_STRICT_ATTEMPT_FRACTION := 0.75

const DIR_TO_DOOR := {
	Vector2i(0, -1): RoomGraphSlotScript.DOOR_NORTH,
	Vector2i(1, 0): RoomGraphSlotScript.DOOR_EAST,
	Vector2i(0, 1): RoomGraphSlotScript.DOOR_SOUTH,
	Vector2i(-1, 0): RoomGraphSlotScript.DOOR_WEST,
}

class GenerationReport extends RefCounted:
	var ok: bool = false
	var used_fallback: bool = false
	var attempts: int = 0
	var reasons: PackedStringArray = []
	var graph: RoomGraph = null
	var main_room_count: int = 0


static var _last_validate_reason := ""


static func last_validate_reason() -> String:
	return _last_validate_reason


static func generate_reported(config: RoomGraphConfig, run_seed: int) -> GenerationReport:
	var report := GenerationReport.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	var strict_attempts := int(config.max_generation_attempts * LOOP_STRICT_ATTEMPT_FRACTION)
	for attempt in config.max_generation_attempts:
		report.attempts = attempt + 1
		var graph := _try_generate_once(config, rng, attempt < strict_attempts)
		if graph != null:
			report.ok = true
			report.used_fallback = false
			report.graph = graph
			report.main_room_count = graph.main_slot_count()
			if config.debug_ascii:
				RoomGraphDebugScript.print_graph(graph)
			return report
		report.reasons.append(_last_validate_reason)
		rng.seed = run_seed + (attempt + 1) * 1_000_003
	report.ok = false
	report.used_fallback = false
	return report


static func generate(config: RoomGraphConfig, run_seed: int) -> Dictionary:
	var report := generate_reported(config, run_seed)
	if report.ok:
		return {
			"ok": true,
			"graph": report.graph,
			"used_fallback": report.used_fallback,
			"attempts": report.attempts,
		}
	var reason := report.reasons[-1] if not report.reasons.is_empty() else ""
	return {
		"ok": false,
		"reason": reason,
		"used_fallback": report.used_fallback,
		"attempts": report.attempts,
	}


static func _try_generate_once(
	config: RoomGraphConfig, rng: RandomNumberGenerator, require_loops: bool = true
) -> RoomGraph:
	var graph := RoomGraphScript.new()
	graph.config = config
	var target_rooms := rng.randi_range(config.min_rooms, config.max_rooms)
	var center := config.grid_center()
	var start := _make_slot(center, "room_0", RoomGraphSlotScript.SlotType.START)
	start.on_critical_path = true
	graph.add_slot(center, start)
	graph.start_id = start.slot_id
	var path_target := maxi(config.boss_min_distance, int(target_rooms / 3.0))
	var path_result := _grow_critical_path(graph, center, path_target, config, rng)
	var next_index: int = path_result["next_index"]
	var path_cells: Array = path_result["path_cells"]
	next_index = _grow_branches(graph, path_cells, next_index, target_rooms, config, rng)
	if graph.main_slot_count() < config.min_rooms:
		var all_cells: Array = []
		all_cells.assign(graph.occupied_cells())
		next_index = _grow_branches(graph, all_cells, next_index, config.min_rooms, config, rng)
	if config.fill_bounding_box and graph.main_slot_count() < config.min_rooms:
		next_index = _fill_bounding_box(graph, next_index, config.min_rooms)
	_connect_fillers(graph)
	_apply_door_connections(graph, rng, config)
	_smooth_height_levels(graph, config)
	_assign_special_rooms(graph, rng, config)
	_place_secret_attachments(graph, rng, config)
	_apply_secret_door_masks(graph)
	if not _validate_graph(graph, config, require_loops).get("ok", false):
		return null
	return graph


static func _grow_critical_path(
	graph: RoomGraph,
	center: Vector2i,
	path_target: int,
	config: RoomGraphConfig,
	rng: RandomNumberGenerator
) -> Dictionary:
	var next_index := 1
	var path_cells: Array[Vector2i] = [center]
	var cursor := center
	var direction: Vector2i = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
	var stuck_turns := 0
	while path_cells.size() < path_target:
		var placed := false
		var dirs_to_try: Array[Vector2i] = [direction]
		var other_dirs := DIRECTIONS.duplicate()
		_shuffle_dirs(other_dirs, rng)
		for dir in other_dirs:
			if dir != direction:
				dirs_to_try.append(dir)
		for dir in dirs_to_try:
			var target_cell: Vector2i = cursor + dir
			if not _can_place_room(graph, target_cell, config):
				continue
			var slot := _make_slot(
				target_cell, "room_%d" % next_index, RoomGraphSlotScript.SlotType.NORMAL
			)
			slot.on_critical_path = true
			var parent_level: int = graph.get_slot_at(cursor).height_level
			slot.height_level = parent_level
			if (
				config.max_height_level > 0
				and path_cells.size() > 0
				and path_cells.size() % HEIGHT_RUN_LENGTH == 0
			):
				if rng.randf() < 0.35:
					slot.height_level = mini(parent_level + 1, config.max_height_level)
			graph.add_slot(target_cell, slot)
			_record_walk_edge(graph, cursor, target_cell)
			path_cells.append(target_cell)
			cursor = target_cell
			direction = dir
			next_index += 1
			placed = true
			stuck_turns = 0
			break
		if placed:
			continue
		stuck_turns += 1
		if stuck_turns > 12:
			break
		cursor = path_cells[rng.randi_range(0, path_cells.size() - 1)]
		direction = DIRECTIONS[rng.randi_range(0, DIRECTIONS.size() - 1)]
	return {"path_cells": path_cells, "next_index": next_index}


static func _grow_branches(
	graph: RoomGraph,
	path_cells: Array,
	next_index: int,
	target_rooms: int,
	config: RoomGraphConfig,
	rng: RandomNumberGenerator
) -> int:
	var branch_attempts := 0
	while graph.slots.size() < target_rooms and branch_attempts < config.max_walk_attempts:
		branch_attempts += 1
		if path_cells.is_empty():
			break
		var origin_cell: Vector2i = path_cells[rng.randi_range(0, path_cells.size() - 1)]
		var frontier: Array = [[origin_cell, 0]]
		var placed_any := false
		while not frontier.is_empty() and graph.slots.size() < target_rooms:
			var entry: Array = frontier.pop_front()
			var cell: Vector2i = entry[0]
			var depth: int = entry[1]
			if depth >= config.branch_max_depth:
				continue
			var dirs := DIRECTIONS.duplicate()
			_shuffle_dirs(dirs, rng)
			for dir in dirs:
				var target_cell: Vector2i = cell + dir
				if not _can_place_room(graph, target_cell, config):
					continue
				var parent_slot: RoomGraphSlot = graph.get_slot_at(cell)
				var slot := _make_slot(
					target_cell, "room_%d" % next_index, RoomGraphSlotScript.SlotType.NORMAL
				)
				slot.height_level = parent_slot.height_level
				graph.add_slot(target_cell, slot)
				_record_walk_edge(graph, cell, target_cell)
				frontier.append([target_cell, depth + 1])
				next_index += 1
				placed_any = true
				break
		if not placed_any:
			continue
	return next_index


static func _can_place_room(graph: RoomGraph, cell: Vector2i, config: RoomGraphConfig) -> bool:
	if not _in_bounds(cell, config):
		return false
	if graph.slots.has(cell):
		return false
	if _occupied_neighbor_count(graph, cell) >= config.max_neighbor_count:
		return false
	if not config.allow_2x2_blocks and _creates_2x2_block(graph, cell):
		return false
	return true


static func _make_slot(
	cell: Vector2i, slot_id: String, slot_type: RoomGraphSlot.SlotType
) -> RoomGraphSlot:
	var slot := RoomGraphSlotScript.new()
	slot.grid_pos = cell
	slot.slot_id = slot_id
	slot.slot_type = slot_type
	return slot


static func _in_bounds(cell: Vector2i, config: RoomGraphConfig) -> bool:
	return (
		cell.x >= 0 and cell.y >= 0 and cell.x < config.grid_width and cell.y < config.grid_height
	)


static func _occupied_neighbor_count(graph: RoomGraph, cell: Vector2i) -> int:
	var count := 0
	for dir in DIRECTIONS:
		if graph.slots.has(cell + dir):
			count += 1
	return count


static func _creates_2x2_block(graph: RoomGraph, cell: Vector2i) -> bool:
	for ox in 2:
		for oy in 2:
			var anchor := cell + Vector2i(-ox, -oy)
			if graph.block_count_at(anchor) == 4:
				return true
	return false


static func _connect_fillers(graph: RoomGraph) -> void:
	var grid_distances := _grid_bfs_distances(graph, graph.start_id)
	var fillers_to_remove: Array[Vector2i] = []
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.get_slot_at(cell)
		if slot == null or not slot.is_filler:
			continue
		var best_neighbor := Vector2i(-99999, -99999)
		var best_dist := 99999
		for dir in DIRECTIONS:
			var neighbor_cell: Vector2i = cell + dir
			if not graph.slots.has(neighbor_cell):
				continue
			var neighbor: RoomGraphSlot = graph.get_slot_at(neighbor_cell)
			if neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			var neighbor_dist: int = int(grid_distances.get(neighbor.slot_id, 99999))
			if neighbor_dist < best_dist:
				best_dist = neighbor_dist
				best_neighbor = neighbor_cell
		if best_neighbor == Vector2i(-99999, -99999):
			fillers_to_remove.append(cell)
		else:
			_record_walk_edge(graph, cell, best_neighbor)
	for cell in fillers_to_remove:
		graph.remove_slot(cell)


static func _grid_bfs_distances(graph: RoomGraph, start_id: String) -> Dictionary:
	var distances := {}
	var start := graph.get_slot(start_id)
	if start == null:
		return distances
	var queue: Array[String] = [start_id]
	distances[start_id] = 0
	while not queue.is_empty():
		var current_id: String = queue.pop_front()
		var current := graph.get_slot(current_id)
		for dir in DIRECTIONS:
			var neighbor_cell: Vector2i = current.grid_pos + dir
			if not graph.slots.has(neighbor_cell):
				continue
			var neighbor: RoomGraphSlot = graph.get_slot_at(neighbor_cell)
			if neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			if distances.has(neighbor.slot_id):
				continue
			distances[neighbor.slot_id] = int(distances[current_id]) + 1
			queue.append(neighbor.slot_id)
	return distances


static func _apply_door_connections(
	graph: RoomGraph, rng: RandomNumberGenerator, config: RoomGraphConfig
) -> void:
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		slot.door_mask = 0
	for edge in graph.walk_edges:
		_set_door_between(graph, edge["a"], edge["b"])
	graph.loop_edges.clear()
	if rng == null or config == null or config.loop_budget <= 0:
		return
	_open_shortcut_loops(graph, rng, config, config.loop_min_detour)
	if graph.loop_edges.size() < config.loop_budget:
		_open_shortcut_loops(graph, rng, config, config.loop_fallback_detour)


static func _open_shortcut_loops(
	graph: RoomGraph, rng: RandomNumberGenerator, config: RoomGraphConfig, min_detour: int
) -> void:
	while graph.loop_edges.size() < config.loop_budget:
		var distances := _door_bfs_cell_distances(graph)
		var best: Array = []
		var origin_distances := {}
		var best_detour := min_detour
		var seen := {}
		for cell in graph.occupied_cells():
			var slot: RoomGraphSlot = graph.slots[cell]
			if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			for dir in DIRECTIONS:
				var neighbor_cell: Vector2i = cell + dir
				if not graph.slots.has(neighbor_cell):
					continue
				var neighbor: RoomGraphSlot = graph.slots[neighbor_cell]
				if neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET:
					continue
				if slot.door_mask & RoomGraphGeometry.dir_to_door(dir):
					continue
				if slot.connection_count() <= 1 or neighbor.connection_count() <= 1:
					continue
				var key := _edge_key(cell, neighbor_cell)
				if seen.has(key):
					continue
				seen[key] = true
				if not distances.has(cell) or not distances.has(neighbor_cell):
					continue
				if absi(slot.height_level - neighbor.height_level) > 1:
					continue
				if not origin_distances.has(cell):
					origin_distances[cell] = _door_bfs_from_cell(graph, cell)
				var from_cell: Dictionary = origin_distances[cell]
				if not from_cell.has(neighbor_cell):
					continue
				var detour: int = int(from_cell[neighbor_cell])
				if detour < best_detour:
					continue
				if detour > best_detour:
					best_detour = detour
					best.clear()
				best.append([cell, neighbor_cell])
		if best.is_empty():
			return
		var pair: Array = best[rng.randi_range(0, best.size() - 1)]
		_set_door_between(graph, pair[0], pair[1])
		graph.loop_edges.append(
			{"key": _edge_key(pair[0], pair[1]), "a": pair[0], "b": pair[1], "detour": best_detour}
		)


static func _door_bfs_from_cell(graph: RoomGraph, origin: Vector2i) -> Dictionary:
	var distances := {}
	if not graph.slots.has(origin):
		return distances
	distances[origin] = 0
	var queue: Array[Vector2i] = [origin]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var slot: RoomGraphSlot = graph.get_slot_at(cell)
		if slot == null:
			continue
		for dir in DIRECTIONS:
			if not (slot.door_mask & RoomGraphGeometry.dir_to_door(dir)):
				continue
			var neighbor_cell: Vector2i = cell + dir
			var neighbor: RoomGraphSlot = graph.get_slot_at(neighbor_cell)
			if neighbor == null or neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			if distances.has(neighbor_cell):
				continue
			distances[neighbor_cell] = int(distances[cell]) + 1
			queue.append(neighbor_cell)
	return distances


static func _door_bfs_cell_distances(graph: RoomGraph) -> Dictionary:
	var distances := {}
	var start := graph.get_slot(graph.start_id)
	if start == null:
		return distances
	distances[start.grid_pos] = 0
	var queue: Array[Vector2i] = [start.grid_pos]
	while not queue.is_empty():
		var cell: Vector2i = queue.pop_front()
		var slot: RoomGraphSlot = graph.get_slot_at(cell)
		if slot == null:
			continue
		for dir in DIRECTIONS:
			if not (slot.door_mask & RoomGraphGeometry.dir_to_door(dir)):
				continue
			var neighbor_cell: Vector2i = cell + dir
			var neighbor: RoomGraphSlot = graph.get_slot_at(neighbor_cell)
			if neighbor == null or neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			if distances.has(neighbor_cell):
				continue
			distances[neighbor_cell] = int(distances[cell]) + 1
			queue.append(neighbor_cell)
	return distances


static func _smooth_height_levels(graph: RoomGraph, config: RoomGraphConfig) -> void:
	if config.max_height_level <= 0:
		for cell in graph.slots:
			var flat_slot: RoomGraphSlot = graph.slots[cell]
			flat_slot.height_level = 0
		return
	for _pass in 8:
		var changed := false
		for cell in graph.occupied_cells():
			var slot: RoomGraphSlot = graph.slots[cell]
			if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			for dir in DIRECTIONS:
				if not (slot.door_mask & RoomGraphGeometry.dir_to_door(dir)):
					continue
				var neighbor: RoomGraphSlot = graph.get_slot_at(cell + dir)
				if neighbor == null or neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET:
					continue
				var gap := neighbor.height_level - slot.height_level
				if gap > 1:
					neighbor.height_level = mini(
						config.max_height_level, slot.height_level + 1
					)
					changed = true
				elif gap < -1:
					neighbor.height_level = maxi(0, slot.height_level - 1)
					changed = true
		if not changed:
			break


static func _record_walk_edge(graph: RoomGraph, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var key := _edge_key(from_cell, to_cell)
	for edge in graph.walk_edges:
		if edge.get("key", "") == key:
			return
	graph.walk_edges.append({"key": key, "a": from_cell, "b": to_cell})


static func _edge_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y < b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


static func _set_door_between(graph: RoomGraph, cell_a: Vector2i, cell_b: Vector2i) -> void:
	var delta := cell_b - cell_a
	if DIR_TO_DOOR.has(delta):
		var slot_a: RoomGraphSlot = graph.slots[cell_a]
		slot_a.door_mask |= DIR_TO_DOOR[delta]
	var reverse := cell_a - cell_b
	if DIR_TO_DOOR.has(reverse):
		var slot_b: RoomGraphSlot = graph.slots[cell_b]
		slot_b.door_mask |= DIR_TO_DOOR[reverse]


static func _assign_special_rooms(
	graph: RoomGraph, rng: RandomNumberGenerator, config: RoomGraphConfig
) -> void:
	var distances := RoomGraphPathsScript.bfs_distances(graph, graph.start_id)
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		slot.graph_distance = int(distances.get(slot.slot_id, 9999))
	var reserved: Dictionary = {}
	var boss_id := _pick_boss_id(graph, distances, config)
	if boss_id != "":
		reserved[boss_id] = "boss"
		graph.boss_id = boss_id
	var stairs_id := _pick_stairs_id(graph, distances, reserved)
	if stairs_id != "":
		reserved[stairs_id] = "stairs"
		graph.stairs_id = stairs_id
	var treasure_id := _pick_treasure_id(graph, distances, reserved)
	if treasure_id != "":
		reserved[treasure_id] = "treasure"
		graph.treasure_id = treasure_id
	if rng.randf() < 0.35:
		var shop_id := _pick_shop_id(graph, distances, reserved, config)
		if shop_id != "":
			reserved[shop_id] = "shop"
			graph.shop_id = shop_id
	var obstacle_id := _pick_obstacle_id(graph, reserved)
	if obstacle_id != "":
		reserved[obstacle_id] = "obstacle"
	for slot_id in reserved:
		var role: String = str(reserved[slot_id])
		var slot := graph.get_slot(slot_id)
		if slot == null:
			continue
		match role:
			"boss":
				slot.slot_type = RoomGraphSlotScript.SlotType.BOSS
			"stairs":
				slot.slot_type = RoomGraphSlotScript.SlotType.STAIRS
			"treasure":
				slot.slot_type = RoomGraphSlotScript.SlotType.TREASURE
			"shop":
				slot.slot_type = RoomGraphSlotScript.SlotType.SHOP
			"obstacle":
				slot.slot_type = RoomGraphSlotScript.SlotType.OBSTACLE


static func _pick_boss_id(
	graph: RoomGraph, distances: Dictionary, config: RoomGraphConfig
) -> String:
	var boss_candidates: Array[String] = []
	for slot_id in distances:
		if slot_id == graph.start_id:
			continue
		if int(distances[slot_id]) >= config.boss_min_distance:
			boss_candidates.append(slot_id)
	if boss_candidates.is_empty():
		for slot_id in distances:
			if slot_id != graph.start_id:
				boss_candidates.append(slot_id)
	boss_candidates.sort_custom(
		func(a: String, b: String) -> bool:
			var sa := graph.get_slot(a)
			var sb := graph.get_slot(b)
			var a_dead := sa != null and sa.connection_count() <= 1
			var b_dead := sb != null and sb.connection_count() <= 1
			if a_dead != b_dead:
				return a_dead
			var da: int = int(distances.get(a, 0))
			var db: int = int(distances.get(b, 0))
			if da == db:
				return sa.connection_count() < sb.connection_count()
			return da > db
	)
	return boss_candidates[0] if not boss_candidates.is_empty() else ""


static func _dead_end_ids(graph: RoomGraph, reserved: Dictionary) -> Array[String]:
	var dead_ends: Array[String] = []
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_id == graph.start_id:
			continue
		if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET or slot.is_filler:
			continue
		if reserved.has(slot.slot_id):
			continue
		if slot.is_dead_end():
			dead_ends.append(slot.slot_id)
	dead_ends.sort()
	return dead_ends


static func _pick_stairs_id(
	graph: RoomGraph, distances: Dictionary, reserved: Dictionary
) -> String:
	var candidates: Array[String] = []
	for slot_id in _dead_end_ids(graph, reserved):
		if int(distances.get(slot_id, 0)) >= 2:
			candidates.append(slot_id)
	candidates.sort_custom(
		func(a: String, b: String) -> bool:
			return int(distances.get(a, 9999)) < int(distances.get(b, 9999))
	)
	if not candidates.is_empty():
		return candidates[0]
	var start := graph.get_slot(graph.start_id)
	var south_cell: Vector2i = start.grid_pos + DIR_SOUTH
	if graph.slots.has(south_cell):
		var south_slot: RoomGraphSlot = graph.get_slot_at(south_cell)
		if not reserved.has(south_slot.slot_id):
			return south_slot.slot_id
	for dir in DIRECTIONS:
		var neighbor_cell: Vector2i = start.grid_pos + dir
		if not graph.slots.has(neighbor_cell):
			continue
		var neighbor: RoomGraphSlot = graph.get_slot_at(neighbor_cell)
		if not reserved.has(neighbor.slot_id):
			return neighbor.slot_id
	return ""


static func _pick_treasure_id(
	graph: RoomGraph, distances: Dictionary, reserved: Dictionary
) -> String:
	var candidates := _dead_end_ids(graph, reserved)
	if candidates.is_empty():
		candidates = _unreserved_slot_ids(graph, reserved)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(
		func(a: String, b: String) -> bool:
			return int(distances.get(a, 0)) > int(distances.get(b, 0))
	)
	return candidates[0]


static func _unreserved_slot_ids(graph: RoomGraph, reserved: Dictionary) -> Array[String]:
	var ids: Array[String] = []
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_id == graph.start_id:
			continue
		if slot.is_filler or slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
			continue
		if reserved.has(slot.slot_id):
			continue
		ids.append(slot.slot_id)
	ids.sort()
	return ids


static func _pick_shop_id(
	graph: RoomGraph, distances: Dictionary, reserved: Dictionary, _config: RoomGraphConfig
) -> String:
	var boss_distance := int(distances.get(graph.boss_id, 0))
	var candidates: Array[String] = []
	for slot_id in _dead_end_ids(graph, reserved):
		var door_distance: int = int(distances.get(slot_id, 0))
		if door_distance >= 2 and door_distance <= boss_distance - 2:
			candidates.append(slot_id)
	if candidates.is_empty():
		return ""
	candidates.sort()
	return candidates[0]


static func _pick_obstacle_id(graph: RoomGraph, reserved: Dictionary) -> String:
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.get_slot_at(cell)
		if slot == null or reserved.has(slot.slot_id):
			continue
		# Every sibling picker (`_pick_boss_id`, `_dead_end_ids` behind stairs/treasure/shop)
		# excludes the entrance explicitly; this one did not. `_assign_special_rooms` reassigns
		# whatever slot this returns to `SlotType.OBSTACLE`, and when it landed on `graph.start_id`
		# -- which it could, since the entrance is on the critical path and sometimes has exactly
		# two doors -- the entrance silently stopped being an entrance. Nothing downstream re-checks
		# that `graph.start_id` still points at a `START` slot, so the floor built anyway, just
		# without one: `ProcgenPlacements.place()` looks up the entrance by type ("hub") to seat the
		# player and never finds it, and the whole floor generation attempt fails.
		if slot.slot_id == graph.start_id:
			continue
		if not slot.on_critical_path:
			continue
		if slot.connection_count() == 2:
			return slot.slot_id
	return ""


static func _place_secret_attachments(
	graph: RoomGraph, rng: RandomNumberGenerator, config: RoomGraphConfig
) -> void:
	var next_index := graph.slots.size()
	var candidates: Array[Vector2i] = []
	for x in config.grid_width:
		for y in config.grid_height:
			var cell := Vector2i(x, y)
			if graph.slots.has(cell):
				continue
			if _occupied_neighbor_count(graph, cell) < 2:
				continue
			candidates.append(cell)
	candidates.sort_custom(
		func(a: Vector2i, b: Vector2i) -> bool:
			if a.x == b.x:
				return a.y < b.y
			return a.x < b.x
	)
	# A secret normally wants a well-connected pocket, but a cramped floor can offer none at all.
	# Rather than ship a floor with nothing hidden on it, fall back to any empty cell that touches
	# the floor at all -- `min_secrets` is a promise to the player, not a preference.
	if candidates.size() < config.min_secrets:
		for x in config.grid_width:
			for y in config.grid_height:
				var relaxed := Vector2i(x, y)
				if graph.slots.has(relaxed) or candidates.has(relaxed):
					continue
				if _occupied_neighbor_count(graph, relaxed) < 1:
					continue
				candidates.append(relaxed)
	# One or two, chosen per floor rather than always taking the cap -- a floor that always hides
	# exactly the same number of rooms stops being a question the player asks themselves.
	var wanted := config.min_secrets
	if config.max_secrets > config.min_secrets:
		wanted = rng.randi_range(config.min_secrets, config.max_secrets)
	var pick_count := mini(wanted, candidates.size())
	for i in pick_count:
		if candidates.is_empty():
			break
		var idx := rng.randi_range(0, candidates.size() - 1)
		var cell: Vector2i = candidates[idx]
		candidates.remove_at(idx)
		var slot := _make_slot(cell, "secret_%d" % next_index, RoomGraphSlotScript.SlotType.SECRET)
		next_index += 1
		var parent_cell := _pick_secret_parent_cell(graph, cell, rng)
		if parent_cell == Vector2i(-99999, -99999):
			continue
		var parent_slot: RoomGraphSlot = graph.get_slot_at(parent_cell)
		slot.secret_parent_id = parent_slot.slot_id
		slot.height_level = parent_slot.height_level
		slot.secret_mechanism = "hidden_lever" if rng.randf() < 0.5 else "illusory_wall"
		graph.add_slot(cell, slot)
		graph.secret_ids.append(slot.slot_id)


static func _pick_secret_parent_cell(
	graph: RoomGraph, secret_cell: Vector2i, rng: RandomNumberGenerator
) -> Vector2i:
	var neighbors: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var cell := secret_cell + dir
		if graph.slots.has(cell):
			var slot: RoomGraphSlot = graph.get_slot_at(cell)
			if slot.slot_type != RoomGraphSlotScript.SlotType.SECRET:
				neighbors.append(cell)
	if neighbors.is_empty():
		return Vector2i(-99999, -99999)
	return neighbors[rng.randi_range(0, neighbors.size() - 1)]


static func _fill_bounding_box(
	graph: RoomGraph, next_index: int, target_rooms: int = 0
) -> int:
	var min_cell := Vector2i(999999, 999999)
	var max_cell := Vector2i(-999999, -999999)
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
			continue
		min_cell.x = mini(min_cell.x, cell.x)
		min_cell.y = mini(min_cell.y, cell.y)
		max_cell.x = maxi(max_cell.x, cell.x)
		max_cell.y = maxi(max_cell.y, cell.y)
	if min_cell.x > max_cell.x:
		return next_index
	for x in range(min_cell.x, max_cell.x + 1):
		for y in range(min_cell.y, max_cell.y + 1):
			var cell := Vector2i(x, y)
			if graph.slots.has(cell):
				continue
			var slot := _make_slot(
				cell, "room_%d" % next_index, RoomGraphSlotScript.SlotType.NORMAL
			)
			slot.is_filler = true
			graph.add_slot(cell, slot)
			next_index += 1
			if target_rooms > 0 and graph.main_slot_count() >= target_rooms:
				return next_index
	return next_index


static func _validate_graph(
	graph: RoomGraph, config: RoomGraphConfig, require_loops: bool = true
) -> Dictionary:
	var main_count := graph.main_slot_count()
	if main_count < config.min_rooms:
		_last_validate_reason = "Room count %d below minimum %d" % [main_count, config.min_rooms]
		return {"ok": false, "reason": _last_validate_reason}
	var component := RoomGraphPathsScript.connected_component(graph, graph.start_id)
	if component.size() != main_count:
		_last_validate_reason = (
			"Door-disconnected component size %d != main slot count %d"
			% [component.size(), main_count]
		)
		return {"ok": false, "reason": _last_validate_reason}
	if graph.boss_id == "":
		_last_validate_reason = "Boss room not assigned"
		return {"ok": false, "reason": _last_validate_reason}
	if graph.stairs_id == "":
		_last_validate_reason = "Stairs room not assigned"
		return {"ok": false, "reason": _last_validate_reason}
	if graph.treasure_id == "":
		_last_validate_reason = "Treasure room not assigned"
		return {"ok": false, "reason": _last_validate_reason}
	var distances := RoomGraphPathsScript.bfs_distances(graph, graph.start_id)
	if int(distances.get(graph.boss_id, 0)) < config.boss_min_distance:
		_last_validate_reason = (
			"Boss too close to start (%d < %d)"
			% [distances.get(graph.boss_id, 0), config.boss_min_distance]
		)
		return {"ok": false, "reason": _last_validate_reason}
	var dead_ends := 0
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET or slot.is_filler:
			continue
		if slot.is_dead_end():
			dead_ends += 1
	if dead_ends < config.min_dead_ends:
		_last_validate_reason = "Not enough dead ends (%d < %d)" % [dead_ends, config.min_dead_ends]
		return {"ok": false, "reason": _last_validate_reason}
	if require_loops and config.loop_budget > 0 and graph.loop_edges.size() < config.min_loops:
		_last_validate_reason = (
			"Not enough shortcut loops (%d < %d)" % [graph.loop_edges.size(), config.min_loops]
		)
		return {"ok": false, "reason": _last_validate_reason}
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.connection_count() < 1:
			_last_validate_reason = "Sealed room '%s' has no doors" % slot.slot_id
			return {"ok": false, "reason": _last_validate_reason}
	if config.max_height_level > 0:
		for cell in graph.slots:
			var slot: RoomGraphSlot = graph.slots[cell]
			if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			for dir in DIRECTIONS:
				if not (slot.door_mask & RoomGraphGeometry.dir_to_door(dir)):
					continue
				var neighbor: RoomGraphSlot = graph.get_slot_at(cell + dir)
				if neighbor == null or neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET:
					continue
				if absi(slot.height_level - neighbor.height_level) > 1:
					_last_validate_reason = (
						"Height gap > 1 between '%s' and '%s'"
						% [slot.slot_id, neighbor.slot_id]
					)
					return {"ok": false, "reason": _last_validate_reason}
	if not config.allow_2x2_blocks:
		for cell in graph.slots:
			var slot: RoomGraphSlot = graph.slots[cell]
			if slot.is_filler or slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
				continue
			if _creates_2x2_block(graph, cell):
				_last_validate_reason = "2x2 block detected at %s" % str(cell)
				return {"ok": false, "reason": _last_validate_reason}
	_last_validate_reason = ""
	return {"ok": true}


static func _apply_secret_door_masks(graph: RoomGraph) -> void:
	for secret_id in graph.secret_ids:
		var secret_slot := graph.get_slot(secret_id)
		if secret_slot == null or secret_slot.secret_parent_id == "":
			continue
		var parent := graph.get_slot(secret_slot.secret_parent_id)
		if parent == null:
			continue
		var to_parent := parent.grid_pos - secret_slot.grid_pos
		if DIR_TO_DOOR.has(to_parent):
			secret_slot.door_mask |= DIR_TO_DOOR[to_parent]
		var to_secret := secret_slot.grid_pos - parent.grid_pos
		if DIR_TO_DOOR.has(to_secret):
			parent.door_mask |= DIR_TO_DOOR[to_secret]


static func _shuffle_dirs(dirs: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(dirs.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp
