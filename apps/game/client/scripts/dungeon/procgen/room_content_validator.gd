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
	# RM-06: full traversability model -- see `_traverse_with_capabilities()`'s header for the
	# invariant. `keys_by_room` used to read a `roomContent[].keyId` field nothing ever wrote; the
	# real source is `locks[].keyRoomIds`.
	var adjacency := _definition_adjacency(definition)
	var keys_by_room := _keys_by_room_from_locks(locks)
	var locks_by_to := {}
	var required_by_to := {}
	for lock in locks:
		if not lock is Dictionary:
			continue
		var to_room := str(lock.get("to", ""))
		locks_by_to[to_room] = str(lock.get("keyId", ""))
		required_by_to[to_room] = maxi(1, int(lock.get("keysRequired", 1)))
	var gate_by_locked_room := _shortcut_gate_targets(definition.get("shortcutGates", []))
	var puzzle_gates := _puzzle_gate_targets(definition.get("puzzles", []))
	var reachable := _traverse_with_capabilities(
		start_id, adjacency, keys_by_room, locks_by_to, required_by_to, gate_by_locked_room, puzzle_gates
	)
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
	# RM-06: the boss, the stairs, and every key room -- not just the boss -- must be provably
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
##
## RM-06: extended from a locks-only walk to the full traversability model. **The invariant: from
## the entrance, using only capabilities obtainable from rooms already reached, the player must be
## able to reach the stairs and the boss. A floor that cannot prove this does not ship.** Locks
## block `to` until their key is held; shortcut gates (`RM-04`) grant passage into the locked side
## only once the open side has been reached (they "only open the other way," per their own design
## comment); a puzzle gate blocks its `gateRoomId` until the lever room has been visited. Every one
## of these is a monotonic capability -- once gained it is never lost -- which is exactly what the
## existing collect/retry fixpoint already assumes, so extending it is additive.
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
## prove reachable -- the boss, the stairs, and every key room (RM-06 item 3).
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
	var locks_by_to := {}
	var required_by_to := {}
	for lock in content.get("locks", []):
		if not lock is Dictionary:
			continue
		var to_room := str((lock as Dictionary).get("to", ""))
		locks_by_to[to_room] = str((lock as Dictionary).get("keyId", ""))
		required_by_to[to_room] = maxi(1, int((lock as Dictionary).get("keysRequired", 1)))
	var gate_by_locked_room := _shortcut_gate_targets(content.get("shortcutGates", []))
	var puzzle_gates := _puzzle_gate_targets(content.get("puzzles", []))
	var reachable := _traverse_with_capabilities(
		start_semantic, adjacency, keys_by_room, locks_by_to, required_by_to, gate_by_locked_room, puzzle_gates
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


## `roomA` (locked) becomes reachable once `roomB`/`openRoomId` (open) has been -- see
## `RoomContentAssigner._add_shortcut_gates()` and `_guarantee_one_way_gate()`, both of which always
## set `roomB == openRoomId`. Keyed by the locked room since that is what the walk needs to unlock.
static func _shortcut_gate_targets(shortcut_gates: Array) -> Dictionary:
	var by_locked_room := {}
	for gate in shortcut_gates:
		if not gate is Dictionary:
			continue
		var gate_dict: Dictionary = gate
		var locked_room := str(gate_dict.get("roomA", ""))
		var open_room := str(gate_dict.get("openRoomId", gate_dict.get("roomB", "")))
		if locked_room != "" and open_room != "":
			by_locked_room[locked_room] = open_room
	return by_locked_room


## `gateRoomId` becomes reachable once `roomId` (the lever's room) has been -- pulling the lever(s)
## is not separately modelled since the walk only cares whether the room holding them was visited.
static func _puzzle_gate_targets(puzzles: Array) -> Dictionary:
	var by_gated_room := {}
	for puzzle in puzzles:
		if not puzzle is Dictionary:
			continue
		var puzzle_dict: Dictionary = puzzle
		var gate_room := str(puzzle_dict.get("gateRoomId", ""))
		var lever_room := str(puzzle_dict.get("roomId", ""))
		if gate_room != "" and lever_room != "":
			by_gated_room[gate_room] = lever_room
	return by_gated_room


## The shared fixpoint: walk, collect whatever capability the rooms reached this pass unlocked
## (a key, a shortcut gate's open side, a puzzle's lever room), and repeat while the last pass found
## something new. Capped at `adjacency.size()` passes -- a capability set can only grow, and there
## are never more capabilities than rooms, so that bound is sound and this never spins forever on a
## malformed floor.
static func _traverse_with_capabilities(
	start_semantic: String,
	adjacency: Dictionary,
	keys_by_room: Dictionary,
	locks_by_to: Dictionary,
	required_by_to: Dictionary,
	gate_by_locked_room: Dictionary,
	puzzle_gate_by_room: Dictionary
) -> Dictionary:
	# Reverse of `gate_by_locked_room` (open room -> the locked rooms it unlocks), built once --
	# a locked room's gate is checked whenever its open room is *in* the reachable set, not per
	# BFS step, so this only needs computing the one time.
	var locked_rooms_by_open_room := {}
	for locked_room in gate_by_locked_room:
		var open_room := str(gate_by_locked_room[locked_room])
		if not locked_rooms_by_open_room.has(open_room):
			locked_rooms_by_open_room[open_room] = []
		(locked_rooms_by_open_room[open_room] as Array).append(locked_room)
	var keys := {}
	var pulled_levers := {}
	var visited := {}
	var iteration_cap := maxi(1, adjacency.size())
	for _i in iteration_cap:
		var found_new_capability := false
		visited = {start_semantic: true}
		var queue: Array[String] = [start_semantic]
		var spent := {}
		while not queue.is_empty():
			var current: String = queue.pop_front()
			if keys_by_room.has(current) and not keys.has(current):
				keys[current] = str(keys_by_room[current])
				found_new_capability = true
			if puzzle_gate_by_room.has(current) and not pulled_levers.has(current):
				pulled_levers[current] = true
				found_new_capability = true
			# A locked room's open side, once reached, always grants entry -- interacting is free,
			# so this adds it in the same pass rather than waiting for the next one.
			for locked_room in locked_rooms_by_open_room.get(current, []):
				if not visited.has(locked_room):
					visited[locked_room] = true
					queue.append(locked_room)
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
				if puzzle_gate_by_room.has(next_id) and not pulled_levers.has(next_id):
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
