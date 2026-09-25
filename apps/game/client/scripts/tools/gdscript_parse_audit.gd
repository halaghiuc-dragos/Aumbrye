extends SceneTree

var _checked := 0
var _failures := 0


func _initialize() -> void:
	_scan_directory("res://scripts")
	print("GDSCRIPT PARSE RESULT %d files, %d failures" % [_checked, _failures])
	quit(1 if _failures > 0 else 0)


func _scan_directory(path: String) -> void:
	var directory := DirAccess.open(path)
	if directory == null:
		push_error("Could not open GDScript directory: %s" % path)
		_failures += 1
		return
	for file_name: String in directory.get_files():
		if file_name.ends_with(".gd"):
			var script_path := path.path_join(file_name)
			_checked += 1
			var script_resource: Resource = load(script_path)
			if script_resource == null:
				push_error("Could not compile GDScript: %s" % script_path)
				_failures += 1
	for directory_name: String in directory.get_directories():
		_scan_directory(path.path_join(directory_name))
