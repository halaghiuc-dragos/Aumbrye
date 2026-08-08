extends Node

## Orchestrates validation suites, writes JSON report v3 + JUnit XML, and quits.
##
## CI entry (recommended):
##   Godot --path . --headless --script res://scripts/validation/validation_main.gd -- --report=artifacts/mcp_validation.json
## In-editor entry:
##   Godot --path . --headless res://scenes/debug/mcp_validation.tscn

const TestContextScript := preload("res://scripts/validation/test_context.gd")
const RunnerOptionsScript := preload("res://scripts/validation/runner_options.gd")
const HelpersScript := preload("res://scripts/validation/helpers.gd")

const SUITE_TIMEOUT_SECONDS := 120.0
const HARNESS_SUITE_TIMEOUT_SECONDS := 2.0
const TOTAL_TIMEOUT_SECONDS := 900.0
const SCHEMA_VERSION := 3
const MANUAL_CHECKLIST_REL := "docs/validation/manual-checklist.md"

const SUITE_PATHS: PackedStringArray = [
	"res://scripts/validation/suites/harness_suite.gd",
	"res://scripts/validation/suites/setup_suite.gd",
	"res://scripts/validation/suites/docs_suite.gd",
	"res://scripts/validation/suites/platform_suite.gd",
	"res://scripts/validation/suites/quality_bar_suite.gd",
	"res://scripts/validation/suites/content_suite.gd",
	"res://scripts/validation/suites/biome_kit_suite.gd",
	"res://scripts/validation/suites/audio_suite.gd",
	"res://scripts/validation/suites/content_drift_suite.gd",
	"res://scripts/validation/suites/inventory_suite.gd",
	"res://scripts/validation/suites/progression_suite.gd",
	"res://scripts/validation/suites/procgen_suite.gd",
	"res://scripts/validation/suites/placements_suite.gd",
	"res://scripts/validation/suites/room_graph_suite.gd",
	"res://scripts/validation/suites/room_kit_suite.gd",
	"res://scripts/validation/suites/procgen_seed_health_suite.gd",
	"res://scripts/validation/suites/cross_stack_parity_suite.gd",
	"res://scripts/validation/suites/affix_suite.gd",
	"res://scripts/validation/suites/room_content_suite.gd",
	"res://scripts/validation/suites/world_state_suite.gd",
	"res://scripts/validation/suites/save_suite.gd",
	"res://scripts/validation/suites/net_suite.gd",
	"res://scripts/validation/suites/hub_suite.gd",
	"res://scripts/validation/suites/hub_m4_suite.gd",
	"res://scripts/validation/suites/arena_suite.gd",
	"res://scripts/validation/suites/camera_suite.gd",
	"res://scripts/validation/suites/lock_on_suite.gd",
	"res://scripts/validation/suites/combat_suite.gd",
	"res://scripts/validation/suites/trap_suite.gd",
	"res://scripts/validation/suites/dungeon_suite.gd",
	"res://scripts/validation/suites/floor_shell_suite.gd",
	"res://scripts/validation/suites/player_suite.gd",
	"res://scripts/validation/suites/enemy_suite.gd",
	"res://scripts/validation/suites/flow_suite.gd",
	"res://scripts/validation/suites/m5_suite.gd",
	"res://scripts/validation/suites/m6_suite.gd",
	"res://scripts/validation/suites/achievements_suite.gd",
	"res://scripts/validation/suites/m7_suite.gd",
	"res://scripts/validation/suites/pause_menu_suite.gd",
	"res://scripts/validation/suites/a11y_suite.gd",
	"res://scripts/validation/suites/ui_suite.gd",
	"res://scripts/validation/suites/status_icon_atlas_suite.gd",
	"res://scripts/validation/suites/ui_symbol_suite.gd",
	"res://scripts/validation/suites/debug_suite.gd",
	"res://scripts/validation/suites/error_paths_suite.gd",
	"res://scripts/validation/suites/pixel_pipeline_suite.gd",
	"res://scripts/validation/suites/pixel_camera_snap_suite.gd",
	"res://scripts/validation/suites/pixel_settings_suite.gd",
	"res://scripts/validation/suites/pixel_style_suite.gd",
	"res://scripts/validation/suites/visual_lighting_suite.gd",
	"res://scripts/validation/suites/death_visual_suite.gd",
	"res://scripts/validation/suites/portal_shader_suite.gd",
	"res://scripts/validation/suites/diorama_anim_suite.gd",
	"res://scripts/validation/suites/vfx_service_suite.gd",
	"res://scripts/validation/suites/export_suite.gd",
	"res://scripts/validation/suites/voxel_grid_suite.gd",
	"res://scripts/validation/suites/perf_gate_suite.gd",
]

