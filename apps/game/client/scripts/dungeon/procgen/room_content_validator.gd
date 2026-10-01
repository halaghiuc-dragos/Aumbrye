class_name RoomContentValidator
extends RefCounted


static func validate_definition(definition: Dictionary) -> Dictionary:
	var locks: Array = definition.get("locks", [])
	if locks.is_empty():
		return {"ok": true}
	var placements: Dictionary = definition.get("placements", {})
	# `entrance` is a bare room id while `boss` is a record with one inside it, so the two are read
	# in their own shapes.
	var start_id := _placement_room_id(placements.get("entrance"))
	if start_id == "":
		return {"ok": false, "reason": "Missing entrance room id"}
	var boss_id := _placement_room_id(placements.get("boss"))
	if boss_id == "":
		return {"ok": true}
	# Full traversability model -- see `_traverse_with_capabilities()`'s header for the
	# invariant. `keys_by_room` is read from `locks[].keyRoomIds`.
	var adjacency := _definition_adjacency(definition)
	var keys_by_room := _keys_by_room_from_locks(locks)
	var blocked_edges := _blocked_edges(
		locks, definition.get("shortcutGates", []), definition.get("puzzles", [])
	)
	var reachable := _traverse_with_capabilities(start_id, adjacency, keys_by_room, blocked_edges)
	var required_ids: Array = [boss_id]
	var stairs_id := _placement_room_id(placements.get("stairs"))
	if stairs_id != "":
		required_ids.append(stairs_id)
	for lock in locks:
		if not lock is Dictionary:
			continue
		for key_room in (lock as Dictionary).get("keyRoomIds", []):
			required_ids.append(str(key_room))
	for required in required_ids:
		if not reachable.has(str(required)):
			return {"ok": false, "reason": "Boss, stairs or a key room unreachable with earned keys"}
	return {"ok": true}


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
			# The rule that matters is that the key is gettable with the door shut. The key room need not be
			# an ancestor of the room behind the door: on a breadth-first tree that would mean a room on the
			# critical path, which is rejected above, and no lock could satisfy both.
			if from_layout != "" and to_layout != "":
				var open_rooms := RoomGraphPaths.reachable_without_edge(
					graph, from_layout, to_layout
				)
				if not open_rooms.has(layout):
					return {
						"ok": false,
						"reason": "Key room %s is behind the lock it opens" % layout
					}
	# The boss, the stairs, and every key room -- not just the boss -- must be provably
	# reachable with only the capabilities the walk itself can gain along the way.
	var required_semantics: Array = [boss_semantic]
	var stairs_semantic := _semantic_for_layout(assignment, graph.stairs_id)
	if stairs_semantic != "":
		required_semantics.append(stairs_semantic)
	for lock in content.get("locks", []):
		if not lock is Dictionary:
			continue
		for key_room in (lock as Dictionary).get("keyRoomIds", []):
			required_semantics.append(str(key_room))
	if not _required_rooms_reachable(
		graph, layout_to_semantic, content, start_semantic, required_semantics
	):
		return {"ok": false, "reason": "Boss, stairs or a key room unreachable with earned keys"}
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
	if config.min_rest_rooms > 0:
		var rests := 0
		for entry in room_content:
			if entry is Dictionary and str((entry as Dictionary).get("contentType", "")) == RoomContentTypes.REST:
				rests += 1
		if rests < config.min_rest_rooms:
			return {"ok": false, "reason": "Floor has %d rest rooms, needs %d" % [rests, config.min_rest_rooms]}
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
## A key is placed *off* the critical path by design -- `_find_key_room_layout` skips on-path rooms,
## and the check above rejects a key room that is on it -- so a walk of the critical path alone could
## never pick one up. Exploring the whole reachable region and repeating until no new key turns up is
## the same fixpoint `validate_definition` runs against the finished floor.
##
## **The invariant: from the entrance, using only capabilities obtainable from rooms already reached,
## the player must be able to reach the stairs and the boss. A floor that cannot prove this does not
## ship.** Locks block `to` until their key is held; shortcut gates grant passage into the locked side
## only once the open side has been reached (they "only open the other way," per their own design
## comment); a puzzle gate blocks its `gateRoomId` until the lever room has been visited. Every one
## of these is a monotonic capability -- once gained it is never lost -- which is exactly what the
## collect/retry fixpoint assumes.
static func _boss_reachable_with_keys(
	graph: RoomGraph,
	layout_to_semantic: Dictionary,
	content: Dictionary,
	start_semantic: String,
	boss_semantic: String
) -> bool:
	return _required_rooms_reachable(
		graph, layout_to_semantic, content, start_semantic, [boss_semantic]
	)


