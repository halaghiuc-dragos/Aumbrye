class_name DungeonProcgen
extends RefCounted


const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphAssignerScript := preload("res://scripts/dungeon/procgen/room_graph_assigner.gd")
const RoomGraphGeometryScript := preload("res://scripts/dungeon/procgen/room_graph_geometry.gd")
const ProcgenPlacementsScript := preload("res://scripts/dungeon/procgen/procgen_placements.gd")
const RoomContentAssignerScript := preload("res://scripts/dungeon/procgen/room_content_assigner.gd")
const RoomContentConfigScript := preload("res://scripts/dungeon/procgen/room_content_config.gd")
const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

const MAX_ASSIGNMENT_ATTEMPTS := 12


static func generate(
	biome_id: String,
	run_seed: int,
	tier: int = 1,
	player_level: int = 1,
	floor_index: int = 1,
	is_final_floor: bool = false,
	debug_ascii: bool = false
) -> Dictionary:
	if is_final_floor:
		return _generate_final_floor(biome_id, run_seed, tier, player_level, floor_index)
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome.is_empty():
		return {"ok": false, "error": "Unknown biome '%s'" % biome_id}
	var config := RoomGraphConfigScript.from_biome(biome)
	config.debug_ascii = debug_ascii
	var graph_seed := ProcgenRng.stream(run_seed, "graph").seed
	var graph_result := RoomGraphGeneratorScript.generate(config, graph_seed)
	if not graph_result.get("ok", false):
		return {
			"ok": false,
			"error": str(graph_result.get("reason", "Room graph generation failed")),
		}
	var graph: RoomGraph = graph_result.get("graph")
	var assignment: Dictionary = {}
	var rooms: Array = []
	var edges: Array = []
	var assign_rng := ProcgenRng.stream(run_seed, "assign")
	for attempt in MAX_ASSIGNMENT_ATTEMPTS:
		if attempt > 0:
			assign_rng.seed = FloorSeedMix.mix(assign_rng.seed, attempt * 1_000_003)
		assignment = RoomGraphAssignerScript.assign(biome, graph, assign_rng)
		var door_check := RoomGraphGeometryScript.validate_door_topology(graph, assignment)
		if not door_check.get("ok", false):
			continue
		rooms = RoomGraphGeometryScript.build_rooms(graph, assignment)
		if rooms.is_empty():
			continue
		edges = RoomGraphGeometryScript.build_edges(graph, assignment)
		break
	if rooms.is_empty():
		return {
			"ok": false,
			"error": "Geometry build failed after %d assignment attempts" % MAX_ASSIGNMENT_ATTEMPTS,
		}
	var placements := ProcgenPlacementsScript.place(
		biome, assignment, run_seed, tier, player_level, floor_index, graph
	)
	if not placements.get("ok", true):
		return {
			"ok": false,
			"error": str(placements.get("error", "Placement failed")),
		}
	if graph.secret_ids.size() > config.max_secrets:
		return {
			"ok": false,
			"error":
			(
				"Secret cap exceeded (%d > %d)"
				% [graph.secret_ids.size(), config.max_secrets]
			),
		}
	var content_rng := ProcgenRng.stream(run_seed, "content")
	var content_config := RoomContentConfigScript.for_floor(
		floor_index, RunFloorConfig.MAX_FLOORS, run_seed
	)
	var content_result := RoomContentAssignerScript.assign(
		graph, assignment, content_rng, content_config, biome_id, tier
	)
	var content: Dictionary = content_result.get("content", {})
	var content_warnings: Array = []
	if bool(content_result.get("used_fallback", false)):
		content_warnings.append("content_assignment_fallback")
	content_warnings.append_array(content_result.get("warnings", []))
	_annotate_minimap_rooms(rooms, content.get("roomContent", []))
	var landmarks := _build_landmark_hints(rooms, graph)
	var run_id := deterministic_run_id(run_seed, biome_id, floor_index)
	var definition := {
		"schemaVersion": 2,
		"runId": run_id,
		"seed": run_seed,
		"biomeId": biome_id,
		"tier": maxi(1, tier),
		"playerLevelSnapshot": maxi(1, player_level),
		"rooms": rooms,
		"edges": edges,
		"placements":
		{
			"enemies": placements.get("enemies", []),
			"loot": placements.get("loot", []),
			"puzzles": placements.get("puzzles", []),
			"traps": placements.get("traps", []),
			"secrets": placements.get("secrets", []),
			"cover": placements.get("cover", []),
			"boss": placements.get("boss"),
			"exit": placements.get("exit"),
			"entrance": placements.get("entrance"),
		},
		"budgets":
		{
			"enemyThreat": placements.get("threat_used", 0.0),
			"lootValue": placements.get("loot_value", 0.0),
		},
		"floorIndex": floor_index,
		"isFinalFloor": false,
		"maxHeightLevel": config.max_height_level,
		"floorTheme": content_config.floor_theme_id,
		"floorThemeLabel": content_config.floor_theme_label,
		"roomContent": content.get("roomContent", []),
		"locks": content.get("locks", []),
		"puzzles": content.get("puzzles", []),
		"branchPreviews":
		RoomContentAssignerScript.build_branch_previews(
			graph, assignment, content.get("roomContent", [])
		),
		"landmarks": landmarks,
	}
	var secret_count := RunFloorConfig.count_secrets(definition)
	if secret_count > config.max_secrets:
		return {
			"ok": false,
			"error": "Secret cap exceeded (%d > %d)" % [secret_count, config.max_secrets],
		}
	return {
		"ok": true,
		"definition": definition,
		"generation_seed": run_seed,
		"run_id": run_id,
		"warnings": content_warnings,
	}


