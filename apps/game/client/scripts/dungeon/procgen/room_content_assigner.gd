class_name RoomContentAssigner
extends RefCounted


const DungeonQuestCatalogScript := preload("res://scripts/quests/dungeon_quest_catalog.gd")


static func assign(
	graph: RoomGraph,
	assignment: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig = null,
	biome_id: String = "",
	tier: int = 1
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
			graph,
			assignment,
			layout_semantic,
			critical_layout,
			critical_semantic,
			critical_set,
			distances,
			rng,
			config,
			biome_id,
			tier
		)
		if result.get("ok", false):
			return result
		rng.seed = rng.seed + 1_000_003 + attempt
	return _fallback_assignment(
		graph,
		assignment,
		layout_semantic,
		critical_semantic,
		critical_layout,
		distances,
		rng,
		biome_id,
		config,
		tier
	)


static func _try_assign_once(
	graph: RoomGraph,
	assignment: Dictionary,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	critical_semantic: Array[String],
	critical_set: Dictionary,
	distances: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig,
	biome_id: String,
	tier: int = 1
) -> Dictionary:
	var pre_boss_layout := ""
	var boss_idx := critical_layout.find(graph.boss_id)
	if boss_idx > 0:
		pre_boss_layout = critical_layout[boss_idx - 1]
	var room_content: Array = []
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	var no_trap_semantics := reserved_semantics.duplicate()
	for layout_id in critical_layout:
		if layout_id == graph.start_id:
			var start_slot := graph.get_slot(layout_id)
			if start_slot:
				for dir in RoomGraphPaths._dirs():
					var neighbor: RoomGraphSlot = (
						graph.slots.get(start_slot.grid_pos + dir) as RoomGraphSlot
					)
					if neighbor:
						no_trap_semantics.append(layout_semantic.get(neighbor.slot_id, ""))
	var dead_ends: Array[String] = []
	for room in assignment.get("rooms", []):
		var semantic: String = room["semantic_id"]
		var layout_id: String = room["layout_id"]
		var slot := graph.get_slot(layout_id)
		if (
			slot
			and slot.is_dead_end()
			and semantic not in reserved_semantics
			and room.get("type", "") != "filler"
		):
			dead_ends.append(semantic)
	dead_ends.sort()
	for room in assignment.get("rooms", []):
		var semantic: String = room["semantic_id"]
		var layout_id: String = room["layout_id"]
		var slot := graph.get_slot(layout_id)
		if room.get("type", "") == "filler":
			(
				room_content
				. append(
					{
						"roomId": semantic,
						"layoutId": layout_id,
						"contentType": RoomContentTypes.EMPTY,
						"templateId": "",
					}
				)
			)
			continue
		if semantic in reserved_semantics:
			room_content.append(_entry_for_special(room, slot))
			continue
		if layout_id == pre_boss_layout:
			(
				room_content
				. append(
					{
						"roomId": semantic,
						"layoutId": layout_id,
						"contentType": RoomContentTypes.COMBAT,
						"templateId": "",
					}
				)
			)
			continue
		var on_critical := critical_set.has(semantic)
		var dist: int = int(distances.get(layout_id, 0))
		var content_type := _pick_content_type(
			on_critical, dist, semantic in dead_ends, semantic in no_trap_semantics, rng, config
		)
		(
			room_content
			. append(
				{
					"roomId": semantic,
					"layoutId": layout_id,
					"contentType": content_type,
					"templateId": RoomContentTypes.TEMPLATE_BY_TYPE.get(content_type, ""),
				}
			)
		)
	_enforce_pacing(room_content, critical_semantic, reserved_semantics, config, rng)
	var locks: Array = []
	if config.enable_locked_door and critical_semantic.size() >= 4:
		locks = _place_locked_doors(
			graph,
			layout_semantic,
			critical_layout,
			critical_semantic,
			distances,
			rng,
			config,
			reserved_semantics
		)
		for lock in locks:
			_apply_key_to_content(room_content, lock, reserved_semantics)
	var puzzles := _finalize_content_entries(
		room_content,
		graph,
		layout_semantic,
		critical_set,
		rng,
		biome_id,
		reserved_semantics,
		tier
	)
	var content := {
		"roomContent": room_content,
		"locks": locks,
		"puzzles": puzzles,
	}
	var validation := RoomContentValidator.validate(graph, assignment, content, config)
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
		var dead_roll := rng.randf()
		if dead_roll < 0.30:
			return RoomContentTypes.LORE
		if dead_roll < 0.55:
			return RoomContentTypes.REWARD
		if dead_roll < 0.65:
			return RoomContentTypes.EMPTY
		if dead_roll < 0.85:
			return RoomContentTypes.COMBAT
		return RoomContentTypes.EMPTY
	if on_critical:
		if distance > 0 and distance % 4 == 0:
			if _rest_allowed() and rng.randf() < 0.65:
				return RoomContentTypes.REST
			return RoomContentTypes.EMPTY
		if distance <= 2:
			return RoomContentTypes.COMBAT if rng.randf() < 0.75 else RoomContentTypes.EMPTY
		return RoomContentTypes.COMBAT if rng.randf() < 0.88 else RoomContentTypes.EMPTY
	if distance < config.min_off_path_distance:
		return RoomContentTypes.COMBAT
	var weights := {
		RoomContentTypes.TRAP: 0.0 if no_trap else config.weight_trap,
		RoomContentTypes.HAZARD: 0.0 if no_trap else config.weight_hazard,
		RoomContentTypes.PUZZLE: config.weight_puzzle if config.weight_puzzle > 0.0 else 0.0,
		RoomContentTypes.NPC_QUEST:
		(
			config.weight_npc_quest
			if config.enable_npc_quest and config.weight_npc_quest > 0.0
			else 0.0
		),
		RoomContentTypes.COMBAT: config.weight_combat,
		RoomContentTypes.EMPTY: config.weight_empty,
		RoomContentTypes.REWARD: config.weight_reward,
		RoomContentTypes.LORE: config.weight_lore,
		RoomContentTypes.REST: 0.0 if not _rest_allowed() else config.weight_rest,
		RoomContentTypes.MERCHANT: config.weight_merchant,
	}
	var total := 0.0
	for weight in weights.values():
		total += float(weight)
	if total <= 0.0:
		return RoomContentTypes.COMBAT
	var roll := rng.randf() * total
	var acc := 0.0
	for content_type in weights:
		acc += float(weights[content_type])
		if roll < acc:
			return content_type
	return RoomContentTypes.EMPTY


