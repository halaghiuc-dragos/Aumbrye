extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "procgen"


func run() -> void:
	_test_generation()
	_test_offline_run_flow()
	_test_cli_json_extraction()
	_test_castle_run_no_fixture_fallback()
	await _test_dungeon_builder_empty_rejection()


func _test_generation() -> void:
	var start := Time.get_ticks_msec()
	var gen_a := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	ctx.timed_record(
		"procgen.seed_generates",
		get_category(),
		gen_a.get("ok", false),
		"seed %d generates dungeon" % TC.SEED_A if gen_a.get("ok", false) else gen_a.get("error", "failed"),
		start,
		"M3.procgen.seed"
	)
	if not gen_a.get("ok", false):
		return

	var def_a: Dictionary = gen_a.get("definition", {})
	var rooms: Array = def_a.get("rooms", [])
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"procgen.has_rooms",
		get_category(),
		not rooms.is_empty(),
		"%d rooms in definition" % rooms.size(),
		start,
		"M3.procgen.rooms"
	)

	start = Time.get_ticks_msec()
	var gen_a2 := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var sig1: String = ctx.layout_signature(def_a)
	var sig2: String = ctx.layout_signature(gen_a2.get("definition", {}))
	ctx.timed_record(
		"procgen.same_seed_deterministic",
		get_category(),
		sig1 == sig2 and not sig1.is_empty(),
		"seed %d produces identical layout signature" % TC.SEED_A,
		start,
		"M3.procgen.determinism"
	)

	start = Time.get_ticks_msec()
	var gen_b := LocalProcgen.generate("forgotten_castle", TC.SEED_B)
	var sig_b: String = ctx.layout_signature(gen_b.get("definition", {}))
	ctx.timed_record(
		"procgen.different_seeds_differ",
		get_category(),
		sig_b != sig1,
		"seeds %d and %d produce different layouts" % [TC.SEED_A, TC.SEED_B],
		start,
		"M3.procgen.variety"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"procgen.not_m2_fixture",
		get_category(),
		not ctx.matches_m2_fixture(def_a),
		"generated layout is not the hand-authored M2 fixture",
		start,
		"M3.procgen.not_fixture"
	)

	start = Time.get_ticks_msec()
	var found_variety := false
	for i in range(20):
		var g := LocalProcgen.generate("forgotten_castle", 1000 + i)
		if not g.get("ok", false):
			continue
		for room in g.get("definition", {}).get("rooms", []):
			var tid: String = room.get("templateId", "")
			if tid == "castle_hall" or tid == "castle_arena":
				found_variety = true
				break
		if found_variety:
			break
	ctx.timed_record(
		"procgen.hall_or_arena_templates",
		get_category(),
		found_variety,
		"hall/arena templates appear across sample seeds",
		start,
		"M3.procgen.templates"
	)

	start = Time.get_ticks_msec()
	var gen_random := LocalProcgen.generate("forgotten_castle", null)
	ctx.timed_record(
		"procgen.random_seed",
		get_category(),
		gen_random.get("ok", false),
		"random new-run seed generates successfully",
		start,
		"M3.procgen.random"
	)


func _test_offline_run_flow() -> void:
	var start := Time.get_ticks_msec()
	var uses_api_for_dungeon: bool = (
		ctx.file_contains("res://scripts/app/run_flow.gd", "ApiClient.create_run")
		or ctx.file_contains("res://scripts/app/run_flow.gd", "ApiClient.get_dungeon")
	)
	ctx.timed_record(
		"procgen.offline_no_api_in_run_flow",
		get_category(),
		not uses_api_for_dungeon,
		"RunFlow does not call ApiClient for dungeon creation",
		start,
		"M3.procgen.offline"
	)


func _test_cli_json_extraction() -> void:
	var start := Time.get_ticks_msec()
	var noisy := "Building...\n{\"rooms\":[{\"id\":\"entrance\"}],\"seed\":42}"
	var extracted := LocalProcgen._extract_json_text(noisy)
	var parsed: Variant = JSON.parse_string(extracted)
	var ok: bool = parsed is Dictionary and parsed.get("seed", 0) == 42
	ctx.timed_record(
		"procgen.cli_json_stripped",
		get_category(),
		ok,
		"LocalProcgen strips CLI noise before JSON parse",
		start,
		"M3.procgen.cli"
	)


func _test_castle_run_no_fixture_fallback() -> void:
	var start := Time.get_ticks_msec()
	var no_fixture: bool = (
		not ctx.file_contains("res://scripts/dungeon/castle_run.gd", "forgotten_castle_slice")
		and ctx.file_contains("res://scripts/dungeon/castle_run.gd", "def.is_empty()")
	)
	ctx.timed_record(
		"procgen.castle_run_no_fixture_fallback",
		get_category(),
		no_fixture,
		"castle_run rejects empty definition without M2 fixture fallback",
		start,
		"M3.procgen.castle_run"
	)


func _test_dungeon_builder_empty_rejection() -> void:
	var start := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "EmptyDefTest"
	ctx.owner.add_child(root)
	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate() as CharacterBody3D
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, {})
	await ctx.await_frame()
	var room_count: int = builder.get_room_ids().size()
	ctx.timed_record(
		"procgen.builder_rejects_empty",
		get_category(),
		room_count == 0,
		"dungeon_builder builds 0 rooms from empty definition",
		start,
		"M3.procgen.builder"
	)
	root.queue_free()
