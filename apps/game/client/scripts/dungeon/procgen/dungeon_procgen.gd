class_name DungeonProcgen
extends RefCounted


const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphAssignerScript := preload("res://scripts/dungeon/procgen/room_graph_assigner.gd")
const RoomGraphGeometryScript := preload("res://scripts/dungeon/procgen/room_graph_geometry.gd")
const RoomGraphLayoutScript := preload("res://scripts/dungeon/procgen/room_graph_layout.gd")
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
	config.apply_discovery_budget(RunHistoryService.run_count(), floor_index)
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
	var layout: Dictionary = {}
	var assign_rng := ProcgenRng.stream(run_seed, "assign")
	for attempt in MAX_ASSIGNMENT_ATTEMPTS:
		if attempt > 0:
			assign_rng.seed = FloorSeedMix.mix(assign_rng.seed, attempt * 1_000_003)
		assignment = RoomGraphAssignerScript.assign(biome, graph, assign_rng, config)
		var door_check := RoomGraphGeometryScript.validate_door_topology(graph, assignment)
		if not door_check.get("ok", false):
			continue
		layout = RoomGraphLayoutScript.solve(graph, assignment)
		if not layout.get("ok", false):
			continue
		rooms = RoomGraphGeometryScript.build_rooms(graph, assignment, layout)
		if rooms.is_empty():
			continue
		# The same test the definition validator will apply in a moment. Checking it here is the
		# difference between this attempt being discarded and the whole floor failing: the loop
		# already exists to throw away layouts that do not work, and an overlapping one does not
		# work. Rejecting it costs one more assignment; letting it through costs the player a run.
		if DungeonDefinitionValidator.has_room_overlap(rooms):
			rooms = []
			continue
		edges = RoomGraphGeometryScript.build_edges(graph, assignment, layout)
		break
	if rooms.is_empty():
		return {
			"ok": false,
			"error":
			(
				"Geometry build failed after %d assignment attempts"
				% MAX_ASSIGNMENT_ATTEMPTS
			),
		}
	# The lattice may leave an optional room unplaced when its branch folds back on ground another
	# branch already took. Prune those out of the assignment before anything downstream reads it:
	# enemies, loot and traps are addressed by room id, and a placement pointing at a room the floor
	# no longer contains is exactly the `placement_in_room` the validator rejects the whole floor for.
	var pruned := _prune_to_placed(graph, assignment, layout)
	assignment = pruned["assignment"]
	layout = pruned["layout"]
	_rebuild_canonical_graph(graph, assignment, layout)
	var realised_contract := RoomGraphGeneratorScript.validate_realised_floor(graph, config)
	if not realised_contract.get("ok", false):
		return {
			"ok": false,
			"error": "realised_floor_contract_failed",
			"reason": str(realised_contract.get("reason", "unknown")),
		}
	rooms = RoomGraphGeometryScript.build_rooms(graph, assignment, layout)
	edges = RoomGraphGeometryScript.build_edges(graph, assignment, layout)
	var door_offsets_by_semantic := {}
	for built_room in rooms:
		door_offsets_by_semantic[str(built_room.get("id", ""))] = built_room.get("doorOffsets", {})
	for assignment_room in assignment.get("rooms", []):
		assignment_room["doorOffsets"] = door_offsets_by_semantic.get(
			str(assignment_room.get("semantic_id", "")), {}
		)
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
	content_config.dead_end_reward_ratio = config.dead_end_reward_ratio
	var content_result := RoomContentAssignerScript.assign(
		graph, assignment, content_rng, content_config, biome_id, tier
	)
	var content: Dictionary = content_result.get("content", {})
	var content_warnings: Array = []
	var fallback_pattern := str(layout.get("fallback_pattern", ""))
	if fallback_pattern != "":
		content_warnings.append("layout_fallback:%s" % fallback_pattern)
	if bool(content_result.get("used_fallback", false)):
		content_warnings.append("content_assignment_fallback")
	content_warnings.append_array(content_result.get("warnings", []))
	_annotate_minimap_rooms(rooms, content.get("roomContent", []), content.get("locks", []))
	_annotate_one_way_edges(edges, content.get("shortcutGates", []))
	var landmarks := _build_landmark_hints(rooms, graph, assignment)
	var expedition_objective := _build_expedition_objective(graph, assignment, content, floor_index)
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
		"shortcutGates": content.get("shortcutGates", []),
		"branchPreviews":
		RoomContentAssignerScript.build_branch_previews(
			graph, assignment, content.get("roomContent", [])
		),
		"landmarks": landmarks,
		"expeditionObjective": expedition_objective,
		"realisedFloorContract": realised_contract,
		"layoutFallbackPattern": fallback_pattern,
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


