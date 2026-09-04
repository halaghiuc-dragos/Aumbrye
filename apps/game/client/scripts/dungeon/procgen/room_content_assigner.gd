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
	var result := _assign_impl(graph, assignment, rng, config, biome_id, tier)
	if result.get("ok", false):
		_add_shortcut_gates(graph, assignment, rng, biome_id, tier, result)
		_guarantee_one_way_gate(graph, assignment, rng, biome_id, tier, result)
	return result


static func _assign_impl(
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
	# A floor with no locked door on it is valid but flat, so a lock-free pass is held as a fallback
	# rather than returned outright. Whether a given pass produces a lock depends on which doorway
	# the spread happened to pick and whether a key room was free behind it, so the same graph will
	# often gate on one attempt and not the next -- taking the first valid pass left roughly a third
	# of floors ungated for no reason other than draw order.
	var ungated_result: Dictionary = {}
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
			var locks: Array = result.get("content", {}).get("locks", [])
			if locks.size() >= config.max_locks_per_floor:
				return result
			# Not enough locks yet -- keep the best attempt seen so far rather than the first, since
			# a graph that cannot support the full ring should still ship with as many as it can.
			var best_locks: Array = ungated_result.get("content", {}).get("locks", [])
			if ungated_result.is_empty() or locks.size() > best_locks.size():
				ungated_result = result
		rng.seed = rng.seed + 1_000_003 + attempt
	if not ungated_result.is_empty():
		return ungated_result
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
		# RM-15: a filler used to always get RoomContentTypes.EMPTY here regardless of anything
		# else -- every filler was a room the player walks through with nothing in it, by design,
		# which is what made a fifth of a floor read as pointless space. It now falls through to
		# the same per-room content roll as any other off-path room below.
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
						# RM-07: one lock-in per floor -- the room immediately before the boss, where
						# the game wants to test the player before the real test. See
						# `room_arena_gate_content.gd` for what this flag actually builds.
						"lockIn": true,
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
		var content_by_semantic := RoomLockPlacer.content_by_semantic(room_content)
		locks = RoomLockPlacer.place_locked_doors(
			graph,
			layout_semantic,
			critical_layout,
			critical_semantic,
			distances,
			rng,
			config,
			reserved_semantics,
			false,
			content_by_semantic
		)
		# Second sweep, this time allowing the key to sit on the critical path. Only reached when
		# the floor offered nowhere off-path to hide one, and a gated floor with an obvious key
		# still beats an ungated one.
		if locks.is_empty():
			locks = RoomLockPlacer.place_locked_doors(
				graph,
				layout_semantic,
				critical_layout,
				critical_semantic,
				distances,
				rng,
				config,
				reserved_semantics,
				true,
				content_by_semantic
			)
		for lock in locks:
			RoomLockPlacer.apply_key_to_content(room_content, lock, reserved_semantics)
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
			entry["targetNpcId"] = str(quest.get("targetNpcId", ""))
		if content_type == RoomContentTypes.PUZZLE:
			var puzzle := _build_puzzle_entry(
				entry, graph, layout_semantic, critical_set, rng, reserved_semantics
			)
			if not puzzle.is_empty():
				puzzles.append(puzzle)
				entry["flagId"] = str(puzzle.get("flagId", ""))
	_ensure_quest_reward_items(room_content)
	return puzzles


## One-way circularity: a loop the lattice managed to seat flush becomes a real door the player can
## always walk up to but can only ever open from the side reached the hard way. Approaching from the
## easy side finds it barred -- a warning, not a puzzle, since there is nothing to solve, only a
## longer route to take. The harder side always gets a guaranteed piece of gear: a shortcut nobody
## has a reason to go looking for the hard way isn't a shortcut, it's a wall with a door drawn on it.
static func _add_shortcut_gates(
	graph: RoomGraph,
	assignment: Dictionary,
	rng: RandomNumberGenerator,
	biome_id: String,
	tier: int,
	result: Dictionary
) -> void:
	if graph.loop_edges.is_empty():
		return
	var content: Dictionary = result.get("content", {})
	var room_content: Array = content.get("roomContent", [])
	if room_content.is_empty():
		return
	var layout_semantic := _layout_to_semantic(assignment)
	var distances := RoomGraphPaths.bfs_distances(graph, graph.start_id)
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	var by_room: Dictionary = {}
	for entry in room_content:
		if entry is Dictionary:
			by_room[str((entry as Dictionary).get("roomId", ""))] = entry
	var gates: Array = []
	var used_open_rooms := {}
	for loop_edge in graph.loop_edges:
		var slot_a := graph.get_slot_at(loop_edge["a"])
		var slot_b := graph.get_slot_at(loop_edge["b"])
		if slot_a == null or slot_b == null:
			continue
		var layout_a := slot_a.slot_id
		var layout_b := slot_b.slot_id
		if layout_a in [graph.start_id, graph.boss_id, graph.stairs_id]:
			continue
		if layout_b in [graph.start_id, graph.boss_id, graph.stairs_id]:
			continue
		var sem_a := str(layout_semantic.get(layout_a, ""))
		var sem_b := str(layout_semantic.get(layout_b, ""))
		if sem_a == "" or sem_b == "" or not by_room.has(sem_a) or not by_room.has(sem_b):
			continue
		var dist_a := int(distances.get(layout_a, 0))
		var dist_b := int(distances.get(layout_b, 0))
		var open_sem := sem_a if dist_a >= dist_b else sem_b
		var locked_sem := sem_b if dist_a >= dist_b else sem_a
		if used_open_rooms.has(open_sem):
			continue
		used_open_rooms[open_sem] = true
		gates.append(
			{
				"gateId": "shortcut_%s_%s" % [locked_sem, open_sem],
				"roomA": locked_sem,
				"roomB": open_sem,
				"openRoomId": open_sem,
			}
		)
		var open_entry: Variant = by_room.get(open_sem)
		if open_entry is Dictionary and _is_mutable(open_entry as Dictionary, reserved_semantics):
			_set_content_type(open_entry as Dictionary, RoomContentTypes.REWARD)
			(open_entry as Dictionary)["items"] = _roll_armory_chest_items(
				biome_id, rng, open_sem, tier
			)
	if gates.is_empty():
		return
	content["shortcutGates"] = gates
	result["content"] = content


## RM-04: `_add_shortcut_gates` only fires when the lattice happened to seat a loop flush against
## another room -- a floor where the solver closed no loops gets zero one-way doors, so the
## soulslike "barred door, opened from the far side" beat appears on some floors and not others.
## This guarantees at least one by promoting a dead-end branch when nothing else produced a gate.
##
## Orientation note: `RoomShortcutGateContent`'s barrier physically blocks *both* directions until
## opened, and it can only be opened by a player standing on the `openRoomId` side. A genuine graph
## dead end has exactly one edge -- its only connection to the rest of the floor -- so that edge
## cannot be barred from the dead-end side without making the room (and its chest) permanently
## unreachable. This deliberately orients the gate the other way: `openRoomId` is the dead end's
## *critical-path parent*, which is always already reachable, so the barred door can always be
## opened before it is ever an obstacle. The invariant this file's header states -- a one-way door
## may never be the only route to anything the floor requires -- holds trivially for this
## orientation, and is reverified below via `RoomGraphPaths.reachable_without_edge` before the gate
## is accepted, exactly as it would be for a lock.
static func _guarantee_one_way_gate(
	graph: RoomGraph,
	assignment: Dictionary,
	rng: RandomNumberGenerator,
	biome_id: String,
	tier: int,
	result: Dictionary
) -> void:
	var content: Dictionary = result.get("content", {})
	var existing: Array = content.get("shortcutGates", [])
	if not existing.is_empty():
		return
	var room_content: Array = content.get("roomContent", [])
	if room_content.is_empty():
		return
	var layout_semantic := _layout_to_semantic(assignment)
	var by_room: Dictionary = {}
	for entry in room_content:
		if entry is Dictionary:
			by_room[str((entry as Dictionary).get("roomId", ""))] = entry
	var distances := RoomGraphPaths.bfs_distances(graph, graph.start_id)
	var reserved_semantics := _reserved_semantics(graph, assignment, layout_semantic)
	var candidate_layout := ""
	var candidate_parent_layout := ""
	var best_distance := -1
	for cell in graph.occupied_cells():
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.is_filler or slot.slot_type == RoomGraphSlot.SlotType.SECRET:
			continue
		if not slot.is_dead_end():
			continue
		if slot.slot_id in [graph.start_id, graph.boss_id, graph.stairs_id]:
			continue
		var parent_id := _dead_end_parent_layout_id(graph, slot)
		if parent_id == "":
			continue
		var parent_slot := graph.get_slot(parent_id)
		if parent_slot == null or not parent_slot.on_critical_path:
			continue
		var sem := str(layout_semantic.get(slot.slot_id, ""))
		var candidate_parent_sem := str(layout_semantic.get(parent_id, ""))
		if (
			sem == ""
			or candidate_parent_sem == ""
			or not by_room.has(sem)
			or not by_room.has(candidate_parent_sem)
		):
			continue
		var dist := int(distances.get(slot.slot_id, 0))
		if dist > best_distance:
			best_distance = dist
			candidate_layout = slot.slot_id
			candidate_parent_layout = parent_id
	if candidate_layout == "":
		return
	if not _one_way_gate_is_safe(
		graph, assignment, content, candidate_parent_layout, candidate_layout
	):
		return
	var dead_end_sem := str(layout_semantic.get(candidate_layout, ""))
	var parent_sem := str(layout_semantic.get(candidate_parent_layout, ""))
	var gates: Array = [
		{
			"gateId": "shortcut_deadend_%s" % dead_end_sem,
			"roomA": dead_end_sem,
			"roomB": parent_sem,
			"openRoomId": parent_sem,
		}
	]
	var dead_end_entry: Variant = by_room.get(dead_end_sem)
	if dead_end_entry is Dictionary and _is_mutable(dead_end_entry as Dictionary, reserved_semantics):
		_set_content_type(dead_end_entry as Dictionary, RoomContentTypes.REWARD)
		(dead_end_entry as Dictionary)["items"] = _roll_armory_chest_items(
			biome_id, rng, dead_end_sem, tier
		)
	content["shortcutGates"] = gates
	result["content"] = content


## The dead-end slot's one neighbour, found straight from its door mask rather than from
## `graph.walk_edges` -- a dead end by construction has exactly one open door, so this is
## unambiguous, and it works the same whether that edge came from the walk or from a later loop.
static func _dead_end_parent_layout_id(graph: RoomGraph, slot: RoomGraphSlot) -> String:
	for dir in [Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)]:
		if not (slot.door_mask & RoomGraphGeometry.dir_to_door(dir)):
			continue
		var neighbor := graph.get_slot_at(slot.grid_pos + dir)
		if neighbor != null:
			return neighbor.slot_id
	return ""