const MIN_ASSERTIONS := {
	"combat": 30,
	"drift": 5,
	"quality": 4,
	"docs": 3,
	"harness": 10,
	"lock_on": 4,
	"arena": 7,
	"traps": 4,
	"tools": 12,
	"accessibility": 6,
	"ui": 2,
	"debug": 2,
}

const _AUTOLOAD_NAMES := [
	"LocalSave",
	"RunFlow",
	"ContentLoader",
	"StorageService",
	"WorldState",
	"AudioDirector",
	"CharacterService",
	"AchievementService",
	"CrashLogger",
	"LeaderboardSettings",
	"VfxService",
	"DungeonCatalog",
	"DungeonTierService",
	"PixelDioramaBootstrap",
	"InputRebindService",
	"AccessibilitySettings",
	"GameFacade",
	"ApiConfig",
	"InventoryService",
	"ProgressionService",
	"QuestService",
	"RunBuffs",
	"WavesRunService",
	"PlayerControls",
	"PixelDioramaViewport",
	"AttackTokenService",
	"SteamService",
	"DebugConsole",
	"InputGlyphWatcher",
]

var _ctx
var _options
var _suite_results: Array[Dictionary] = []
var _finished := false
var _exit_reason := "complete"
var _verbose := false
var _suite_timeout := SUITE_TIMEOUT_SECONDS
var _reachability: Dictionary = {}


func _ready() -> void:
	_options = RunnerOptionsScript.from_cmdline()
	_verbose = _options.verbose
	_suite_timeout = (
		HARNESS_SUITE_TIMEOUT_SECONDS if _options.harness_fast_timeout else SUITE_TIMEOUT_SECONDS
	)
	_ctx = TestContextScript.new(self)
	_ctx.test_prefix_filter = _options.test_prefix
	_arm_total_watchdog()
	for repeat_index in _options.repeat_count:
		if repeat_index > 0:
			_reset_repeat_state()
		await _run_all_suites()
		_detect_flaky_from_repeat(repeat_index)
		if _options.fail_fast and _ctx.failed > 0:
			break
	_enforce_coverage_gates()
	_compute_reachability()
	_finish(0 if _ctx.failed == 0 else 1)


func _arm_total_watchdog() -> void:
	var timer := get_tree().create_timer(TOTAL_TIMEOUT_SECONDS, true, false, true)
	timer.timeout.connect(
		func():
			if _finished:
				return
			_exit_reason = "total_timeout"
			_ctx.record(
				"runner.total_timeout",
				"runner",
				false,
				"validation exceeded %ds; report is partial" % int(TOTAL_TIMEOUT_SECONDS)
			)
			_finish(2)
	)


func _finish(reason_code: int) -> void:
	if _finished:
		return
	_finished = true
	var wrote := _write_report()
	if not wrote and reason_code != 2:
		reason_code = 2
	_print_failures()
	get_tree().quit(reason_code)


func _reset_repeat_state() -> void:
	_ctx.tests.clear()
	_ctx.passed = 0
	_ctx.failed = 0
	_ctx.skipped = 0
	_ctx._seen_ids.clear()
	_suite_results.clear()


func _detect_flaky_from_repeat(repeat_index: int) -> void:
	if repeat_index == 0 or _options.repeat_count <= 1:
		return
	for test in _ctx.tests:
		if test.get("status", "") == "fail":
			(
				_ctx
				. record(
					"runner.flaky.%s" % test.get("id", "unknown"),
					"runner",
					false,
					"test result varied across --repeat runs",
				)
			)