const FINAL_ARENA_THREAT_BASE := 90.0
const FINAL_ARENA_THREAT_PER_TIER := 26.0
const FINAL_ARENA_ANCHORS: Array[Vector3] = [
	Vector3(6.0, 0.0, 4.0),
	Vector3(-6.0, 0.0, -5.0),
	Vector3(0.0, 0.0, 0.0),
	Vector3(7.0, 0.0, -4.0),
	Vector3(-5.0, 0.0, 6.0),
	Vector3(4.0, 0.0, -3.0),
]


static func _final_floor_arena_enemies(
	biome: Dictionary, final_floor: Dictionary, run_seed: int, tier: int, floor_index: int
) -> Array:
	var authored: Variant = final_floor.get("arenaEnemies", null)
	if authored is Array:
		return (authored as Array).duplicate(true)
	var pool: Array = biome.get("enemyPool", [])
	if pool.is_empty():
		return []
	var boss_ids := {}
	for entry in biome.get("bossPool", []):
		if entry is Dictionary:
			boss_ids[str((entry as Dictionary).get("enemyId", ""))] = true
	boss_ids[str(final_floor.get("bossId", ""))] = true
	var rng := RandomNumberGenerator.new()
	rng.seed = FloorSeedMix.mix(run_seed, floor_index * 613 + tier * 29)
	var budget := FINAL_ARENA_THREAT_BASE + FINAL_ARENA_THREAT_PER_TIER * float(maxi(0, tier - 1))
	var placements: Array = []
	var spent := 0.0
	for i in FINAL_ARENA_ANCHORS.size():
		var entry := _pick_weighted_enemy(pool, rng)
		if entry.is_empty():
			break
		var enemy_id := str(entry.get("enemyId", ""))
		if enemy_id == "" or boss_ids.has(enemy_id):
			continue
		var cost := float(EnemyCatalog.get_definition(enemy_id).get("threat_cost", 20))
		if spent + cost > budget:
			break
		var offset: Vector3 = FINAL_ARENA_ANCHORS[i]
		placements.append(
			{
				"roomId": "arena",
				"enemyId": enemy_id,
				"offset": {"x": offset.x, "y": offset.y, "z": offset.z},
				"sampleNavmesh": true,
				"isElite": false,
			}
		)
		spent += cost
	return placements


static func _pick_weighted_enemy(pool: Array, rng: RandomNumberGenerator) -> Dictionary:
	var total := 0.0
	for entry in pool:
		if entry is Dictionary:
			total += maxf(0.0, float((entry as Dictionary).get("weight", 1)))
	if total <= 0.0:
		return {}
	var roll := rng.randf() * total
	for entry in pool:
		if not entry is Dictionary:
			continue
		roll -= maxf(0.0, float((entry as Dictionary).get("weight", 1)))
		if roll <= 0.0:
			return entry as Dictionary
	return {}


