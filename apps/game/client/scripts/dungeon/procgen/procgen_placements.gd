class_name ProcgenPlacements
extends RefCounted

## Enemy and loot placement (mirrors C# EnemyPlacer + LootPlacer).

const SPAWN_OFFSETS := [
	Vector3(4, 0, 2),
	Vector3(-5, 0, -4),
	Vector3(0, 0, 0),
	Vector3(5, 0, -3),
	Vector3(-4, 0, 4),
	Vector3(3, 0, -2),
]

const COVER_OFFSETS := [
	Vector3(-3, 0, -2),
	Vector3(3, 0, 2),
	Vector3(0, 0, -4),
	Vector3(-2, 0, 3),
]


static func place(
	biome: Dictionary,
	assignment: Dictionary,
	run_seed: int,
	tier: int,
	player_level: int,
	rng: RandomNumberGenerator,
	graph: RoomGraph = null
) -> Dictionary:
	var enemies_result := _place_enemies(biome, assignment, tier, player_level, rng, graph)
	var loot_result := _place_loot(biome, assignment, enemies_result["enemies"], run_seed, tier, player_level, rng, graph)
	var cover := _place_cover(assignment, rng, graph)
	return {
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
	tier: int,
	player_level: int,
	rng: RandomNumberGenerator,
	graph: RoomGraph = null
) -> Dictionary:
	var budgets: Dictionary = biome.get("budgets", {})
	var budget := (
		float(budgets.get("baseEnemyThreat", 200))
		+ float(budgets.get("threatPerTier", 35)) * float(tier - 1)
		+ float(player_level) * 5.0
	)
	var placements: Array = []
	var threat_used := 0.0
	var combat_rooms: Array = []
	for room in assignment.get("rooms", []):
		if room.get("type", "") == "combat":
			combat_rooms.append(room)
	combat_rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("semantic_id", "")) < str(b.get("semantic_id", ""))
	)
	for room in combat_rooms:
		if room.get("type", "") == "filler":
			continue
		var depth := 0
		if graph != null:
			var slot := graph.get_slot(room["layout_id"])
			if slot:
				depth = slot.graph_distance
		var max_per_room := rng.randi_range(1, mini(3, 1 + int(depth / 3.0)))
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
				var offset: Vector3 = SPAWN_OFFSETS[(placements.size() + i) % SPAWN_OFFSETS.size()]
				placements.append({
					"roomId": room["semantic_id"],
					"enemyId": enemy_id,
					"offset": {"x": offset.x, "y": offset.y, "z": offset.z},
					"sampleNavmesh": true,
				})
				threat_used += threat_cost
				placed = true
				break
			if not placed:
				continue
	return {"enemies": placements, "threat_used": threat_used}


