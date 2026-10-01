class_name ModelLoader
extends RefCounted

## Loads Blender-authored .glb models (tools/blender/) as single vertex-coloured meshes.
##
## Colour lives in the material names the Blender build assigns:
##   slotN       index N of `GLB_PALETTE_SLOTS` in the biome palette (characters and weapons)
##   lit_RRGGBB  a literal colour
##   eqN         role N of a worn item's material family (metal, dark, accent, cloth)
## Every surface is merged into one, so the shader, the mesh merger and the outline pass see the
## same kind of mesh whatever produced it.

const GLB_PALETTE_SLOTS: Array[int] = [2, 3, 4, 5, 6, 7, 1]
const CACHE_LIMIT := 512

static var _cache: Dictionary = {}
static var _cache_order: Array[String] = []
static var _hits := 0
static var _misses := 0
static var _evictions := 0
static var _peak := 0


## A model coloured from the biome palette (`theme` < 0 uses the castle palette).
static func load_mesh(path: String, theme: int = -1) -> ArrayMesh:
	var key := "%s|%d" % [path, theme]
	var known: ArrayMesh = _lookup(key)
	if known != null:
		return known
	var themed := PixelDioramaStyle.get_palette(
		(theme if theme >= 0 else PixelDioramaStyle.PaletteTheme.CASTLE) as PixelDioramaStyle.PaletteTheme
	)
	var mesh := _merge(path, func(material_name: String) -> Color: return _named_colour(material_name, themed, []))
	_store(key, mesh)
	return mesh


## A worn-equipment model coloured from a material family, optionally mirrored across X so the
## second glove or boot has its thumb and buckles on the correct side.
static func load_equipment_mesh(path: String, family: Array, mirrored: bool = false) -> ArrayMesh:
	var colours: Array[Color] = []
	for entry in family:
		var rgb: Array = entry
		colours.append(Color(float(rgb[0]), float(rgb[1]), float(rgb[2])))
	var key := "%s|%s|%s" % [path, ",".join(colours.map(func(c: Color) -> String: return c.to_html(false))), mirrored]
	var known: ArrayMesh = _lookup(key)
	if known != null:
		return known
	var themed := PixelDioramaStyle.get_palette(PixelDioramaStyle.PaletteTheme.CASTLE)
	var mesh := _merge(path, func(material_name: String) -> Color: return _named_colour(material_name, themed, colours))
	if mesh != null and mirrored:
		mesh = _mirror_x(mesh)
	_store(key, mesh)
	return mesh


static func get_cache_stats() -> Dictionary:
	return {
		"retained": _cache.size(), "limit": CACHE_LIMIT, "peak": _peak,
		"hits": _hits, "misses": _misses, "evictions": _evictions,
	}


static func clear_cache() -> void:
	_cache.clear()
	_cache_order.clear()


static func _lookup(key: String) -> ArrayMesh:
	var known: Variant = _cache.get(key)
	if known is ArrayMesh:
		_hits += 1
		return known as ArrayMesh
	return null


static func _store(key: String, mesh: ArrayMesh) -> void:
	_misses += 1
	if mesh == null:
		return
	if _cache_order.size() >= CACHE_LIMIT:
		_cache.erase(_cache_order.pop_front())
		_evictions += 1
	_cache_order.append(key)
	_cache[key] = mesh
	_peak = maxi(_peak, _cache.size())


static func _named_colour(material_name: String, themed: Array[Color], family: Array[Color]) -> Color:
	if material_name.begins_with("slot"):
		var index := clampi(material_name.substr(4).to_int(), 0, GLB_PALETTE_SLOTS.size() - 1)
		return themed[clampi(GLB_PALETTE_SLOTS[index], 0, themed.size() - 1)]
	if material_name.begins_with("eq") and not family.is_empty():
		return family[clampi(material_name.substr(2).to_int(), 0, family.size() - 1)]
	if material_name.begins_with("lit_") and material_name.length() >= 10:
		return Color.html(material_name.substr(4, 6))
	return Color(0.5, 0.5, 0.5)


static func _merge(path: String, colour_for: Callable) -> ArrayMesh:
	var scene := load(path) as PackedScene
	if scene == null:
		push_error("ModelLoader: cannot load %s" % path)
		return null
	var root := scene.instantiate()
	var source: MeshInstance3D = root as MeshInstance3D
	if source == null:
		for node in root.find_children("*", "MeshInstance3D", true, false):
			source = node as MeshInstance3D
			break
	if source == null or source.mesh == null:
		root.free()
		push_error("ModelLoader: %s has no mesh" % path)
		return null
	var vertices := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	for surface in source.mesh.get_surface_count():
		var arrays := source.mesh.surface_get_arrays(surface)
		var material := source.mesh.surface_get_material(surface)
		var colour: Color = colour_for.call(material.resource_name if material else "")
		var surface_vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var surface_indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
		var base := vertices.size()
		vertices.append_array(surface_vertices)
		normals.append_array(arrays[Mesh.ARRAY_NORMAL])
		var tint := PackedColorArray()
		tint.resize(surface_vertices.size())
		tint.fill(colour)
		colors.append_array(tint)
		if surface_indices.is_empty():
			for i in surface_vertices.size():
				indices.append(base + i)
		else:
			for index in surface_indices:
				indices.append(base + index)
	root.free()
	return _build(vertices, normals, colors, indices)


static func _build(
	vertices: PackedVector3Array, normals: PackedVector3Array, colors: PackedColorArray, indices: PackedInt32Array
) -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = vertices
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## The same model reflected across X. Reflection reverses winding, so each triangle's indices are
## swapped to keep faces pointing outward.
static func _mirror_x(mesh: ArrayMesh) -> ArrayMesh:
	var arrays := mesh.surface_get_arrays(0)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
	var indices: PackedInt32Array = arrays[Mesh.ARRAY_INDEX]
	var flipped_vertices := PackedVector3Array()
	var flipped_normals := PackedVector3Array()
	for v in vertices:
		flipped_vertices.append(Vector3(-v.x, v.y, v.z))
	for n in normals:
		flipped_normals.append(Vector3(-n.x, n.y, n.z))
	var flipped_indices := PackedInt32Array()
	for i in range(0, indices.size(), 3):
		flipped_indices.append(indices[i])
		flipped_indices.append(indices[i + 2])
		flipped_indices.append(indices[i + 1])
	return _build(flipped_vertices, flipped_normals, arrays[Mesh.ARRAY_COLOR], flipped_indices)
