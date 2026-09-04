class_name ProcgenPlacements
extends RefCounted


static var _threat_cost_cache: Dictionary = {}


static func place(
	biome: Dictionary,
	assignment: Dictionary,
	run_seed: int,
	tier: int,
	player_level: int,
	floor_index: int,
	graph: RoomGraph = null
) -> Dictionary:
	var enemies_rng := ProcgenRng.stream(run_seed, "enemies")
	var loot_rng := ProcgenRng.stream(run_seed, "loot")
	var traps_rng := ProcgenRng.stream(run_seed, "traps")
	var cover_rng := ProcgenRng.stream(run_seed, "cover")
	var boss_rng := ProcgenRng.stream_with_mix(run_seed, "boss", tier * 1009 + floor_index * 9176)
	var enemies_result := _place_enemies(
		biome, assignment, run_seed, tier, player_level, enemies_rng, graph
	)
	var loot_result := _place_loot(
		biome,
		assignment,
		run_seed,
		tier,
		floor_index,
		loot_rng,
		traps_rng,
		boss_rng,
		graph
	)
	if not loot_result.get("ok", true):
		return loot_result
	var cover := _place_cover(biome, assignment, run_seed, cover_rng)
	return {
		"ok": true,
		"enemies": enemies_result["enemies"],
		"loot": loot_result["loot"],
		"puzzles": [],
		"traps": loot_result["traps"],
		"secrets": loot_result["secrets"],
		"cover": cover,
		"boss": loot_result["boss"],
		"exit": loot_result["exit"],
		"entrance": loot_result["entrance"],
		"threat_used": enemies_result["threat_used"],
		"loot_value": loot_result["loot_value"],
	}


static func _place_enemies(
	biome: Dictionary,
	assignment: Dictionary,
	run_seed: int,
	tier: int,
	player_level: int,
	rng: RandomNumberGenerator,
	graph: RoomGraph = null
) -> Dictionary:
	var biome_id := str(biome.get("id", ""))
	var elite_rule := (
		RunModifierService.has_modifier(RunModifierService.MODIFIER_ELITE_PACKS)
		or RunModifierService.has_modifier(RunModifierService.MODIFIER_ELITE_VIGIL)
	)
	var elites_required := 0
	if RunModifierService.has_modifier(RunModifierService.MODIFIER_ELITE_VIGIL):
		elites_required = 1
	var budgets: Dictionary = biome.get("budgets", {})
	var combat_rooms: Array = _sorted_combat_rooms(assignment)
	# A flat per-floor budget starved most rooms once floors grew past a handful of encounters --
	# the first several combat rooms in sort order spent the whole budget and every room after them
	# came up empty. Every combat room earns a guaranteed cheapest-enemy slot before anything spends
	# on the depth-based bonus below, so a floor with more encounters gets a floor that can afford
	# them instead of silently going quiet past room six or seven.
	var min_cost := _cheapest_enemy_cost(biome)
	var budget := maxf(
		(
			float(budgets.get("baseEnemyThreat", 200))
			+ float(budgets.get("threatPerTier", 35)) * float(tier - 1)
			+ float(player_level) * 5.0
		),
		float(combat_rooms.size()) * min_cost
	)
	var placements: Array = []
	var state := {"threat_used": 0.0, "elites_placed": 0}
	var door_distances := {}
	if graph != null:
		door_distances = RoomGraphPaths.bfs_distances(graph, graph.start_id)
	var room_anchor_idx := {}
	var room_max: Dictionary = {}
	for room in combat_rooms:
		var room_id := str(room.get("semantic_id", ""))
		room_anchor_idx[room_id] = 0
		var depth := 0
		if graph != null:
			var layout_id: String = room.get("layout_id", "")
			depth = int(door_distances.get(layout_id, 0))
		room_max[room_id] = clampi(1 + int(depth / 3.0) + int((tier - 1) / 2.0), 1, 4)
	# Pass one: every combat room gets its guaranteed first enemy before any room gets a second.
	for room in combat_rooms:
		var anchors: Array = _room_anchors(biome_id, run_seed, room, "enemy")
		var placed: Dictionary = _attempt_place_enemy(
			biome, room, anchors, room_anchor_idx, rng, budget, state, elite_rule,
			elites_required, true
		)
		if not placed.is_empty():
			placements.append(placed)
	# Pass two: rooms that want more than one (deeper rooms, higher tiers) fill in with whatever
	# budget is left, deepest first so the bonus favours the encounters it was meant for.
	var deeper_first := combat_rooms.duplicate()
	if graph != null:
		deeper_first.sort_custom(
			func(a: Dictionary, b: Dictionary) -> bool:
				var da: int = door_distances.get(str(a.get("layout_id", "")), 0)
				var db: int = door_distances.get(str(b.get("layout_id", "")), 0)
				return da > db
		)
	# RM-08: at most one ambush on the floor, and only on a room's second-or-later enemy (never the
	# guaranteed first one from pass one above, so a room always reads as inhabited from the
	# doorway). Eligible = depth from entrance >= 3 and not the entrance or one of its neighbours
	# (`_spawn_safe_room_ids`) -- an ambush in the first two rooms teaches the wrong lesson before
	# the player has any sense of the floor's danger at all.
	var unsafe_layout_ids := _spawn_safe_room_ids(graph)
	state["ambush_placed"] = false
	for extra_slot in range(1, 4):
		for room in deeper_first:
			var room_id := str(room.get("semantic_id", ""))
			if extra_slot >= int(room_max.get(room_id, 1)):
				continue
			var layout_id := str(room.get("layout_id", ""))
			var depth: int = int(door_distances.get(layout_id, 0))
			var ambush_eligible := (
				not bool(state["ambush_placed"])
				and depth >= 3
				and not unsafe_layout_ids.has(layout_id)
				and rng.randf() < 0.35
			)
			var anchors: Array = _room_anchors(biome_id, run_seed, room, "enemy")
			var placed: Dictionary = _attempt_place_enemy(
				biome, room, anchors, room_anchor_idx, rng, budget, state, elite_rule,
				elites_required, false, ambush_eligible
			)
			if not placed.is_empty():
				placements.append(placed)
	return {"enemies": placements, "threat_used": state["threat_used"]}