## Drops assignment rooms the lattice could not seat, and any room left unreachable once they go.
##
## Takes the caller's already-solved `layout` for this exact `(graph, assignment)` rather than
## solving again -- `RoomGraphLayout.solve` mutates `graph`'s slots (`_place_secrets` records a
## secret's chosen parent there), so a second solve of the same inputs is not guaranteed to answer
## the same way as the first, and downstream content had already been handed out against the first
## answer. Returns the filtered layout alongside the pruned assignment so the caller can build rooms
## and edges from it directly instead of asking for a third solve.
static func _prune_to_placed(graph: RoomGraph, assignment: Dictionary, layout: Dictionary) -> Dictionary:
	var placements: Dictionary = layout["placements"]
	var realised: Dictionary = layout["realised_edges"]
	var neighbors := {}
	for key in realised:
		var edge: Dictionary = realised[key]
		var from_id := str(edge["from"])
		var to_id := str(edge["to"])
		if not neighbors.has(from_id):
			neighbors[from_id] = []
		if not neighbors.has(to_id):
			neighbors[to_id] = []
		neighbors[from_id].append(to_id)
		neighbors[to_id].append(from_id)
	var entrance_id := str(assignment.get("entrance_layout_id", graph.start_id))
	var reachable := {entrance_id: true}
	var queue: Array[String] = [entrance_id]
	while not queue.is_empty():
		var current: String = queue.pop_front()
		for next_id in neighbors.get(current, []):
			if reachable.has(next_id):
				continue
			reachable[next_id] = true
			queue.append(next_id)
	# A secret hangs off its host rather than through a realised door, so it rides along with it.
	for secret_id in graph.secret_ids:
		if not placements.has(secret_id):
			continue
		var slot := graph.get_slot(secret_id)
		if slot != null and reachable.has(slot.secret_parent_id):
			reachable[secret_id] = true
	var kept: Array = []
	for room in assignment.get("rooms", []):
		var layout_id := str(room.get("layout_id", ""))
		if placements.has(layout_id) and reachable.has(layout_id):
			kept.append(room)
	var pruned := assignment.duplicate(true)
	pruned["rooms"] = kept
	var kept_ids := {}
	for room in kept:
		kept_ids[str(room.get("layout_id", ""))] = true
	var secrets_kept: Array = []
	for secret_id in assignment.get("secret_layout_ids", graph.secret_ids):
		if kept_ids.has(str(secret_id)):
			secrets_kept.append(secret_id)
	pruned["secret_layout_ids"] = secrets_kept
	var pruned_placements := {}
	for layout_id in placements:
		if kept_ids.has(str(layout_id)):
			pruned_placements[layout_id] = placements[layout_id]
	var pruned_realised := {}
	for key in realised:
		var edge: Dictionary = realised[key]
		if kept_ids.has(str(edge["from"])) and kept_ids.has(str(edge["to"])):
			pruned_realised[key] = edge
	return {
		"assignment": pruned,
		"layout":
		{
			"placements": pruned_placements,
			"realised_edges": pruned_realised,
			"dropped": layout.get("dropped", []),
			"ok": true,
		},
	}


