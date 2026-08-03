class_name RoomContentAssigner
extends RefCounted

## Post-layout content tagging + lock-and-key placement with solvability validation.


static func assign(
	graph: RoomGraph,
	assignment: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig = null
) -> Dictionary:
	config = config if config != null else RoomContentConfig.default()
	var layout_semantic := _layout_to_semantic(assignment)
	var critical_layout: Array[String] = RoomGraphPaths.critical_path_ids(graph)
	var critical_semantic: Array[String] = []
	for layout_id in critical_layout:
		critical_semantic.append(layout_semantic.get(layout_id, layout_id))
	var critical_set := {}
	for room_id in critical_semantic:
		critical_set[room_id] = true
	var distances := RoomGraphPaths.bfs_distances(graph, graph.start_id)
	for attempt in config.max_assignment_attempts:
		var result := _try_assign_once(
			graph, assignment, layout_semantic, critical_layout, critical_semantic, critical_set, distances, rng, config
		)
		if result.get("ok", false):
			return result
		rng.seed = rng.seed + 1_000_003 + attempt
	return _fallback_assignment(graph, assignment, layout_semantic, critical_semantic, critical_layout, distances, rng)


static func _try_assign_once(
	graph: RoomGraph,
	assignment: Dictionary,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	critical_semantic: Array[String],
	critical_set: Dictionary,
	distances: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig
) -> Dictionary:
	var room_content: Array = []
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	var no_trap_semantics := reserved_semantics.duplicate()
	for layout_id in critical_layout:
		if layout_id == graph.start_id:
			var start_slot := graph.get_slot(layout_id)
			if start_slot:
				for dir in RoomGraphPaths._dirs():
					var neighbor: RoomGraphSlot = graph.slots.get(start_slot.grid_pos + dir) as RoomGraphSlot
					if neighbor:
						no_trap_semantics.append(layout_semantic.get(neighbor.slot_id, ""))
	var dead_ends: Array[String] = []
	for room in assignment.get("rooms", []):
		var semantic: String = room["semantic_id"]
		var layout_id: String = room["layout_id"]
		var slot := graph.get_slot(layout_id)
		if slot and slot.is_dead_end() and semantic not in reserved_semantics and room.get("type", "") != "filler":
			dead_ends.append(semantic)
	dead_ends.sort()
	for room in assignment.get("rooms", []):
		var semantic: String = room["semantic_id"]
		var layout_id: String = room["layout_id"]
		var slot := graph.get_slot(layout_id)
		if room.get("type", "") == "filler":
			room_content.append({
				"roomId": semantic,
				"layoutId": layout_id,
				"contentType": RoomContentTypes.EMPTY,
				"templateId": "",
			})
			continue
		if semantic in reserved_semantics:
			room_content.append(_entry_for_special(room, slot))
			continue
		var on_critical := critical_set.has(semantic)
		var dist: int = int(distances.get(layout_id, 0))
		var content_type := _pick_content_type(
			on_critical, dist, semantic in dead_ends, semantic in no_trap_semantics, rng, config
		)
		room_content.append({
			"roomId": semantic,
			"layoutId": layout_id,
			"contentType": content_type,
			"templateId": RoomContentTypes.TEMPLATE_BY_TYPE.get(content_type, ""),
		})
	var locks: Array = []
	if config.enable_locked_door and critical_semantic.size() >= 4:
		locks = _place_locked_doors(
			graph, layout_semantic, critical_layout, critical_semantic, distances, rng, config
		)
		if locks.is_empty():
			return {"ok": false, "reason": "No valid locked door placement"}
		for lock in locks:
			_apply_key_to_content(room_content, lock)
	var content := {
		"roomContent": room_content,
		"locks": locks,
		"puzzles": [],
	}
	var validation := RoomContentValidator.validate(graph, assignment, content)
	if not validation.get("ok", false):
		return validation
	return {"ok": true, "content": content}


static func _pick_content_type(
	on_critical: bool,
	distance: int,
	is_dead_end: bool,
	no_trap: bool,
	rng: RandomNumberGenerator,
	config: RoomContentConfig
) -> String:
	if is_dead_end:
		return RoomContentTypes.REWARD
	if on_critical:
		return RoomContentTypes.COMBAT if rng.randf() < 0.88 else RoomContentTypes.EMPTY
	if distance < config.min_off_path_distance:
		return RoomContentTypes.COMBAT
	var roll := rng.randf()
	var cumulative := 0.0
	var weights := {
		RoomContentTypes.TRAP: 0.0 if no_trap else config.weight_trap,
		RoomContentTypes.HAZARD: 0.0 if no_trap else config.weight_hazard,
		RoomContentTypes.COMBAT: config.weight_combat,
		RoomContentTypes.EMPTY: config.weight_empty,
	}
	for content_type in weights:
		cumulative += float(weights[content_type])
		if roll <= cumulative:
			return content_type
	return RoomContentTypes.COMBAT