## One placement attempt for `room`, spending from the shared `state` (threat_used, elites_placed).
## Returns the placement dict, or null if nothing affordable could be found in four tries.
static func _attempt_place_enemy(
	biome: Dictionary,
	room: Dictionary,
	anchors: Array,
	room_anchor_idx: Dictionary,
	rng: RandomNumberGenerator,
	budget: float,
	state: Dictionary,
	elite_rule: bool,
	elites_required: int,
	is_first_in_room: bool,
	ambush_eligible: bool = false
) -> Dictionary:
	var room_id := str(room.get("semantic_id", ""))
	for _attempt in 4:
		var entry := _pick_weighted(biome.get("enemyPool", []), rng)
		if entry.is_empty():
			return {}
		var enemy_id: String = str(entry.get("enemyId", ""))
		if _is_reserved_boss_enemy(enemy_id, biome):
			continue
		var threat_cost := _enemy_threat_cost(enemy_id)
		# RM-08: the one floor-wide ambush ignores the shared budget, the same guarantee pass
		# one already gives every room's first enemy -- by the time a room reaches its second
		# or later slot the budget is usually thin, so gating the ambush behind leftover budget
		# meant the 35% roll almost always landed where the placement would fail anyway and
		# nothing ever spawned.
		if float(state["threat_used"]) + threat_cost > budget and not ambush_eligible:
			return {}
		var idx: int = room_anchor_idx.get(room_id, 0)
		# RM-08: an ambush/delayed spawn always takes the last anchor in the list -- a stand-in for
		# "the far anchor" the plan asks for, without the doorway-relative geometry a precise
		# "behind the door the player entered" placement would need.
		var offset: Vector3 = anchors[anchors.size() - 1] if ambush_eligible else anchors[idx % anchors.size()]
		room_anchor_idx[room_id] = idx + 1
		var is_elite := false
		if elite_rule and is_first_in_room:
			if int(state["elites_placed"]) < elites_required or rng.randf() < 0.3:
				is_elite = true
				state["elites_placed"] = int(state["elites_placed"]) + 1
		state["threat_used"] = float(state["threat_used"]) + threat_cost
		var placement := {
			"roomId": room_id,
			"enemyId": enemy_id,
			"offset": _vec_dict(offset),
			"sampleNavmesh": true,
			"isElite": is_elite,
		}
		if ambush_eligible:
			placement["trigger"] = "ambush"
			state["ambush_placed"] = true
		return placement
	return {}