static func _rebuild_canonical_graph(
	graph: RoomGraph, assignment: Dictionary, layout: Dictionary
) -> void:
	var kept_ids := {}
	for room in assignment.get("rooms", []):
		kept_ids[str(room.get("layout_id", ""))] = true
	for cell in graph.occupied_cells():
		var slot := graph.get_slot_at(cell)
		if slot != null and not kept_ids.has(slot.slot_id):
			graph.remove_slot(cell)
	var original_loop_keys := {}
	for edge in graph.loop_edges:
		if edge is Dictionary:
			original_loop_keys[str(edge.get("key", ""))] = true
	graph.walk_edges.clear()
	graph.loop_edges.clear()
	for cell in graph.occupied_cells():
		var slot := graph.get_slot_at(cell)
		if slot != null and slot.slot_type != RoomGraphSlot.SlotType.SECRET:
			slot.door_mask = 0
	for key in layout.get("realised_edges", {}):
		var edge: Dictionary = layout["realised_edges"][key]
		var from_slot := graph.get_slot(str(edge.get("from", "")))
		var to_slot := graph.get_slot(str(edge.get("to", "")))
		if from_slot == null or to_slot == null:
			continue
		var delta := to_slot.grid_pos - from_slot.grid_pos
		if absi(delta.x) + absi(delta.y) != 1:
			continue
		from_slot.door_mask |= RoomGraphGeometry.dir_to_door(delta)
		to_slot.door_mask |= RoomGraphGeometry.dir_to_door(-delta)
		var canonical := {"key": str(key), "a": from_slot.grid_pos, "b": to_slot.grid_pos}
		if original_loop_keys.has(str(key)):
			graph.loop_edges.append(canonical)
		else:
			graph.walk_edges.append(canonical)
	graph.secret_ids = graph.secret_ids.filter(func(id: String) -> bool: return kept_ids.has(id))
	if not kept_ids.has(graph.treasure_id):
		graph.treasure_id = ""
	if not kept_ids.has(graph.stairs_id):
		graph.stairs_id = ""
	RoomGraphPaths.invalidate(graph)
	var distances := RoomGraphPaths.bfs_distances(graph, graph.start_id)
	var critical := RoomGraphPaths.critical_path_ids(graph)
	for cell in graph.occupied_cells():
		var slot := graph.get_slot_at(cell)
		if slot == null:
			continue
		slot.graph_distance = int(distances.get(slot.slot_id, -1))
		slot.on_critical_path = slot.slot_id in critical


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
	var approaches: Array = final_floor.get("approaches", ["direct", "side_lobby", "prep_alcove"])
	var approach := str(approaches[posmod(run_seed, approaches.size())]) if not approaches.is_empty() else "direct"
	var layout := _build_final_floor_layout(prefix, approach)
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
		"finaleApproach": approach,
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