func _run_all_suites() -> void:
	var paths := _filtered_suite_paths()
	if _options.shuffle:
		var rng := RandomNumberGenerator.new()
		rng.seed = _options.seed if _options.seed != 0 else 20260805
		paths.shuffle()
	for path in paths:
		if _options.fail_fast and _ctx.failed > 0:
			break
		await _run_one_suite(path)
		await _isolate()


func _filtered_suite_paths() -> Array[String]:
	if _options.suite_filter.is_empty():
		var all: Array[String] = []
		for path in SUITE_PATHS:
			all.append(path)
		return all
	var selected: Array[String] = []
	for path in SUITE_PATHS:
		var suite_name := path.get_file().get_basename()
		if (
			suite_name in _options.suite_filter
			or suite_name.trim_suffix("_suite") in _options.suite_filter
		):
			selected.append(path)
	return selected


func _run_one_suite(path: String) -> void:
	var script: Script = load(path) as Script
	var suite_name := path.get_file().get_basename()
	if script == null:
		_ctx.record("suite.load_%s" % suite_name, "runner", false, "failed to load suite script")
		return
	var suite: RefCounted = script.new(_ctx) as RefCounted
	if suite == null:
		_ctx.record("suite.init_%s" % suite_name, "runner", false, "failed to instantiate suite")
		return
	var category := "unknown"
	if suite.has_method("get_category"):
		category = str(suite.call("get_category"))
	var suite_start := Time.get_ticks_msec()
	var before_passed: int = _ctx.passed
	var before_failed: int = _ctx.failed
	var before_skipped: int = _ctx.skipped
	var timed_out := false
	if suite.has_method("setup"):
		timed_out = await _run_with_watchdog(
			func(): await suite.call("setup"), suite_name, category, "setup"
		)
	if not timed_out and suite.has_method("run"):
		timed_out = await _run_with_watchdog(
			func(): await suite.call("run"), suite_name, category, "run"
		)
	if suite.has_method("teardown"):
		await _run_with_watchdog(
			func(): await suite.call("teardown"), suite_name, category, "teardown"
		)
	(
		_suite_results
		. append(
			{
				"name":
				suite.get_suite_name() if suite.has_method("get_suite_name") else suite_name,
				"category": category,
				"passed": _ctx.passed - before_passed,
				"failed": _ctx.failed - before_failed,
				"skipped": _ctx.skipped - before_skipped,
				"timedOut": timed_out,
				"duration_ms": Time.get_ticks_msec() - suite_start,
			}
		)
	)


func _run_with_watchdog(
	callable: Callable, suite_name: String, category: String, phase: String
) -> bool:
	var state := {"done": false}
	_race_callable(callable, state)
	var elapsed := 0.0
	while not state["done"] and elapsed < _suite_timeout:
		await get_tree().process_frame
		elapsed += get_process_delta_time()
	if state["done"]:
		return false
	_ctx.record(
		"suite.timeout_%s.%s" % [suite_name, phase],
		category,
		false,
		"%s exceeded %ds and was abandoned" % [phase, int(_suite_timeout)]
	)
	return true


func _race_callable(callable: Callable, state: Dictionary) -> void:
	await callable.call()
	state["done"] = true


func _isolate() -> void:
	for child in get_tree().root.get_children():
		if child == self or child.name in _AUTOLOAD_NAMES:
			continue
		_ctx.record(
			"suite.leaked_node_%s" % child.name,
			"runner",
			false,
			"suite left %s in the tree" % child.get_path()
		)
		child.queue_free()
	await get_tree().process_frame


func _enforce_coverage_gates() -> void:
	var counts := {}
	for test in _ctx.tests:
		var category: String = test.get("category", "unknown")
		counts[category] = int(counts.get(category, 0)) + 1
	for gate_category in MIN_ASSERTIONS:
		var minimum: int = MIN_ASSERTIONS[gate_category]
		var actual: int = int(counts.get(gate_category, 0))
		if actual < minimum:
			_ctx.record(
				"runner.coverage_%s" % gate_category,
				"runner",
				false,
				"category %s recorded %d assertions (minimum %d)" % [gate_category, actual, minimum]
			)