## The cheapest non-boss enemy in the biome's pool, in threat points -- the unit the guaranteed
## per-room budget floor is measured in, so a floor with more combat rooms always has enough left
## to give every one of them at least its weakest possible encounter.
static func _cheapest_enemy_cost(biome: Dictionary) -> float:
	var cheapest := 20.0
	var found := false
	for entry in biome.get("enemyPool", []):
		var enemy_id := str(entry.get("enemyId", ""))
		if _is_reserved_boss_enemy(enemy_id, biome):
			continue
		var cost := _enemy_threat_cost(enemy_id)
		if not found or cost < cheapest:
			cheapest = cost
			found = true
	return cheapest


static func _place_loot(
	biome: Dictionary,
	assignment: Dictionary,
	run_seed: int,
	tier: int,
	floor_index: int,
	loot_rng: RandomNumberGenerator,
	traps_rng: RandomNumberGenerator,
	boss_rng: RandomNumberGenerator,
	graph: RoomGraph = null
) -> Dictionary:
	var biome_id := str(biome.get("id", ""))
	var loot: Array = []
	var traps: Array = []
	var secrets: Array = []
	var rooms: Array = assignment.get("rooms", [])
	var treasure_room: Dictionary = _first_room_of_type(rooms, "treasure")
	if not treasure_room.is_empty():
		var chest_anchors: Array = _room_anchors(
			biome_id, run_seed, treasure_room, "chest"
		)
		loot.append(
			_loot_placement(
				treasure_room["semantic_id"],
				"treasure_main",
				chest_anchors[0],
				ProcgenLootRoller.roll_chest(biome, "treasure", tier, loot_rng)
			)
		)
	for room in rooms:
		if room.get("type", "") == "secret":
			var layout_id: String = room.get("layout_id", "")
			var mechanism := "illusory_wall"
			var parent_room_id := ""
			var wall_direction := ""
			if graph != null:
				var secret_slot := graph.get_slot(layout_id)
				if secret_slot:
					mechanism = (
						secret_slot.secret_mechanism
						if secret_slot.secret_mechanism != ""
						else "illusory_wall"
					)
					if secret_slot.secret_parent_id != "":
						for parent_room in rooms:
							if parent_room.get("layout_id", "") == secret_slot.secret_parent_id:
								parent_room_id = parent_room.get("semantic_id", "")
								break
						# The solver's own answer first. It is the only one that survives a secret
						# being rehomed onto a different host, where the two cells are no longer
						# neighbours and the grid delta is not a single step at all.
						var step: Vector2i = secret_slot.secret_parent_dir
						if step == Vector2i.ZERO:
							var parent_slot := graph.get_slot(secret_slot.secret_parent_id)
							if parent_slot != null:
								step = secret_slot.grid_pos - parent_slot.grid_pos
						if absi(step.x) + absi(step.y) == 1:
							var doors := RoomTemplateCatalog.doors_for_step(step.x, step.y)
							wall_direction = _wall_direction_from_mask(int(doors[0]))
			secrets.append(
				{
					"roomId": room["semantic_id"],
					"mechanism": mechanism,
					"parentRoomId": parent_room_id,
					"wallDirection": wall_direction,
				}
			)
			var secret_anchors: Array = _room_anchors(biome_id, run_seed, room, "chest")
			var secret_rank := secrets.size()
			var secret_role := "secret"
			if secret_rank >= 3:
				secret_role = "armory"
			elif secret_rank >= 2 and mechanism == "hidden_lever":
				secret_role = "treasure"
			if not _has_loot_role(biome, secret_role):
				secret_role = "secret"
			var secret_tier := tier + secret_rank - 1
			loot.append(
				_loot_placement(
					room["semantic_id"],
					"secret_vault_%d" % secrets.size(),
					secret_anchors[0],
					ProcgenLootRoller.roll_chest(biome, secret_role, secret_tier, loot_rng)
				)
			)
	var combat_rooms: Array = _sorted_combat_rooms(assignment)
	var side_room_id := ""
	if combat_rooms.size() > 0:
		var side_room: Dictionary = combat_rooms[
			loot_rng.randi_range(0, combat_rooms.size() - 1)
		]
		var side_depth := 0
		if graph != null:
			var distances := RoomGraphPaths.bfs_distances(graph, graph.start_id)
			side_depth = int(distances.get(side_room.get("layout_id", ""), 0))
		var side_role := "side"
		if side_depth >= 6:
			side_role = "armory"
		elif side_depth >= 4:
			side_role = "treasure"
		if RunModifierService.has_modifier(RunModifierService.MODIFIER_RICH_VEINS):
			side_role = "armory" if _has_loot_role(biome, "armory") else "treasure"
		side_room_id = str(side_room.get("semantic_id", ""))
		var side_anchors: Array = _room_anchors(biome_id, run_seed, side_room, "chest")
		loot.append(
			_loot_placement(
				side_room["semantic_id"],
				"%s_side" % side_room["semantic_id"],
				side_anchors[0],
				ProcgenLootRoller.roll_chest(biome, side_role, tier, loot_rng)
			)
		)
	if combat_rooms.size() > 0:
		var armory_pool: Array = combat_rooms
		if combat_rooms.size() > 1 and side_room_id != "":
			armory_pool = []
			for room in combat_rooms:
				if str(room.get("semantic_id", "")) != side_room_id:
					armory_pool.append(room)
			if armory_pool.is_empty():
				armory_pool = combat_rooms
		var armory_room: Dictionary = armory_pool[
			loot_rng.randi_range(0, armory_pool.size() - 1)
		]
		var armory_anchors: Array = _room_anchors(biome_id, run_seed, armory_room, "chest")
		var armory_offset: Vector3 = (
			armory_anchors[1] if armory_anchors.size() > 1 else armory_anchors[0]
		)
		loot.append(
			_loot_placement(
				armory_room["semantic_id"],
				"%s_armory" % armory_room["semantic_id"],
				armory_offset,
				ProcgenLootRoller.roll_chest(biome, "armory", tier, loot_rng)
			)
		)
	var spawn_safe_ids := _spawn_safe_room_ids(graph)
	var corridor: Dictionary = _first_room_of_type(rooms, "corridor", spawn_safe_ids)
	if corridor.is_empty():
		corridor = _first_room_of_type(rooms, "hub", spawn_safe_ids)
	if corridor.is_empty() and graph != null and graph.stairs_id != "":
		for room in rooms:
			if room.get("layout_id", "") == graph.stairs_id:
				corridor = room
				break
	if not corridor.is_empty():
		var trap_anchors: Array = _room_anchors(biome_id, run_seed, corridor, "trap")
		traps.append(
			{
				"roomId": corridor["semantic_id"],
				"trapId": _pick_trap(biome, traps_rng),
				"offset": _vec_dict(trap_anchors[0]),
				"sampleNavmesh": true,
			}
		)
	# Traps go where the player has just stopped being careful, not only in the rooms they chose to
	# detour into. The pool below is weighted towards the moments after a reward and the approach to
	# the stairs, and it deliberately includes the critical path -- a floor whose main route is safe
	# teaches players that the main route is safe. Two rooms stay clear on purpose: the entrance,
	# because dying before you have taken an action is not a lesson, and the boss room, because the
	# boss is the fight. Everything is drawn from `traps_rng`, which is derived from the run seed, so
	# a floor traps the same way every time it is entered and can be learned rather than guessed.
	var trap_pool := _trap_room_pool(assignment, graph)
	var trap_count := clampi(1 + int(tier / 2.0) + int(floor_index / 3.0), 1, 6)
	if RunModifierService.has_modifier(RunModifierService.MODIFIER_THICK_TRAPS):
		trap_count = clampi(trap_count * 2, 1, 10)
	var used_anchors := {}
	for _i in trap_count:
		if trap_pool.is_empty():
			break
		var pick_idx := _weighted_pick_index(trap_pool, traps_rng)
		var entry: Dictionary = trap_pool[pick_idx]
		var trap_room: Dictionary = entry["room"]
		var room_id := str(trap_room["semantic_id"])
		var trap_anchors: Array = _room_anchors(biome_id, run_seed, trap_room, "trap")
		if trap_anchors.is_empty():
			trap_pool.remove_at(pick_idx)
			continue
		# Several traps may share a room -- an ambush is more convincing when the second one lands
		# while the player is reacting to the first -- but never the same spot twice.
		var anchor_index := int(used_anchors.get(room_id, 0))
		if anchor_index >= trap_anchors.size():
			trap_pool.remove_at(pick_idx)
			continue
		used_anchors[room_id] = anchor_index + 1
		if anchor_index + 1 >= trap_anchors.size():
			trap_pool.remove_at(pick_idx)
		traps.append(
			{
				"roomId": room_id,
				"trapId": _pick_trap(biome, traps_rng),
				"offset": _vec_dict(trap_anchors[anchor_index]),
				"sampleNavmesh": true,
			}
		)
	var boss_pool: Array = biome.get("bossPool", [])
	var boss_entry: Dictionary = (
		_pick_weighted(boss_pool, boss_rng)
		if not boss_pool.is_empty()
		else {"enemyId": "boss_castle_knight"}
	)
	var boss_room: Dictionary = _first_room_of_type(rooms, "boss")
	var entrance_room: Dictionary = _first_room_of_type(rooms, "hub")
	if boss_room.is_empty() or entrance_room.is_empty():
		return {
			"ok": false,
			"error": "Procgen placements missing boss or entrance room",
			"loot": loot,
			"traps": traps,
			"secrets": secrets,
			"boss": null,
			"exit": null,
			"entrance": "entrance",
			"loot_value": ProcgenLootRoller.estimate_loot_value(loot),
		}
	if RunModifierService.has_modifier(RunModifierService.MODIFIER_BOSS_HOARD):
		var hoard_role := "treasure" if _has_loot_role(biome, "treasure") else "secret"
		var hoard_anchors: Array = _room_anchors(biome_id, run_seed, boss_room, "chest")
		loot.append(
			_loot_placement(
				boss_room["semantic_id"],
				"boss_hoard",
				hoard_anchors[hoard_anchors.size() - 1],
				ProcgenLootRoller.roll_chest(biome, hoard_role, tier + 2, loot_rng)
			)
		)
	return {
		"ok": true,
		"loot": loot,
		"traps": traps,
		"secrets": secrets,
		"boss":
		{
			"roomId": boss_room["semantic_id"],
			"enemyId": boss_entry.get("enemyId", "boss_castle_knight")
		},
		"exit": boss_room["semantic_id"],
		"entrance": entrance_room["semantic_id"],
		"loot_value": ProcgenLootRoller.estimate_loot_value(loot),
	}


