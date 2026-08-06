extends "res://scripts/validation/validation_suite.gd"

const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")


func get_category() -> String:
	return "procgen"


func run() -> void:
	_test_generation()
	_test_write_v2_fixture()
	_test_definition_matches_v2_schema()
	_test_final_floor_boss_matches_biome()
	_test_offline_run_flow()
	_test_cli_json_extraction()
	_test_castle_run_no_fixture_fallback()
	_test_placement_offset_compat()
	_test_seed_determinism_across_tiers()
	_test_tier_seed_uniqueness()
	_test_floor_seed_identity()
	_test_floor_seed_decorrelation()
	_test_no_silent_cli_fallback()
	_test_validator_rejects_broken_definitions()
	_test_rolled_seed_replay()
	await _test_dungeon_builder_empty_rejection()


func _test_generation() -> void:
	var start := Time.get_ticks_msec()
	var gen_a := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	ctx.timed_record(
		"procgen.seed_generates",
		get_category(),
		gen_a.get("ok", false),
		(
			"seed %d generates dungeon" % TC.SEED_A
			if gen_a.get("ok", false)
			else gen_a.get("error", "failed")
		),
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


func _test_write_v2_fixture() -> void:
	var start := Time.get_ticks_msec()
	var gen_result: Dictionary = DungeonProcgenScript.generate(
		"forgotten_castle", 4242, 1, 1, 1, false, false
	)
	var ok: bool = gen_result.get("ok", false) == true
	if ok:
		var path := ContentLoader.content_path(
			"content/fixtures/dungeon_definition_v2_gdscript.json"
		)
		var file := FileAccess.open(path, FileAccess.WRITE)
		if file != null:
			file.store_string(JSON.stringify(gen_result.get("definition", {}), "\t"))
			file.close()
		else:
			ok = false
	ctx.timed_record(
		"procgen.write_v2_fixture",
		get_category(),
		ok,
		"Wrote content/fixtures/dungeon_definition_v2_gdscript.json for seed 4242",
		start,
		"RGP-01"
	)


func _test_definition_matches_v2_schema() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var room_types := {
		"combat": true,
		"treasure": true,
		"puzzle": true,
		"boss": true,
		"hub": true,
		"corridor": true,
		"secret": true,
		"filler": true,
		"shop": true,
		"obstacle": true,
		"arena": true,
	}
	var allowed_root := {
		"schemaVersion": true,
		"runId": true,
		"seed": true,
		"biomeId": true,
		"tier": true,
		"playerLevelSnapshot": true,
		"rooms": true,
		"edges": true,
		"placements": true,
		"budgets": true,
		"floorIndex": true,
		"isFinalFloor": true,
		"maxHeightLevel": true,
		"roomContent": true,
		"locks": true,
		"puzzles": true,
		"branchPreviews": true,
		"landmarks": true,
		"checksum": true,
	}
	for biome_id in [
		"forgotten_castle",
		"crystal_caverns",
		"poison_swamp",
		"frozen_fortress",
		"dark_cathedral",
		"iron_vault",
		"prism_depths",
		"venom_mire",
		"glacial_hollow",
		"umbral_chapel",
	]:
		for i in 20:
			var gen: Dictionary = LocalProcgen.generate(biome_id, TC.SEED_A + i * 503)
			if not gen.get("ok", false):
				ok = false
				break
			var def: Dictionary = gen.get("definition", {})
			if int(def.get("schemaVersion", 0)) != 2:
				ok = false
				break
			for key in def.keys():
				if not allowed_root.has(key):
					ok = false
					break
			if not ok:
				break
			for room in def.get("rooms", []):
				if not room_types.has(str(room.get("type", ""))):
					ok = false
					break
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"procgen.definition_matches_v2_schema",
		get_category(),
		ok,
		"Generated definitions match v2 closed-object rules (20 seeds x 10 biomes)",
		start,
		"RGP-01"
	)