## Confirms cutting this edge (in the direction the gate blocks until opened) still leaves the
## boss, the stairs and every key room reachable -- the same soundness test `RoomLockPlacer` runs
## for a lock. The dead end itself is expected to drop out; that is the point of the gate.
static func _one_way_gate_is_safe(
	graph: RoomGraph,
	assignment: Dictionary,
	content: Dictionary,
	parent_layout_id: String,
	dead_end_layout_id: String
) -> bool:
	var reachable := RoomGraphPaths.reachable_without_edge(
		graph, parent_layout_id, dead_end_layout_id
	)
	if graph.boss_id != "" and not reachable.has(graph.boss_id):
		return false
	if graph.stairs_id != "" and not reachable.has(graph.stairs_id):
		return false
	var layout_semantic := _layout_to_semantic(assignment)
	var semantic_layout := {}
	for layout_id in layout_semantic:
		semantic_layout[str(layout_semantic[layout_id])] = layout_id
	var locks: Array = content.get("locks", [])
	for lock in locks:
		if not lock is Dictionary:
			continue
		var key_rooms: Array = (lock as Dictionary).get(
			"keyRoomIds", [(lock as Dictionary).get("keyRoomId", "")]
		)
		for key_sem in key_rooms:
			var key_layout: String = str(semantic_layout.get(str(key_sem), ""))
			if key_layout != "" and not reachable.has(key_layout):
				return false
	return true


