class_name RoomGraphPaths
extends RefCounted

## Graph path utilities for critical-path and branch analysis.


## C-209: every helper here rebuilt the adjacency map from scratch — `branch_depth_for_slot` did it
## three times per call, and `room_content_assigner` calls it once per candidate room while placing
## a key. On a 30-room floor that was ~100 full rebuilds and ~100 BFS passes to place one key.
## Memoised against the graph instance; `RoomGraph` is rebuilt per generation attempt, so a stale
## entry cannot outlive its graph.
static var _adj_cache_graph: RoomGraph = null
static var _adj_cache: Dictionary = {}
static var _dist_cache_graph: RoomGraph = null
static var _dist_cache: Dictionary = {}


static func build_adjacency(graph: RoomGraph) -> Dictionary:
	if graph == _adj_cache_graph and not _adj_cache.is_empty():
		return _adj_cache
	var adj := {}
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlot.SlotType.SECRET:
			continue
		adj[slot.slot_id] = []
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlot.SlotType.SECRET:
			continue
		for dir in _dirs():
			if not (slot.door_mask & _door_for_dir(dir)):
				continue
			var neighbor: RoomGraphSlot = graph.slots.get(cell + dir) as RoomGraphSlot
			if neighbor == null or neighbor.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			adj[slot.slot_id].append(neighbor.slot_id)
	_adj_cache_graph = graph
	_adj_cache = adj
	return adj


static func connected_component(graph: RoomGraph, start_id: String) -> Dictionary:
	var adj := build_adjacency(graph)
	var component := {start_id: true}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in adj.get(current, []):
			if component.has(next_id):
				continue
			component[next_id] = true
			queue.append(next_id)
	return component


static func bfs_distances(graph: RoomGraph, start_id: String) -> Dictionary:
	if graph == _dist_cache_graph and _dist_cache.has(start_id):
		return _dist_cache[start_id]
	var adj := build_adjacency(graph)
	var distances := {start_id: 0}
	var queue: Array[String] = [start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in adj.get(current, []):
			if distances.has(next_id):
				continue
			distances[next_id] = int(distances[current]) + 1
			queue.append(next_id)
	if graph != _dist_cache_graph:
		_dist_cache_graph = graph
		_dist_cache = {}
	_dist_cache[start_id] = distances
	return distances


static func critical_path_ids(graph: RoomGraph) -> Array[String]:
	if graph.start_id == "" or graph.boss_id == "":
		return []
	var distances := bfs_distances(graph, graph.start_id)
	if not distances.has(graph.boss_id):
		return []
	var adj := build_adjacency(graph)
	var path: Array[String] = []
	var current := graph.boss_id
	while current != "":
		path.append(current)
		if current == graph.start_id:
			break
		var current_dist: int = int(distances.get(current, 0))
		var best := ""
		var best_dist := current_dist
		for neighbor_id in adj.get(current, []):
			var nd: int = int(distances.get(neighbor_id, 9999))
			if nd < best_dist:
				best_dist = nd
				best = neighbor_id
		current = best
	path.reverse()
	return path


static func critical_edges(path_ids: Array[String]) -> Array:
	var edges: Array = []
	for i in range(path_ids.size() - 1):
		edges.append({"from": path_ids[i], "to": path_ids[i + 1]})
	return edges


static func is_on_branch_to(graph: RoomGraph, ancestor_id: String, descendant_id: String) -> bool:
	var distances := bfs_distances(graph, graph.start_id)
	if not distances.has(ancestor_id) or not distances.has(descendant_id):
		return false
	if int(distances[descendant_id]) <= int(distances[ancestor_id]):
		return false
	var adj := build_adjacency(graph)
	var current := descendant_id
	while current != "" and current != ancestor_id:
		var current_dist: int = int(distances.get(current, 0))
		var best := ""
		var best_dist := current_dist
		for neighbor_id in adj.get(current, []):
			var nd: int = int(distances.get(neighbor_id, 9999))
			if nd < best_dist:
				best_dist = nd
				best = neighbor_id
		current = best
	return current == ancestor_id


static func branch_depth_for_slot(graph: RoomGraph, slot_id: String) -> int:
	var path := critical_path_ids(graph)
	if path.is_empty():
		return 0
	var path_set := {}
	for pid in path:
		path_set[pid] = true
	if path_set.has(slot_id):
		return 0
	# C-208: this took the *minimum* distance over every critical-path node. The path always
	# contains the start room, whose distance is 0, so `min_path_dist` was always 0 and the whole
	# function collapsed to plain distance-from-start. Both consumers — locked-door key placement
	# and puzzle-lever placement — rank candidates on this value, so keys and levers went to the
	# room furthest from the entrance rather than the one deepest off the critical path.
	#
	# The intended quantity is the distance to the *nearest* path node.
	#
	# C-155: the first fix computed that as `min |dist(slot) - dist(path_node)|` over the path,
	# which is the same depth-difference approximation C-149 found wrong in the shortcut scorer: it
	# equals the real walking distance only when one node is an ancestor of the other, and a slot
	# hanging off an early branch could score as though it were adjacent to a late path room. A
	# multi-source BFS seeded from every critical-path node measures the actual number of rooms
	# between the slot and the path, which is what "branch depth" means and what both consumers —
	# key placement and puzzle-lever placement — rank on.
	var adj := build_adjacency(graph)
	var queue: Array[String] = []
	var depth := {}
	for pid in path:
		depth[pid] = 0
		queue.append(pid)
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for neighbor in adj.get(current, []):
			var next_id := str(neighbor)
			if depth.has(next_id):
				continue
			depth[next_id] = int(depth[current]) + 1
			if next_id == slot_id:
				return int(depth[next_id])
			queue.append(next_id)
	return maxi(0, int(depth.get(slot_id, 0)))


static func slots_on_critical_path(graph: RoomGraph) -> Array[String]:
	var result: Array[String] = []
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.on_critical_path:
			result.append(slot.slot_id)
	if result.is_empty():
		return critical_path_ids(graph)
	return result


static func _dirs() -> Array[Vector2i]:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]


static func _door_for_dir(dir: Vector2i) -> int:
	if dir == Vector2i(0, -1):
		return RoomGraphSlot.DOOR_NORTH
	if dir == Vector2i(1, 0):
		return RoomGraphSlot.DOOR_EAST
	if dir == Vector2i(0, 1):
		return RoomGraphSlot.DOOR_SOUTH
	return RoomGraphSlot.DOOR_WEST
