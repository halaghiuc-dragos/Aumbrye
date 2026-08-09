extends RefCounted
class_name ValidationSuite

## Base class for validation suites. Override run() and get_category().

const Fixtures := preload("res://scripts/validation/fixtures.gd")
const TC := Fixtures

var ctx: TestContext
var _save_backup: Dictionary = {}
var manage_save_file: bool = true


func _init(context: TestContext) -> void:
	ctx = context


func get_category() -> String:
	return "unknown"


func get_suite_name() -> String:
	return get_script().resource_path.get_file().get_basename()


func setup() -> void:
	if manage_save_file:
		_save_backup = ctx.backup_save_file()


func teardown() -> void:
	if manage_save_file:
		ctx.restore_save_file(_save_backup)


func run() -> void:
	pass


func check(id: String, condition: bool, message: String, ref := "") -> bool:
	var start := Time.get_ticks_msec()
	ctx.timed_record(id, get_category(), condition, message, start, ref)
	return condition


func check_eq(id: String, actual, expected, message: String, ref := "") -> bool:
	return ctx.assert_eq(id, get_category(), actual, expected, message, Time.get_ticks_msec(), ref)


func check_ne(id: String, actual, unexpected: Variant, message: String, ref := "") -> bool:
	var ok: bool = actual != unexpected
	var start := Time.get_ticks_msec()
	var msg := message
	if not ok:
		msg = "%s (expected not %s, got %s)" % [message, str(unexpected), str(actual)]
	ctx.timed_record(id, get_category(), ok, msg, start, ref, actual if not ok else null)
	return ok


func check_near(
	id: String, actual: float, expected: float, epsilon: float, message: String, ref := ""
) -> bool:
	return ctx.assert_near(
		id, get_category(), actual, expected, epsilon, message, Time.get_ticks_msec(), ref
	)


func check_in(id: String, needle, haystack, message: String, ref := "") -> bool:
	var ok := false
	if haystack is Array:
		ok = needle in haystack
	elif haystack is Dictionary:
		ok = haystack.has(needle)
	elif haystack is String:
		ok = str(needle) in haystack
	return check(id, ok, message, ref)


func check_has(id: String, dict: Dictionary, key: String, message: String, ref := "") -> bool:
	return check(id, dict.has(key), message, ref)


func check_not_null(id: String, value, message: String, ref := "") -> bool:
	return check(id, value != null, message, ref)


func check_file_exists(id: String, path: String, message: String, ref := "") -> bool:
	return check(id, FileAccess.file_exists(path), message, ref)


func skip(id: String, message: String, ref := "") -> void:
	ctx.skip(id, get_category(), message, ref)