const DOOR_ANCHOR_CLEARANCE := 2.2


static func _door_local_positions(template_id: String, door_offsets: Dictionary) -> Array:
	var spec := RoomTemplateCatalog.get_spec(template_id)
	var hw: float = spec["half_width"]
	var hd: float = spec["half_depth"]
	var out: Array = []
	if door_offsets.has("north"):
		out.append(Vector3(float(door_offsets["north"]), 0.0, -hd))
	if door_offsets.has("south"):
		out.append(Vector3(float(door_offsets["south"]), 0.0, hd))
	if door_offsets.has("east"):
		out.append(Vector3(hw, 0.0, float(door_offsets["east"])))
	if door_offsets.has("west"):
		out.append(Vector3(-hw, 0.0, float(door_offsets["west"])))
	return out


static func _clear_of_doors(anchors: Array, door_positions: Array) -> Array:
	if door_positions.is_empty():
		return anchors
	var kept: Array = []
	for anchor in anchors:
		var clear := true
		for door_pos in door_positions:
			if Vector2(anchor.x - door_pos.x, anchor.z - door_pos.z).length() < DOOR_ANCHOR_CLEARANCE:
				clear = false
				break
		if clear:
			kept.append(anchor)
	return kept if not kept.is_empty() else anchors


static func _room_anchors(
	biome_id: String, run_seed: int, room: Dictionary, role: String
) -> Array:
	var template_id := str(room.get("template_id", ""))
	var variant := RoomLayoutCatalog.variant_for_room(
		biome_id, run_seed, str(room.get("semantic_id", "")), template_id
	)
	var anchors := RoomLayoutCatalog.anchors_for(biome_id, template_id, role, variant)
	var door_offsets: Dictionary = room.get("doorOffsets", {})
	if door_offsets.is_empty():
		return anchors
	return _clear_of_doors(anchors, _door_local_positions(template_id, door_offsets))


