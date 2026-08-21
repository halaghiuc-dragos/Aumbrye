extends SceneTree

## Procgen seed health sweep — retry-aware fallback-rate report for room graph generation.
##
## C-256: **Phase 1 only.** This covers the room graph — cell walk, door masks, dead ends, secret
## attachment, loop budget — and stops there. Everything Phase 2 owns is outside its reach: template
## assignment, socket alignment, world positions, doorway spans, and the room-content pass. A run
## reporting `fallbackRate 0.000000` therefore means "the graph generator is healthy", not "procgen
## is healthy", and the same tree booted normally can still lose a room to a Phase 2 fault on the
## very first seed. Both statements are true about different halves of the generator.
##
## The header and the JSON report both say so now, because the previous output gave no hint of it
## and read as a whole-generator clean bill of health.
## From repo root:
##   godot --path apps/game/client --headless --script res://scripts/tools/procgen_seed_health.gd -- --from 1 --count 100
## From apps/game/client:
##   godot --path . --headless --script res://scripts/tools/procgen_seed_health.gd -- --from 1 --count 100

const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphDebugScript := preload("res://scripts/dungeon/procgen/room_graph_debug.gd")
const RoomGraphPathsScript := preload("res://scripts/dungeon/procgen/room_graph_paths.gd")

const DEFAULT_FROM := 1
const DEFAULT_COUNT := 1000
const DEFAULT_MAX_FALLBACK_RATE := 0.01
const DEFAULT_REPORT_PATH := "reports/procgen_seed_health.json"
const WORST_SEED_LIMIT := 10
const RATE_DECIMALS := 6

