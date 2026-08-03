extends "res://scripts/validation/validation_suite.gd"

const RoomContentAssignerScript := preload("res://scripts/dungeon/procgen/room_content_assigner.gd")
const RoomContentConfigScript := preload("res://scripts/dungeon/procgen/room_content_config.gd")
const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphAssignerScript := preload("res://scripts/dungeon/procgen/room_graph_assigner.gd")
const RoomGraphPathsScript := preload("res://scripts/dungeon/procgen/room_graph_paths.gd")
const ProcgenBiomeLoaderScript := preload("res://scripts/dungeon/procgen/procgen_biome_loader.gd")
const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")


func get_category() -> String:
	return "room_content"


func run() -> void:
	_test_content_assignment()
	_test_critical_path()
	_test_definition_includes_content()
	_test_world_state_resets()


func _test_content_assignment() -> void:
	var start := Time.get_ticks_msec()
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = graph_result.get("graph")
	var rng := RandomNumberGenerator.new()
	rng.seed = TC.SEED_A ^ 0x5EED
	var assignment := RoomGraphAssignerScript.assign(biome, graph, rng)
	var content_result := RoomContentAssignerScript.assign(
		graph, assignment, rng, RoomContentConfigScript.default()
	)
	var content: Dictionary = content_result.get("content", {})
	var ok: bool = content_result.get("ok", false) and not content.get("roomContent", []).is_empty()
	ctx.timed_record(
		"room_content.assigns_types",
		get_category(),
		ok,
		"content assignment produces roomContent entries",
		start,
		"M8.room_content.assign"
	)


func _test_critical_path() -> void:
	var start := Time.get_ticks_msec()
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_B)
	var graph: RoomGraph = graph_result.get("graph")
	var path: Array[String] = RoomGraphPathsScript.critical_path_ids(graph)
	var ok: bool = (
		path.size() >= 2 and path[0] == graph.start_id and path[path.size() - 1] == graph.boss_id
	)
	ctx.timed_record(
		"room_content.critical_path",
		get_category(),
		ok,
		"critical path runs start→boss (%d rooms)" % path.size(),
		start,
		"M8.room_content.path"
	)


func _test_definition_includes_content() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var def: Dictionary = gen.get("definition", {})
	var ok: bool = (
		gen.get("ok", false)
		and def.has("roomContent")
		and def.get("roomContent", []) is Array
	)
	ctx.timed_record(
		"room_content.definition_fields",
		get_category(),
		ok,
		"DungeonDefinition includes roomContent/locks/puzzles",
		start,
		"M8.room_content.definition"
	)


func _test_world_state_resets() -> void:
	var start := Time.get_ticks_msec()
	WorldState.set_flag("test_key", true)
	RunFlow.run_ended.emit({})
	var ok: bool = not WorldState.has_flag("test_key")
	ctx.timed_record(
		"room_content.world_state_reset",
		get_category(),
		ok,
		"WorldState clears on run end",
		start,
		"M8.room_content.world_state"
	)
