class_name RoomLockPlacer
extends RefCounted

## Everything about hiding a key behind a locked door: picking which doorway on the critical path
## gets a lock, finding a room to hide its key that is reachable with the door shut, and writing
## the result into a floor's room-content entries. Split out of `RoomContentAssigner` because this
## is a genuinely separate concern from the rest of content assignment (deciding what a room *is*)
## with its own soundness rule (a key can never sit behind its own lock) and its own history of
## subtle bugs from that rule -- see the comments below.


static func content_by_semantic(room_content: Array) -> Dictionary:
	var out := {}
	for entry in room_content:
		if entry is Dictionary:
			out[str(entry.get("roomId", ""))] = str(entry.get("contentType", ""))
	return out


static func place_locked_doors(
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	critical_semantic: Array[String],
	distances: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig,
	reserved_semantics: Array[String],
	allow_on_path: bool = false,
	content_by_semantic_map: Dictionary = {}
) -> Array:
	var candidates: Array = []
	for i in range(1, critical_semantic.size() - 1):
		var from_sem := critical_semantic[i]
		var to_sem := critical_semantic[i + 1]
		if (
			from_sem == layout_semantic.get(graph.stairs_id, "")
			or to_sem == layout_semantic.get(graph.stairs_id, "")
		):
			continue
		(
			candidates
			. append(
				{
					"from": from_sem,
					"to": to_sem,
					"fromLayout": critical_layout[i],
					"toLayout": critical_layout[i + 1],
					"distance": int(distances.get(critical_layout[i + 1], 0)),
					"index": i,
				}
			)
		)
	if candidates.is_empty():
		return []
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("distance", 0)) < int(b.get("distance", 0))
	)
	# Always aim for the full ring -- a graph that cannot fit that many locks falls short on its own
	# (the candidate sweep below just returns fewer), so there is no benefit to rolling a lower target
	# up front the way `min_locks_per_floor` might suggest.
	var lock_count := config.max_locks_per_floor
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
	# Everything the spread did not choose, deepest first, as fallback.
	#
	# A pick whose key room cannot be found is not a reason to ship a floor with no locked door at
	# all. The spread picks evenly from a list sorted nearest-first, so index 0 is the doorway
	# closest to the entrance -- exactly the one least likely to have a side branch in front of it
	# to hide a key in. A floor asking for a single lock therefore drew the worst candidate almost
	# every time and gave up. Sweeping the rest costs a few more searches and is the difference
	# between roughly half the floors being gated and nearly all of them.
	var ordered_indices: Array[int] = pick_indices.duplicate()
	var remaining: Array[int] = []
	for idx in range(candidates.size()):
		if idx not in pick_indices:
			remaining.append(idx)
	remaining.reverse()
	ordered_indices.append_array(remaining)
	for idx in ordered_indices:
		if locks.size() >= lock_count:
			break
		var pick: Dictionary = candidates[idx]
		var key_room_layout := _find_key_room_layout(
			graph,
			layout_semantic,
			critical_layout,
			pick,
			distances,
			reserved_semantics,
			rng,
			used_key_rooms,
			allow_on_path,
			content_by_semantic_map
		)
		if key_room_layout == "":
			continue
		if used_key_rooms.has(key_room_layout):
			continue
		used_key_rooms[key_room_layout] = true
		var key_layouts: Array[String] = [key_room_layout]
		var wanted_keys := (
			2
			if RunModifierService.has_modifier(RunModifierService.MODIFIER_SEALED_DOORS)
			else 1
		)
		while key_layouts.size() < wanted_keys:
			var extra_layout := _find_key_room_layout(
				graph,
				layout_semantic,
				critical_layout,
				pick,
				distances,
				reserved_semantics,
				rng,
				used_key_rooms,
				allow_on_path,
				content_by_semantic_map
			)
			if extra_layout == "" or used_key_rooms.has(extra_layout):
				break
			used_key_rooms[extra_layout] = true
			key_layouts.append(extra_layout)
		var lock_id := "lock_%s_%s" % [pick["from"], pick["to"]]
		var key_id := "key_%s_%s" % [pick["from"], pick["to"]]
		(
			locks
			. append(
				{
					"lockId": lock_id,
					"from": pick["from"],
					"to": pick["to"],
					"keyId": key_id,
					"keyRoomId": layout_semantic.get(key_room_layout, ""),
					"keyLayoutId": key_room_layout,
					"keyRoomIds": _semantics_for_layouts(layout_semantic, key_layouts),
					"keyLayoutIds": key_layouts,
					"keyLabel": "Key (%s)" % pick["from"].capitalize(),
					"keysRequired": key_layouts.size(),
				}
			)
		)
	return locks