## Like `_boss_reachable_with_keys`, but for an arbitrary set of rooms the floor must be able to
## prove reachable -- the boss, the stairs, and every key room.
static func _required_rooms_reachable(
	graph: RoomGraph,
	layout_to_semantic: Dictionary,
	content: Dictionary,
	start_semantic: String,
	required_semantics: Array
) -> bool:
	if start_semantic == "":
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
	var keys_by_room := _keys_by_room_from_locks(content.get("locks", []))
	var blocked_edges := _blocked_edges(
		content.get("locks", []), content.get("shortcutGates", []), content.get("puzzles", [])
	)
	var reachable := _traverse_with_capabilities(
		start_semantic, adjacency, keys_by_room, blocked_edges
	)
	for required in required_semantics:
		if not reachable.has(str(required)):
			return false
	return true


## `locks[].keyRoomIds` (or the singular `keyRoomId`) is where a key actually sits -- the room a key
## was hidden in never gets a matching field written onto its own `roomContent` entry, so reading
## `keyId` off `roomContent` (the previous approach) found nothing on every floor with a lock, and
## the walk below silently treated every locked door as impassable forever.
static func _keys_by_room_from_locks(locks: Array) -> Dictionary:
	var keys_by_room := {}
	for lock in locks:
		if not lock is Dictionary:
			continue
		var lock_dict: Dictionary = lock
		var key_id := str(lock_dict.get("keyId", ""))
		if key_id == "":
			continue
		var key_rooms: Array = lock_dict.get("keyRoomIds", [lock_dict.get("keyRoomId", "")])
		for key_room in key_rooms:
			var room_id := str(key_room)
			if room_id != "":
				keys_by_room[room_id] = key_id
	return keys_by_room


static func _edge_key(a: String, b: String) -> String:
	return "%s>%s" % [a, b] if a < b else "%s>%s" % [b, a]


## Every gate blocks one doorway, not the room behind it: a room with a second way in is not
## locked, and a validator that treated it as locked would pass floors where the lock is walked
## around. A shut door is shut from both sides, so an edge key does not depend on direction.
##
## - a key lock needs `keysRequired` of its key's fragments;
## - a puzzle gate opens once the lever room has been visited (`roomId` holds the levers);
## - a shortcut gate is a one-way door: open from `openRoomId` at any time, and from the locked
##   side once the open side has been reached.
static func _blocked_edges(locks: Array, shortcut_gates: Array, puzzles: Array) -> Dictionary:
	var blocked := {}
	for lock in locks:
		if not lock is Dictionary:
			continue
		var key_id := str((lock as Dictionary).get("keyId", ""))
		if key_id == "":
			continue
		blocked[_edge_key(str((lock as Dictionary).get("from", "")), str((lock as Dictionary).get("to", "")))] = {
			"kind": "key",
			"keyId": key_id,
			"needed": maxi(1, int((lock as Dictionary).get("keysRequired", 1))),
		}
	for gate in shortcut_gates:
		if not gate is Dictionary:
			continue
		var locked_room := str((gate as Dictionary).get("roomA", ""))
		var open_room := str((gate as Dictionary).get("openRoomId", (gate as Dictionary).get("roomB", "")))
		if locked_room != "" and open_room != "":
			blocked[_edge_key(locked_room, open_room)] = {"kind": "oneway", "openRoom": open_room}
	for puzzle in puzzles:
		if not puzzle is Dictionary:
			continue
		var lever_room := str((puzzle as Dictionary).get("roomId", ""))
		var gate_room := str((puzzle as Dictionary).get("gateRoomId", ""))
		if lever_room != "" and gate_room != "":
			blocked[_edge_key(lever_room, gate_room)] = {"kind": "lever", "leverRoom": lever_room}
	return blocked


static func _gate_open(
	gate: Dictionary, current: String, visited: Dictionary, keys: Dictionary, levers: Dictionary
) -> bool:
	match str(gate.get("kind", "")):
		"key":
			var held := 0
			for room_id in keys:
				if str(keys[room_id]) == str(gate.get("keyId", "")):
					held += 1
			return held >= int(gate.get("needed", 1))
		"oneway":
			var open_room := str(gate.get("openRoom", ""))
			return current == open_room or visited.has(open_room)
		"lever":
			return levers.has(str(gate.get("leverRoom", "")))
	return true