static func _rest_allowed() -> bool:
	return not RunModifierService.has_modifier(RunModifierService.MODIFIER_NO_REST)


static func _enforce_pacing(
	room_content: Array,
	critical_semantic: Array[String],
	reserved_semantics: Array[String],
	config: RoomContentConfig,
	rng: RandomNumberGenerator
) -> void:
	var by_room := {}
	for entry in room_content:
		if entry is Dictionary:
			by_room[str((entry as Dictionary).get("roomId", ""))] = entry
	_break_combat_runs(room_content, critical_semantic, by_room, reserved_semantics, config)
	_guarantee_type(
		room_content,
		by_room,
		reserved_semantics,
		RoomContentTypes.REWARD,
		config.min_reward_rooms,
		critical_semantic,
		rng
	)
	if config.min_rest_rooms > 0 and _rest_allowed():
		_guarantee_rest_before_boss(
			room_content, by_room, critical_semantic, reserved_semantics, config
		)


static func _set_content_type(entry: Dictionary, content_type: String) -> void:
	entry["contentType"] = content_type
	entry["templateId"] = str(RoomContentTypes.TEMPLATE_BY_TYPE.get(content_type, ""))


static func _is_mutable(entry: Dictionary, reserved_semantics: Array[String]) -> bool:
	var room_id := str(entry.get("roomId", ""))
	if room_id in reserved_semantics or room_id.begins_with("filler_"):
		return false
	var content_type := str(entry.get("contentType", ""))
	if content_type in [
		RoomContentTypes.BOSS,
		RoomContentTypes.STAIRS,
		RoomContentTypes.LOCKED_VAULT,
		RoomContentTypes.NPC_QUEST,
		RoomContentTypes.PUZZLE,
	]:
		return false
	return str(entry.get("templateId", "")) != "" or content_type != ""


