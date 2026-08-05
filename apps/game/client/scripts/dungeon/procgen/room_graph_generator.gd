class_name RoomGraphGenerator
extends RefCounted

## Phase 1 — Isaac-style grid room graph with backtracking walk, bbox fill, and validation.

const RoomGraphSlotScript := preload("res://scripts/dungeon/procgen/room_graph_slot.gd")
const RoomGraphScript := preload("res://scripts/dungeon/procgen/room_graph.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphDebugScript := preload("res://scripts/dungeon/procgen/room_graph_debug.gd")

const DIR_NORTH := Vector2i(0, -1)
const DIR_EAST := Vector2i(1, 0)
const DIR_SOUTH := Vector2i(0, 1)
const DIR_WEST := Vector2i(-1, 0)
const DIRECTIONS: Array[Vector2i] = [DIR_NORTH, DIR_EAST, DIR_SOUTH, DIR_WEST]

const OPPOSITE := {
	RoomGraphSlotScript.DOOR_NORTH: RoomGraphSlotScript.DOOR_SOUTH,
	RoomGraphSlotScript.DOOR_EAST: RoomGraphSlotScript.DOOR_WEST,
	RoomGraphSlotScript.DOOR_SOUTH: RoomGraphSlotScript.DOOR_NORTH,
	RoomGraphSlotScript.DOOR_WEST: RoomGraphSlotScript.DOOR_EAST,
}

const DIR_TO_DOOR := {
	Vector2i(0, -1): RoomGraphSlotScript.DOOR_NORTH,
	Vector2i(1, 0): RoomGraphSlotScript.DOOR_EAST,
	Vector2i(0, 1): RoomGraphSlotScript.DOOR_SOUTH,
	Vector2i(-1, 0): RoomGraphSlotScript.DOOR_WEST,
}

static var _last_validate_reason := ""


static func generate(config: RoomGraphConfig, run_seed: int) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = run_seed
	for attempt in config.max_generation_attempts:
		var graph := _try_generate_once(config, rng)
		if graph != null:
			if config.debug_ascii:
				RoomGraphDebugScript.print_graph(graph)
			return {"ok": true, "graph": graph}
		rng.seed = run_seed + (attempt + 1) * 1_000_003
	var fallback_rng := RandomNumberGenerator.new()
	fallback_rng.seed = run_seed ^ 0xFA11BAC
	var fallback := _build_fallback_graph(config, fallback_rng)
	if config.debug_ascii:
		RoomGraphDebugScript.print_graph(fallback)
	return {"ok": true, "graph": fallback, "used_fallback": true}


static func _try_generate_once(config: RoomGraphConfig, rng: RandomNumberGenerator) -> RoomGraph:
	var graph := RoomGraphScript.new()
	graph.config = config
	var target_rooms := rng.randi_range(config.min_rooms, config.max_rooms)
	var center := config.grid_center()
	var start := _make_slot(center, "room_0", RoomGraphSlotScript.SlotType.START)
	start.on_critical_path = true
	graph.slots[center] = start
	graph.start_id = start.slot_id
	var path_target := maxi(config.boss_min_distance, int(target_rooms / 3.0))
	var path_result := _grow_critical_path(graph, center, path_target, config, rng)
	var next_index: int = path_result["next_index"]
	var path_cells: Array = path_result["path_cells"]
	next_index = _grow_branches(graph, path_cells, next_index, target_rooms, config, rng)
	if _count_main_slots(graph) < config.min_rooms:
		var all_cells: Array = []
		all_cells.assign(graph.occupied_cells())
		next_index = _grow_branches(
			graph,
			all_cells,
			next_index,
			config.min_rooms,
			config,
			rng
		)
	_assign_special_rooms(graph, rng, config)
	if config.fill_bounding_box and _count_main_slots(graph) < config.min_rooms:
		next_index = _fill_bounding_box(graph, next_index)
	_apply_door_connections(graph, rng, config)
	if not _validate_graph(graph, config).get("ok", false):
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
				target_cell,
				"room_%d" % next_index,
				RoomGraphSlotScript.SlotType.NORMAL
			)
			slot.on_critical_path = true
			slot.height_level = graph.slots[cursor].height_level
			graph.slots[target_cell] = slot
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
				var parent_slot: RoomGraphSlot = graph.slots[cell]
				var slot := _make_slot(
					target_cell,
					"room_%d" % next_index,
					RoomGraphSlotScript.SlotType.NORMAL
				)
				slot.height_level = parent_slot.height_level
				graph.slots[target_cell] = slot
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


