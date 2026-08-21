extends Node

## Loads every GDScript in the project so the compiler reports its warnings.
##
## There is no CLI that dumps the analyzer's output: `--check-only --script` cannot resolve
## autoloads or `class_name` globals, and `--import` does not recompile what it has already cached.
## Loading each file from a running scene does both — autoloads are up, globals resolve, and any
## warning configured as an error in `project.godot` surfaces as a load failure naming the file and
## line.
##
## Usage, with the warnings under investigation set to 2 (error) in `[gdscript]`:
##   godot --headless --path apps/game/client res://scenes/debug/lint_scripts.tscn

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


## Compiles one script from source, rather than asking `ResourceLoader` for it.
##
## `load()` returns whatever is already in the resource cache, and every `class_name` global and
## every autoload is loaded before this tool runs — so the files most worth checking were the exact
## ones that were never recompiled, and the sweep reported them clean no matter what they contained.
## Two live warnings in `diorama_character_skin.gd` sat through a "322 scripts, 0 failed" run.
##
## `CACHE_MODE_IGNORE` is not the fix either: a second uncached instance of a script that is also a
## `class_name` global segfaults the engine. Building a fresh `GDScript` from the file's text and
## reloading it compiles it in isolation, which is what actually exercises the analyser.
func _compiles_clean(path: String) -> bool:
	var source := FileAccess.get_file_as_string(path)
	if source.is_empty():
		return true
	var script := GDScript.new()
	script.source_code = source
	# The compiler resolves `preload()` and relative paths against this.
	script.resource_path = path
	return script.reload(true) == OK
