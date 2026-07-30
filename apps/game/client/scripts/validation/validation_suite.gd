extends RefCounted
class_name ValidationSuite

## Base class for validation suites. Override run() and get_category().

const TC := preload("res://scripts/validation/test_context.gd")

var ctx


func _init(context) -> void:
	ctx = context


func get_category() -> String:
	return "unknown"


func get_suite_name() -> String:
	return get_script().resource_path.get_file().get_basename()


func run() -> void:
	pass
