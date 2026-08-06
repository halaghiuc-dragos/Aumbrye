extends RefCounted
class_name VoxelMeshBuilder

## Builds greedy-merged voxel ArrayMeshes from authored .voxels.json data.

static var _cache: Dictionary = {}


static func load_mesh(path: String, theme: int = -1) -> ArrayMesh:
	var cache_key := "%s:%d" % [path, theme]
	if _cache.has(cache_key):
		return _cache[cache_key]
	var data: Dictionary = {}
	if path.ends_with(".voxels.json"):
		var text := FileAccess.get_file_as_string(path)
		if not text.is_empty():
			var parsed = JSON.parse_string(text)
			if parsed is Dictionary:
				data = parsed
	else:
		var loaded := load(path)
		if loaded is ArrayMesh:
			_cache[cache_key] = loaded
			return loaded
	if data.is_empty():
		return null
	var mesh := _build_from_voxels(data, theme)
	_cache[cache_key] = mesh
	return mesh


static func clear_cache() -> void:
	_cache.clear()


static func _build_from_voxels(data: Dictionary, theme: int = -1) -> ArrayMesh:
	var edge: float = float(data.get("edge", VoxelGrid.EDGE))
	var cells: Array = data.get("cells", [])
	var color_arr: Array = data.get("color", [0.5, 0.5, 0.5])
	var base_color := Color(float(color_arr[0]), float(color_arr[1]), float(color_arr[2]))
	if theme >= 0:
		base_color = _snap_to_palette(base_color, theme)
	if cells.is_empty():
		var size_arr: Array = data.get("size", [1, 1, 1])
		for x in int(size_arr[0]):
			for y in int(size_arr[1]):
				for z in int(size_arr[2]):
					cells.append([x, y, z])
	var solid: Dictionary = {}
	for cell in cells:
		if cell is Array and cell.size() >= 3:
			solid[Vector3i(int(cell[0]), int(cell[1]), int(cell[2]))] = true
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for key in solid:
		var pos := Vector3(key) * edge
		for face in _FACE_DIRS:
			var neighbor: Vector3i = key + face["normal"]
			if solid.has(neighbor):
				continue
			var n: Vector3 = Vector3(face["normal"])
			for tri in face["tris"]:
				var v: Vector3 = pos + tri["a"] * edge
				st.set_normal(n)
				st.set_color(base_color)
				st.add_vertex(v)
				v = pos + tri["b"] * edge
				st.set_normal(n)
				st.set_color(base_color)
				st.add_vertex(v)
				v = pos + tri["c"] * edge
				st.set_normal(n)
				st.set_color(base_color)
				st.add_vertex(v)
	return st.commit()


static func _snap_to_palette(color: Color, theme: int) -> Color:
	const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
	var best := color
	var best_dist := INF
	for slot_idx in 8:
		var candidate := PixelStyle.get_palette_color(theme, slot_idx as PixelStyle.PaletteSlot)
		var dist := _color_distance(color, candidate)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


static func _color_distance(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)


const _FACE_DIRS := [
	{
		"normal": Vector3i(1, 0, 0),
		"tris":
		[
			{"a": Vector3(1, 0, 0), "b": Vector3(1, 1, 0), "c": Vector3(1, 1, 1)},
			{"a": Vector3(1, 0, 0), "b": Vector3(1, 1, 1), "c": Vector3(1, 0, 1)},
		],
	},
	{
		"normal": Vector3i(-1, 0, 0),
		"tris":
		[
			{"a": Vector3(0, 0, 0), "b": Vector3(0, 1, 1), "c": Vector3(0, 1, 0)},
			{"a": Vector3(0, 0, 0), "b": Vector3(0, 0, 1), "c": Vector3(0, 1, 1)},
		],
	},
	{
		"normal": Vector3i(0, 1, 0),
		"tris":
		[
			{"a": Vector3(0, 1, 0), "b": Vector3(0, 1, 1), "c": Vector3(1, 1, 1)},
			{"a": Vector3(0, 1, 0), "b": Vector3(1, 1, 1), "c": Vector3(1, 1, 0)},
		],
	},
	{
		"normal": Vector3i(0, -1, 0),
		"tris":
		[
			{"a": Vector3(0, 0, 0), "b": Vector3(1, 0, 0), "c": Vector3(1, 0, 1)},
			{"a": Vector3(0, 0, 0), "b": Vector3(1, 0, 1), "c": Vector3(0, 0, 1)},
		],
	},
	{
		"normal": Vector3i(0, 0, 1),
		"tris":
		[
			{"a": Vector3(0, 0, 1), "b": Vector3(1, 0, 1), "c": Vector3(1, 1, 1)},
			{"a": Vector3(0, 0, 1), "b": Vector3(1, 1, 1), "c": Vector3(0, 1, 1)},
		],
	},
	{
		"normal": Vector3i(0, 0, -1),
		"tris":
		[
			{"a": Vector3(0, 0, 0), "b": Vector3(0, 1, 0), "c": Vector3(1, 1, 0)},
			{"a": Vector3(0, 0, 0), "b": Vector3(1, 1, 0), "c": Vector3(1, 0, 0)},
		],
	},
]
