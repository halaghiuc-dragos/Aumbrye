class_name RoomContentValidator
extends RefCounted

## Simulates traversal from start to boss with earned keys/flags.


static func validate(
	graph: RoomGraph,
	assignment: Dictionary,
	content: Dictionary
) -> Dictionary:
	var semantic_to_layout := _semantic_to_layout(assignment)
	var start_semantic := _semantic_for_layout(assignment, graph.start_id)
	var boss_semantic := _semantic_for_layout(assignment, graph.boss_id)
	if start_semantic == "" or boss_semantic == "":
		return {"ok": false, "reason": "Missing start or boss semantic id"}
	for lock in content.get("locks", []):
		var key_room: String = lock.get("keyRoomId", "")
		var to_room: String = lock.get("to", "")
		var key_layout: String = lock.get("keyLayoutId", "")
		var to_layout := ""
		for layout_id in semantic_to_layout:
			if semantic_to_layout[layout_id] == to_room:
				to_layout = layout_id
				break
		if key_room == "" or to_room == "":
			return {"ok": false, "reason": "Lock missing key or target room"}
		if key_layout != "" and to_layout != "":
			if not RoomGraphPaths.is_on_branch_to(graph, key_layout, to_layout):
				return {"ok": false, "reason": "Key room not on branch to locked door"}
	var keys_on_path := {}
	for entry in content.get("roomContent", []):
		if entry.get("keyId", "") != "":
			keys_on_path[entry.get("roomId", "")] = entry.get("keyId", "")
	var path := RoomGraphPaths.critical_path_ids(graph)
	var path_semantic: Array[String] = []
	for layout_id in path:
		path_semantic.append(semantic_to_layout.get(layout_id, ""))
	if not _simulate_path(path_semantic, content, start_semantic, boss_semantic):
		return {"ok": false, "reason": "Boss unreachable on critical path with earned keys"}
	return {"ok": true}


static func _simulate_path(
	path_semantic: Array[String],
	content: Dictionary,
	start_semantic: String,
	boss_semantic: String
) -> bool:
	if path_semantic.is_empty():
		return false
	if path_semantic[0] != start_semantic or path_semantic[path_semantic.size() - 1] != boss_semantic:
		return false
	var locks_by_to := {}
	for lock in content.get("locks", []):
		locks_by_to[lock.get("to", "")] = lock.get("keyId", "")
	var keys := {}
	var idx := 0
	while idx < path_semantic.size():
		var room_id: String = path_semantic[idx]
		for entry in content.get("roomContent", []):
			if entry.get("roomId", "") == room_id and entry.get("keyId", "") != "":
				keys[entry.get("keyId", "")] = true
		idx += 1
		if idx >= path_semantic.size():
			break
		var next_room: String = path_semantic[idx]
		if locks_by_to.has(next_room):
			var required_key: String = locks_by_to[next_room]
			if required_key != "" and not keys.has(required_key):
				return false
	return true


static func simulate_collectibles(
	_graph: RoomGraph,
	_assignment: Dictionary,
	content: Dictionary,
	path_semantics: Array[String]
) -> Dictionary:
	var keys := {}
	var flags := {}
	for entry in content.get("roomContent", []):
		var room_id: String = entry.get("roomId", "")
		if room_id not in path_semantics:
			continue
		match str(entry.get("contentType", "")):
			"locked_vault":
				var key_id: String = entry.get("keyId", "")
				if key_id != "":
					keys[key_id] = true
			"npc_quest":
				var quest_key: String = entry.get("questKeyId", "")
				if quest_key != "":
					keys[quest_key] = true
			"puzzle":
				var flag_id: String = entry.get("flagId", "")
				if flag_id != "":
					flags[flag_id] = true
	return {"keys": keys, "flags": flags}


static func _semantic_to_layout(assignment: Dictionary) -> Dictionary:
	var map := {}
	for room in assignment.get("rooms", []):
		map[room["layout_id"]] = room["semantic_id"]
	return map


static func _semantic_for_layout(assignment: Dictionary, layout_id: String) -> String:
	for room in assignment.get("rooms", []):
		if room.get("layout_id", "") == layout_id:
			return str(room.get("semantic_id", ""))
	return ""
