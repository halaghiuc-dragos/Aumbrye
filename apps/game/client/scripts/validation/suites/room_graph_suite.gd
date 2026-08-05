extends "res://scripts/validation/validation_suite.gd"

const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphDebugScript := preload("res://scripts/dungeon/procgen/room_graph_debug.gd")
const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const ProcgenBiomeLoaderScript := preload("res://scripts/dungeon/procgen/procgen_biome_loader.gd")


func get_category() -> String:
	return "room_graph"


func run() -> void:
	_test_phase1_deterministic()
	_test_phase1_ascii()
	_test_phase1_validation_fields()
	_test_phase1_variation()
	_test_phase1_no_fallback()
	_test_full_pipeline()


func _test_phase1_deterministic() -> void:
	var start := Time.get_ticks_msec()
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var a := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var b := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph_a: RoomGraph = a.get("graph")
	var graph_b: RoomGraph = b.get("graph")
	var ok: bool = (
		a.get("ok", false)
		and b.get("ok", false)
		and graph_a.occupied_ids().size() == graph_b.occupied_ids().size()
		and graph_a.boss_id == graph_b.boss_id
	)
	ctx.timed_record(
		"room_graph.phase1_deterministic",
		get_category(),
		ok,
		"Phase 1 graph is deterministic for seed %d" % TC.SEED_A,
		start,
		"M8.room_graph.determinism"
	)


func _test_phase1_ascii() -> void:
	var start := Time.get_ticks_msec()
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result := RoomGraphGeneratorScript.generate(config, TC.SEED_B)
	var graph: RoomGraph = result.get("graph")
	var ascii := RoomGraphDebugScript.render_ascii(graph)
	var ok: bool = ascii.contains("Start=") and ascii.contains("Boss=")
	ctx.timed_record(
		"room_graph.phase1_ascii",
		get_category(),
		ok,
		"ASCII debug renderer includes start/boss markers",
		start,
		"M8.room_graph.ascii"
	)


func _test_phase1_validation_fields() -> void:
	var start := Time.get_ticks_msec()
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = result.get("graph")
	var main_count := 0
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type != RoomGraphSlot.SlotType.SECRET:
			main_count += 1
	var ok: bool = (
		result.get("ok", false)
		and graph.start_id != ""
		and graph.boss_id != ""
		and main_count >= config.min_rooms
	)
	ctx.timed_record(
		"room_graph.phase1_validated",
		get_category(),
		ok,
		"Phase 1 graph has start/boss and >= %d rooms (got %d)" % [config.min_rooms, main_count],
		start,
		"M8.room_graph.validation"
	)


func _test_phase1_variation() -> void:
	var start := Time.get_ticks_msec()
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result_a := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var result_b := RoomGraphGeneratorScript.generate(config, TC.SEED_B)
	var graph_a: RoomGraph = result_a.get("graph")
	var graph_b: RoomGraph = result_b.get("graph")
	var sig_a := "|".join(graph_a.occupied_ids())
	var sig_b := "|".join(graph_b.occupied_ids())
	var ok: bool = result_a.get("ok", false) and result_b.get("ok", false) and sig_a != sig_b
	ctx.timed_record(
		"room_graph.phase1_variation",
		get_category(),
		ok,
		"Different seeds produce different layout signatures",
		start,
		"M8.room_graph.variation"
	)


func _test_phase1_no_fallback() -> void:
	var start := Time.get_ticks_msec()
	var biome := ProcgenBiomeLoaderScript.load("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var ok: bool = result.get("ok", false) and not result.get("used_fallback", false)
	ctx.timed_record(
		"room_graph.phase1_no_fallback",
		get_category(),
		ok,
		"Phase 1 generation does not use fallback layout for seed %d" % TC.SEED_A,
		start,
		"M8.room_graph.no_fallback"
	)


func _test_full_pipeline() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var def: Dictionary = gen.get("definition", {})
	var rooms: Array = def.get("rooms", [])
	var ok: bool = (
		gen.get("ok", false)
		and rooms.size() >= 8
		and not gen.get("used_fallback", false)
	)
	ctx.timed_record(
		"room_graph.full_pipeline",
		get_category(),
		ok,
		"Phase 1+2 pipeline produces %d rooms" % rooms.size(),
		start,
		"M8.room_graph.pipeline"
	)

	start = Time.get_ticks_msec()
	var gen2 := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var sig1: String = ctx.layout_signature(def)
	var sig2: String = ctx.layout_signature(gen2.get("definition", {}))
	ctx.timed_record(
		"room_graph.full_deterministic",
		get_category(),
		sig1 == sig2 and not sig1.is_empty(),
		"Full pipeline is deterministic for seed %d" % TC.SEED_A,
		start,
		"M8.room_graph.full_determinism"
	)