## Where to hide the key for one locked door.
##
## `allow_on_path` is the fallback sweep. A key is far better hidden down a side branch, but a floor
## whose approach to the lock is a plain corridor run has no side branch to hide it in, and shipping
## that floor ungated is worse than putting the key in a room the player walks through anyway. The
## room is still reachable with the door shut either way, which is the part that has to hold.
static func _find_key_room_layout(
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	pick: Dictionary,
	distances: Dictionary,
	reserved_semantics: Array[String],
	rng: RandomNumberGenerator,
	used_key_rooms: Dictionary = {},
	allow_on_path: bool = false,
	content_by_semantic_map: Dictionary = {}
) -> String:
	var from_layout := str(pick.get("fromLayout", ""))
	var to_layout := str(pick.get("toLayout", ""))
	var reachable := RoomGraphPaths.reachable_without_edge(graph, from_layout, to_layout)
	var candidates: Array[Dictionary] = []
	for layout_id in reachable.keys():
		if layout_id == graph.start_id or layout_id == graph.stairs_id:
			continue
		if layout_id == graph.boss_id:
			continue
		# Handing the same room out twice would gate two doors behind one key.
		if used_key_rooms.has(layout_id):
			continue
		var semantic := str(layout_semantic.get(layout_id, ""))
		if semantic in reserved_semantics:
			continue
		# A key cannot sit in a room with no container to put it in -- an empty room, or one already
		# reserved for the boss/stairs. Content types are assigned before locks are placed, so this
		# is the only place that knows which off-path rooms actually have somewhere to hide a key.
		var existing_content := str(content_by_semantic_map.get(semantic, ""))
		if existing_content in [
			RoomContentTypes.EMPTY, RoomContentTypes.BOSS, RoomContentTypes.STAIRS
		]:
			continue
		if not allow_on_path and layout_id in critical_layout:
			continue
		# `reachable` was already built with the locked edge cut, so every room left in it is one
		# the player can walk to with the door shut. That is the whole soundness requirement, and
		# it is why there is no ancestry test here any more.
		#
		# There used to be one: the room had to be an ancestor of `to_layout`, the room *behind*
		# the door. On a breadth-first tree every ancestor of a critical-path room is itself on the
		# critical path, and the line above rejects those -- so the two conditions could never both
		# hold and this function returned "" for every candidate on every floor. No floor in the
		# game has ever had a locked door on it.
		var off_depth := RoomGraphPaths.branch_depth_for_slot(graph, layout_id)
		if off_depth < 1 and not allow_on_path:
			continue
		(
			candidates
			. append(
				{
					"layoutId": layout_id,
					"offDepth": off_depth,
					"distance": int(distances.get(layout_id, 0)),
				}
			)
		)
	if candidates.is_empty():
		return ""
	# Deepest down a side branch first, then furthest from the entrance -- a key is worth hiding.
	#
	# These two maxima used to be taken independently and then required together, which asks for a
	# candidate that is both the deepest *and* the furthest. Usually no one room is both, so the
	# tied list came out empty and the function indexed off the end of it and yielded "" -- it
	# discarded a perfectly good key room roughly nineteen times in twenty.
	var best_off := -1
	var best_dist := -1
	for candidate in candidates:
		var off := int(candidate.get("offDepth", 0))
		var dist := int(candidate.get("distance", 0))
		if off > best_off or (off == best_off and dist > best_dist):
			best_off = off
			best_dist = dist
	var tied: Array[Dictionary] = []
	for candidate in candidates:
		if (
			int(candidate.get("offDepth", 0)) == best_off
			and int(candidate.get("distance", 0)) == best_dist
		):
			tied.append(candidate)
	if tied.is_empty():
		return ""
	return str(tied[rng.randi_range(0, tied.size() - 1)].get("layoutId", ""))


static func revert_key_rooms(room_content: Array, lock: Dictionary) -> void:
	var key_rooms: Array = lock.get("keyRoomIds", [lock.get("keyRoomId", "")])
	for entry in room_content:
		if str(entry.get("roomId", "")) not in key_rooms:
			continue
		if str(entry.get("contentType", "")) != RoomContentTypes.LOCKED_VAULT:
			continue
		entry["contentType"] = RoomContentTypes.REWARD
		entry["templateId"] = RoomContentTypes.TEMPLATE_BY_TYPE[RoomContentTypes.REWARD]
		entry.erase("keyId")
		entry.erase("lockId")
		entry.erase("keyLabel")


static func _semantics_for_layouts(
	layout_semantic: Dictionary, layouts: Array[String]
) -> Array[String]:
	var out: Array[String] = []
	for layout in layouts:
		out.append(str(layout_semantic.get(layout, "")))
	return out


static func apply_key_to_content(
	room_content: Array, lock: Dictionary, reserved_semantics: Array[String]
) -> void:
	var key_rooms: Array = lock.get("keyRoomIds", [lock.get("keyRoomId", "")])
	for entry in room_content:
		if str(entry.get("roomId", "")) not in key_rooms:
			continue
		var room_id := str(entry.get("roomId", ""))
		if room_id in reserved_semantics:
			push_error("Key room %s is reserved semantics" % room_id)
			return
		var content_type := str(entry.get("contentType", ""))
		if content_type in [
			RoomContentTypes.BOSS, RoomContentTypes.STAIRS, RoomContentTypes.EMPTY
		]:
			push_error("Key room %s has reserved content type %s" % [room_id, content_type])
			return
		entry["contentType"] = RoomContentTypes.LOCKED_VAULT
		entry["templateId"] = RoomContentTypes.TEMPLATE_BY_TYPE[RoomContentTypes.LOCKED_VAULT]
		entry["keyId"] = lock.get("keyId", "")
		entry["lockId"] = lock.get("lockId", "")
		entry["keyLabel"] = lock.get("keyLabel", "Dungeon Key")
	return