static func _place_locked_doors(
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	critical_semantic: Array[String],
	distances: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig
) -> Array:
	var candidates: Array = []
	for i in range(1, critical_semantic.size() - 1):
		var from_sem := critical_semantic[i]
		var to_sem := critical_semantic[i + 1]
		if from_sem == layout_semantic.get(graph.stairs_id, "") or to_sem == layout_semantic.get(graph.stairs_id, ""):
			continue
		candidates.append({
			"from": from_sem,
			"to": to_sem,
			"fromLayout": critical_layout[i],
			"toLayout": critical_layout[i + 1],
			"distance": int(distances.get(critical_layout[i + 1], 0)),
			"index": i,
		})
	if candidates.is_empty():
		return []
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return int(a.get("distance", 0)) < int(b.get("distance", 0))
	)
	var lock_count := rng.randi_range(config.min_locks_per_floor, config.max_locks_per_floor)
	lock_count = mini(lock_count, candidates.size())
	var locks: Array = []
	var used_key_rooms: Dictionary = {}
	var step := maxi(1, int(candidates.size() / float(lock_count)))
	var pick_indices: Array[int] = []
	for i in lock_count:
		var idx := mini(i * step, candidates.size() - 1)
		if idx not in pick_indices:
			pick_indices.append(idx)
	while pick_indices.size() < lock_count and pick_indices.size() < candidates.size():
		var extra := rng.randi_range(0, candidates.size() - 1)
		if extra not in pick_indices:
			pick_indices.append(extra)
	for idx in pick_indices:
		var pick: Dictionary = candidates[idx]
		var key_room_layout := _find_key_room_layout(graph, critical_layout, pick, distances)
		if key_room_layout == "":
			continue
		if used_key_rooms.has(key_room_layout):
			continue
		used_key_rooms[key_room_layout] = true
		var lock_id := "lock_%s_%s" % [pick["from"], pick["to"]]
		var key_id := "key_%s_%s" % [pick["from"], pick["to"]]
		locks.append({
			"lockId": lock_id,
			"from": pick["from"],
			"to": pick["to"],
			"keyId": key_id,
			"keyRoomId": layout_semantic.get(key_room_layout, ""),
			"keyLayoutId": key_room_layout,
			"keyLabel": "Key (%s)" % pick["from"].capitalize(),
		})
	return locks


static func _find_key_room_layout(
	graph: RoomGraph,
	critical_layout: Array[String],
	pick: Dictionary,
	distances: Dictionary
) -> String:
	var best_layout := ""
	var best_dist := -1
	for layout_id in critical_layout:
		var dist: int = int(distances.get(layout_id, 0))
		if dist >= int(pick.get("distance", 0)):
			continue
		if layout_id == graph.start_id:
			continue
		if not RoomGraphPaths.is_on_branch_to(graph, layout_id, pick.get("toLayout", "")):
			continue
		if dist > best_dist:
			best_dist = dist
			best_layout = layout_id
	return best_layout


static func _apply_key_to_content(room_content: Array, lock: Dictionary) -> void:
	for entry in room_content:
		if entry.get("roomId", "") == lock.get("keyRoomId", ""):
			entry["contentType"] = RoomContentTypes.LOCKED_VAULT
			entry["templateId"] = RoomContentTypes.TEMPLATE_BY_TYPE[RoomContentTypes.LOCKED_VAULT]
			entry["keyId"] = lock.get("keyId", "")
			entry["lockId"] = lock.get("lockId", "")
			entry["keyLabel"] = lock.get("keyLabel", "Dungeon Key")
			return


static func _entry_for_special(room: Dictionary, slot: RoomGraphSlot) -> Dictionary:
	var content_type := RoomContentTypes.COMBAT
	if slot:
		match slot.slot_type:
			RoomGraphSlot.SlotType.BOSS:
				content_type = RoomContentTypes.BOSS
			RoomGraphSlot.SlotType.TREASURE:
				content_type = RoomContentTypes.REWARD
			RoomGraphSlot.SlotType.STAIRS:
				content_type = RoomContentTypes.STAIRS
			RoomGraphSlot.SlotType.START:
				content_type = RoomContentTypes.EMPTY
	return {
		"roomId": room["semantic_id"],
		"layoutId": room["layout_id"],
		"contentType": content_type,
		"templateId": "",
	}


static func _reserved_semantics(
	graph: RoomGraph,
	_assignment: Dictionary,
	layout_semantic: Dictionary
) -> Array[String]:
	var reserved: Array[String] = []
	reserved.append(layout_semantic.get(graph.start_id, "entrance"))
	reserved.append(layout_semantic.get(graph.stairs_id, "stairs"))
	reserved.append(layout_semantic.get(graph.boss_id, "boss"))
	if graph.treasure_id != "":
		reserved.append(layout_semantic.get(graph.treasure_id, "treasure"))
	return reserved


static func _layout_to_semantic(assignment: Dictionary) -> Dictionary:
	var map := {}
	for room in assignment.get("rooms", []):
		map[room["layout_id"]] = room["semantic_id"]
	return map


static func _fallback_assignment(
	graph: RoomGraph,
	assignment: Dictionary,
	layout_semantic: Dictionary,
	critical_semantic: Array[String],
	critical_layout: Array[String],
	distances: Dictionary,
	rng: RandomNumberGenerator
) -> Dictionary:
	var room_content: Array = []
	for room in assignment.get("rooms", []):
		var entry := {
			"roomId": room["semantic_id"],
			"layoutId": room["layout_id"],
			"contentType": RoomContentTypes.COMBAT if room.get("type", "") != "filler" else RoomContentTypes.EMPTY,
			"templateId": "",
		}
		room_content.append(entry)
	var locks: Array = []
	var config := RoomContentConfig.default()
	if critical_semantic.size() >= 4:
		locks = _place_locked_doors(
			graph, layout_semantic, critical_layout, critical_semantic, distances, rng, config
		)
		for lock in locks:
			_apply_key_to_content(room_content, lock)
	return {
		"ok": true,
		"content": {"roomContent": room_content, "locks": locks, "puzzles": []},
		"used_fallback": true,
	}