static func _make_slot(cell: Vector2i, slot_id: String, slot_type: RoomGraphSlot.SlotType) -> RoomGraphSlot:
	var slot := RoomGraphSlotScript.new()
	slot.grid_pos = cell
	slot.slot_id = slot_id
	slot.slot_type = slot_type
	return slot


static func _pick_random_cell(graph: RoomGraph, rng: RandomNumberGenerator) -> Vector2i:
	var cells := graph.occupied_cells()
	return cells[rng.randi_range(0, cells.size() - 1)]


static func _in_bounds(cell: Vector2i, config: RoomGraphConfig) -> bool:
	return cell.x >= 0 and cell.y >= 0 and cell.x < config.grid_width and cell.y < config.grid_height


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
			var block := true
			for bx in 2:
				for by in 2:
					var check_cell := anchor + Vector2i(bx, by)
					if not graph.slots.has(check_cell):
						block = false
						break
					var check_slot: RoomGraphSlot = graph.slots[check_cell]
					if check_slot.is_filler or check_slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
						block = false
						break
				if not block:
					break
			if block:
				return true
	return false


static func _recompute_connections(graph: RoomGraph) -> void:
	_apply_door_connections(graph, null, graph.config)


static func _apply_door_connections(
	graph: RoomGraph,
	rng: RandomNumberGenerator,
	config: RoomGraphConfig
) -> void:
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		slot.door_mask = 0
	for edge in graph.walk_edges:
		_set_door_between(graph, edge["a"], edge["b"])
	var loop_candidates: Array = []
	var seen_loops := {}
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET or slot.is_filler:
			continue
		for dir in DIRECTIONS:
			var neighbor_cell: Vector2i = cell + dir
			if not graph.slots.has(neighbor_cell):
				continue
			var neighbor: RoomGraphSlot = graph.slots[neighbor_cell]
			if neighbor.slot_type == RoomGraphSlotScript.SlotType.SECRET or neighbor.is_filler:
				continue
			if _has_walk_edge(graph, cell, neighbor_cell):
				continue
			var key := _edge_key(cell, neighbor_cell)
			if seen_loops.has(key):
				continue
			seen_loops[key] = true
			loop_candidates.append([cell, neighbor_cell])
	if rng != null and config != null and loop_candidates.size() > 0:
		_shuffle_pairs(loop_candidates, rng)
		var budget := mini(config.loop_budget, loop_candidates.size())
		for i in budget:
			var pair: Array = loop_candidates[i]
			_set_door_between(graph, pair[0], pair[1])
	_apply_secret_door_masks(graph)


static func _record_walk_edge(graph: RoomGraph, from_cell: Vector2i, to_cell: Vector2i) -> void:
	var key := _edge_key(from_cell, to_cell)
	for edge in graph.walk_edges:
		if edge.get("key", "") == key:
			return
	graph.walk_edges.append({"key": key, "a": from_cell, "b": to_cell})


static func _has_walk_edge(graph: RoomGraph, a: Vector2i, b: Vector2i) -> bool:
	var key := _edge_key(a, b)
	for edge in graph.walk_edges:
		if edge.get("key", "") == key:
			return true
	return false


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