const BIOME_IDS: PackedStringArray = [
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

const REASON_TEMPLATES: PackedStringArray = [
	"Room count %d below minimum %d",
	"Door-disconnected component size %d != main slot count %d",
	"Boss room not assigned",
	"Stairs room not assigned",
	"Treasure room not assigned",
	"Boss too close to start (%d < %d)",
	"Not enough dead ends (%d < %d)",
	"Sealed room '%s' has no doors",
	"Height gap > 1 between '%s' and '%s'",
	"2x2 block detected at %s",
]


func _initialize() -> void:
	var options := parse_args(OS.get_cmdline_user_args())
	var exit_code := run_tool(options)
	quit(exit_code)


static func parse_args(user_args: PackedStringArray) -> Dictionary:
	var options := {
		"seed": -1,
		"from": DEFAULT_FROM,
		"count": DEFAULT_COUNT,
		"biomes": PackedStringArray(),
		"max_fallback_rate": DEFAULT_MAX_FALLBACK_RATE,
		"report": DEFAULT_REPORT_PATH,
		"ascii": false,
		"find_first_fallback": false,
	}
	var i := 0
	while i < user_args.size():
		var token := str(user_args[i])
		match token:
			"--seed":
				i += 1
				if i < user_args.size():
					options["seed"] = int(user_args[i])
			"--from":
				i += 1
				if i < user_args.size():
					options["from"] = int(user_args[i])
			"--count":
				i += 1
				if i < user_args.size():
					options["count"] = int(user_args[i])
			"--biome":
				i += 1
				if i < user_args.size():
					options["biomes"] = _split_csv(str(user_args[i]))
			"--max-fallback-rate":
				i += 1
				if i < user_args.size():
					options["max_fallback_rate"] = float(user_args[i])
			"--report":
				i += 1
				if i < user_args.size():
					options["report"] = str(user_args[i])
			"--ascii":
				options["ascii"] = true
			"--find-first-fallback":
				options["find_first_fallback"] = true
		i += 1
	if options["biomes"].is_empty():
		var all := BIOME_IDS.duplicate()
		all.sort()
		options["biomes"] = all
	else:
		var sorted: PackedStringArray = options["biomes"].duplicate()
		sorted.sort()
		options["biomes"] = sorted
	return options


static func run_tool(options: Dictionary) -> int:
	if int(options.get("seed", -1)) >= 0:
		return _run_single_seed(options)
	if bool(options.get("find_first_fallback", false)):
		return _run_find_first_fallback(options)
	var report := build_sweep_report(
		int(options.get("from", DEFAULT_FROM)),
		int(options.get("count", DEFAULT_COUNT)),
		options.get("biomes", PackedStringArray()),
		false
	)
	if not bool(report.get("ok", false)):
		_print_error(str(report.get("error", "sweep failed")))
		return 2
	print_summary_table(report)
	var report_path := str(options.get("report", DEFAULT_REPORT_PATH))
	if not write_report_file(report_path, report):
		_print_error("failed to write report: %s" % report_path)
		return 2
	print("Wrote %s" % report_path)
	return evaluate_exit_code(report, float(options.get("max_fallback_rate", DEFAULT_MAX_FALLBACK_RATE)))


static func build_sweep_report(
	seed_from: int, seed_count: int, biome_ids: PackedStringArray, include_timestamp: bool = true
) -> Dictionary:
	var report := {
		"ok": true,
		"schemaVersion": 1,
		# C-256: a consumer reading this JSON has to be able to tell what it does *not* cover.
		"coverage": "phase1_room_graph",
		"coverageNote":
		(
			"Room graph only. Template assignment, socket alignment, world positions, doorway"
			+ " spans and room content are not exercised by this sweep."
		),
		"seedFrom": seed_from,
		"seedCount": seed_count,
		"biomes": {},
		"totals": {"seeds": 0, "usedFallback": 0, "fallbackRate": 0.0},
	}
	if include_timestamp:
		report["generatedAtUnix"] = int(Time.get_unix_time_from_system())
	var total_seeds := 0
	var total_fallback := 0
	for biome_id in biome_ids:
		var biome_result := _sweep_biome(biome_id, seed_from, seed_count)
		if not bool(biome_result.get("ok", false)):
			report["ok"] = false
			report["error"] = biome_result.get("error", "biome sweep failed")
			return report
		report["biomes"][biome_id] = biome_result.get("stats", {})
		total_seeds += int(biome_result.get("stats", {}).get("seeds", 0))
		total_fallback += int(biome_result.get("stats", {}).get("usedFallback", 0))
	report["totals"]["seeds"] = total_seeds
	report["totals"]["usedFallback"] = total_fallback
	report["totals"]["fallbackRate"] = _rate(total_fallback, total_seeds)
	return report


static func evaluate_exit_code(report: Dictionary, max_fallback_rate: float) -> int:
	if not bool(report.get("ok", false)):
		return 2
	for biome_id in report.get("biomes", {}).keys():
		var stats: Dictionary = report["biomes"][biome_id]
		if float(stats.get("fallbackRate", 0.0)) > max_fallback_rate:
			return 1
	return 0


static func write_report_file(path: String, report: Dictionary) -> bool:
	var absolute: String = _resolve_report_path(path)
	_ensure_parent_dir(absolute)
	var body := serialize_report(report)
	var file := FileAccess.open(absolute, FileAccess.WRITE)
	if file == null:
		return false
	file.store_string(body)
	return true


static func serialize_report(report: Dictionary) -> String:
	return JSON.stringify(_format_report_for_json(report), "\t") + "\n"


static func report_without_timestamp(report: Dictionary) -> Dictionary:
	var copy: Dictionary = report.duplicate(true)
	copy.erase("generatedAtUnix")
	return copy


static func reason_bucket(reason: String) -> String:
	if reason.is_empty():
		return ""
	for template in REASON_TEMPLATES:
		if template.contains("%"):
			var prefix := template.split("%", false)[0]
			if reason.begins_with(prefix):
				return template
		elif reason == template:
			return template
	return reason


static func print_summary_table(report: Dictionary) -> void:
	# C-256: name the scope in the output, not only in the source.
	print("Phase 1 (room graph) only — template assignment and geometry are not covered.")
	print("Biome                 Seeds  1st-try  Fallback  Rooms min/mean/max")
	for biome_id in report.get("biomes", {}).keys():
		var stats: Dictionary = report["biomes"][biome_id]
		var seeds := int(stats.get("seeds", 0))
		var first_rate := _rate(int(stats.get("firstAttemptOk", 0)), seeds)
		var fallback_rate := float(stats.get("fallbackRate", 0.0))
		var room_stats: Dictionary = stats.get("mainRoomCount", {})
		print(
			"%-20s %5d  %7.4f  %8.6f  %d / %.1f / %d"
			% [
				biome_id,
				seeds,
				first_rate,
				fallback_rate,
				int(room_stats.get("min", 0)),
				float(room_stats.get("mean", 0.0)),
				int(room_stats.get("max", 0)),
			]
		)


static func _run_single_seed(options: Dictionary) -> int:
	var seed_value := int(options.get("seed", 0))
	var biome_ids: PackedStringArray = options.get("biomes", PackedStringArray())
	if biome_ids.is_empty():
		biome_ids = BIOME_IDS.duplicate()
		biome_ids.sort()
	var biome_id := str(biome_ids[0])
	var biome := _fetch_biome(biome_id)
	if biome.is_empty():
		_print_error("failed to load biome '%s'" % biome_id)
		return 2
	var config := RoomGraphConfigScript.from_biome(biome)
	var gen_report := RoomGraphGeneratorScript.generate_reported(config, seed_value)
	if not gen_report.ok:
		_print_error(
			"seed %d failed after %d attempts: %s"
			% [seed_value, gen_report.attempts, "; ".join(gen_report.reasons)]
		)
		return 2
	var graph: RoomGraph = gen_report.graph
	var metrics := _graph_metrics(graph, config)
	print(
		(
			"seed %d biome=%s attempts=%d used_fallback=%s main=%d boss_dist=%d (min %d) dead_ends=%d (min %d)"
			% [
				seed_value,
				biome_id,
				gen_report.attempts,
				gen_report.used_fallback,
				gen_report.main_room_count,
				metrics["boss_distance"],
				config.boss_min_distance,
				metrics["dead_ends"],
				config.min_dead_ends,
			]
		)
	)
	if bool(options.get("ascii", false)):
		RoomGraphDebugScript.print_graph(graph)
	return 0


static func _run_find_first_fallback(options: Dictionary) -> int:
	var seed_from := int(options.get("from", DEFAULT_FROM))
	var biome_ids: PackedStringArray = options.get("biomes", PackedStringArray())
	for biome_id in biome_ids:
		var biome := _fetch_biome(biome_id)
		if biome.is_empty():
			_print_error("failed to load biome '%s'" % biome_id)
			return 2
		var config := RoomGraphConfigScript.from_biome(biome)
		var seed_value := seed_from
		while seed_value < seed_from + 1_000_000:
			var gen_report := RoomGraphGeneratorScript.generate_reported(config, seed_value)
			if not gen_report.ok:
				_print_error("generation failed for seed %d" % seed_value)
				return 2
			if gen_report.used_fallback or gen_report.attempts > 1:
				print(
					"first retry seed %d biome=%s attempts=%d used_fallback=%s"
					% [seed_value, biome_id, gen_report.attempts, gen_report.used_fallback]
				)
				return 0
			seed_value += 1
	_print_error("no retry seed found in range starting at %d" % seed_from)
	return 2


static func _sweep_biome(biome_id: String, seed_from: int, seed_count: int) -> Dictionary:
	var biome := _fetch_biome(biome_id)
	if biome.is_empty():
		return {"ok": false, "error": "failed to load biome '%s'" % biome_id}
	var config := RoomGraphConfigScript.from_biome(biome)
	var stats := {
		"seeds": seed_count,
		"firstAttemptOk": 0,
		"retriedOk": 0,
		"usedFallback": 0,
		"fallbackRate": 0.0,
		"attemptHistogram": {},
		"failureReasons": {},
		"mainRoomCount": {"min": 0, "max": 0, "mean": 0.0, "histogram": {}},
		"worstSeeds": [],
	}
	var room_total := 0
	var room_min := 999999
	var room_max := 0
	var room_histogram := {}
	var worst_seeds: Array = []
	for offset in seed_count:
		var seed_value := seed_from + offset
		var gen_report := RoomGraphGeneratorScript.generate_reported(config, seed_value)
		if not gen_report.ok:
			return {
				"ok": false,
				"error": "generation failed biome=%s seed=%d" % [biome_id, seed_value],
			}
		var attempts_key := str(gen_report.attempts)
		stats["attemptHistogram"][attempts_key] = (
			int(stats["attemptHistogram"].get(attempts_key, 0)) + 1
		)
		if gen_report.used_fallback:
			stats["usedFallback"] += 1
		elif gen_report.attempts == 1:
			stats["firstAttemptOk"] += 1
		else:
			stats["retriedOk"] += 1
		for reason in gen_report.reasons:
			var bucket := reason_bucket(reason)
			stats["failureReasons"][bucket] = int(stats["failureReasons"].get(bucket, 0)) + 1
		var main_count := gen_report.main_room_count
		room_total += main_count
		room_min = mini(room_min, main_count)
		room_max = maxi(room_max, main_count)
		room_histogram[str(main_count)] = int(room_histogram.get(str(main_count), 0)) + 1
		if gen_report.attempts > 1 or gen_report.used_fallback:
			worst_seeds.append(
				{
					"seed": seed_value,
					"attempts": gen_report.attempts,
					"reasons": gen_report.reasons.duplicate(),
				}
			)
	stats["fallbackRate"] = _rate(int(stats["usedFallback"]), seed_count)
	stats["mainRoomCount"] = {
		"min": room_min if seed_count > 0 else 0,
		"max": room_max if seed_count > 0 else 0,
		"mean": float(room_total) / float(seed_count) if seed_count > 0 else 0.0,
		"histogram": room_histogram,
	}
	worst_seeds.sort_custom(
		func(a: Dictionary, b: Dictionary) -> bool:
			if int(a.get("attempts", 0)) == int(b.get("attempts", 0)):
				return int(a.get("seed", 0)) < int(b.get("seed", 0))
			return int(a.get("attempts", 0)) > int(b.get("attempts", 0))
	)
	stats["worstSeeds"] = worst_seeds.slice(0, WORST_SEED_LIMIT)
	return {"ok": true, "stats": stats}


static func _graph_metrics(graph: RoomGraph, _config: RoomGraphConfig) -> Dictionary:
	var distances := RoomGraphPathsScript.bfs_distances(graph, graph.start_id)
	var boss_distance := int(distances.get(graph.boss_id, 0))
	var dead_ends := 0
	for cell in graph.slots:
		var slot: RoomGraphSlot = graph.slots[cell]
		if slot.slot_type == RoomGraphSlot.SlotType.SECRET or slot.is_filler:
			continue
		if slot.is_dead_end():
			dead_ends += 1
	return {"boss_distance": boss_distance, "dead_ends": dead_ends}


static func _format_report_for_json(report: Dictionary) -> Dictionary:
	var formatted: Dictionary = {}
	for key in report.keys():
		var value: Variant = report[key]
		if key == "biomes" and value is Dictionary:
			var biomes_out := {}
			for biome_id in value.keys():
				biomes_out[biome_id] = _format_biome_stats(value[biome_id])
			formatted[key] = biomes_out
		elif key.ends_with("Rate") and value is float:
			formatted[key] = _format_rate(value)
		else:
			formatted[key] = value
	if formatted.has("totals"):
		var totals: Dictionary = formatted["totals"]
		if totals.has("fallbackRate"):
			totals["fallbackRate"] = _format_rate(float(totals["fallbackRate"]))
	return formatted


static func _format_biome_stats(stats: Dictionary) -> Dictionary:
	var out: Dictionary = stats.duplicate(true)
	if out.has("fallbackRate"):
		out["fallbackRate"] = _format_rate(float(out["fallbackRate"]))
	if out.has("mainRoomCount") and out["mainRoomCount"] is Dictionary:
		var room_stats: Dictionary = out["mainRoomCount"]
		if room_stats.has("mean"):
			room_stats["mean"] = _format_rate(float(room_stats["mean"]))
	return out


static func _format_rate(value: float) -> float:
	return float("%.6f" % value)


static func _rate(numerator: int, denominator: int) -> float:
	if denominator <= 0:
		return 0.0
	return _format_rate(float(numerator) / float(denominator))


static func _split_csv(value: String) -> PackedStringArray:
	var parts := value.split(",", false)
	var out: PackedStringArray = []
	for part in parts:
		var trimmed := str(part).strip_edges()
		if not trimmed.is_empty():
			out.append(trimmed)
	return out


static func _resolve_report_path(path: String) -> String:
	if path.begins_with("res://") or path.begins_with("user://"):
		return ProjectSettings.globalize_path(path)
	if path.begins_with("/") or path.contains(":/"):
		return path
	return _content_root().path_join(path)


static func _ensure_parent_dir(absolute_path: String) -> void:
	var parent := absolute_path.get_base_dir()
	if parent.is_empty() or DirAccess.dir_exists_absolute(parent):
		return
	DirAccess.make_dir_recursive_absolute(parent)


static func _content_root() -> String:
	var configured := str(ProjectSettings.get_setting("aumbrye/content_root", ""))
	if not configured.is_empty():
		return configured
	return ProjectSettings.globalize_path("res://").path_join("../../..")


static func _fetch_biome(biome_id: String) -> Dictionary:
	var path := _content_root().path_join("content/biomes/%s.json" % biome_id)
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return {}
	return parsed


static func _print_error(message: String) -> void:
	push_error(message)
	print("ERROR: %s" % message)