static func _has_loot_role(biome: Dictionary, role: String) -> bool:
	var tables: Variant = biome.get("lootTables", {})
	if not tables is Dictionary:
		return false
	var table: Variant = (tables as Dictionary).get(role, [])
	return table is Array and not (table as Array).is_empty()


static func _cover_entry(room_id: String, offset: Vector3, kind: String) -> Dictionary:
	var size_y := 2.4 if kind == "pillar" else 3.6
	return {
		"roomId": room_id,
		"offset": _vec_dict(offset),
		"size": {"x": 1.2, "y": size_y, "z": 1.2},
		"kind": kind,
	}


## RM-03: a room's biome layout variant may name a `coverPattern` ("ring", "corridor", "scatter" or
## "none") instead of leaving cover to the template's authored anchor list. "scatter" (or an
## unauthored room, which has no variant) keeps the original anchor-based placement unchanged.
static func _cover_for_pattern(
	pattern: String, room_id: String, template_id: String, pillar_count: int, rng: RandomNumberGenerator
) -> Array:
	var spec := RoomTemplateCatalog.get_spec(template_id)
	var entries: Array = []
	if pattern == "ring":
		var radius: float = (
			minf(float(spec.get("half_width", 6.0)), float(spec.get("half_depth", 6.0))) * 0.55
		)
		var start_angle := rng.randf_range(0.0, TAU)
		for i in pillar_count:
			var angle := start_angle + TAU * float(i) / float(pillar_count)
			var offset := Vector3(sin(angle) * radius, 0.0, -cos(angle) * radius)
			entries.append(_cover_entry(room_id, offset, "pillar" if i % 2 == 0 else "chokepoint"))
		return entries
	if pattern == "corridor":
		var half_d: float = float(spec.get("half_depth", 6.0)) * 0.6
		@warning_ignore("integer_division")
		var rows := maxi(1, (pillar_count + 1) / 2)
		for i in pillar_count:
			var side := -1.0 if i % 2 == 0 else 1.0
			@warning_ignore("integer_division")
			var row := i / 2
			var z: float = lerp(-half_d, half_d, float(row) / maxf(1.0, float(rows - 1)))
			var offset := Vector3(side * 2.2, 0.0, z)
			entries.append(_cover_entry(room_id, offset, "pillar" if i % 2 == 0 else "chokepoint"))
		return entries
	return entries