static func _shuffle_pairs(pairs: Array, rng: RandomNumberGenerator) -> void:
	for i in range(pairs.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp = pairs[i]
		pairs[i] = pairs[j]
		pairs[j] = tmp


static func _compute_distances(graph: RoomGraph, start_id: String) -> Dictionary:
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
			var neighbor: RoomGraphSlot = graph.slots[neighbor_cell]
			if distances.has(neighbor.slot_id):
				continue
			distances[neighbor.slot_id] = int(distances[current_id]) + 1
			queue.append(neighbor.slot_id)
	return distances


static func _assign_special_rooms(graph: RoomGraph, rng: RandomNumberGenerator, config: RoomGraphConfig) -> void:
	var distances := _compute_distances(graph, graph.start_id)
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		slot.graph_distance = int(distances.get(slot.slot_id, 9999))
	var dead_ends: Array[String] = []
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_id == graph.start_id:
			continue
		if slot.is_dead_end():
			dead_ends.append(slot.slot_id)
	dead_ends.sort()
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
	boss_candidates.sort_custom(func(a: String, b: String) -> bool:
		var da: int = int(distances.get(a, 0))
		var db: int = int(distances.get(b, 0))
		if da == db:
			var sa := graph.get_slot(a)
			var sb := graph.get_slot(b)
			return sa.connection_count() < sb.connection_count()
		return da > db
	)
	if boss_candidates.is_empty():
		return
	graph.boss_id = boss_candidates[0]
	graph.get_slot(graph.boss_id).slot_type = RoomGraphSlotScript.SlotType.BOSS
	var remaining_dead_ends: Array[String] = []
	for slot_id in dead_ends:
		if slot_id != graph.boss_id:
			remaining_dead_ends.append(slot_id)
	remaining_dead_ends.sort()
	if not remaining_dead_ends.is_empty():
		graph.treasure_id = remaining_dead_ends[rng.randi_range(0, remaining_dead_ends.size() - 1)]
		graph.get_slot(graph.treasure_id).slot_type = RoomGraphSlotScript.SlotType.TREASURE
	var start := graph.get_slot(graph.start_id)
	var south_cell: Vector2i = start.grid_pos + DIR_SOUTH
	if graph.slots.has(south_cell):
		graph.stairs_id = graph.slots[south_cell].slot_id
		graph.get_slot(graph.stairs_id).slot_type = RoomGraphSlotScript.SlotType.STAIRS
	else:
		for dir in DIRECTIONS:
			var neighbor_cell: Vector2i = start.grid_pos + dir
			if graph.slots.has(neighbor_cell):
				graph.stairs_id = graph.slots[neighbor_cell].slot_id
				graph.get_slot(graph.stairs_id).slot_type = RoomGraphSlotScript.SlotType.STAIRS
				break
	_place_secret_attachments(graph, rng, config)


static func _place_secret_attachments(graph: RoomGraph, rng: RandomNumberGenerator, config: RoomGraphConfig) -> void:
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
	candidates.sort_custom(func(a: Vector2i, b: Vector2i) -> bool:
		if a.x == b.x:
			return a.y < b.y
		return a.x < b.x
	)
	var pick_count := mini(config.max_secrets, candidates.size())
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
		slot.secret_parent_id = graph.slots[parent_cell].slot_id
		slot.secret_mechanism = "hidden_lever" if rng.randf() < 0.5 else "illusory_wall"
		graph.slots[cell] = slot
		graph.secret_ids.append(slot.slot_id)
	_apply_secret_door_masks(graph)


static func _pick_secret_parent_cell(graph: RoomGraph, secret_cell: Vector2i, rng: RandomNumberGenerator) -> Vector2i:
	var neighbors: Array[Vector2i] = []
	for dir in DIRECTIONS:
		var cell := secret_cell + dir
		if graph.slots.has(cell):
			var slot: RoomGraphSlot = graph.slots[cell]
			if slot.slot_type != RoomGraphSlotScript.SlotType.SECRET:
				neighbors.append(cell)
	if neighbors.is_empty():
		return Vector2i(-99999, -99999)
	return neighbors[rng.randi_range(0, neighbors.size() - 1)]


static func _fill_bounding_box(graph: RoomGraph, next_index: int) -> int:
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
			var slot := _make_slot(cell, "room_%d" % next_index, RoomGraphSlotScript.SlotType.NORMAL)
			slot.is_filler = true
			graph.slots[cell] = slot
			next_index += 1
	return next_index


static func _validate_graph(graph: RoomGraph, config: RoomGraphConfig) -> Dictionary:
	var main_count := 0
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type != RoomGraphSlotScript.SlotType.SECRET:
			main_count += 1
	if main_count < config.min_rooms:
		_last_validate_reason = "Room count %d below minimum %d" % [main_count, config.min_rooms]
		return {
			"ok": false,
			"reason": _last_validate_reason,
		}
	var distances := _compute_distances(graph, graph.start_id)
	for slot_id in graph.occupied_ids():
		if slot_id.begins_with("secret_"):
			continue
		if not distances.has(slot_id):
			_last_validate_reason = "Unreachable room '%s' from start" % slot_id
			return {"ok": false, "reason": _last_validate_reason}
	if graph.boss_id == "":
		_last_validate_reason = "Boss room not assigned"
		return {"ok": false, "reason": _last_validate_reason}
	if int(distances.get(graph.boss_id, 0)) < config.boss_min_distance:
		_last_validate_reason = "Boss too close to start (%d < %d)" % [distances.get(graph.boss_id, 0), config.boss_min_distance]
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


static func _count_main_slots(graph: RoomGraph) -> int:
	var count := 0
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type != RoomGraphSlotScript.SlotType.SECRET:
			count += 1
	return count


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


static func _build_fallback_graph(config: RoomGraphConfig, rng: RandomNumberGenerator) -> RoomGraph:
	var graph := RoomGraphScript.new()
	graph.config = config
	var center := config.grid_center()
	var chain: Array[Vector2i] = [center]
	var cursor := center
	var turn_dirs := DIRECTIONS.duplicate()
	_shuffle_dirs(turn_dirs, rng)
	var direction: Vector2i = turn_dirs[0]
	var leg_length := 0
	var max_leg := rng.randi_range(3, maxi(3, int(config.grid_width / 3.0)))
	var turn_index := 1
	while chain.size() < config.min_rooms:
		var next: Vector2i = cursor + direction
		if not _in_bounds(next, config) or next in chain:
			direction = turn_dirs[turn_index % turn_dirs.size()]
			turn_index += 1
			leg_length = 0
			max_leg = rng.randi_range(3, maxi(3, int(config.grid_width / 3.0)))
			next = cursor + direction
			if not _in_bounds(next, config) or next in chain:
				break
		chain.append(next)
		cursor = next
		leg_length += 1
		if leg_length >= max_leg:
			direction = turn_dirs[turn_index % turn_dirs.size()]
			turn_index += 1
			leg_length = 0
			max_leg = rng.randi_range(3, maxi(3, int(config.grid_width / 3.0)))
	for i in chain.size():
		var cell := chain[i]
		var slot_type := RoomGraphSlotScript.SlotType.NORMAL
		if i == 0:
			slot_type = RoomGraphSlotScript.SlotType.START
		elif i == 1:
			slot_type = RoomGraphSlotScript.SlotType.STAIRS
		elif i == chain.size() - 1:
			slot_type = RoomGraphSlotScript.SlotType.BOSS
		elif i == mini(3, chain.size() - 1):
			slot_type = RoomGraphSlotScript.SlotType.TREASURE
		var slot := _make_slot(cell, "room_%d" % i, slot_type)
		slot.on_critical_path = true
		graph.slots[cell] = slot
		if i > 0:
			_record_walk_edge(graph, chain[i - 1], cell)
	graph.start_id = "room_0"
	graph.stairs_id = "room_1"
	graph.treasure_id = "room_%d" % mini(3, chain.size() - 1)
	graph.boss_id = "room_%d" % (chain.size() - 1)
	_apply_door_connections(graph, rng, config)
	if config.fill_bounding_box:
		_fill_bounding_box(graph, chain.size())
		_apply_door_connections(graph, rng, config)
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		slot.graph_distance = int(_compute_distances(graph, graph.start_id).get(slot.slot_id, 0))
	return graph


static func _shuffle_dirs(dirs: Array[Vector2i], rng: RandomNumberGenerator) -> void:
	for i in range(dirs.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp := dirs[i]
		dirs[i] = dirs[j]
		dirs[j] = tmp
