class_name RoomContentValidator
extends RefCounted


static func validate_definition(definition: Dictionary) -> Dictionary:
	var locks: Array = definition.get("locks", [])
	if locks.is_empty():
		return {"ok": true}
	var placements: Dictionary = definition.get("placements", {})
	var entrance: Variant = placements.get("entrance")
	if not entrance is Dictionary:
		return {"ok": false, "reason": "Missing entrance placement"}
	var start_id := str(entrance.get("roomId", ""))
	if start_id == "":
		return {"ok": false, "reason": "Missing entrance room id"}
	var boss_placement: Variant = placements.get("boss")
	var boss_id := str(boss_placement.get("roomId", "")) if boss_placement is Dictionary else ""
	if boss_id == "":
		return {"ok": true}
	var adjacency := _definition_adjacency(definition)
	var keys_by_room := {}
	for entry in definition.get("roomContent", []):
		if not entry is Dictionary:
			continue
		var key_id := str(entry.get("keyId", ""))
		if key_id == "":
			continue
		keys_by_room[str(entry.get("roomId", ""))] = key_id
	var locks_by_to := {}
	var required_by_to := {}
	for lock in locks:
		if not lock is Dictionary:
			continue
		var to_room := str(lock.get("to", ""))
		locks_by_to[to_room] = str(lock.get("keyId", ""))
		required_by_to[to_room] = maxi(1, int(lock.get("keysRequired", 1)))
	var keys := {}
	var visited := {}
	while true:
		var found_new_key := false
		var queue: Array[String] = [start_id]
		visited = {start_id: true}
		var spent := {}
		while not queue.is_empty():
			var current: String = queue.pop_front()
			if keys_by_room.has(current):
				var key_id: String = str(keys_by_room[current])
				if not keys.has(current):
					keys[current] = key_id
					found_new_key = true
			if current == boss_id:
				return {"ok": true}
			for neighbor in adjacency.get(current, []):
				var next_id := str(neighbor)
				if visited.has(next_id):
					continue
				if locks_by_to.has(next_id):
					var required_key: String = str(locks_by_to[next_id])
					if required_key != "":
						var needed: int = int(required_by_to.get(next_id, 1))
						var held := 0
						for room_id in keys:
							if str(keys[room_id]) == required_key:
								held += 1
						held -= int(spent.get(required_key, 0))
						if held < needed:
							continue
						spent[required_key] = int(spent.get(required_key, 0)) + needed
				visited[next_id] = true
				queue.append(next_id)
		if not found_new_key:
			break
	return {"ok": false, "reason": "Boss unreachable with earned keys"}


static func _definition_adjacency(definition: Dictionary) -> Dictionary:
	var adjacency := {}
	for edge in definition.get("edges", []):
		if not edge is Dictionary:
			continue
		if str(edge.get("kind", "")) == "secret":
			continue
		var from_id := str(edge.get("from", ""))
		var to_id := str(edge.get("to", ""))
		if from_id == "" or to_id == "":
			continue
		if not adjacency.has(from_id):
			adjacency[from_id] = []
		if not adjacency.has(to_id):
			adjacency[to_id] = []
		adjacency[from_id].append(to_id)
		adjacency[to_id].append(from_id)
	return adjacency


static func validate(
	graph: RoomGraph,
	assignment: Dictionary,
	content: Dictionary,
	config: RoomContentConfig = null
) -> Dictionary:
	var layout_to_semantic := _layout_to_semantic(assignment)
	var start_semantic := _semantic_for_layout(assignment, graph.start_id)
	var boss_semantic := _semantic_for_layout(assignment, graph.boss_id)
	if start_semantic == "" or boss_semantic == "":
		return {"ok": false, "reason": "Missing start or boss semantic id"}
	var path := RoomGraphPaths.critical_path_ids(graph)
	var path_semantic: Array[String] = []
	for layout_id in path:
		path_semantic.append(layout_to_semantic.get(layout_id, ""))
	var puzzle_rooms := {}
	for puzzle in content.get("puzzles", []):
		if puzzle is Dictionary:
			puzzle_rooms[str((puzzle as Dictionary).get("roomId", ""))] = true
	for entry in content.get("roomContent", []):
		if not entry is Dictionary:
			continue
		if str((entry as Dictionary).get("templateId", "")) != "puzzle_lever_gate":
			continue
		var puzzle_room := str((entry as Dictionary).get("roomId", ""))
		if not puzzle_rooms.has(puzzle_room):
			return {
				"ok": false,
				"reason": "Puzzle content in room %s has no matching puzzles record" % puzzle_room
			}
	for lock in content.get("locks", []):
		var keys_required := maxi(1, int(lock.get("keysRequired", 1)))
		var key_rooms: Array = lock.get("keyRoomIds", [lock.get("keyRoomId", "")])
		var placed_keys := 0
		for room_id in key_rooms:
			if str(room_id) != "":
				placed_keys += 1
		if placed_keys < keys_required:
			return {
				"ok": false,
				"reason":
				(
					"Lock %s requires %d keys but the floor places %d"
					% [str(lock.get("lockId", "?")), keys_required, placed_keys]
				)
			}
		var key_room: String = lock.get("keyRoomId", "")
		var to_room: String = lock.get("to", "")
		var key_layout: String = lock.get("keyLayoutId", "")
		var to_layout := ""
		for layout_id in layout_to_semantic:
			if layout_to_semantic[layout_id] == to_room:
				to_layout = layout_id
				break
		if key_room == "" or to_room == "":
			return {"ok": false, "reason": "Lock missing key or target room"}
		var key_layouts: Array = lock.get("keyLayoutIds", [key_layout])
		for candidate in key_layouts:
			var layout := str(candidate)
			if layout == "":
				continue
			if layout in path:
				return {"ok": false, "reason": "Key room on critical path"}
			if layout == graph.start_id or layout == graph.stairs_id or layout == graph.boss_id:
				return {"ok": false, "reason": "Key room uses reserved layout"}
			if to_layout != "" and not RoomGraphPaths.is_on_branch_to(graph, layout, to_layout):
				return {"ok": false, "reason": "Key room not on branch to locked door"}
	if not _simulate_path(path_semantic, content, start_semantic, boss_semantic):
		return {"ok": false, "reason": "Boss unreachable on critical path with earned keys"}
	var collectible_check := _validate_collectibles(content, path_semantic)
	if not collectible_check.get("ok", false):
		return collectible_check
	if config != null:
		var pacing_check := validate_pacing(content, path_semantic, config)
		if not pacing_check.get("ok", false):
			return pacing_check
	return {"ok": true}


