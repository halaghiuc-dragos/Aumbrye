extends SceneTree


const INTERMEDIATE_ROOT := "res://assets/characters/_intermediate/"
const OUTPUT_ROOT := "res://assets/characters/"


func _initialize() -> void:
	var converted := 0
	converted += _export_tree(INTERMEDIATE_ROOT, OUTPUT_ROOT)
	converted += _export_tree(INTERMEDIATE_ROOT + "equipment/", OUTPUT_ROOT + "equipment/")
	print("export_voxel_meshes: wrote %d meshes" % converted)
	quit()


func _export_tree(intermediate_dir: String, output_dir: String) -> int:
	var global_intermediate := ProjectSettings.globalize_path(intermediate_dir)
	if not DirAccess.dir_exists_absolute(global_intermediate):
		return 0
	var global_output := ProjectSettings.globalize_path(output_dir)
	if not DirAccess.dir_exists_absolute(global_output):
		DirAccess.make_dir_recursive_absolute(global_output)

	var count := 0
	var dir := DirAccess.open(intermediate_dir)
	if dir == null:
		return 0
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		var sub_path := intermediate_dir.path_join(entry)
		if dir.current_is_dir() and not entry.begins_with("."):
			count += _export_tree(sub_path, output_dir.path_join(entry))
		elif entry.ends_with(".mesh.json"):
			var mesh_name := entry.trim_suffix(".json")
			var output_path := output_dir.path_join(mesh_name)
			if _export_mesh_json(sub_path, output_path):
				count += 1
		entry = dir.get_next()
	dir.list_dir_end()
	return count


func _export_mesh_json(json_path: String, output_path: String) -> bool:
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(json_path))
	if not parsed is Dictionary:
		push_error("invalid mesh json: %s" % json_path)
		return false
	var data: Dictionary = parsed
	var vertices: PackedVector3Array = _to_vector3_array(data.get("vertices", []))
	var normals: PackedVector3Array = _to_vector3_array(data.get("normals", []))
	var colors: PackedColorArray = _to_color_array(data.get("colors", []))
	var indices: PackedInt32Array = PackedInt32Array(data.get("indices", []))

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)

	var global_output := ProjectSettings.globalize_path(output_path)
	DirAccess.make_dir_recursive_absolute(global_output.get_base_dir())
	var err := ResourceSaver.save(mesh, output_path)
	if err != OK:
		push_error("failed to save %s err=%s" % [output_path, err])
		return false
	return true


func _to_vector3_array(raw: Variant) -> PackedVector3Array:
	var out := PackedVector3Array()
	if raw is Array:
		for item in raw:
			if item is Array and item.size() >= 3:
				out.append(Vector3(float(item[0]), float(item[1]), float(item[2])))
	return out


func _to_color_array(raw: Variant) -> PackedColorArray:
	var out := PackedColorArray()
	if raw is Array:
		for item in raw:
			if item is Array and item.size() >= 3:
				out.append(Color(float(item[0]), float(item[1]), float(item[2]), 1.0))
	return out
