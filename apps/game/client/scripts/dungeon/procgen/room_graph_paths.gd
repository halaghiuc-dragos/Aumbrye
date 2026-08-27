class_name RoomGraphPaths
extends RefCounted


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
			if not (slot.door_mask & RoomGraphGeometry.dir_to_door(dir)):
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


static func _dirs() -> Array[Vector2i]:
	return [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]