static func _build_final_floor_layout(prefix: String, approach: String = "direct") -> Dictionary:
	var entrance_id := "%s_entrance" % prefix
	var arena_id := "%s_arena" % prefix
	var boss_id := "%s_boss" % prefix
	var entrance_spec := RoomTemplateCatalogScript.get_spec(entrance_id)
	var arena_spec := RoomTemplateCatalogScript.get_spec(arena_id)
	var boss_spec := RoomTemplateCatalogScript.get_spec(boss_id)
	var arena_z := float(entrance_spec["half_depth"]) + float(arena_spec["half_depth"])
	var boss_z := arena_z + float(arena_spec["half_depth"]) + float(boss_spec["half_depth"])
	var approach_x := -8.0 if approach == "side_lobby" else 8.0 if approach == "prep_alcove" else 0.0
	return {
		"rooms":
		[
			{
				"id": "entrance",
				"templateId": entrance_id,
				"type": "hub",
				"transform": {"x": approach_x, "y": 0.0, "z": 0.0, "yaw": 0.0},
				"tags": ["spawn", "final_lobby", approach],
				"size": {"x": float(entrance_spec["width"]), "z": float(entrance_spec["depth"])},
				"kind": "entrance",
			},
			{
				"id": "arena",
				"templateId": arena_id,
				"type": "arena",
				"transform": {"x": approach_x, "y": 0.0, "z": arena_z, "yaw": 0.0},
				"tags": ["final_arena", approach],
				"size": {"x": float(arena_spec["width"]), "z": float(arena_spec["depth"])},
				"kind": "combat",
			},
			{
				"id": "boss",
				"templateId": boss_id,
				"type": "boss",
				"transform": {"x": approach_x, "y": 0.0, "z": boss_z, "yaw": 0.0},
				"tags": ["final_boss", approach],
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


static func _build_landmark_hints(rooms: Array, graph: RoomGraph, assignment: Dictionary = {}) -> Array:
	var landmarks: Array = []
	var layout_by_semantic := {}
	for assigned_room in assignment.get("rooms", []):
		layout_by_semantic[str(assigned_room.get("semantic_id", ""))] = str(assigned_room.get("layout_id", ""))
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
	for room in rooms:
		if not room is Dictionary:
			continue
		var room_id := str(room.get("id", ""))
		var slot := graph.get_slot(str(layout_by_semantic.get(room_id, room_id)))
		if slot == null or _count_set_bits(int(slot.door_mask)) < 3:
			continue
		var transform: Dictionary = room.get("transform", {})
		var position := Vector3(float(transform.get("x", 0.0)), float(transform.get("y", 0.0)), float(transform.get("z", 0.0)))
		landmarks.append({"kind": "junction_beacon", "roomId": room_id, "position": {"x": position.x, "y": position.y + 9.0, "z": position.z}, "scale": {"x": 1.25, "y": 12.0, "z": 1.25}})
	return landmarks


static func _build_expedition_objective(
	graph: RoomGraph, assignment: Dictionary, _content: Dictionary, floor_index: int
) -> Dictionary:
	var candidates: Array = []
	for room in assignment.get("rooms", []):
		var layout_id := str(room.get("layout_id", ""))
		if layout_id == graph.start_id or layout_id == graph.boss_id or layout_id == graph.stairs_id:
			continue
		var slot := graph.get_slot(layout_id)
		if slot != null and not slot.on_critical_path:
			candidates.append(str(room.get("semantic_id", "")))
	if candidates.is_empty():
		return {"kind": "reach_boss", "required": true}
	var kinds := ["restore_elevator", "interrupt_ritual", "rescue_guide"]
	var kind := str(kinds[posmod(floor_index - 1, kinds.size())])
	return {"kind": kind, "roomId": candidates[0], "required": false, "reward": "route_knowledge"}


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


## RM-05: `locks` carries the actual lock/key relationship (`to` is the room behind the door,
## `keyRoomIds` are where its key(s) sit, `keyColor` is `FloorKeyring`'s colour string) -- reading
## it here, rather than a `roomContent`-entry field nothing ever wrote, is what lets the minimap
## draw the lock mark and the key room in the same colour instead of a colourless generic mark.
static func _annotate_minimap_rooms(rooms: Array, room_content: Array, locks: Array = []) -> void:
	var content_kind := {}
	for entry in room_content:
		if not entry is Dictionary:
			continue
		var room_id := str(entry.get("roomId", ""))
		var content_type := str(entry.get("contentType", ""))
		if MINIMAP_KIND_BY_CONTENT.has(content_type):
			content_kind[room_id] = str(MINIMAP_KIND_BY_CONTENT[content_type])
	var locked_rooms := {}
	var key_room_colors := {}
	for lock in locks:
		if not lock is Dictionary:
			continue
		var lock_dict: Dictionary = lock
		var color := str(lock_dict.get("keyColor", ""))
		var to_room := str(lock_dict.get("to", ""))
		if to_room != "":
			locked_rooms[to_room] = color
		for key_room in lock_dict.get("keyRoomIds", []):
			key_room_colors[str(key_room)] = color
	for room in rooms:
		if not room is Dictionary:
			continue
		var room_id := str(room.get("id", ""))
		var current_kind := str(room.get("kind", ""))
		if current_kind not in MINIMAP_RESERVED_KINDS and content_kind.has(room_id):
			room["kind"] = content_kind[room_id]
		if locked_rooms.has(room_id):
			room["locked"] = true
			room["lockColor"] = locked_rooms[room_id]
		if key_room_colors.has(room_id):
			room["keyColor"] = key_room_colors[room_id]


## RM-04: `shortcutGates` (the barred-door content) and `edges` (the minimap's own connection list)
## are built by two separate systems and only meet here. This tags the matching `edges` entry so
## `minimap.gd` can draw a chevron toward `openRoomId` instead of a plain line, without minimap.gd
## needing to know the gate/content schema at all.
static func _annotate_one_way_edges(edges: Array, shortcut_gates: Array) -> void:
	if shortcut_gates.is_empty():
		return
	var open_room_by_pair := {}
	for gate in shortcut_gates:
		if not gate is Dictionary:
			continue
		var room_a := str((gate as Dictionary).get("roomA", ""))
		var room_b := str((gate as Dictionary).get("roomB", ""))
		var open_room := str((gate as Dictionary).get("openRoomId", ""))
		if room_a == "" or room_b == "" or open_room == "":
			continue
		open_room_by_pair[_pair_key(room_a, room_b)] = open_room
	for edge in edges:
		if not edge is Dictionary:
			continue
		var from_id := str((edge as Dictionary).get("from", ""))
		var to_id := str((edge as Dictionary).get("to", ""))
		var open_room: Variant = open_room_by_pair.get(_pair_key(from_id, to_id))
		if open_room == null:
			continue
		(edge as Dictionary)["oneWay"] = "gate"
		(edge as Dictionary)["openRoomId"] = open_room


static func _pair_key(a: String, b: String) -> String:
	return "%s|%s" % [a, b] if a < b else "%s|%s" % [b, a]


static func _count_set_bits(value: int) -> int:
	var remaining := value
	var count := 0
	while remaining != 0:
		count += remaining & 1
		remaining >>= 1
	return count
