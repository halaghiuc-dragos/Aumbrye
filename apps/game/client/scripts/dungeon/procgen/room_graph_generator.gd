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
	var fallback := _build_fallback_graph(config)
	if config.debug_ascii:
		RoomGraphDebugScript.print_graph(fallback)
	return {"ok": true, "graph": fallback, "used_fallback": true}


static func _try_generate_once(config: RoomGraphConfig, rng: RandomNumberGenerator) -> RoomGraph:
	var graph := RoomGraphScript.new()
	graph.config = config
	var target_rooms := rng.randi_range(config.min_rooms, config.max_rooms)
	var center := config.grid_center()
	var start := _make_slot(center, "room_0", RoomGraphSlotScript.SlotType.START)
	graph.slots[center] = start
	graph.start_id = start.slot_id
	var next_index := 1
	var walk_attempts := 0
	while graph.slots.size() < target_rooms and walk_attempts < config.max_walk_attempts:
		walk_attempts += 1
		var origin_cell := _pick_random_cell(graph, rng)
		var origin: RoomGraphSlot = graph.slots[origin_cell]
		var distances := _compute_distances(graph, graph.start_id)
		var origin_dist := int(distances.get(origin.slot_id, 0))
		var continue_chance := config.continue_probability_base * exp(-config.continue_decay_rate * float(origin_dist))
		if rng.randf() > continue_chance:
			continue
		var dirs := DIRECTIONS.duplicate()
		_shuffle_dirs(dirs, rng)
		var placed := false
		for dir in dirs:
			var target_cell: Vector2i = origin_cell + dir
			if not _in_bounds(target_cell, config):
				continue
			if graph.slots.has(target_cell):
				continue
			if _occupied_neighbor_count(graph, target_cell) >= config.max_neighbor_count:
				continue
			if not config.allow_2x2_blocks and _creates_2x2_block(graph, target_cell):
				continue
			var slot := _make_slot(
				target_cell,
				"room_%d" % next_index,
				RoomGraphSlotScript.SlotType.NORMAL
			)
			next_index += 1
			graph.slots[target_cell] = slot
			placed = true
			break
		if not placed:
			continue
	_recompute_connections(graph)
	_assign_special_rooms(graph, rng, config)
	if config.fill_bounding_box:
		next_index = _fill_bounding_box(graph, next_index)
		_recompute_connections(graph)
	if not _validate_graph(graph, config).get("ok", false):
		return null
	return graph


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
					if not graph.slots.has(anchor + Vector2i(bx, by)):
						block = false
						break
				if not block:
					break
			if block:
				return true
	return false


static func _recompute_connections(graph: RoomGraph) -> void:
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		slot.door_mask = 0
	for cell in graph.slots:
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
			slot.door_mask |= DIR_TO_DOOR[dir]


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
	for dir in DIRECTIONS:
		var neighbor_cell: Vector2i = start.grid_pos + dir
		if graph.slots.has(neighbor_cell):
			graph.stairs_id = graph.slots[neighbor_cell].slot_id
			graph.get_slot(graph.stairs_id).slot_type = RoomGraphSlotScript.SlotType.STAIRS
			break
	for slot_id in graph.occupied_ids():
		if slot_id in [graph.start_id, graph.boss_id, graph.treasure_id, graph.stairs_id]:
			continue
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
		graph.slots[cell] = slot
		graph.secret_ids.append(slot.slot_id)
	_recompute_connections(graph)


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
		return {
			"ok": false,
			"reason": "Room count %d below minimum %d" % [main_count, config.min_rooms],
		}
	var distances := _compute_distances(graph, graph.start_id)
	for slot_id in graph.occupied_ids():
		if slot_id.begins_with("secret_"):
			continue
		if not distances.has(slot_id):
			return {"ok": false, "reason": "Unreachable room '%s' from start" % slot_id}
	if graph.boss_id == "":
		return {"ok": false, "reason": "Boss room not assigned"}
	if int(distances.get(graph.boss_id, 0)) < config.boss_min_distance:
		return {"ok": false, "reason": "Boss too close to start (%d < %d)" % [distances.get(graph.boss_id, 0), config.boss_min_distance]}
	var dead_ends := 0
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlotScript.SlotType.SECRET:
			continue
		if slot.is_dead_end():
			dead_ends += 1
	if dead_ends < config.min_dead_ends:
		return {"ok": false, "reason": "Not enough dead ends (%d < %d)" % [dead_ends, config.min_dead_ends]}
	if not config.allow_2x2_blocks:
		for cell in graph.slots:
			if _creates_2x2_block(graph, cell):
				return {"ok": false, "reason": "2x2 block detected at %s" % str(cell)}
	return {"ok": true}


static func _build_fallback_graph(config: RoomGraphConfig) -> RoomGraph:
	var graph := RoomGraphScript.new()
	graph.config = config
	var center := config.grid_center()
	var chain: Array[Vector2i] = [center]
	var cursor := center
	var direction := DIR_SOUTH
	var leg_length := 0
	var max_leg := maxi(3, int(config.grid_width / 3.0))
	while chain.size() < config.min_rooms:
		var next := cursor + direction
		if not _in_bounds(next, config) or next in chain:
			direction = DIR_EAST if direction == DIR_SOUTH else DIR_SOUTH
			leg_length = 0
			next = cursor + direction
			if not _in_bounds(next, config) or next in chain:
				break
		chain.append(next)
		cursor = next
		leg_length += 1
		if leg_length >= max_leg:
			direction = DIR_EAST if direction == DIR_SOUTH else DIR_SOUTH
			leg_length = 0
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
		graph.slots[cell] = slot
	graph.start_id = "room_0"
	graph.stairs_id = "room_1"
	graph.treasure_id = "room_%d" % mini(3, chain.size() - 1)
	graph.boss_id = "room_%d" % (chain.size() - 1)
	_recompute_connections(graph)
	if config.fill_bounding_box:
		_fill_bounding_box(graph, chain.size())
		_recompute_connections(graph)
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