static func _place_cover(
	biome: Dictionary,
	assignment: Dictionary,
	run_seed: int,
	rng: RandomNumberGenerator,
	_graph: RoomGraph = null
) -> Array:
	var biome_id := str(biome.get("id", ""))
	var cover: Array = []
	for room in assignment.get("rooms", []):
		if room.get("type", "") != "combat":
			continue
		var room_id := str(room.get("semantic_id", ""))
		var template_id := str(room.get("template_id", ""))
		var variant := RoomLayoutCatalog.variant_for_room(biome_id, run_seed, room_id, template_id)
		var pattern := RoomLayoutCatalog.cover_pattern_for(biome_id, template_id, variant)
		if pattern == "none":
			continue
		var pillar_count := rng.randi_range(2, 3)
		if pattern == "ring" or pattern == "corridor":
			cover.append_array(
				_cover_for_pattern(pattern, room_id, template_id, pillar_count, rng)
			)
			continue
		var anchors: Array = _room_anchors(biome_id, run_seed, room, "cover")
		for i in pillar_count:
			var offset: Vector3 = anchors[i % anchors.size()]
			cover.append(_cover_entry(room_id, offset, "pillar" if i % 2 == 0 else "chokepoint"))
	return cover


static func _sorted_combat_rooms(assignment: Dictionary) -> Array:
	var combat_rooms: Array = []
	for room in assignment.get("rooms", []):
		if room.get("type", "") == "combat":
			combat_rooms.append(room)
	combat_rooms.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return _semantic_sort_key(a.get("semantic_id", "")) < _semantic_sort_key(
				b.get("semantic_id", "")
			)
	)
	return combat_rooms