func _test_final_floor_boss_matches_biome() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in [
		"forgotten_castle",
		"crystal_caverns",
		"poison_swamp",
		"frozen_fortress",
		"dark_cathedral",
		"iron_vault",
		"prism_depths",
		"venom_mire",
		"glacial_hollow",
		"umbral_chapel",
	]:
		var biome := ContentLoader.load_json("content/biomes/%s.json" % biome_id)
		var boss_pool: Array = biome.get("bossPool", [])
		var pool_ids: Array[String] = []
		for entry in boss_pool:
			if entry is Dictionary:
				pool_ids.append(str(entry.get("enemyId", "")))
		var final_floor: Dictionary = biome.get("finalFloor", {})
		var final_boss: String = str(final_floor.get("bossId", ""))
		var gen := DungeonProcgenScript.generate(biome_id, TC.SEED_A, 1, 1, 10, true, false)
		if not gen.get("ok", false):
			ok = false
			break
		var placements: Dictionary = gen.get("definition", {}).get("placements", {})
		var boss_entry: Dictionary = placements.get("boss", {})
		var boss_id: String = str(boss_entry.get("enemyId", ""))
		if boss_id != final_boss and not pool_ids.has(boss_id):
			ok = false
			break
	ctx.timed_record(
		"procgen.final_floor_boss_matches_biome",
		get_category(),
		ok,
		"Final-floor boss id comes from biome finalFloor.bossId or bossPool",
		start,
		"RGP-08"
	)


func _test_offline_run_flow() -> void:
	var start := Time.get_ticks_msec()
	# NET-5.1: optional online path exists but must stay disabled by default (M3 offline lock).
	var offline_default: bool = (
		ctx.file_contains("res://scripts/app/run_flow.gd", "const USE_ONLINE_PROCgen := false")
		or ctx.file_contains(
			"res://scripts/app/run_flow.gd", "const USE_ONLINE_PROCgen: bool = false"
		)
	)
	ctx.timed_record(
		"procgen.offline_no_api_in_run_flow",
		get_category(),
		offline_default,
		"RunFlow offline procgen is default (USE_ONLINE_PROCgen false)",
		start,
		"M3.procgen.offline"
	)


func _test_cli_json_extraction() -> void:
	var start := Time.get_ticks_msec()
	var noisy := 'Building...\n{"rooms":[{"id":"entrance"}],"seed":42}'
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


func _test_placement_offset_compat() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	if not gen.get("ok", false):
		ctx.timed_record(
			"procgen.placement_offset_field",
			get_category(),
			false,
			"generation failed before offset check",
			start,
			"M3.procgen.offset"
		)
		return
	var placements: Dictionary = gen.get("definition", {}).get("placements", {})
	var enemies: Array = placements.get("enemies", [])
	var has_offset := false
	for enemy in enemies:
		if enemy is Dictionary and enemy.has("offset"):
			has_offset = true
			break
	var builder_reads_offset: bool = ctx.file_contains(
		"res://scripts/dungeon/dungeon_builder.gd",
		'placement.get("offset", placement.get("position", {}))'
	)
	ctx.timed_record(
		"procgen.placement_offset_field",
		get_category(),
		has_offset and builder_reads_offset,
		"procgen emits offset and builder accepts offset/position",
		start,
		"M3.procgen.offset"
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


const DungeonDefinitionValidatorScript := preload("res://scripts/dungeon/dungeon_definition_validator.gd")

const _BIOME_IDS := [
	"forgotten_castle",
	"crystal_caverns",
	"poison_swamp",
	"frozen_fortress",
	"dark_cathedral",
	"iron_vault",
	"prism_depths",
	"venom_mire",
	"glacial_hollow",
	"umbral_chapel",
]

const _FLOOR_SEED_SAMPLES := [1, 2, 12345, 2147483646]


func _test_seed_determinism_across_tiers() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for tier in range(1, 11):
		var gen_a := LocalProcgen.generate("forgotten_castle", 4242, 1, "castle", tier)
		var gen_b := LocalProcgen.generate("forgotten_castle", 4242, 1, "castle", tier)
		if not gen_a.get("ok", false) or not gen_b.get("ok", false):
			ok = false
			break
		if (
			ctx.layout_signature(gen_a.get("definition", {}))
			!= ctx.layout_signature(gen_b.get("definition", {}))
			or int(gen_a.get("generation_seed", -1)) != int(gen_b.get("generation_seed", -2))
		):
			ok = false
			break
	ctx.timed_record(
		"procgen.seed_determinism_across_tiers",
		get_category(),
		ok,
		"tier seeds 1..10 deterministic for base seed 4242",
		start,
		"LPG.procgen.tier_determinism"
	)


func _test_tier_seed_uniqueness() -> void:
	var start := Time.get_ticks_msec()
	var seen := {}
	var ok := true
	for tier in range(1, 11):
		var tier_seed := DungeonSeedService.derive_tier_seed(4242, tier)
		if seen.has(tier_seed):
			ok = false
			break
		seen[tier_seed] = true
	ctx.timed_record(
		"procgen.tier_seed_uniqueness",
		get_category(),
		ok,
		"derive_tier_seed(4242, tier) unique for tiers 1..10",
		start,
		"LPG.procgen.tier_unique"
	)


func _test_floor_seed_identity() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for seed in _FLOOR_SEED_SAMPLES:
		if RunFloorConfig.mix_seed(seed, 1) != seed:
			ok = false
			break
	ctx.timed_record(
		"procgen.floor_seed_identity",
		get_category(),
		ok,
		"mix_seed(s, 1) == s for sample seeds",
		start,
		"LPG.procgen.floor_identity"
	)


func _test_floor_seed_decorrelation() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for seed in _FLOOR_SEED_SAMPLES:
		for floor in range(2, 26):
			var delta := absi(RunFloorConfig.mix_seed(seed, floor) - RunFloorConfig.mix_seed(seed, floor - 1))
			if delta == RunFloorConfig.FLOOR_SEED_MULTIPLIER:
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"procgen.floor_seed_decorrelation",
		get_category(),
		ok,
		"adjacent floor seeds no longer differ by 7919",
		start,
		"LPG.procgen.floor_decorrelation"
	)


