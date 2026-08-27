extends Node


## Loading every script from a running scene is the lint mechanism, not a convenience:
## `--check-only --script` cannot resolve autoloads or `class_name` globals, and `--import` does
## not recompile what it has cached. Warnings set to 2 in `project.godot` surface as load
## failures naming file and line.
const ROOTS: Array[String] = ["res://scripts"]

var _checked := 0
var _failed: Array[String] = []


func _ready() -> void:
	for root in ROOTS:
		_scan(root)
	print("lint_scripts: loaded %d scripts, %d failed" % [_checked, _failed.size()])
	for path in _failed:
		print("  FAILED %s" % path)
	get_tree().quit(0 if _failed.is_empty() else 1)


func _scan(dir_path: String) -> void:
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var full := dir_path.path_join(entry)
		if dir.current_is_dir():
			if not entry.begins_with("."):
				_scan(full)
		elif entry.ends_with(".gd"):
			_checked += 1
			if not _compiles_clean(full):
				_failed.append(full)
		entry = dir.get_next()
	dir.list_dir_end()


func _compiles_clean(path: String) -> bool:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		return true
	var script := GDScript.new()
	script.source_code = source
	script.resource_path = path
	return script.reload(true) == OK