## Loot for the room on the far side of a one-way shortcut -- rolled from the armory table rather
## than the general side-room table, and topped up with a forced pick if the roll came back without
## one, so the reward for taking the hard way around is never just consumables.
static func _roll_armory_chest_items(
	biome_id: String, rng: RandomNumberGenerator, room_id: String, tier: int
) -> Array:
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome.is_empty():
		return []
	var table: Array = ProcgenLootRoller.roll_chest(biome, "armory", maxi(1, tier), rng)
	var has_equipment := false
	for row in table:
		if _is_equipment_item(str(row.get("itemId", ""))):
			has_equipment = true
			break
	if not has_equipment:
		var armory_table: Array = biome.get("lootTables", {}).get("armory", [])
		var forced := _pick_equipment_entry(armory_table, tier, rng)
		if not forced.is_empty():
			table.append(forced)
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


static func _is_equipment_item(item_id: String) -> bool:
	if item_id.is_empty():
		return false
	return str(ItemCatalog.get_definition(item_id).get("equipmentSlot", "")) != ""


static func _pick_equipment_entry(
	table: Array, tier: int, rng: RandomNumberGenerator
) -> Dictionary:
	var eligible: Array = []
	for entry in table:
		var item_id := str(entry.get("itemId", ""))
		if int(entry.get("minTier", 1)) > tier:
			continue
		if _is_equipment_item(item_id):
			eligible.append(entry)
	if eligible.is_empty():
		return {}
	var entry: Dictionary = eligible[rng.randi_range(0, eligible.size() - 1)]
	var qty: Variant = entry.get("quantity", 1)
	var quantity := int(qty[0]) if qty is Array and not (qty as Array).is_empty() else int(qty)
	return {"itemId": str(entry.get("itemId", "")), "quantity": maxi(1, quantity)}


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
	# SY-08: the day half of the day/night mechanical tie -- night gets an extra enemy per combat
	# room (`ProcgenPlacements._place_enemies()`'s `night_bonus`), day gets a little extra value in
	# the chests it generates instead.
	var day_bonus := 15.0 if DayNightService and not DayNightService.is_night() else 0.0
	var table: Array = ProcgenLootRoller.roll_chest(biome, role, maxi(1, tier), rng, day_bonus)
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


