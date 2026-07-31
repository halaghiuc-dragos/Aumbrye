extends Node

## Orchestrates validation suites, writes JSON report v2, and quits.

const TestContextScript := preload("res://scripts/validation/test_context.gd")
const REPORT_PATH := "user://mcp_validation.json"

const SUITE_PATHS: PackedStringArray = [
	"res://scripts/validation/suites/setup_suite.gd",
	"res://scripts/validation/suites/content_suite.gd",
	"res://scripts/validation/suites/inventory_suite.gd",
	"res://scripts/validation/suites/progression_suite.gd",
	"res://scripts/validation/suites/procgen_suite.gd",
	"res://scripts/validation/suites/save_suite.gd",
	"res://scripts/validation/suites/hub_suite.gd",
	"res://scripts/validation/suites/hub_m4_suite.gd",
	"res://scripts/validation/suites/arena_suite.gd",
	"res://scripts/validation/suites/camera_suite.gd",
	"res://scripts/validation/suites/lock_on_suite.gd",
	"res://scripts/validation/suites/combat_suite.gd",
	"res://scripts/validation/suites/dungeon_suite.gd",
	"res://scripts/validation/suites/player_suite.gd",
	"res://scripts/validation/suites/flow_suite.gd",
	"res://scripts/validation/suites/m5_suite.gd",
	"res://scripts/validation/suites/m6_suite.gd",
	"res://scripts/validation/suites/m7_suite.gd",
]

var _ctx
var _suite_results: Array[Dictionary] = []


func _ready() -> void:
	_ctx = TestContextScript.new(self)
	await _run_all_suites()
	_write_report()
	get_tree().quit()


func _run_all_suites() -> void:
	for path in SUITE_PATHS:
		var script: Script = load(path) as Script
		if script == null:
			_ctx.record("suite.load_%s" % path.get_file().get_basename(), "runner", false, "failed to load suite script")
			continue
		var suite: RefCounted = script.new(_ctx) as RefCounted
		if suite == null:
			_ctx.record("suite.init_%s" % path.get_file().get_basename(), "runner", false, "failed to instantiate suite")
			continue
		var suite_start := Time.get_ticks_msec()
		var before_passed: int = _ctx.passed
		var before_failed: int = _ctx.failed
		if suite.has_method("run"):
			await suite.call("run")
		var suite_passed: int = _ctx.passed - before_passed
		var suite_failed: int = _ctx.failed - before_failed
		var category: String = "unknown"
		if suite.has_method("get_category"):
			category = str(suite.call("get_category"))
		var suite_name: String = path.get_file().get_basename()
		_suite_results.append({
			"name": suite_name,
			"category": category,
			"passed": suite_passed,
			"failed": suite_failed,
			"duration_ms": Time.get_ticks_msec() - suite_start,
		})


func _write_report() -> void:
	var report := {
		"schemaVersion": 2,
		"generatedAt": Time.get_datetime_string_from_system(),
		"passed": _ctx.passed,
		"failed": _ctx.failed,
		"suites": _suite_results,
		"tests": _ctx.tests,
		"coverage": {
			"automated": _ctx.tests.size(),
			"manual_remaining": TestContextScript.MANUAL_REMAINING,
		},
		"reportPath": OS.get_user_data_dir().path_join("mcp_validation.json"),
	}
	var file := FileAccess.open(REPORT_PATH, FileAccess.WRITE)
	if file:
		file.store_string(JSON.stringify(report, "\t"))
	print("[ValidationRunner] %d passed, %d failed -> %s" % [
		_ctx.passed, _ctx.failed, REPORT_PATH,
	])