static func _break_combat_runs(
	_room_content: Array,
	critical_semantic: Array[String],
	by_room: Dictionary,
	reserved_semantics: Array[String],
	config: RoomContentConfig
) -> void:
	if config.max_consecutive_combat <= 0:
		return
	var streak := 0
	for room_id in critical_semantic:
		var entry: Variant = by_room.get(room_id)
		if not entry is Dictionary:
			streak = 0
			continue
		if str((entry as Dictionary).get("contentType", "")) != RoomContentTypes.COMBAT:
			streak = 0
			continue
		streak += 1
		if streak <= config.max_consecutive_combat:
			continue
		if not _is_mutable(entry as Dictionary, reserved_semantics):
			continue
		var relief := RoomContentTypes.LORE
		if _rest_allowed() and streak > config.max_consecutive_combat + 1:
			relief = RoomContentTypes.REST
		_set_content_type(entry as Dictionary, relief)
		streak = 0


static func _guarantee_type(
	room_content: Array,
	by_room: Dictionary,
	reserved_semantics: Array[String],
	content_type: String,
	minimum: int,
	critical_semantic: Array[String],
	rng: RandomNumberGenerator
) -> void:
	if minimum <= 0:
		return
	var present := 0
	for entry in room_content:
		if entry is Dictionary and str((entry as Dictionary).get("contentType", "")) == content_type:
			present += 1
	if present >= minimum:
		return
	var candidates: Array[Dictionary] = []
	for entry in room_content:
		if not entry is Dictionary:
			continue
		var room_id := str((entry as Dictionary).get("roomId", ""))
		if room_id in critical_semantic:
			continue
		if not _is_mutable(entry as Dictionary, reserved_semantics):
			continue
		if str((entry as Dictionary).get("contentType", "")) == content_type:
			continue
		candidates.append(entry as Dictionary)
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a.get("roomId", "")) < str(b.get("roomId", ""))
	)
	while present < minimum and not candidates.is_empty():
		var idx := rng.randi_range(0, candidates.size() - 1)
		_set_content_type(candidates[idx], content_type)
		candidates.remove_at(idx)
		present += 1
	if present < minimum:
		for room_id in critical_semantic:
			if present >= minimum:
				break
			var entry: Variant = by_room.get(room_id)
			if not entry is Dictionary:
				continue
			if not _is_mutable(entry as Dictionary, reserved_semantics):
				continue
			if str((entry as Dictionary).get("contentType", "")) == content_type:
				continue
			_set_content_type(entry as Dictionary, content_type)
			present += 1


static func _guarantee_rest_before_boss(
	room_content: Array,
	by_room: Dictionary,
	critical_semantic: Array[String],
	reserved_semantics: Array[String],
	config: RoomContentConfig
) -> void:
	if critical_semantic.size() < 3:
		return
	var window := maxi(1, config.rest_within_of_boss)
	var start_index := maxi(0, critical_semantic.size() - 1 - window)
	for i in range(critical_semantic.size() - 2, start_index - 1, -1):
		var entry: Variant = by_room.get(critical_semantic[i])
		if entry is Dictionary and str((entry as Dictionary).get("contentType", "")) == RoomContentTypes.REST:
			return
	for i in range(critical_semantic.size() - 2, start_index - 1, -1):
		var entry: Variant = by_room.get(critical_semantic[i])
		if not entry is Dictionary:
			continue
		if not _is_mutable(entry as Dictionary, reserved_semantics):
			continue
		_set_content_type(entry as Dictionary, RoomContentTypes.REST)
		return
	for entry in room_content:
		if not entry is Dictionary:
			continue
		if str((entry as Dictionary).get("contentType", "")) == RoomContentTypes.REST:
			return
	for entry in room_content:
		if entry is Dictionary and _is_mutable(entry as Dictionary, reserved_semantics):
			_set_content_type(entry as Dictionary, RoomContentTypes.REST)
			return


