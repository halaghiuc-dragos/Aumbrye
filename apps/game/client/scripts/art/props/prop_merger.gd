class_name PropMerger
extends RefCounted

## Folds the static meshes under a node into one mesh per material.
##
## A dressed room or the hub is hundreds of small models. Left as separate nodes they cost a draw
## call each and exhaust the renderer's shader-instance buffer, so once everything is placed the
## static pieces are merged. Anything that must stay its own node (a flickering coal bed, a banner
## that sways, a door that opens) carries the `no_merge` meta on itself or on an ancestor.

const NO_MERGE_META := &"no_merge"


static func merge_static(root: Node3D, merged_name: String = "MergedProps") -> int:
	if OS.get_environment("AUMBRYE_NO_MERGE") != "":
		return 0
	var sources: Array[MeshInstance3D] = []
	_collect(root, root, sources)
	if sources.size() < 2:
		return 0
	var per_material: Dictionary = {}
	var materials: Array[Material] = []
	for source in sources:
		var relative := _relative_transform(source, root)
		var normal_basis := relative.basis.inverse().transposed()
		for surface in source.mesh.get_surface_count():
			var material := _material_of(source, surface)
			if material == null:
				continue
			var bucket: Dictionary = per_material.get(material, {})
			if bucket.is_empty():
				bucket = {"v": PackedVector3Array(), "n": PackedVector3Array(), "c": PackedColorArray(), "i": PackedInt32Array()}
				per_material[material] = bucket
				materials.append(material)
			_append_surface(bucket, source.mesh, surface, relative, normal_basis)
	var merged := ArrayMesh.new()
	for material in materials:
		var bucket: Dictionary = per_material[material]
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = bucket["v"]
		arrays[Mesh.ARRAY_NORMAL] = bucket["n"]
		arrays[Mesh.ARRAY_COLOR] = bucket["c"]
		arrays[Mesh.ARRAY_INDEX] = bucket["i"]
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		merged.surface_set_material(merged.get_surface_count() - 1, material)
	var instance := MeshInstance3D.new()
	instance.name = merged_name
	instance.mesh = merged
	root.add_child(instance)
	for source in sources:
		source.get_parent().remove_child(source)
		source.queue_free()
	return sources.size()


static func _collect(node: Node, root: Node3D, out: Array[MeshInstance3D]) -> void:
	if node.has_meta(NO_MERGE_META):
		return
	if node != root and node is Light3D:
		return
	var mesh_instance := node as MeshInstance3D
	if mesh_instance != null and mesh_instance.mesh != null and mesh_instance.visible and mesh_instance.material_override == null:
		out.append(mesh_instance)
	for child in node.get_children():
		_collect(child, root, out)


static func _material_of(instance: MeshInstance3D, surface: int) -> Material:
	var override := instance.get_surface_override_material(surface)
	return override if override != null else instance.mesh.surface_get_material(surface)


## The transform taking `node`'s local space into `root`'s, from the node tree alone, so it works
## before the nodes have entered the scene tree.
static func _relative_transform(node: Node3D, root: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var current: Node = node
	while current != null and current != root:
		var spatial := current as Node3D
		if spatial != null:
			result = spatial.transform * result
		current = current.get_parent()
	return result


static func _append_surface(
	bucket: Dictionary, mesh: Mesh, surface: int, relative: Transform3D, normal_basis: Basis
) -> void:
	var arrays := mesh.surface_get_arrays(surface)
	var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
	var normals: Variant = arrays[Mesh.ARRAY_NORMAL]
	var colors: Variant = arrays[Mesh.ARRAY_COLOR]
	var indices: Variant = arrays[Mesh.ARRAY_INDEX]
	# Packed arrays are values: take each out of the bucket, extend it, and put it back.
	var out_vertices: PackedVector3Array = bucket["v"]
	var out_normals: PackedVector3Array = bucket["n"]
	var out_colors: PackedColorArray = bucket["c"]
	var out_indices: PackedInt32Array = bucket["i"]
	var base := out_vertices.size()
	for i in vertices.size():
		out_vertices.append(relative * vertices[i])
		var normal := Vector3.UP
		if normals is PackedVector3Array and (normals as PackedVector3Array).size() > i:
			normal = (normal_basis * (normals as PackedVector3Array)[i]).normalized()
		out_normals.append(normal)
		var colour := Color.WHITE
		if colors is PackedColorArray and (colors as PackedColorArray).size() > i:
			colour = (colors as PackedColorArray)[i]
		out_colors.append(colour)
	if indices is PackedInt32Array and not (indices as PackedInt32Array).is_empty():
		for index in (indices as PackedInt32Array):
			out_indices.append(base + index)
	else:
		for i in vertices.size():
			out_indices.append(base + i)
	bucket["v"] = out_vertices
	bucket["n"] = out_normals
	bucket["c"] = out_colors
	bucket["i"] = out_indices