static func _generate_final_floor(
	biome_id: String, run_seed: int, tier: int, player_level: int, floor_index: int
) -> Dictionary:
	var biome := BiomeRegistry.get_biome(biome_id)
	if biome.is_empty():
		return {"ok": false, "error": "Unknown biome '%s'" % biome_id}
	var prefix := RoomTemplateCatalogScript.template_prefix_for_biome(biome_id)
	var final_floor: Dictionary = biome.get("finalFloor", {})
	var boss_enemy_id := _resolve_final_boss_id(biome, final_floor)
	var lobby_chests: Array = final_floor.get("lobbyChests", _default_final_lobby_chests())
	var layout := _build_final_floor_layout(prefix)
	var run_id := deterministic_run_id(run_seed, biome_id, floor_index)
	var definition := {
		"schemaVersion": 2,
		"runId": run_id,
		"seed": run_seed,
		"biomeId": biome_id,
		"tier": maxi(1, tier),
		"playerLevelSnapshot": maxi(1, player_level),
		"rooms": layout.get("rooms", []),
		"edges": layout.get("edges", []),
		"placements":
		{
			"enemies": _final_floor_arena_enemies(biome, final_floor, run_seed, tier, floor_index),
			"loot": lobby_chests,
			"puzzles": [],
			"traps": [],
			"secrets": [],
			"boss": {"roomId": "boss", "enemyId": boss_enemy_id},
			"exit": "boss",
			"entrance": "entrance",
		},
		"budgets": {"enemyThreat": 0.0, "lootValue": 0.0},
		"floorIndex": floor_index,
		"isFinalFloor": true,
		"maxHeightLevel": 0,
		"floorTheme": "plain",
		"floorThemeLabel": "",
		"roomContent": [],
		"locks": [],
		"puzzles": [],
		"branchPreviews": [],
		"landmarks": [],
	}
	return {
		"ok": true,
		"definition": definition,
		"generation_seed": run_seed,
		"run_id": run_id,
	}


static func _resolve_final_boss_id(biome: Dictionary, final_floor: Dictionary) -> String:
	var configured: String = str(final_floor.get("bossId", ""))
	if configured != "":
		return configured
	var boss_pool: Array = biome.get("bossPool", [])
	if not boss_pool.is_empty():
		return str(boss_pool[0].get("enemyId", "boss_castle_knight"))
	return "boss_castle_knight"


static func _default_final_lobby_chests() -> Array:
	return [
		{
			"roomId": "entrance",
			"chestId": "final_lobby_potion",
			"offset": {"x": 2.0, "y": 0.0, "z": 4.0},
			"items": [{"itemId": "health_potion", "quantity": 1}],
		},
		{
			"roomId": "entrance",
			"chestId": "final_lobby_scroll",
			"offset": {"x": -2.0, "y": 0.0, "z": 4.0},
			"items": [{"itemId": "elixir_might", "quantity": 1}],
		},
	]


static func _build_final_floor_layout(prefix: String) -> Dictionary:
	var entrance_id := "%s_entrance" % prefix
	var arena_id := "%s_arena" % prefix
	var boss_id := "%s_boss" % prefix
	var entrance_spec := RoomTemplateCatalogScript.get_spec(entrance_id)
	var arena_spec := RoomTemplateCatalogScript.get_spec(arena_id)
	var boss_spec := RoomTemplateCatalogScript.get_spec(boss_id)
	var arena_z := float(entrance_spec["half_depth"]) + float(arena_spec["half_depth"])
	var boss_z := arena_z + float(arena_spec["half_depth"]) + float(boss_spec["half_depth"])
	return {
		"rooms":
		[
			{
				"id": "entrance",
				"templateId": entrance_id,
				"type": "hub",
				"transform": {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0},
				"tags": ["spawn", "final_lobby"],
				"size": {"x": float(entrance_spec["width"]), "z": float(entrance_spec["depth"])},
				"kind": "entrance",
			},
			{
				"id": "arena",
				"templateId": arena_id,
				"type": "arena",
				"transform": {"x": 0.0, "y": 0.0, "z": arena_z, "yaw": 0.0},
				"tags": ["final_arena"],
				"size": {"x": float(arena_spec["width"]), "z": float(arena_spec["depth"])},
				"kind": "combat",
			},
			{
				"id": "boss",
				"templateId": boss_id,
				"type": "boss",
				"transform": {"x": 0.0, "y": 0.0, "z": boss_z, "yaw": 0.0},
				"tags": ["final_boss"],
				"size": {"x": float(boss_spec["width"]), "z": float(boss_spec["depth"])},
				"kind": "boss",
			},
		],
		"edges":
		[
			{"from": "entrance", "to": "arena", "kind": "door"},
			{"from": "arena", "to": "boss", "kind": "door"},
		],
	}