## The shared fixpoint: walk, collect whatever capability the rooms reached this pass unlocked
## (a key, a puzzle's lever room), and repeat while the last pass found something new. Capped at
## `adjacency.size()` passes -- a capability set can only grow, and there are never more
## capabilities than rooms, so that bound is sound and this never spins forever on a malformed
## floor.
static func _traverse_with_capabilities(
	start_semantic: String,
	adjacency: Dictionary,
	keys_by_room: Dictionary,
	blocked_edges: Dictionary
) -> Dictionary:
	var lever_rooms := {}
	for edge_key in blocked_edges:
		var gate: Dictionary = blocked_edges[edge_key]
		if str(gate.get("kind", "")) == "lever":
			lever_rooms[str(gate.get("leverRoom", ""))] = true
	var keys := {}
	var levers := {}
	var visited := {}
	var iteration_cap := maxi(1, adjacency.size())
	for _i in iteration_cap:
		var found_new_capability := false
		visited = {start_semantic: true}
		var queue: Array[String] = [start_semantic]
		while not queue.is_empty():
			var current: String = queue.pop_front()
			if keys_by_room.has(current) and not keys.has(current):
				keys[current] = str(keys_by_room[current])
				found_new_capability = true
			if lever_rooms.has(current) and not levers.has(current):
				levers[current] = true
				found_new_capability = true
			for neighbor in adjacency.get(current, []):
				var next_id := str(neighbor)
				if visited.has(next_id):
					continue
				var gate: Dictionary = blocked_edges.get(_edge_key(current, next_id), {})
				if not gate.is_empty() and not _gate_open(gate, current, visited, keys, levers):
					continue
				visited[next_id] = true
				queue.append(next_id)
		if not found_new_capability:
			break
	return visited


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
	var entries_by_placement: Dictionary = {}
	for entry in content.get("roomContent", []):
		if not entry is Dictionary:
			continue
		entries_by_placement[str(entry.get("placementId", ""))] = entry
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
		var quest := DungeonQuestCatalog.quest_for_dialogue(dialogue_id)
		var delivery := DungeonQuestCatalog.delivery_for_quest(quest)
		var delivery_check := validate_quest_delivery(delivery, entry, entries_by_placement, path_semantics)
		if not bool(delivery_check.get("ok", false)):
			return delivery_check
	return {"ok": true}


static func validate_quest_delivery(
	delivery: Dictionary, entry: Dictionary, entries_by_placement: Dictionary, path_semantics: Array[String]
) -> Dictionary:
	var delivery_kind := str(delivery.get("kind", ""))
	var item_id := str(delivery.get("itemId", ""))
	if delivery_kind == "" or item_id == "" or ItemCatalog.get_definition(item_id).is_empty():
		return {"ok": false, "reason": "Quest delivery is invalid"}
	if delivery_kind == "npc_payment":
		if str(delivery.get("receiptFlag", "")) == "":
			return {"ok": false, "reason": "NPC payment needs an earned receipt"}
		return {"ok": true}
	if delivery_kind == "ordinary_floor_loot" or delivery_kind == "rescue_return":
		return {"ok": true}
	if delivery_kind != "required_pickup":
		return {"ok": false, "reason": "Unknown quest delivery kind %s" % delivery_kind}
	var placement_id := str(entry.get("rewardPlacementId", ""))
	var pickup: Dictionary = entries_by_placement.get(placement_id, {})
	if pickup.is_empty() or str(pickup.get("roomId", "")) not in path_semantics:
		return {"ok": false, "reason": "Required quest pickup is not traversably reachable"}
	if str(pickup.get("contentType", "")) == "locked_vault":
		return {"ok": false, "reason": "Required quest pickup cannot hide behind an unrelated lock"}
	if not _entry_has_item(pickup, item_id):
		return {"ok": false, "reason": "Required quest pickup item is missing"}
	return {"ok": true}


static func _entry_has_item(entry: Dictionary, item_id: String) -> bool:
	for item in entry.get("items", []):
		if item is Dictionary and str(item.get("itemId", "")) == item_id:
			return true
	return false


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