static func validate_pacing(
	content: Dictionary, path_semantic: Array[String], config: RoomContentConfig
) -> Dictionary:
	var room_content: Array = content.get("roomContent", [])
	if config.min_reward_rooms > 0:
		var rewards := 0
		for entry in room_content:
			if not entry is Dictionary:
				continue
			if str((entry as Dictionary).get("contentType", "")) == RoomContentTypes.REWARD:
				rewards += 1
		if rewards < config.min_reward_rooms:
			return {
				"ok": false,
				"reason": "Floor has %d reward rooms, needs %d" % [rewards, config.min_reward_rooms],
			}
	if config.max_consecutive_combat > 0:
		var by_room := {}
		for entry in room_content:
			if entry is Dictionary:
				by_room[str((entry as Dictionary).get("roomId", ""))] = entry
		var streak := 0
		for room_id in path_semantic:
			var entry: Variant = by_room.get(room_id)
			if not entry is Dictionary:
				streak = 0
				continue
			if str((entry as Dictionary).get("contentType", "")) != RoomContentTypes.COMBAT:
				streak = 0
				continue
			streak += 1
			if streak > config.max_consecutive_combat:
				return {
					"ok": false,
					"reason": "More than %d combat rooms in a row" % config.max_consecutive_combat,
				}
	return {"ok": true}


static func _simulate_path(
	path_semantic: Array[String], content: Dictionary, start_semantic: String, boss_semantic: String
) -> bool:
	if path_semantic.is_empty():
		return false
	if (
		path_semantic[0] != start_semantic
		or path_semantic[path_semantic.size() - 1] != boss_semantic
	):
		return false
	var locks_by_to := {}
	var required_by_to := {}
	for lock in content.get("locks", []):
		var to_room := str(lock.get("to", ""))
		locks_by_to[to_room] = str(lock.get("keyId", ""))
		required_by_to[to_room] = maxi(1, int(lock.get("keysRequired", 1)))
	var held_keys := {}
	var idx := 0
	while idx < path_semantic.size():
		var room_id: String = path_semantic[idx]
		for entry in content.get("roomContent", []):
			if entry.get("roomId", "") != room_id:
				continue
			var found_key := str(entry.get("keyId", ""))
			if found_key != "":
				held_keys[found_key] = int(held_keys.get(found_key, 0)) + 1
		idx += 1
		if idx >= path_semantic.size():
			break
		var next_room: String = path_semantic[idx]
		if locks_by_to.has(next_room):
			var required_key: String = locks_by_to[next_room]
			if required_key == "":
				continue
			var needed: int = int(required_by_to.get(next_room, 1))
			if int(held_keys.get(required_key, 0)) < needed:
				return false
			held_keys[required_key] = int(held_keys[required_key]) - needed
	return true


static func simulate_collectibles(
	_graph: RoomGraph, _assignment: Dictionary, content: Dictionary, path_semantics: Array[String]
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


static func _validate_collectibles(content: Dictionary, path_semantics: Array[String]) -> Dictionary:
	var simulated := simulate_collectibles(null, {}, content, path_semantics)
	var floor_items := {}
	for entry in content.get("roomContent", []):
		if not entry is Dictionary:
			continue
		for item in entry.get("items", []):
			if item is Dictionary:
				var item_id := str(item.get("itemId", ""))
				if item_id != "":
					floor_items[item_id] = true
		if str(entry.get("contentType", "")) == "npc_quest":
			var quest_key := str(entry.get("questKeyId", ""))
			if quest_key != "":
				simulated.keys[quest_key] = true
	for entry in content.get("roomContent", []):
		if str(entry.get("contentType", "")) != "npc_quest":
			continue
		var dialogue_id := str(entry.get("dialogueId", ""))
		if dialogue_id == "":
			continue
		var reward_item := _reward_item_for_npc(entry)
		if reward_item == "":
			continue
		if not ItemCatalog.get_definition(reward_item).is_empty():
			if not floor_items.has(reward_item):
				return {
					"ok": false,
					"reason": "Quest reward item %s not spawned on floor" % reward_item,
				}
	return {"ok": true}


static func _reward_item_for_npc(entry: Dictionary) -> String:
	var dialogue_id := str(entry.get("dialogueId", ""))
	var quest := DungeonQuestCatalog.quest_for_dialogue(dialogue_id)
	return str(quest.get("rewardItemId", ""))


static func _layout_to_semantic(assignment: Dictionary) -> Dictionary:
	var map := {}
	for room in assignment.get("rooms", []):
		map[room["layout_id"]] = room["semantic_id"]
	return map


static func _semantic_for_layout(assignment: Dictionary, layout_id: String) -> String:
	for room in assignment.get("rooms", []):
		if room.get("layout_id", "") == layout_id:
			return str(room.get("semantic_id", ""))
	return ""
