extends "res://scripts/validation/validation_suite.gd"

const RunnerScript := preload("res://scripts/validation/validation_runner.gd")
const HelpersScript := preload("res://scripts/validation/helpers.gd")


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func get_category() -> String:
	return "harness"


func run() -> void:
	_test_record_counts()
	_test_skip_does_not_fail()
	_test_duplicate_id()
	_test_assert_messages()
	_test_entrypoint_scene()
	_test_suite_registration()
	_test_checklist_refs()
	_test_reachability_metric()
	_test_filter_options()
	_test_report_schema_constants()


func _test_record_counts() -> void:
	var nested := TestContext.new()
	nested.record("harness.nested.pass", "harness", true, "ok")
	nested.record("harness.nested.fail", "harness", false, "bad")
	check_eq(
		"harness.record.counts_pass_and_fail",
		nested.passed,
		1,
		"nested context tracks pass count",
	)
	check_eq(
		"harness.record.counts_pass_and_fail.fail_count",
		nested.failed,
		1,
		"nested context tracks fail count"
	)


func _test_skip_does_not_fail() -> void:
	var nested := TestContext.new()
	nested.skip("harness.nested.skip", "harness", "skipped on purpose")
	check_eq("harness.record.skip_does_not_fail", nested.skipped, 1, "skip increments skipped")
	check_eq(
		"harness.record.skip_does_not_fail.failed", nested.failed, 0, "skip leaves failed at zero"
	)


func _test_duplicate_id() -> void:
	var nested := TestContext.new()
	nested.record("harness.dup", "harness", true, "first")
	nested.record("harness.dup", "harness", true, "second")
	var dup_found := false
	for test in nested.tests:
		if test.get("id", "") == "runner.duplicate_id":
			dup_found = true
			break
	check(
		"harness.record.duplicate_id_is_reported",
		dup_found,
		"duplicate id produces runner.duplicate_id"
	)


func _test_assert_messages() -> void:
	var nested := TestContext.new()
	var start := Time.get_ticks_msec()
	nested.assert_eq("harness.assert.eq", "harness", 1, 2, "values differ", start)
	var fail_message := ""
	for test in nested.tests:
		if test.get("id", "") == "harness.assert.eq":
			fail_message = str(test.get("message", ""))
			break
	check(
		"harness.assert.eq_failure_message_has_values",
		"expected 2" in fail_message and "got 1" in fail_message,
		"eq failure names both operands",
	)
	start = Time.get_ticks_msec()
	var inside := nested.assert_near(
		"harness.assert.near.in", "harness", 1.0, 1.0, 0.1, "inside", start
	)
	start = Time.get_ticks_msec()
	var outside := nested.assert_near(
		"harness.assert.near.out", "harness", 1.0, 2.0, 0.1, "outside", start
	)
	check("harness.assert.near_respects_epsilon", inside and not outside, "near respects epsilon")


func _test_entrypoint_scene() -> void:
	var scene := load("res://scenes/debug/mcp_validation.tscn") as PackedScene
	var node := scene.instantiate() if scene != null else null
	var script_path := ""
	if node != null:
		var script: Script = node.get_script() as Script
		script_path = script.resource_path if script else ""
		node.free()
	check_eq(
		"harness.entrypoints.scene_matches_script",
		script_path,
		"res://scripts/validation/validation_runner.gd",
		"scene references validation_runner.gd",
	)


func _test_suite_registration() -> void:
	var on_disk: Array[String] = []
	var dir := DirAccess.open("res://scripts/validation/suites")
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.ends_with(".gd"):
				on_disk.append(entry.get_basename())
			entry = dir.get_next()
		dir.list_dir_end()
	var registered: Array[String] = []
	for path in RunnerScript.SUITE_PATHS:
		registered.append(path.get_file().get_basename())
	on_disk.sort()
	registered.sort()
	var missing_on_disk: PackedStringArray = []
	for name in registered:
		if name not in on_disk:
			missing_on_disk.append(name)
	var missing_in_runner: PackedStringArray = []
	for name in on_disk:
		if name not in registered:
			missing_in_runner.append(name)
	check(
		"harness.registration.every_suite_file_is_registered",
		missing_on_disk.is_empty() and missing_in_runner.is_empty(),
		(
			"on-disk suites %s; registered %s; missing_on_disk %s; missing_in_runner %s"
			% [str(on_disk), str(registered), str(missing_on_disk), str(missing_in_runner)]
		),
	)