static func _place_locked_doors(
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	critical_semantic: Array[String],
	distances: Dictionary,
	rng: RandomNumberGenerator,
	config: RoomContentConfig,
	reserved_semantics: Array[String]
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
		var key_room_layout := _find_key_room_layout(
			graph,
			layout_semantic,
			critical_layout,
			pick,
			distances,
			reserved_semantics,
			rng
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
				rng
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


static func _find_key_room_layout(
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_layout: Array[String],
	pick: Dictionary,
	distances: Dictionary,
	reserved_semantics: Array[String],
	rng: RandomNumberGenerator
) -> String:
	var from_layout := str(pick.get("fromLayout", ""))
	var to_layout := str(pick.get("toLayout", ""))
	var reachable := _reachable_without_edge(graph, from_layout, to_layout)
	var candidates: Array[Dictionary] = []
	for layout_id in reachable.keys():
		if layout_id == graph.start_id or layout_id == graph.stairs_id:
			continue
		var semantic := str(layout_semantic.get(layout_id, ""))
		if semantic in reserved_semantics:
			continue
		if layout_id in critical_layout:
			continue
		if not RoomGraphPaths.is_on_branch_to(graph, layout_id, to_layout):
			continue
		var off_depth := RoomGraphPaths.branch_depth_for_slot(graph, layout_id)
		if off_depth < 1:
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
	var best_off := -1
	var best_dist := -1
	for candidate in candidates:
		best_off = maxi(best_off, int(candidate.get("offDepth", 0)))
		best_dist = maxi(best_dist, int(candidate.get("distance", 0)))
	var tied: Array[Dictionary] = []
	for candidate in candidates:
		if (
			int(candidate.get("offDepth", 0)) == best_off
			and int(candidate.get("distance", 0)) == best_dist
		):
			tied.append(candidate)
	return str(tied[rng.randi_range(0, tied.size() - 1)].get("layoutId", ""))


static func _reachable_without_edge(
	graph: RoomGraph, from_layout: String, to_layout: String
) -> Dictionary:
	var adj := RoomGraphPaths.build_adjacency(graph)
	if adj.has(from_layout):
		var neighbors: Array = adj[from_layout]
		var filtered: Array = []
		for neighbor_id in neighbors:
			if neighbor_id != to_layout:
				filtered.append(neighbor_id)
		adj[from_layout] = filtered
	var reachable := {graph.start_id: true}
	var queue: Array[String] = [graph.start_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in adj.get(current, []):
			if reachable.has(next_id):
				continue
			reachable[next_id] = true
			queue.append(next_id)
	return reachable


static func _revert_key_rooms(room_content: Array, lock: Dictionary) -> void:
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


static func _apply_key_to_content(
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


static func _finalize_content_entries(
	room_content: Array,
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_set: Dictionary,
	rng: RandomNumberGenerator,
	biome_id: String,
	reserved_semantics: Array[String],
	tier: int = 1
) -> Array:
	var puzzles: Array = []
	for entry in room_content:
		if not entry is Dictionary:
			continue
		var content_type := str(entry.get("contentType", ""))
		var room_id := str(entry.get("roomId", ""))
		if content_type == RoomContentTypes.REWARD or content_type == RoomContentTypes.LOCKED_VAULT:
			entry["items"] = _roll_chest_items(biome_id, rng, room_id, content_type, tier)
		if content_type == RoomContentTypes.NPC_QUEST:
			var quest := _pick_dungeon_quest(biome_id, rng)
			entry["questKeyId"] = str(quest.get("questKeyId", ""))
			entry["dialogueId"] = str(quest.get("dialogueId", "dungeon_npc_stranded"))
		if content_type == RoomContentTypes.PUZZLE:
			var puzzle := _build_puzzle_entry(
				entry, graph, layout_semantic, critical_set, rng, reserved_semantics
			)
			if not puzzle.is_empty():
				puzzles.append(puzzle)
				entry["flagId"] = str(puzzle.get("flagId", ""))
	_ensure_quest_reward_items(room_content)
	return puzzles


static func _roll_chest_items(
	biome_id: String,
	rng: RandomNumberGenerator,
	room_id: String,
	content_type: String,
	tier: int = 1
) -> Array:
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome.is_empty():
		return []
	var role := "secret" if content_type == RoomContentTypes.LOCKED_VAULT else "side"
	var table: Array = ProcgenLootRoller.roll_chest(biome, role, maxi(1, tier), rng)
	var items: Array = []
	for i in table.size():
		var row: Dictionary = table[i]
		items.append(
			{
				"itemId": str(row.get("itemId", "")),
				"quantity": int(row.get("quantity", 1)),
				"instanceId": "%s_%d" % [room_id, i],
			}
		)
	return items


static func _pick_dungeon_quest(biome_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var quests := DungeonQuestCatalogScript.quests_for_biome(biome_id)
	if quests.is_empty():
		return {
			"questKeyId": "met_dungeon_npc",
			"dialogueId": "dungeon_npc_stranded",
		}
	return quests[rng.randi_range(0, quests.size() - 1)]


static func _build_puzzle_entry(
	entry: Dictionary,
	graph: RoomGraph,
	layout_semantic: Dictionary,
	critical_set: Dictionary,
	rng: RandomNumberGenerator,
	reserved_semantics: Array[String]
) -> Dictionary:
	var room_id := str(entry.get("roomId", ""))
	var layout_id := str(entry.get("layoutId", ""))
	var gate_layout := _find_puzzle_gate_layout(
		graph, layout_id, layout_semantic, critical_set, reserved_semantics, rng
	)
	if gate_layout == "":
		return {}
	var lever_count := rng.randi_range(1, 3)
	var flag_id := "puzzle_%s" % room_id
	return {
		"puzzleId": flag_id,
		"roomId": room_id,
		"kind": "lever_gate",
		"flagId": flag_id,
		"gateRoomId": str(layout_semantic.get(gate_layout, "")),
		"gateLayoutId": gate_layout,
		"leverCount": lever_count,
		"solutionOrder": _shuffled_indices(lever_count, rng),
	}


static func _find_puzzle_gate_layout(
	graph: RoomGraph,
	puzzle_layout: String,
	layout_semantic: Dictionary,
	critical_set: Dictionary,
	reserved_semantics: Array[String],
	rng: RandomNumberGenerator
) -> String:
	var adj := RoomGraphPaths.build_adjacency(graph)
	var candidates: Array[Dictionary] = []
	for neighbor_id in adj.get(puzzle_layout, []):
		var semantic := str(layout_semantic.get(neighbor_id, ""))
		if semantic in reserved_semantics or critical_set.has(semantic):
			continue
		var off_depth := RoomGraphPaths.branch_depth_for_slot(graph, neighbor_id)
		if off_depth < 1:
			continue
		(
			candidates
			. append({"layoutId": neighbor_id, "offDepth": off_depth})
		)
	if candidates.is_empty():
		return ""
	candidates.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return int(a.get("offDepth", 0)) > int(b.get("offDepth", 0))
	)
	var best_off := int(candidates[0].get("offDepth", 0))
	var tied: Array[Dictionary] = []
	for candidate in candidates:
		if int(candidate.get("offDepth", 0)) == best_off:
			tied.append(candidate)
	return str(tied[rng.randi_range(0, tied.size() - 1)].get("layoutId", ""))


static func _ensure_quest_reward_items(room_content: Array) -> void:
	for entry in room_content:
		if str(entry.get("contentType", "")) != RoomContentTypes.NPC_QUEST:
			continue
		var quest := DungeonQuestCatalogScript.quest_for_dialogue(str(entry.get("dialogueId", "")))
		var reward_item := str(quest.get("rewardItemId", ""))
		if reward_item == "":
			continue
		if _content_has_item(room_content, reward_item):
			continue
		for candidate in room_content:
			var candidate_type := str(candidate.get("contentType", ""))
			if candidate_type not in [RoomContentTypes.REWARD, RoomContentTypes.LOCKED_VAULT]:
				continue
			var items: Array = candidate.get("items", [])
			items.append(
				{
					"itemId": reward_item,
					"quantity": 1,
					"instanceId": "%s_quest_reward" % entry.get("roomId", ""),
				}
			)
			candidate["items"] = items
			break


static func _content_has_item(room_content: Array, item_id: String) -> bool:
	for entry in room_content:
		for item in entry.get("items", []):
			if str(item.get("itemId", "")) == item_id:
				return true
	return false


static func _shuffled_indices(count: int, rng: RandomNumberGenerator) -> Array:
	var indices: Array = []
	for i in count:
		indices.append(i)
	for i in range(count - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var tmp: int = int(indices[i])
		indices[i] = indices[j]
		indices[j] = tmp
	return indices


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
			RoomGraphSlot.SlotType.SHOP:
				content_type = RoomContentTypes.MERCHANT
			RoomGraphSlot.SlotType.START:
				content_type = RoomContentTypes.EMPTY
	return {
		"roomId": room["semantic_id"],
		"layoutId": room["layout_id"],
		"contentType": content_type,
		"templateId": "",
	}


static func _reserved_semantics(
	graph: RoomGraph, _assignment: Dictionary, layout_semantic: Dictionary
) -> Array[String]:
	var reserved: Array[String] = []
	reserved.append(layout_semantic.get(graph.start_id, "entrance"))
	reserved.append(layout_semantic.get(graph.stairs_id, "stairs"))
	reserved.append(layout_semantic.get(graph.boss_id, "boss"))
	if graph.treasure_id != "":
		reserved.append(layout_semantic.get(graph.treasure_id, "treasure"))
	if graph.shop_id != "":
		reserved.append(layout_semantic.get(graph.shop_id, "shop"))
	return reserved


static func build_branch_previews(
	graph: RoomGraph, assignment: Dictionary, room_content: Array
) -> Array:
	var layout_semantic := _layout_to_semantic(assignment)
	var content_by_room: Dictionary = {}
	for entry in room_content:
		if entry is Dictionary:
			content_by_room[str(entry.get("roomId", ""))] = str(
				entry.get("contentType", RoomContentTypes.COMBAT)
			)
	var critical_layout: Array[String] = RoomGraphPaths.critical_path_ids(graph)
	var critical_layout_set := {}
	for layout_id in critical_layout:
		critical_layout_set[layout_id] = true
	var adj := RoomGraphPaths.build_adjacency(graph)
	var previews: Array = []
	var seen: Dictionary = {}
	for layout_id in adj:
		for neighbor_layout in adj.get(layout_id, []):
			if critical_layout_set.has(neighbor_layout):
				continue
			var from_sem := str(layout_semantic.get(layout_id, layout_id))
			var to_sem := str(layout_semantic.get(neighbor_layout, neighbor_layout))
			var key := "%s>%s" % [from_sem, to_sem]
			if seen.has(key):
				continue
			seen[key] = true
			(
				previews
				. append(
					{
						"fromRoomId": from_sem,
						"toRoomId": to_sem,
						"hint":
						_preview_hint_for_content(
							content_by_room.get(to_sem, RoomContentTypes.COMBAT)
						),
					}
				)
			)
	previews.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			var ak := "%s>%s" % [a.get("fromRoomId", ""), a.get("toRoomId", "")]
			var bk := "%s>%s" % [b.get("fromRoomId", ""), b.get("toRoomId", "")]
			return ak < bk
	)
	return previews


static func _preview_hint_for_content(content_type: String) -> String:
	match content_type:
		RoomContentTypes.REWARD, RoomContentTypes.LORE, RoomContentTypes.REST, RoomContentTypes.MERCHANT, RoomContentTypes.LOCKED_VAULT, RoomContentTypes.NPC_QUEST:
			return "reward"
		RoomContentTypes.EMPTY, RoomContentTypes.PUZZLE:
			return "neutral"
		_:
			return "danger"


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
	rng: RandomNumberGenerator,
	biome_id: String,
	config: RoomContentConfig,
	tier: int
) -> Dictionary:
	var room_content: Array = []
	for room in assignment.get("rooms", []):
		var entry := {
			"roomId": room["semantic_id"],
			"layoutId": room["layout_id"],
			"contentType":
			RoomContentTypes.COMBAT if room.get("type", "") != "filler" else RoomContentTypes.EMPTY,
			"templateId": "",
		}
		room_content.append(entry)
	var locks: Array = []
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	if critical_semantic.size() >= 4:
		locks = _place_locked_doors(
			graph,
			layout_semantic,
			critical_layout,
			critical_semantic,
			distances,
			rng,
			config,
			reserved_semantics
		)
		for lock in locks:
			_apply_key_to_content(room_content, lock, reserved_semantics)
	var critical_set := {}
	for room_id in critical_semantic:
		critical_set[room_id] = true
	var puzzles := _finalize_content_entries(
		room_content,
		graph,
		layout_semantic,
		critical_set,
		rng,
		biome_id,
		reserved_semantics,
		tier
	)
	var content := {"roomContent": room_content, "locks": locks, "puzzles": puzzles}
	var warnings: Array[String] = []
	var check := RoomContentValidator.validate(graph, assignment, content, config)
	if not bool(check.get("ok", false)):
		var reason := str(check.get("reason", "unknown"))
		push_warning(
			"RoomContentAssigner: fallback floor failed validation (%s) — dropping locks" % reason
		)
		warnings.append("fallback_locks_dropped: %s" % reason)
		for lock in locks:
			_revert_key_rooms(room_content, lock)
		locks = []
		content = {"roomContent": room_content, "locks": locks, "puzzles": puzzles}
	return {
		"ok": true,
		"content": content,
		"used_fallback": true,
		"warnings": warnings,
	}
