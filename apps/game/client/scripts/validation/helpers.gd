extends RefCounted
class_name ValidationHelpers

## File, save, and scene-tree helpers for validation suites.

const SAVE_PATH := ValidationFixtures.SAVE_PATH
const MANUAL_CHECKLIST_REL := "docs/validation/manual-checklist.md"


static func repo_root() -> String:
	return ProjectSettings.globalize_path("res://").path_join("../../..")


static func manual_checklist_path() -> String:
	return repo_root().path_join(MANUAL_CHECKLIST_REL)


static func file_contains(path: String, needle: String) -> bool:
	if not FileAccess.file_exists(path):
		return false
	return needle in FileAccess.get_file_as_string(path)


static func load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script


static func script_has_method(path: String, method_name: String) -> bool:
	var script := load_script(path)
	if script == null:
		return false
	for entry in script.get_script_method_list():
		if str(entry.get("name", "")) == method_name:
			return true
	var base := script.get_base_script()
	while base != null:
		for entry in base.get_script_method_list():
			if str(entry.get("name", "")) == method_name:
				return true
		base = base.get_base_script()
	return false


static func script_has_constant(path: String, constant_name: String) -> bool:
	var script := load_script(path)
	if script == null:
		return false
	return script.get_script_constant_map().has(constant_name)


static func script_constant(path: String, constant_name: String, fallback: Variant = null) -> Variant:
	var script := load_script(path)
	if script == null:
		return fallback
	return script.get_script_constant_map().get(constant_name, fallback)


static func script_has_signal(path: String, signal_name: String) -> bool:
	var script := load_script(path)
	if script == null:
		return false
	for entry in script.get_script_signal_list():
		if str(entry.get("name", "")) == signal_name:
			return true
	return false


static func script_has_property(path: String, property_name: String) -> bool:
	var script := load_script(path)
	if script == null:
		return false
	for entry in script.get_script_property_list():
		if str(entry.get("name", "")) == property_name:
			return true
	return false


static func node_has_method(path: String, method_name: String) -> bool:
	var script := load_script(path)
	if script == null:
		return false
	if script_has_method(path, method_name):
		return true
	var instance: Variant = null
	if script.can_instantiate():
		instance = script.new()
	if instance == null:
		return false
	var found: bool = (instance as Object).has_method(method_name)
	if instance is Node:
		(instance as Node).queue_free()
	return found


static func resource_depends_on(path: String, dependency_path: String) -> bool:
	if not ResourceLoader.exists(path):
		return false
	for dep in ResourceLoader.get_dependencies(path):
		if dependency_path in str(dep):
			return true
	return false


static func backup_save_file() -> Dictionary:
	var backup := {"exists": false, "text": ""}
	if FileAccess.file_exists(SAVE_PATH):
		backup["exists"] = true
		backup["text"] = FileAccess.get_file_as_string(SAVE_PATH)
	return backup


static func restore_save_file(backup: Dictionary) -> void:
	var local_save := _local_save()
	if local_save == null:
		return
	if backup.get("exists", false):
		var text: String = str(backup.get("text", ""))
		var parsed: Variant = JSON.parse_string(text)
		if parsed is Dictionary:
			var file := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
			if file:
				file.store_string(text)
		else:
			local_save.call("delete_save")
	else:
		local_save.call("delete_save")
	local_save.call("load_into_services")


static func count_nodes_by_script(node: Node, script_name: String) -> int:
	var count := 0
	var node_script: Script = node.get_script() as Script
	if node_script and str(node_script.resource_path).ends_with(script_name):
		count += 1
	for child in node.get_children():
		count += count_nodes_by_script(child, script_name)
	return count


static func count_loot_chests(node: Node) -> int:
	return count_nodes_by_script(node, "loot_chest.gd")


static func collect_gdscript_paths(root: String = "res://scripts/") -> PackedStringArray:
	var paths: PackedStringArray = []
	_collect_gdscript_paths_recursive(root, paths)
	return paths


static func collect_referenced_script_paths() -> Dictionary:
	var referenced := {}
	var dir := DirAccess.open("res://scripts/validation/suites")
	if dir == null:
		return referenced
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if file_name.ends_with(".gd"):
			var text := FileAccess.get_file_as_string(
				"res://scripts/validation/suites/%s" % file_name
			)
			for path in collect_gdscript_paths():
				if path in text:
					referenced[path] = true
		file_name = dir.get_next()
	dir.list_dir_end()
	return referenced


static func checklist_heading_exists(checklist_ref: String) -> bool:
	var path := manual_checklist_path()
	if not FileAccess.file_exists(path):
		return false
	var text := FileAccess.get_file_as_string(path)
	return "## %s" % checklist_ref in text


static func _collect_gdscript_paths_recursive(abs_path: String, paths: PackedStringArray) -> void:
	var dir := DirAccess.open(abs_path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var path := abs_path.path_join(entry)
		if dir.current_is_dir():
			_collect_gdscript_paths_recursive(path, paths)
		elif entry.ends_with(".gd"):
			paths.append(path)
		entry = dir.get_next()
	dir.list_dir_end()


static func _local_save() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/LocalSave")