static func deterministic_run_id(run_seed: int, biome_id: String, floor_index: int) -> String:
	var mixed := (
		run_seed
		^ FloorSeedMix.stable_string_hash(biome_id)
		^ (floor_index * 7919)
	)
	mixed = maxi(1, mixed)
	return "%08x-0000-4000-8000-%012x" % [mixed & 0xFFFFFFFF, mixed & 0xFFFFFFFFFFFF]


static func _build_landmark_hints(rooms: Array, graph: RoomGraph) -> Array:
	var landmarks: Array = []
	var boss_pos := Vector3.ZERO
	var entrance_pos := Vector3.ZERO
	for room in rooms:
		var room_type: String = str(room.get("type", ""))
		var t: Dictionary = room.get("transform", {})
		var pos := Vector3(float(t.get("x", 0.0)), float(t.get("y", 0.0)), float(t.get("z", 0.0)))
		if room_type == "boss":
			boss_pos = pos
		if room_type == "hub":
			entrance_pos = pos
	if boss_pos != Vector3.ZERO:
		(
			landmarks
			. append(
				{
					"kind": "boss_spire",
					"position": {"x": boss_pos.x, "y": boss_pos.y + 18.0, "z": boss_pos.z},
					"scale": {"x": 2.0, "y": 24.0, "z": 2.0},
				}
			)
		)
		(
			landmarks
			. append(
				{
					"kind": "boss_silhouette",
					"position": {"x": boss_pos.x, "y": boss_pos.y + 8.0, "z": boss_pos.z - 6.0},
					"scale": {"x": 6.0, "y": 10.0, "z": 1.0},
				}
			)
		)
	if entrance_pos != Vector3.ZERO and graph != null and graph.boss_id != "":
		var boss_slot := graph.get_slot(graph.boss_id)
		if boss_slot:
			(
				landmarks
				. append(
					{
						"kind": "orientation_spire",
						"position":
						{
							"x":
							(
								entrance_pos.x
								+ (
									float(
										(
											boss_slot.grid_pos.x
											- graph.get_slot(graph.start_id).grid_pos.x
										)
									)
									* 2.0
								)
							),
							"y": entrance_pos.y + 14.0,
							"z":
							(
								entrance_pos.z
								+ (
									float(
										(
											boss_slot.grid_pos.y
											- graph.get_slot(graph.start_id).grid_pos.y
										)
									)
									* 2.0
								)
							),
						},
						"scale": {"x": 1.5, "y": 16.0, "z": 1.5},
					}
				)
			)
	return landmarks


const MINIMAP_KIND_BY_CONTENT := {
	RoomContentTypes.REST: "rest",
	RoomContentTypes.REWARD: "treasure",
	RoomContentTypes.MERCHANT: "shop",
	RoomContentTypes.LORE: "lore",
	RoomContentTypes.PUZZLE: "puzzle",
	RoomContentTypes.TRAP: "hazard",
	RoomContentTypes.HAZARD: "hazard",
	RoomContentTypes.LOCKED_VAULT: "vault",
	RoomContentTypes.NPC_QUEST: "npc",
	RoomContentTypes.COMBAT: "combat",
}

const MINIMAP_RESERVED_KINDS := ["boss", "entrance", "stairs", "secret"]


static func _annotate_minimap_rooms(rooms: Array, room_content: Array) -> void:
	var key_rooms := {}
	var content_kind := {}
	var locked_rooms := {}
	for entry in room_content:
		if not entry is Dictionary:
			continue
		var room_id := str(entry.get("roomId", ""))
		if str(entry.get("keyId", "")) != "":
			key_rooms[room_id] = true
			locked_rooms[room_id] = true
		var content_type := str(entry.get("contentType", ""))
		if MINIMAP_KIND_BY_CONTENT.has(content_type):
			content_kind[room_id] = str(MINIMAP_KIND_BY_CONTENT[content_type])
	for room in rooms:
		if not room is Dictionary:
			continue
		var room_id := str(room.get("id", ""))
		var current_kind := str(room.get("kind", ""))
		if current_kind not in MINIMAP_RESERVED_KINDS and content_kind.has(room_id):
			room["kind"] = content_kind[room_id]
		if key_rooms.has(room_id):
			room["kind"] = "key"
		if locked_rooms.has(room_id):
			room["locked"] = true