## SY-02: an accepted escort quest (`content/quests/*.json`, type `escort`) names a `targetNpcId`
## that used to never actually appear in a run -- `dungeon_quests.json`'s matching `rescue_<name>`
## entry now carries the same `targetNpcId`, so an active escort quest's NPC is preferred over the
## uniform-random pick whenever this biome can place it.
static func _pick_dungeon_quest(biome_id: String, rng: RandomNumberGenerator) -> Dictionary:
	var quests := DungeonQuestCatalogScript.quests_for_biome(biome_id)
	if quests.is_empty():
		return {
			"questKeyId": "met_dungeon_npc",
			"dialogueId": "dungeon_npc_stranded",
		}
	if QuestService:
		var active_targets: Dictionary = {}
		for quest_def in QuestService.get_active_quests():
			if str(quest_def.get("type", "")) != "escort":
				continue
			var target_npc := str(quest_def.get("targetNpcId", ""))
			if target_npc != "":
				active_targets[target_npc] = true
		if not active_targets.is_empty():
			for quest in quests:
				if active_targets.has(str(quest.get("targetNpcId", ""))):
					return quest
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
		locks = RoomLockPlacer.place_locked_doors(
			graph,
			layout_semantic,
			critical_layout,
			critical_semantic,
			distances,
			rng,
			config,
			reserved_semantics,
			false,
			RoomLockPlacer.content_by_semantic(room_content)
		)
		for lock in locks:
			RoomLockPlacer.apply_key_to_content(room_content, lock, reserved_semantics)
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
		# Peel one lock at a time rather than clearing them all. It is usually a single bad lock
		# that sinks the check -- one whose key room the fallback could not actually furnish -- and
		# discarding its siblings with it is what left these floors with no gating at all.
		warnings.append("fallback_locks_peeled: %s" % reason)
		while not locks.is_empty():
			var dropped: Dictionary = locks.pop_back()
			RoomLockPlacer.revert_key_rooms(room_content, dropped)
			content = {"roomContent": room_content, "locks": locks, "puzzles": puzzles}
			if locks.is_empty():
				break
			if bool(
				RoomContentValidator.validate(graph, assignment, content, config).get("ok", false)
			):
				break
		content = {"roomContent": room_content, "locks": locks, "puzzles": puzzles}
	return {
		"ok": true,
		"content": content,
		"used_fallback": true,
		"warnings": warnings,
	}