func _test_no_silent_cli_fallback() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_index in _BIOME_IDS.size():
		for i in range(5):
			var gen := LocalProcgen.generate(_BIOME_IDS[biome_index], 1000 + biome_index * 97 + i)
			if not gen.get("ok", false) or str(gen.get("generator", "")) != "gdscript":
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"procgen.no_silent_cli_fallback",
		get_category(),
		ok,
		"50 seeds across 10 biomes stay on gdscript generator",
		start,
		"LPG.procgen.no_cli"
	)


func _test_validator_rejects_broken_definitions() -> void:
	var start := Time.get_ticks_msec()
	var base := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var ok: bool = base.get("ok", false) == true
	if ok:
		var def: Dictionary = base.get("definition", {}).duplicate(true)
		var dup := def.duplicate(true)
		var rooms: Array = dup.get("rooms", [])
		if rooms.size() >= 2 and rooms[0] is Dictionary and rooms[1] is Dictionary:
			rooms[1]["id"] = rooms[0].get("id", "")
			ok = "room_ids_unique" in DungeonDefinitionValidatorScript.validate(dup).get("errors", [])
		dup = def.duplicate(true)
		var edges: Array = dup.get("edges", [])
		if ok and not edges.is_empty() and edges[0] is Dictionary:
			edges[0]["to"] = "missing_room_id"
			ok = "edge_endpoints_exist" in DungeonDefinitionValidatorScript.validate(dup).get("errors", [])
		dup = def.duplicate(true)
		var placements: Dictionary = dup.get("placements", {})
		if ok and placements.get("exit") is Dictionary:
			placements["exit"]["roomId"] = "unreachable_exit"
			ok = "exit_reachable" in DungeonDefinitionValidatorScript.validate(dup).get("errors", [])
		dup = def.duplicate(true)
		var overlap_rooms: Array = dup.get("rooms", [])
		if ok and overlap_rooms.size() >= 2 and overlap_rooms[0] is Dictionary:
			var transform: Dictionary = overlap_rooms[0].get("transform", {})
			overlap_rooms[1]["transform"] = transform.duplicate(true)
			ok = "no_room_overlap" in DungeonDefinitionValidatorScript.validate(dup).get("errors", [])
		dup = def.duplicate(true)
		var bad_rooms: Array = dup.get("rooms", [])
		if ok and not bad_rooms.is_empty() and bad_rooms[0] is Dictionary:
			bad_rooms[0]["templateId"] = "missing_template_id"
			ok = "room_template_resolves" in DungeonDefinitionValidatorScript.validate(dup).get("errors", [])
	ctx.timed_record(
		"procgen.validator_rejects_broken_definitions",
		get_category(),
		ok,
		"DungeonDefinitionValidator returns expected error codes",
		start,
		"LPG.procgen.validator"
	)


func _test_rolled_seed_replay() -> void:
	var start := Time.get_ticks_msec()
	var rolled := LocalProcgen.generate("forgotten_castle", null)
	var ok: bool = rolled.get("ok", false) == true
	var replay_sig := ""
	var rolled_sig := ""
	if ok:
		var input_seed := int(rolled.get("input_seed", 0))
		rolled_sig = ctx.layout_signature(rolled.get("definition", {}))
		var replay := LocalProcgen.generate("forgotten_castle", input_seed)
		ok = replay.get("ok", false)
		if ok:
			replay_sig = ctx.layout_signature(replay.get("definition", {}))
			ok = replay_sig == rolled_sig and not replay_sig.is_empty()
	ctx.timed_record(
		"procgen.rolled_seed_replay",
		get_category(),
		ok,
		"replaying rolled input_seed reproduces layout signature",
		start,
		"LPG.procgen.rolled_replay"
	)
