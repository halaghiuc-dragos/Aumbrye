extends RefCounted
class_name TestContext

## Shared recording state and await helpers for validation suites.

const REPORT_PATH := "user://mcp_validation.json"

var owner: Node
var tests: Array[Dictionary] = []
var passed: int = 0
var failed: int = 0
var skipped: int = 0
var test_prefix_filter: String = ""
var _seen_ids: Dictionary = {}


func _init(host: Node = null) -> void:
	owner = host


func record(
	id: String,
	category: String,
	passed_test: bool,
	message: String,
	checklist_ref: String = "",
	duration_ms: int = 0,
	observed: Variant = null,
	status_override: String = ""
) -> void:
	if test_prefix_filter != "" and not id.begins_with(test_prefix_filter):
		return
	var status := status_override
	if status == "":
		status = "pass" if passed_test else "fail"
	if status == "skip":
		skipped += 1
	elif passed_test:
		passed += 1
	else:
		failed += 1
	if _seen_ids.has(id):
		failed += 1
		(
			tests
			. append(
				{
					"id": "runner.duplicate_id",
					"category": "runner",
					"status": "fail",
					"message": "duplicate test id %s (category %s)" % [id, str(_seen_ids[id])],
					"duration_ms": 0,
				}
			)
		)
	_seen_ids[id] = category
	var entry := {
		"id": id,
		"category": category,
		"status": status,
		"message": message,
		"duration_ms": duration_ms,
	}
	if checklist_ref != "":
		entry["checklist_ref"] = checklist_ref
	if observed != null:
		entry["observed"] = observed
	tests.append(entry)


func skip(
	id: String, category: String, message: String, checklist_ref: String = "", duration_ms: int = 0
) -> void:
	record(id, category, true, message, checklist_ref, duration_ms, null, "skip")


func timed_record(
	id: String,
	category: String,
	passed_test: bool,
	message: String,
	start_ms: int,
	checklist_ref: String = "",
	observed: Variant = null
) -> void:
	record(
		id,
		category,
		passed_test,
		message,
		checklist_ref,
		Time.get_ticks_msec() - start_ms,
		observed
	)


func assert_eq(
	id: String,
	category: String,
	actual: Variant,
	expected: Variant,
	what: String,
	start_ms: int,
	checklist_ref: String = ""
) -> bool:
	var ok: bool = actual == expected
	var message := what
	if not ok:
		message = "%s (expected %s, got %s)" % [what, str(expected), str(actual)]
	timed_record(id, category, ok, message, start_ms, checklist_ref, actual if not ok else null)
	return ok


func assert_near(
	id: String,
	category: String,
	actual: float,
	expected: float,
	tolerance: float,
	what: String,
	start_ms: int,
	checklist_ref: String = ""
) -> bool:
	var ok: bool = absf(actual - expected) <= tolerance
	var message := what
	if not ok:
		message = (
			"%s (expected %s ± %s, got %s)" % [what, str(expected), str(tolerance), str(actual)]
		)
	timed_record(id, category, ok, message, start_ms, checklist_ref, actual if not ok else null)
	return ok


func assert_true(
	id: String,
	category: String,
	value: bool,
	what: String,
	start_ms: int,
	checklist_ref: String = ""
) -> bool:
	var message := what
	if not value:
		message = "%s: expected true, got false" % what
	timed_record(id, category, value, message, start_ms, checklist_ref, value)
	return value


func repo_root() -> String:
	return ValidationHelpers.repo_root()


func file_contains(path: String, needle: String) -> bool:
	return ValidationHelpers.file_contains(path, needle)


func script_has_method(path: String, method_name: String) -> bool:
	return ValidationHelpers.script_has_method(path, method_name)


func script_has_constant(path: String, constant_name: String) -> bool:
	return ValidationHelpers.script_has_constant(path, constant_name)


func script_constant(path: String, constant_name: String, fallback: Variant = null) -> Variant:
	return ValidationHelpers.script_constant(path, constant_name, fallback)


func script_has_signal(path: String, signal_name: String) -> bool:
	return ValidationHelpers.script_has_signal(path, signal_name)


func script_has_property(path: String, property_name: String) -> bool:
	return ValidationHelpers.script_has_property(path, property_name)


func node_has_method(path: String, method_name: String) -> bool:
	return ValidationHelpers.node_has_method(path, method_name)


func resource_depends_on(path: String, dependency_path: String) -> bool:
	return ValidationHelpers.resource_depends_on(path, dependency_path)


func backup_save_file() -> Dictionary:
	return ValidationHelpers.backup_save_file()


func restore_save_file(backup: Dictionary) -> void:
	ValidationHelpers.restore_save_file(backup)


func layout_signature(def: Dictionary) -> String:
	return ValidationFixtures.layout_signature(def)


func matches_m2_fixture(def: Dictionary) -> bool:
	return ValidationFixtures.matches_m2_fixture(def)


func count_nodes_by_script(node: Node, script_name: String) -> int:
	return ValidationHelpers.count_nodes_by_script(node, script_name)


func count_loot_chests(node: Node) -> int:
	return ValidationHelpers.count_loot_chests(node)


func await_physics(frames: int = 1) -> void:
	for _i in frames:
		await owner.get_tree().physics_frame


func await_frame(frames: int = 1) -> void:
	for _i in frames:
		await owner.get_tree().process_frame
