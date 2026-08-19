extends RefCounted
class_name VoxelMeshBuilder

## Builds greedy-merged voxel ArrayMeshes from authored .voxels.json data.

static var _cache: Dictionary = {}


static func baked_mesh_path(path: String) -> String:
	if not path.ends_with(".voxels.json"):
		return path
	return path.substr(0, path.length() - ".voxels.json".length()) + ".tres"


static func load_mesh(source_path: String, theme: int = -1) -> ArrayMesh:
	var path := source_path
	var baked := baked_mesh_path(path)
	if theme < 0 and baked != path and ResourceLoader.exists(baked):
		path = baked
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
	_palette_cache.clear()


## Standard binary-plane greedy mesher: for each of the 3 axes, sweep every boundary slice
## perpendicular to that axis, build a 2D mask of exposed-face direction (+1 / -1 / 0 = none),
## then merge the mask into maximal rectangles instead of emitting one quad per exposed voxel
## face. All voxels in one part share a single flat `base_color`, so merging never has to
## compare per-cell material — any two adjacent same-direction faces can always join.
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
	if solid.is_empty():
		var empty_st := SurfaceTool.new()
		empty_st.begin(Mesh.PRIMITIVE_TRIANGLES)
		return empty_st.commit()
	var min_cell := Vector3i(2147483647, 2147483647, 2147483647)
	var max_cell := Vector3i(-2147483648, -2147483648, -2147483648)
	for key in solid:
		var k: Vector3i = key
		min_cell.x = mini(min_cell.x, k.x)
		min_cell.y = mini(min_cell.y, k.y)
		min_cell.z = mini(min_cell.z, k.z)
		max_cell.x = maxi(max_cell.x, k.x)
		max_cell.y = maxi(max_cell.y, k.y)
		max_cell.z = maxi(max_cell.z, k.z)
	var dims := [
		max_cell.x - min_cell.x + 1, max_cell.y - min_cell.y + 1, max_cell.z - min_cell.z + 1
	]
	var origin := [min_cell.x, min_cell.y, min_cell.z]
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	for d in 3:
		var u := (d + 1) % 3
		var v := (d + 2) % 3
		var dim_u: int = dims[u]
		var dim_v: int = dims[v]
		for slice in range(dims[d] + 1):
			var mask := PackedInt32Array()
			mask.resize(dim_u * dim_v)
			var any_face := false
			for i in dim_u:
				for j in dim_v:
					var neg := _make_coord(d, u, v, slice - 1, i, j, origin)
					var pos := _make_coord(d, u, v, slice, i, j, origin)
					var solid_neg := solid.has(neg)
					var solid_pos := solid.has(pos)
					var m := 0
					if solid_neg and not solid_pos:
						m = 1
					elif solid_pos and not solid_neg:
						m = -1
					mask[i * dim_v + j] = m
					if m != 0:
						any_face = true
			if not any_face:
				continue
			_emit_slice_quads(st, mask, dim_u, dim_v, d, u, v, slice, origin, edge, base_color)
	st.index()
	return st.commit()


static func _make_coord(d: int, u: int, v: int, d_val: int, u_val: int, v_val: int, origin: Array) -> Vector3i:
	var arr := [0, 0, 0]
	arr[d] = origin[d] + d_val
	arr[u] = origin[u] + u_val
	arr[v] = origin[v] + v_val
	return Vector3i(arr[0], arr[1], arr[2])


static func _emit_slice_quads(
	st: SurfaceTool,
	mask: PackedInt32Array,
	dim_u: int,
	dim_v: int,
	d: int,
	u: int,
	v: int,
	slice: int,
	origin: Array,
	edge: float,
	base_color: Color
) -> void:
	var i := 0
	while i < dim_u:
		var j := 0
		while j < dim_v:
			var c: int = mask[i * dim_v + j]
			if c == 0:
				j += 1
				continue
			var w := 1
			while j + w < dim_v and mask[i * dim_v + (j + w)] == c:
				w += 1
			var h := 1
			var grow := true
			while i + h < dim_u and grow:
				for k in w:
					if mask[(i + h) * dim_v + (j + k)] != c:
						grow = false
						break
				if grow:
					h += 1
			_emit_quad(st, d, u, v, slice, i, j, h, w, c, origin, edge, base_color)
			for di in h:
				for dj in w:
					mask[(i + di) * dim_v + (j + dj)] = 0
			j += w
		i += 1


static func _emit_quad(
	st: SurfaceTool,
	d: int,
	u: int,
	v: int,
	slice: int,
	i0: int,
	j0: int,
	h: int,
	w: int,
	c: int,
	origin: Array,
	edge: float,
	base_color: Color
) -> void:
	var plane_d := float(origin[d] + slice) * edge
	var u0 := float(origin[u] + i0) * edge
	var u1 := float(origin[u] + i0 + h) * edge
	var v0 := float(origin[v] + j0) * edge
	var v1 := float(origin[v] + j0 + w) * edge
	var a := _uv_to_vec3(d, u, v, plane_d, u0, v0)
	var b := _uv_to_vec3(d, u, v, plane_d, u1, v0)
	var c2 := _uv_to_vec3(d, u, v, plane_d, u1, v1)
	var e := _uv_to_vec3(d, u, v, plane_d, u0, v1)
	var normal_arr := [0.0, 0.0, 0.0]
	normal_arr[d] = 1.0 if c > 0 else -1.0
	var n := Vector3(normal_arr[0], normal_arr[1], normal_arr[2])
	if c > 0:
		_emit_triangle(st, a, b, c2, n, base_color)
		_emit_triangle(st, a, c2, e, n, base_color)
	else:
		_emit_triangle(st, a, c2, b, n, base_color)
		_emit_triangle(st, a, e, c2, n, base_color)


static func _uv_to_vec3(d: int, u: int, v: int, d_val: float, u_val: float, v_val: float) -> Vector3:
	var arr := [0.0, 0.0, 0.0]
	arr[d] = d_val
	arr[u] = u_val
	arr[v] = v_val
	return Vector3(arr[0], arr[1], arr[2])


static func _emit_triangle(
	st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, n: Vector3, color: Color
) -> void:
	st.set_normal(n)
	st.set_color(color)
	st.add_vertex(a)
	st.set_normal(n)
	st.set_color(color)
	st.add_vertex(b)
	st.set_normal(n)
	st.set_color(color)
	st.add_vertex(c)


static func _snap_to_palette(color: Color, theme: int) -> Color:
	var palette := _palette_for_theme(theme)
	var best := color
	var best_dist := INF
	for candidate in palette:
		var dist := _color_distance(color, candidate)
		if dist < best_dist:
			best_dist = dist
			best = candidate
	return best


static var _palette_cache: Dictionary = {}


static func _palette_for_theme(theme: int) -> Array:
	if _palette_cache.has(theme):
		return _palette_cache[theme]
	const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
	var palette: Array = []
	for slot_idx in 8:
		palette.append(PixelStyle.get_palette_color(theme, slot_idx as PixelStyle.PaletteSlot))
	_palette_cache[theme] = palette
	return palette


static func _color_distance(a: Color, b: Color) -> float:
	var dr := a.r - b.r
	var dg := a.g - b.g
	var db := a.b - b.b
	return sqrt(dr * dr + dg * dg + db * db)
