class_name DungeonProcgen
extends RefCounted

## Two-phase dungeon generator: room graph (Phase 1) → geometry + placements (Phase 2).

const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphAssignerScript := preload("res://scripts/dungeon/procgen/room_graph_assigner.gd")
const RoomGraphGeometryScript := preload("res://scripts/dungeon/procgen/room_graph_geometry.gd")
const ProcgenBiomeLoaderScript := preload("res://scripts/dungeon/procgen/procgen_biome_loader.gd")
const ProcgenPlacementsScript := preload("res://scripts/dungeon/procgen/procgen_placements.gd")
const RoomContentAssignerScript := preload("res://scripts/dungeon/procgen/room_content_assigner.gd")
const RoomContentConfigScript := preload("res://scripts/dungeon/procgen/room_content_config.gd")

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
	var biome := ProcgenBiomeLoaderScript.load(biome_id)
	if biome.is_empty():
		return {"ok": false, "error": "Unknown biome '%s'" % biome_id}
	var config := RoomGraphConfigScript.from_biome(biome)
	config.debug_ascii = debug_ascii
	var graph_result := RoomGraphGeneratorScript.generate(config, run_seed)
	if not graph_result.get("ok", false):
		return {"ok": false, "error": "Room graph generation failed"}
	if graph_result.get("used_fallback", false):
		push_warning("Room graph used fallback layout for seed %d (floor %d)" % [run_seed, floor_index])
	var graph: RoomGraph = graph_result.get("graph")
	var assignment: Dictionary = {}
	var rooms: Array = []
	var edges: Array = []
	var assign_rng := RandomNumberGenerator.new()
	for attempt in MAX_ASSIGNMENT_ATTEMPTS:
		assign_rng.seed = run_seed ^ 0x5EED + attempt * 1_000_003
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
		biome, assignment, run_seed, tier, player_level, assign_rng, graph
	)
	var content_result := RoomContentAssignerScript.assign(
		graph, assignment, assign_rng, RoomContentConfigScript.default()
	)
	var content: Dictionary = content_result.get("content", {})
	var landmarks := _build_landmark_hints(rooms, graph)
	var run_id := _deterministic_run_id(run_seed, biome_id, floor_index)
	var definition := {
		"schemaVersion": 1,
		"runId": run_id,
		"seed": run_seed,
		"biomeId": biome_id,
		"tier": maxi(1, tier),
		"playerLevelSnapshot": maxi(1, player_level),
		"rooms": rooms,
		"edges": edges,
		"placements": {
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
		"budgets": {
			"enemyThreat": placements.get("threat_used", 0.0),
			"lootValue": placements.get("loot_value", 0.0),
		},
		"floorIndex": floor_index,
		"isFinalFloor": false,
		"roomContent": content.get("roomContent", []),
		"locks": content.get("locks", []),
		"puzzles": content.get("puzzles", []),
		"branchPreviews": RoomContentAssignerScript.build_branch_previews(
			graph, assignment, content.get("roomContent", [])
		),
		"landmarks": landmarks,
	}
	return {
		"ok": true,
		"definition": definition,
		"generation_seed": run_seed,
		"run_id": run_id,
		"used_fallback": graph_result.get("used_fallback", false),
	}


static func _generate_final_floor(
	biome_id: String,
	run_seed: int,
	tier: int,
	player_level: int,
	floor_index: int
) -> Dictionary:
	var prefix := RoomTemplateCatalog.template_prefix_for_biome(biome_id)
	var run_id := _deterministic_run_id(run_seed, biome_id, floor_index)
	var definition := {
		"schemaVersion": 1,
		"runId": run_id,
		"seed": run_seed,
		"biomeId": biome_id,
		"tier": maxi(1, tier),
		"playerLevelSnapshot": maxi(1, player_level),
		"rooms": [
			{
				"id": "entrance",
				"templateId": "%s_entrance" % prefix,
				"type": "hub",
				"transform": {"x": 0.0, "y": 0.0, "z": 0.0, "yaw": 0.0},
				"tags": ["spawn", "final_lobby"],
			},
			{
				"id": "boss",
				"templateId": "%s_boss" % prefix,
				"type": "boss",
				"transform": {"x": 0.0, "y": 0.0, "z": 20.0, "yaw": 0.0},
				"tags": ["final_boss"],
			},
		],
		"edges": [{"from": "entrance", "to": "boss", "kind": "door"}],
		"placements": {
			"enemies": [],
			"loot": [
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
			],
			"puzzles": [],
			"traps": [],
			"secrets": [],
			"boss": {"roomId": "boss", "enemyId": "final_boss_forgotten_castle"},
			"exit": "boss",
			"entrance": "entrance",
		},
		"budgets": {"enemyThreat": 0.0, "lootValue": 0.0},
		"floorIndex": floor_index,
		"isFinalFloor": true,
	}
	return {
		"ok": true,
		"definition": definition,
		"generation_seed": run_seed,
		"run_id": run_id,
	}


static func _deterministic_run_id(run_seed: int, biome_id: String, floor_index: int) -> String:
	var mixed := run_seed ^ (biome_id.hash() & 0x7FFFFFFF) ^ (floor_index * 7919)
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
		landmarks.append({
			"kind": "boss_spire",
			"position": {"x": boss_pos.x, "y": boss_pos.y + 18.0, "z": boss_pos.z},
			"scale": {"x": 2.0, "y": 24.0, "z": 2.0},
		})
		landmarks.append({
			"kind": "boss_silhouette",
			"position": {"x": boss_pos.x, "y": boss_pos.y + 8.0, "z": boss_pos.z - 6.0},
			"scale": {"x": 6.0, "y": 10.0, "z": 1.0},
		})
	if entrance_pos != Vector3.ZERO and graph != null and graph.boss_id != "":
		var boss_slot := graph.get_slot(graph.boss_id)
		if boss_slot:
			landmarks.append({
				"kind": "orientation_spire",
				"position": {
					"x": entrance_pos.x + float(boss_slot.grid_pos.x - graph.get_slot(graph.start_id).grid_pos.x) * 2.0,
					"y": entrance_pos.y + 14.0,
					"z": entrance_pos.z + float(boss_slot.grid_pos.y - graph.get_slot(graph.start_id).grid_pos.y) * 2.0,
				},
				"scale": {"x": 1.5, "y": 16.0, "z": 1.5},
			})
	return landmarks
