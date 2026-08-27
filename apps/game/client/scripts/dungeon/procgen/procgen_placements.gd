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
	var elites_placed := 0
	var budgets: Dictionary = biome.get("budgets", {})
	var budget := (
		float(budgets.get("baseEnemyThreat", 200))
		+ float(budgets.get("threatPerTier", 35)) * float(tier - 1)
		+ float(player_level) * 5.0
	)
	var placements: Array = []
	var threat_used := 0.0
	var combat_rooms: Array = _sorted_combat_rooms(assignment)
	var door_distances := {}
	if graph != null:
		door_distances = RoomGraphPaths.bfs_distances(graph, graph.start_id)
	for room in combat_rooms:
		var depth := 0
		if graph != null:
			var layout_id: String = room.get("layout_id", "")
			depth = int(door_distances.get(layout_id, 0))
		var max_per_room := clampi(
			1 + int(depth / 3.0) + int((tier - 1) / 2.0), 1, 4
		)
		var anchor_idx := 0
		var room_template := str(room.get("template_id", ""))
		var anchors: Array = RoomLayoutCatalog.anchors_for(
			biome_id,
			room_template,
			"enemy",
			RoomLayoutCatalog.variant_for_room(
				biome_id, run_seed, str(room.get("semantic_id", "")), room_template
			)
		)
		for i in max_per_room:
			var placed := false
			for _attempt in 4:
				var entry := _pick_weighted(biome.get("enemyPool", []), rng)
				if entry.is_empty():
					break
				var enemy_id: String = str(entry.get("enemyId", ""))
				if _is_reserved_boss_enemy(enemy_id, biome):
					continue
				var threat_cost := _enemy_threat_cost(enemy_id)
				if threat_used + threat_cost > budget:
					break
				var offset: Vector3 = anchors[anchor_idx % anchors.size()]
				anchor_idx += 1
				var is_elite := false
				if elite_rule and i == 0:
					if elites_placed < elites_required or rng.randf() < 0.3:
						is_elite = true
						elites_placed += 1
				placements.append(
					{
						"roomId": room["semantic_id"],
						"enemyId": enemy_id,
						"offset": _vec_dict(offset),
						"sampleNavmesh": true,
						"isElite": is_elite,
					}
				)
				threat_used += threat_cost
				placed = true
				break
			if not placed:
				break
	return {"enemies": placements, "threat_used": threat_used}


static func _place_loot(
	biome: Dictionary,
	assignment: Dictionary,
	run_seed: int,
	tier: int,
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
						var parent_slot := graph.get_slot(secret_slot.secret_parent_id)
						if parent_slot != null:
							var dx := secret_slot.grid_pos.x - parent_slot.grid_pos.x
							var dz := secret_slot.grid_pos.y - parent_slot.grid_pos.y
							var doors := RoomTemplateCatalog.doors_for_step(dx, dz)
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
	var off_path_rooms := _off_path_combat_rooms(assignment, graph)
	var trap_count := clampi(1 + int(tier / 2.0), 1, 4)
	if RunModifierService.has_modifier(RunModifierService.MODIFIER_THICK_TRAPS):
		trap_count = clampi(trap_count * 2, 1, 8)
	for _i in mini(trap_count, off_path_rooms.size()):
		if off_path_rooms.is_empty():
			break
		var pick_idx := traps_rng.randi_range(0, off_path_rooms.size() - 1)
		var trap_room: Dictionary = off_path_rooms[pick_idx]
		off_path_rooms.remove_at(pick_idx)
		var trap_anchors: Array = _room_anchors(biome_id, run_seed, trap_room, "trap")
		traps.append(
			{
				"roomId": trap_room["semantic_id"],
				"trapId": _pick_trap(biome, traps_rng),
				"offset": _vec_dict(trap_anchors[0]),
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


static func _room_anchors(
	biome_id: String, run_seed: int, room: Dictionary, role: String
) -> Array:
	var template_id := str(room.get("template_id", ""))
	var variant := RoomLayoutCatalog.variant_for_room(
		biome_id, run_seed, str(room.get("semantic_id", "")), template_id
	)
	return RoomLayoutCatalog.anchors_for(biome_id, template_id, role, variant)


static func _has_loot_role(biome: Dictionary, role: String) -> bool:
	var tables: Variant = biome.get("lootTables", {})
	if not tables is Dictionary:
		return false
	var table: Variant = (tables as Dictionary).get(role, [])
	return table is Array and not (table as Array).is_empty()


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
		var anchors: Array = _room_anchors(biome_id, run_seed, room, "cover")
		var pillar_count := rng.randi_range(2, 3)
		for i in pillar_count:
			var offset: Vector3 = anchors[i % anchors.size()]
			var kind := "pillar" if i % 2 == 0 else "chokepoint"
			var size_y := 2.4 if kind == "pillar" else 3.6
			cover.append(
				{
					"roomId": room["semantic_id"],
					"offset": _vec_dict(offset),
					"size": {"x": 1.2, "y": size_y, "z": 1.2},
					"kind": kind,
				}
			)
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