static func _semantic_sort_key(semantic_id: String) -> int:
	var parts := semantic_id.rsplit("_", true, 1)
	if parts.size() == 2 and parts[1].is_valid_int():
		return int(parts[1])
	return semantic_id.hash() & 0x7FFFFFFF


## Rooms that may be trapped, each with a weight for how badly it wants one.
##
## Weights encode where a Souls-like puts its traps: heaviest on the run up to the stairs and in
## rooms holding treasure, because that is where a player is either hurrying or congratulating
## themselves. The entrance and the boss room are excluded outright.
static func _trap_room_pool(assignment: Dictionary, graph: RoomGraph) -> Array:
	var critical_set := {}
	if graph != null:
		for layout_id in RoomGraphPaths.critical_path_ids(graph):
			critical_set[layout_id] = true
	var stairs_id: String = graph.stairs_id if graph != null else ""
	var pool: Array = []
	for room in assignment.get("rooms", []):
		var room_type := str(room.get("type", ""))
		var semantic := str(room.get("semantic_id", ""))
		if room_type == "boss" or semantic == "boss":
			continue
		if room_type == "entrance" or semantic == "entrance":
			continue
		if room_type == "secret":
			continue
		var layout_id := str(room.get("layout_id", ""))
		# The stairs room is a lever antechamber, not a real encounter space -- its floor is mostly
		# taken up by the ramp dressing and the lever the player actually interacts with, so a trap
		# there either sits on top of the ramp or crowds the one thing the room exists to let the
		# player reach.
		if layout_id == stairs_id:
			continue
		var weight := 1.0
		if critical_set.has(layout_id):
			weight += 1.0
		if room_type == "treasure":
			weight += 2.0
		if room_type == "corridor":
			weight += 1.0
		pool.append({"room": room, "weight": weight})
	pool.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["room"]["semantic_id"]) < str(b["room"]["semantic_id"])
	)
	return pool


static func _weighted_pick_index(pool: Array, rng: RandomNumberGenerator) -> int:
	var total := 0.0
	for entry in pool:
		total += float(entry.get("weight", 1.0))
	if total <= 0.0:
		return rng.randi_range(0, pool.size() - 1)
	var roll := rng.randf() * total
	for i in pool.size():
		roll -= float(pool[i].get("weight", 1.0))
		if roll <= 0.0:
			return i
	return pool.size() - 1


