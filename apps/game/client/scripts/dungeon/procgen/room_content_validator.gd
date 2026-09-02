class_name RoomContentValidator
extends RefCounted


static func validate_definition(definition: Dictionary) -> Dictionary:
	var locks: Array = definition.get("locks", [])
	if locks.is_empty():
		return {"ok": true}
	var placements: Dictionary = definition.get("placements", {})
	# `entrance` is a bare room id while `boss` is a record with one inside it. This used to insist
	# on the record shape for both, so a floor with a lock on it always failed here with "missing
	# entrance placement" -- the solvability walk below has never once run.
	var start_id := _placement_room_id(placements.get("entrance"))
	if start_id == "":
		return {"ok": false, "reason": "Missing entrance room id"}
	var boss_id := _placement_room_id(placements.get("boss"))
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


## A placement is written either as a bare room id or as a record carrying one.
static func _placement_room_id(placement: Variant) -> String:
	if placement is Dictionary:
		return str((placement as Dictionary).get("roomId", ""))
	return str(placement) if placement != null else ""


static func _definition_adjacency(definition: Dictionary) -> Dictionary:
	return DungeonDefinitionValidator.adjacency_from_edges(definition)


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
		var from_room: String = lock.get("from", "")
		var to_layout := ""
		var from_layout := ""
		for layout_id in layout_to_semantic:
			if layout_to_semantic[layout_id] == to_room:
				to_layout = layout_id
			if layout_to_semantic[layout_id] == from_room:
				from_layout = layout_id
		if key_room == "" or to_room == "":
			return {"ok": false, "reason": "Lock missing key or target room"}
		var key_layouts: Array = lock.get("keyLayoutIds", [key_layout])
		for candidate in key_layouts:
			var layout := str(candidate)
			if layout == "":
				continue
			# A key on the critical path is a weaker hiding place, not an invalid floor, and the
			# assigner only resorts to one when the approach to the lock has no side branch at all.
			# Rejecting it here just sent the generator back for an ungated floor instead.
			if layout == graph.start_id or layout == graph.stairs_id or layout == graph.boss_id:
				return {"ok": false, "reason": "Key room uses reserved layout"}
			# The rule that matters is that the key is gettable with the door shut. This used to
			# demand the key room be an ancestor of the room behind the door, which on a
			# breadth-first tree means a room on the critical path -- rejected four lines above.
			# No lock could satisfy both, so every floor carrying one failed validation and the
			# assigner retried until it happened to produce a floor with no locks at all.
			if from_layout != "" and to_layout != "":
				var open_rooms := RoomGraphPaths.reachable_without_edge(
					graph, from_layout, to_layout
				)
				if not open_rooms.has(layout):
					return {
						"ok": false,
						"reason": "Key room %s is behind the lock it opens" % layout
					}
	if not _boss_reachable_with_keys(graph, layout_to_semantic, content, start_semantic, boss_semantic):
		return {"ok": false, "reason": "Boss unreachable with earned keys"}
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


## Whether the player can reach the boss, picking keys up as they explore.
##
## This used to walk the critical path and collect only the keys lying on it. But a key is placed
## *off* the critical path by design -- `_find_key_room_layout` skips on-path rooms, and the check
## above rejects a key room that is on it -- so the walk could never pick one up, every floor
## carrying a lock was judged unwinnable, and the assigner retried until it produced a floor with
## no locks. Exploring the whole reachable region and repeating until no new key turns up is the
## same fixpoint `validate_definition` already runs against the finished floor.
static func _boss_reachable_with_keys(
	graph: RoomGraph,
	layout_to_semantic: Dictionary,
	content: Dictionary,
	start_semantic: String,
	boss_semantic: String
) -> bool:
	if start_semantic == "" or boss_semantic == "":
		return false
	var adjacency := {}
	var adj := RoomGraphPaths.build_adjacency(graph)
	for layout_id in adj:
		var room_id := str(layout_to_semantic.get(layout_id, ""))
		if room_id == "":
			continue
		var neighbors: Array[String] = []
		for neighbor_layout in adj[layout_id]:
			var neighbor_id := str(layout_to_semantic.get(str(neighbor_layout), ""))
			if neighbor_id != "":
				neighbors.append(neighbor_id)
		adjacency[room_id] = neighbors
	var keys_by_room := {}
	for entry in content.get("roomContent", []):
		if not entry is Dictionary:
			continue
		var key_id := str((entry as Dictionary).get("keyId", ""))
		if key_id != "":
			keys_by_room[str((entry as Dictionary).get("roomId", ""))] = key_id
	var locks_by_to := {}
	var required_by_to := {}
	for lock in content.get("locks", []):
		if not lock is Dictionary:
			continue
		var to_room := str((lock as Dictionary).get("to", ""))
		locks_by_to[to_room] = str((lock as Dictionary).get("keyId", ""))
		required_by_to[to_room] = maxi(1, int((lock as Dictionary).get("keysRequired", 1)))
	var keys := {}
	while true:
		var found_new_key := false
		var visited := {start_semantic: true}
		var queue: Array[String] = [start_semantic]
		var spent := {}
		while not queue.is_empty():
			var current: String = queue.pop_front()
			if keys_by_room.has(current) and not keys.has(current):
				keys[current] = str(keys_by_room[current])
				found_new_key = true
			if current == boss_semantic:
				return true
			for neighbor in adjacency.get(current, []):
				var next_id := str(neighbor)
				if visited.has(next_id):
					continue
				if locks_by_to.has(next_id):
					var required_key := str(locks_by_to[next_id])
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
			return false
	return false


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
