class_name RoomGraphPaths
extends RefCounted

## Graph path utilities for critical-path and branch analysis.


static func build_adjacency(graph: RoomGraph) -> Dictionary:
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
	return adj


static func bfs_distances(graph: RoomGraph, start_id: String) -> Dictionary:
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
	var distances := bfs_distances(graph, graph.start_id)
	var min_path_dist := 9999
	for pid in path:
		min_path_dist = mini(min_path_dist, int(distances.get(pid, 9999)))
	var slot_dist := int(distances.get(slot_id, 0))
	return maxi(0, slot_dist - min_path_dist)


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