static func _off_path_combat_rooms(assignment: Dictionary, graph: RoomGraph) -> Array:
	if graph == null:
		return _sorted_combat_rooms(assignment)
	var critical: Array[String] = RoomGraphPaths.critical_path_ids(graph)
	var critical_set := {}
	for layout_id in critical:
		critical_set[layout_id] = true
	var result: Array = []
	for room in assignment.get("rooms", []):
		if room.get("type", "") != "combat":
			continue
		if not critical_set.has(room.get("layout_id", "")):
			result.append(room)
	return result


static func _pick_trap(biome: Dictionary, rng: RandomNumberGenerator) -> String:
	var pool: Array = biome.get("trapPool", [])
	if pool.is_empty():
		return "spike_trap"
	var entry := _pick_weighted(pool, rng)
	return str(entry.get("trapId", "spike_trap"))


static func _loot_placement(
	room_id: String, chest_id: String, offset: Vector3, items: Array
) -> Dictionary:
	return {
		"roomId": room_id,
		"chestId": chest_id,
		"offset": _vec_dict(offset),
		"items": items,
	}


static func _vec_dict(offset: Vector3) -> Dictionary:
	return {"x": offset.x, "y": offset.y, "z": offset.z}


static func _first_room_of_type(
	rooms: Array, room_type: String, excluded: Dictionary = {}
) -> Dictionary:
	for room in rooms:
		if room.get("type", "") != room_type:
			continue
		if excluded.has(str(room.get("layout_id", ""))):
			continue
		return room
	return {}


static func _spawn_safe_room_ids(graph: RoomGraph) -> Dictionary:
	var unsafe := {}
	if graph == null or graph.start_id == "":
		return unsafe
	unsafe[graph.start_id] = true
	for neighbor in RoomGraphPaths.build_adjacency(graph).get(graph.start_id, []):
		unsafe[str(neighbor)] = true
	return unsafe


static func _is_reserved_boss_enemy(enemy_id: String, biome: Dictionary) -> bool:
	if enemy_id.is_empty():
		return false
	for entry in biome.get("bossPool", []):
		if str(entry.get("enemyId", "")) == enemy_id:
			return true
	if (
		enemy_id.begins_with("boss_")
		or enemy_id.begins_with("miniboss_")
		or enemy_id.begins_with("final_boss")
	):
		return true
	return false


static func _pick_weighted(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0
	for entry in pool:
		total += int(entry.get("weight", 1))
	if total <= 0:
		return pool[0]
	var roll := rng.randi_range(0, total - 1)
	var acc := 0
	for entry in pool:
		acc += int(entry.get("weight", 1))
		if roll < acc:
			return entry
	return pool[pool.size() - 1]


static func _enemy_threat_cost(enemy_id: String) -> float:
	if enemy_id.is_empty():
		return 20.0
	if _threat_cost_cache.has(enemy_id):
		return float(_threat_cost_cache[enemy_id])
	var path := "content/enemies/%s.json" % enemy_id
	var cost := 20.0
	if FileAccess.file_exists(ContentLoader.content_path(path)):
		var data: Dictionary = ContentLoader.load_json(path)
		cost = float(data.get("threat_cost", data.get("threatCost", 20)))
	else:
		var boss_path := "content/bosses/%s.json" % enemy_id
		if FileAccess.file_exists(ContentLoader.content_path(boss_path)):
			var boss_data: Dictionary = ContentLoader.load_json(boss_path)
			cost = float(boss_data.get("threat_cost", boss_data.get("threatCost", 50)))
	_threat_cost_cache[enemy_id] = cost
	return cost


static func _wall_direction_from_mask(door_mask: int) -> String:
	match door_mask:
		RoomGraphSlot.DOOR_NORTH:
			return "north"
		RoomGraphSlot.DOOR_EAST:
			return "east"
		RoomGraphSlot.DOOR_SOUTH:
			return "south"
		RoomGraphSlot.DOOR_WEST:
			return "west"
	return ""