func _compute_reachability() -> void:
	var all_paths := HelpersScript.collect_gdscript_paths()
	var referenced := HelpersScript.collect_referenced_script_paths()
	var unreferenced: PackedStringArray = []
	for path in all_paths:
		if not referenced.has(path):
			unreferenced.append(path)
	_reachability = {
		"totalScripts": all_paths.size(),
		"reachableScripts": referenced.size(),
		"unreferenced": unreferenced,
	}


func _write_report() -> bool:
	var report := {
		"schemaVersion": SCHEMA_VERSION,
		"generatedAt": Time.get_datetime_string_from_system(),
		"total": _ctx.tests.size(),
		"passed": _ctx.passed,
		"failed": _ctx.failed,
		"skipped": _ctx.skipped,
		"exitReason": _exit_reason,
		"suites": _suite_results,
		"tests": _ctx.tests,
		"coverage":
		{
			"automated": _ctx.tests.size(),
			"reachableScripts": _reachability.get("reachableScripts", 0),
			"totalScripts": _reachability.get("totalScripts", 0),
			"manualChecklist": MANUAL_CHECKLIST_REL,
		},
		"reportPath": ProjectSettings.globalize_path(_options.report_json_path),
	}
	var json_ok := _write_json(report, _options.report_json_path)
	var junit_ok := _write_junit(_options.report_junit_path)
	if not json_ok:
		_exit_reason = "report_error"
		return false
	return junit_ok or json_ok


func _write_json(report: Dictionary, path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_ctx.record("runner.report_write_failed", "runner", false, "could not open %s" % path)
		return false
	file.store_string(JSON.stringify(report, "\t"))
	file.flush()
	file.close()
	if _verbose:
		print("[ValidationRunner] wrote %s" % path)
	return true


func _write_junit(path: String) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	var total: int = _ctx.tests.size()
	var failures: int = _ctx.failed
	file.store_string('<?xml version="1.0" encoding="UTF-8"?>\n')
	file.store_string(
		'<testsuites tests="%d" failures="%d" skipped="%d">\n' % [total, failures, _ctx.skipped]
	)
	var by_suite := {}
	for test in _ctx.tests:
		var suite_name: String = str(test.get("category", "unknown"))
		if not by_suite.has(suite_name):
			by_suite[suite_name] = []
		(by_suite[suite_name] as Array).append(test)
	for suite_name in by_suite:
		var cases: Array = by_suite[suite_name]
		file.store_string(
			'  <testsuite name="%s" tests="%d">\n' % [_xml_escape(suite_name), cases.size()]
		)
		for test in cases:
			var test_id: String = str(test.get("id", ""))
			var status: String = str(test.get("status", "pass"))
			(
				file
				. store_string(
					(
						'    <testcase classname="%s" name="%s">'
						% [
							_xml_escape(suite_name),
							_xml_escape(test_id),
						]
					)
				)
			)
			if status == "fail":
				var message := _xml_escape(str(test.get("message", "")))
				file.store_string('<failure message="%s"/>' % message)
			elif status == "skip":
				file.store_string("<skipped/>")
			file.store_string("</testcase>\n")
		file.store_string("  </testsuite>\n")
	file.store_string("</testsuites>\n")
	file.flush()
	file.close()
	return true


func _print_failures() -> void:
	for test in _ctx.tests:
		if test.get("status", "") == "fail":
			print(
				(
					"FAIL %s [%s] %s"
					% [test.get("id", ""), test.get("category", ""), test.get("message", "")]
				)
			)
	print(
		(
			"[ValidationRunner] %d passed, %d failed, %d skipped"
			% [_ctx.passed, _ctx.failed, _ctx.skipped]
		)
	)


func _xml_escape(text: String) -> String:
	return text.replace("&", "&amp;").replace("<", "&lt;").replace(">", "&gt;").replace(
		'"', "&quot;"
	)