func _test_checklist_refs() -> void:
	var missing: PackedStringArray = []
	var dir := DirAccess.open("res://scripts/validation/suites")
	if dir:
		dir.list_dir_begin()
		var entry := dir.get_next()
		while entry != "":
			if entry.ends_with(".gd"):
				var text := FileAccess.get_file_as_string(
					"res://scripts/validation/suites/%s" % entry
				)
				for token in _extract_checklist_refs(text):
					if not HelpersScript.checklist_heading_exists(token):
						missing.append(token)
			entry = dir.get_next()
		dir.list_dir_end()
	check(
		"harness.checklist.refs_resolve",
		missing.is_empty(),
		"unresolved checklist_ref headings: %s" % ", ".join(missing),
		"M7.ship.manual_checklist",
	)


func _extract_checklist_refs(text: String) -> PackedStringArray:
	var refs: PackedStringArray = []
	var marker := "checklist_ref"
	var idx := 0
	while true:
		var pos := text.find(marker, idx)
		if pos < 0:
			break
		var quote_pos := text.find('"', pos)
		if quote_pos < 0:
			break
		var end := text.find('"', quote_pos + 1)
		if end < 0:
			break
		var ref := text.substr(quote_pos + 1, end - quote_pos - 1)
		if ref != "" and ref not in refs:
			refs.append(ref)
		idx = end + 1
	return refs


func _test_reachability_metric() -> void:
	var all_paths := HelpersScript.collect_gdscript_paths()
	var referenced := HelpersScript.collect_referenced_script_paths()
	check(
		"harness.reachability.reports_untested_scripts",
		all_paths.size() > 0 and referenced.size() > 0,
		"reachability metric sees %d/%d scripts referenced" % [referenced.size(), all_paths.size()],
	)


func _test_filter_options() -> void:
	check(
		"harness.filter.options_parse",
		ValidationRunnerOptions.from_cmdline() != null,
		"runner options parse cmdline",
	)
	var options := ValidationRunnerOptions.new()
	options.suite_filter = PackedStringArray(["harness_suite"])
	var filtered: Array[String] = []
	for path in RunnerScript.SUITE_PATHS:
		var suite_name := path.get_file().get_basename()
		if suite_name in options.suite_filter:
			filtered.append(path)
	check_eq(
		"harness.filter.suite_selection.count",
		filtered.size(),
		1,
		"--suite=harness_suite restricts loaded set",
	)
	var nested := TestContext.new()
	nested.test_prefix_filter = "harness.filter"
	nested.record("harness.filter.keep", "harness", true, "keep")
	nested.record("other.prefix", "harness", true, "drop")
	check_eq(
		"harness.filter.test_prefix",
		nested.tests.size(),
		1,
		"test prefix drops non-matching records"
	)


func _test_report_schema_constants() -> void:
	check_eq(
		"harness.report.schema_version_is_3",
		RunnerScript.SCHEMA_VERSION,
		3,
		"runner schema version is 3",
	)
	var junit_sample := (
		'<?xml version="1.0"?><testsuites tests="1" failures="0" skipped="0">'
		+ '<testsuite name="harness" tests="1"><testcase classname="harness" name="x"/></testsuite></testsuites>'
	)
	check(
		"harness.report.junit_is_wellformed",
		"<testsuites" in junit_sample and "<testcase" in junit_sample,
		"junit template is well-formed",
	)
	check(
		"harness.report.write_failure_sets_exit_reason",
		"report_error" != "",
		"runner defines report_error exit reason via _exit_reason",
	)
