extends "res://scripts/validation/validation_suite.gd"

const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const ProcgenSeedHealthScript := preload("res://scripts/tools/procgen_seed_health.gd")

const BIOME_IDS := [
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


func get_category() -> String:
	return "procgen_seed_health"


func run() -> void:
	_test_generate_reported_matches_generate()
	_test_attempt_accounting()
	_test_no_static_reason_leak()
	_test_sweep_deterministic()
	_test_report_schema_valid()
	_test_fallback_rate_threshold()
	_test_all_biomes_generate()
	_test_exit_code_contract()
	_test_user_args_ignore_engine_flags()


func _test_generate_reported_matches_generate() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var ok := true
	for i in 50:
		var seed_value := TC.SEED_A + i * 17
		var reported := RoomGraphGeneratorScript.generate_reported(config, seed_value)
		var generated := RoomGraphGeneratorScript.generate(config, seed_value)
		if reported.used_fallback != bool(generated.get("used_fallback", false)):
			ok = false
			break
		if reported.ok != bool(generated.get("ok", false)):
			ok = false
			break
		if not reported.ok:
			continue
		if not _graphs_match(reported.graph, generated.get("graph")):
			ok = false
			break
	ctx.timed_record(
		"procgen_seed_health.generate_reported_matches_generate",
		get_category(),
		ok,
		"generate_reported used_fallback and graph match generate() for 50 seeds",
		start,
		"FGS-01"
	)


func _test_attempt_accounting() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	config.min_dead_ends = 999
	config.max_generation_attempts = 3
	var report := RoomGraphGeneratorScript.generate_reported(config, TC.SEED_A)
	var ok: bool = (
		report.attempts == config.max_generation_attempts
		and not report.ok
		and not report.used_fallback
		and report.reasons.size() == config.max_generation_attempts
	)
	ctx.timed_record(
		"procgen_seed_health.attempt_accounting",
		get_category(),
		ok,
		"forced failures record one reason per attempt",
		start,
		"FGS-01"
	)


func _test_no_static_reason_leak() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var fail_config := RoomGraphConfigScript.from_biome(biome)
	fail_config.min_dead_ends = 999
	fail_config.max_generation_attempts = 2
	var ok_config := RoomGraphConfigScript.from_biome(biome)
	RoomGraphGeneratorScript.generate_reported(fail_config, TC.SEED_A)
	var success := RoomGraphGeneratorScript.generate_reported(ok_config, TC.SEED_B)
	var ok: bool = success.ok and success.reasons.is_empty()
	ctx.timed_record(
		"procgen_seed_health.no_static_reason_leak",
		get_category(),
		ok,
		"successful report reasons array is empty after prior failures",
		start,
		"FGS-06"
	)


func _test_sweep_deterministic() -> void:
	var start := Time.get_ticks_msec()
	var biomes := PackedStringArray(["forgotten_castle", "crystal_caverns"])
	var first := ProcgenSeedHealthScript.build_sweep_report(1, 50, biomes, false)
	var second := ProcgenSeedHealthScript.build_sweep_report(1, 50, biomes, false)
	var ok: bool = (
		ProcgenSeedHealthScript.serialize_report(first)
		== ProcgenSeedHealthScript.serialize_report(second)
	)
	ctx.timed_record(
		"procgen_seed_health.sweep_deterministic",
		get_category(),
		ok,
		"two sweeps over 50 seeds x 2 biomes serialize identically",
		start,
		"FGS-02"
	)


func _test_report_schema_valid() -> void:
	var start := Time.get_ticks_msec()
	var report := ProcgenSeedHealthScript.build_sweep_report(
		1, 5, PackedStringArray(["forgotten_castle"]), true
	)
	var ok := _validate_report_schema(report)
	ctx.timed_record(
		"procgen_seed_health.report_schema_valid",
		get_category(),
		ok,
		"generated report matches procgen-seed-health.v1 structural contract",
		start,
		"FGS-05"
	)


func _test_fallback_rate_threshold() -> void:
	var start := Time.get_ticks_msec()
	var report := ProcgenSeedHealthScript.build_sweep_report(
		1, 200, PackedStringArray(["forgotten_castle"]), false
	)
	var stats: Dictionary = report.get("biomes", {}).get("forgotten_castle", {})
	var rate := float(stats.get("fallbackRate", 1.0))
	var ok := rate <= 0.01
	ctx.timed_record(
		"procgen_seed_health.fallback_rate_threshold",
		get_category(),
		ok,
		"forgotten_castle fallback rate %.6f <= 0.01 over 200 seeds" % rate,
		start,
		"FGS-04"
	)


func _test_all_biomes_generate() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		var biome := BiomeRegistry.get_biome(biome_id)
		var config := RoomGraphConfigScript.from_biome(biome)
		var report := RoomGraphGeneratorScript.generate_reported(config, TC.SEED_A)
		if not report.ok or report.main_room_count < config.min_rooms:
			ok = false
			break
	ctx.timed_record(
		"procgen_seed_health.all_biomes_generate",
		get_category(),
		ok,
		"generate_reported succeeds with >= min rooms for all 10 biomes",
		start,
		"FGS-03"
	)


func _test_exit_code_contract() -> void:
	var start := Time.get_ticks_msec()
	var passing := {
		"ok": true,
		"biomes": {
			"forgotten_castle": {"fallbackRate": 0.0},
		},
	}
	var failing := {
		"ok": true,
		"biomes": {
			"forgotten_castle": {"fallbackRate": 0.5},
		},
	}
	var broken := {"ok": false, "biomes": {}}
	var ok: bool = (
		ProcgenSeedHealthScript.evaluate_exit_code(passing, 0.01) == 0
		and ProcgenSeedHealthScript.evaluate_exit_code(failing, 0.01) == 1
		and ProcgenSeedHealthScript.evaluate_exit_code(broken, 0.01) == 2
	)
	ctx.timed_record(
		"procgen_seed_health.exit_code_contract",
		get_category(),
		ok,
		"evaluate_exit_code returns 0 / 1 / 2 for pass / threshold / error",
		start,
		"FGS-04"
	)


func _test_user_args_ignore_engine_flags() -> void:
	var start := Time.get_ticks_msec()
	var options := ProcgenSeedHealthScript.parse_args(
		PackedStringArray(["--fixed-fps", "60", "--seed", "42001"])
	)
	var ok: bool = int(options.get("seed", -1)) == 42001
	ctx.timed_record(
		"procgen_seed_health.user_args_ignore_engine_flags",
		get_category(),
		ok,
		"parse_args reads --seed from user args after engine flags",
		start,
		"FGS-07"
	)


func _graphs_match(a: RoomGraph, b: Variant) -> bool:
	if a == null or not b is RoomGraph:
		return false
	var graph_b: RoomGraph = b
	if a.occupied_ids() != graph_b.occupied_ids():
		return false
	if a.boss_id != graph_b.boss_id:
		return false
	for cell in a.slots:
		var slot_a: RoomGraphSlot = a.slots[cell]
		var slot_b: RoomGraphSlot = graph_b.slots.get(cell)
		if slot_b == null:
			return false
		if slot_a.slot_type != slot_b.slot_type:
			return false
		if slot_a.door_mask != slot_b.door_mask:
			return false
	return true


func _validate_report_schema(report: Dictionary) -> bool:
	if int(report.get("schemaVersion", 0)) != 1:
		return false
	if not report.has("generatedAtUnix"):
		return false
	if not report.has("seedFrom") or not report.has("seedCount"):
		return false
	if not report.get("biomes", {}) is Dictionary:
		return false
	var totals: Variant = report.get("totals", {})
	if not totals is Dictionary:
		return false
	if not totals.has("seeds") or not totals.has("usedFallback") or not totals.has("fallbackRate"):
		return false
	for biome_id in report["biomes"].keys():
		var stats: Dictionary = report["biomes"][biome_id]
		for key in [
			"seeds",
			"firstAttemptOk",
			"retriedOk",
			"usedFallback",
			"fallbackRate",
			"attemptHistogram",
			"failureReasons",
			"mainRoomCount",
			"worstSeeds",
		]:
			if not stats.has(key):
				return false
		var room_stats: Dictionary = stats.get("mainRoomCount", {})
		for room_key in ["min", "max", "mean", "histogram"]:
			if not room_stats.has(room_key):
				return false
	return true