static func _place_loot(
	biome: Dictionary,
	assignment: Dictionary,
	_enemies: Array,
	run_seed: int,
	_tier: int,
	_player_level: int,
	_rng: RandomNumberGenerator,
	graph: RoomGraph = null
) -> Dictionary:
	var biome_id := str(biome.get("id", "forgotten_castle"))
	var loot: Array = []
	var traps: Array = []
	var secrets: Array = []
	var rooms: Array = assignment.get("rooms", [])
	var treasure_room: Dictionary = _first_room_of_type(rooms, "treasure")
	if not treasure_room.is_empty():
		loot.append(_loot_placement(
			treasure_room["semantic_id"],
			"treasure_main",
			Vector3.ZERO,
			ProcgenLootTables.treasure_loot(biome_id)
		))
	for room in rooms:
		if room.get("type", "") == "secret":
			var layout_id: String = room.get("layout_id", "")
			var mechanism := "illusory_wall"
			var parent_room_id := ""
			if graph != null:
				var secret_slot := graph.get_slot(layout_id)
				if secret_slot:
					mechanism = secret_slot.secret_mechanism if secret_slot.secret_mechanism != "" else "illusory_wall"
					if secret_slot.secret_parent_id != "":
						for parent_room in rooms:
							if parent_room.get("layout_id", "") == secret_slot.secret_parent_id:
								parent_room_id = parent_room.get("semantic_id", "")
								break
			secrets.append({
				"roomId": room["semantic_id"],
				"mechanism": mechanism,
				"parentRoomId": parent_room_id,
			})
			loot.append(_loot_placement(
				room["semantic_id"],
				"secret_vault_%d" % secrets.size(),
				Vector3.ZERO,
				ProcgenLootTables.secret_loot(biome_id)
			))
	var combat_rooms: Array = []
	for room in rooms:
		if room.get("type", "") == "combat":
			combat_rooms.append(room)
	combat_rooms.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return str(a.get("semantic_id", "")) < str(b.get("semantic_id", ""))
	)
	if combat_rooms.size() > 0:
		var side_rng := RandomNumberGenerator.new()
		side_rng.seed = run_seed ^ 0x51DE
		var side_room: Dictionary = combat_rooms[side_rng.randi_range(0, combat_rooms.size() - 1)]
		var side_depth := 0
		if graph != null:
			var side_slot := graph.get_slot(side_room["layout_id"])
			if side_slot:
				side_depth = side_slot.graph_distance
		var side_items := ProcgenLootTables.side_loot(biome_id)
		if side_depth >= 6:
			side_items = ProcgenLootTables.armory_loot(biome_id)
		elif side_depth >= 4:
			side_items = ProcgenLootTables.treasure_loot(biome_id)
		loot.append(_loot_placement(
			side_room["semantic_id"],
			"%s_side" % side_room["semantic_id"],
			Vector3(7, 0, 6),
			side_items
		))
	if combat_rooms.size() > 1:
		var armory_room: Dictionary = combat_rooms[1]
		loot.append(_loot_placement(
			armory_room["semantic_id"],
			"%s_armory" % armory_room["semantic_id"],
			Vector3(-4, 0, 4),
			ProcgenLootTables.armory_loot(biome_id)
		))
	var corridor: Dictionary = _first_room_of_type(rooms, "corridor")
	if not corridor.is_empty():
		traps.append({
			"roomId": corridor["semantic_id"],
			"trapId": ProcgenLootTables.corridor_trap(biome_id),
			"offset": {"x": 0.0, "y": 0.0, "z": 4.0},
			"sampleNavmesh": true,
		})
	if combat_rooms.size() > 0:
		var trap_rng := RandomNumberGenerator.new()
		trap_rng.seed = run_seed ^ 0x7A2B
		var trap_room: Dictionary = combat_rooms[trap_rng.randi_range(0, combat_rooms.size() - 1)]
		traps.append({
			"roomId": trap_room["semantic_id"],
			"trapId": "falling_trap",
			"offset": {"x": -2.0, "y": 3.0, "z": -5.0},
			"sampleNavmesh": true,
		})
	var boss_rng := RandomNumberGenerator.new()
	boss_rng.seed = run_seed ^ 0xB055
	var boss_pool: Array = biome.get("bossPool", [])
	var boss_entry: Dictionary = boss_pool[boss_rng.randi_range(0, boss_pool.size() - 1)] if not boss_pool.is_empty() else {"enemyId": "boss_castle_knight"}
	var boss_room: Dictionary = _first_room_of_type(rooms, "boss")
	var entrance_room: Dictionary = _first_room_of_type(rooms, "hub")
	if boss_room.is_empty() or entrance_room.is_empty():
		push_error("Procgen placements missing boss or entrance room")
		return {
			"loot": loot,
			"traps": traps,
			"secrets": secrets,
			"boss": null,
			"exit": null,
			"entrance": "entrance",
			"loot_value": _estimate_loot_value(loot),
		}
	return {
		"loot": loot,
		"traps": traps,
		"secrets": secrets,
		"boss": {"roomId": boss_room["semantic_id"], "enemyId": boss_entry.get("enemyId", "boss_castle_knight")},
		"exit": boss_room["semantic_id"],
		"entrance": entrance_room["semantic_id"],
		"loot_value": _estimate_loot_value(loot),
	}


static func _place_cover(assignment: Dictionary, rng: RandomNumberGenerator, _graph: RoomGraph = null) -> Array:
	var cover: Array = []
	for room in assignment.get("rooms", []):
		if room.get("type", "") != "combat":
			continue
		var pillar_count := rng.randi_range(2, 3)
		for i in pillar_count:
			var offset: Vector3 = COVER_OFFSETS[i % COVER_OFFSETS.size()]
			cover.append({
				"roomId": room["semantic_id"],
				"offset": {"x": offset.x, "y": 0.0, "z": offset.z},
				"size": {"x": 1.2, "y": 2.4, "z": 1.2},
				"kind": "pillar" if i % 2 == 0 else "chokepoint",
			})
	return cover


static func _loot_placement(room_id: String, chest_id: String, offset: Vector3, items: Array) -> Dictionary:
	return {
		"roomId": room_id,
		"chestId": chest_id,
		"offset": {"x": offset.x, "y": offset.y, "z": offset.z},
		"items": items,
	}


static func _first_room_of_type(rooms: Array, room_type: String) -> Dictionary:
	for room in rooms:
		if room.get("type", "") == room_type:
			return room
	return {}


static func _is_reserved_boss_enemy(enemy_id: String, biome: Dictionary) -> bool:
	if enemy_id.is_empty():
		return false
	for entry in biome.get("bossPool", []):
		if str(entry.get("enemyId", "")) == enemy_id:
			return true
	if enemy_id.begins_with("boss_") or enemy_id.begins_with("miniboss_") or enemy_id.begins_with("final_boss"):
		return true
	return false


static func _pick_weighted(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	if pool.is_empty():
		return {}
	var total := 0
	for entry in pool:
		total += int(entry.get("weight", 1))
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
	var path := "content/enemies/%s.json" % enemy_id
	if FileAccess.file_exists(ContentLoader.content_path(path)):
		var data: Dictionary = ContentLoader.load_json(path)
		return float(data.get("threat_cost", data.get("threatCost", 20)))
	var boss_path := "content/bosses/%s.json" % enemy_id
	if FileAccess.file_exists(ContentLoader.content_path(boss_path)):
		var boss_data: Dictionary = ContentLoader.load_json(boss_path)
		return float(boss_data.get("threat_cost", boss_data.get("threatCost", 50)))
	return 20.0


static func _estimate_loot_value(loot: Array) -> float:
	var total := 0.0
	for chest in loot:
		for item in chest.get("items", []):
			total += float(item.get("quantity", 1)) * 10.0
	return total
