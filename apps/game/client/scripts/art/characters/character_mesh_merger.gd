extends RefCounted
class_name CharacterMeshMerger


const MERGED_NAME := "Merged"
const MERGED_FLAG := &"merged_into_parent"
const SKIN_TINT_PARAM := &"skin_tint"

const BARRIER_NAMES := {
	"Root": true,
	"Torso": true,
	"Head": true,
	"ArmL": true,
	"ArmR": true,
	"LegL": true,
	"LegR": true,
	"LegBL": true,
	"LegBR": true,
	"Tail": true,
	"WeaponMount": true,
	"ShieldMount": true,
}


const MERGE_EXCLUDED := {
	"WeaponMount": true,
	"ShieldMount": true,
}


static func merge(visual: Node3D) -> void:
	if visual == null:
		return
	for pivot in _collect_barriers(visual):
		if MERGE_EXCLUDED.has(str(pivot.name)):
			continue
		_merge_pivot(pivot)


static func unmerge(visual: Node3D) -> void:
	if visual == null:
		return
	_restore(visual)


static func is_merged_source(mesh: MeshInstance3D) -> bool:
	return mesh != null and mesh.has_meta(MERGED_FLAG)


static func _restore(node: Node) -> void:
	for child in node.get_children():
		var mesh := child as MeshInstance3D
		if mesh != null and str(mesh.name).begins_with(MERGED_NAME):
			node.remove_child(mesh)
			mesh.queue_free()
			continue
		if mesh != null and mesh.has_meta(MERGED_FLAG):
			mesh.remove_meta(MERGED_FLAG)
			mesh.visible = true
		_restore(child)


static func _collect_barriers(visual: Node3D) -> Array[Node3D]:
	var out: Array[Node3D] = []
	_collect_barriers_recursive(visual, out)
	return out


static func _collect_barriers_recursive(node: Node, out: Array[Node3D]) -> void:
	for child in node.get_children():
		var pivot := child as Node3D
		if pivot != null and BARRIER_NAMES.has(str(pivot.name)):
			out.append(pivot)
		_collect_barriers_recursive(child, out)


static func _gather_sources(pivot: Node3D, out: Array[MeshInstance3D]) -> void:
	for child in pivot.get_children():
		var node := child as Node3D
		if node == null:
			continue
		if BARRIER_NAMES.has(str(node.name)):
			continue
		var mesh := node as MeshInstance3D
		if mesh != null:
			if str(mesh.name).begins_with(MERGED_NAME) or mesh.has_meta(MERGED_FLAG):
				continue
			if mesh.visible and mesh.mesh != null:
				out.append(mesh)
			continue
		if not node.visible:
			continue
		_gather_sources(node, out)


static func _relative_transform(from: Node3D, ancestor: Node3D) -> Transform3D:
	var result := Transform3D.IDENTITY
	var node := from
	while node != null and node != ancestor:
		result = node.transform * result
		node = node.get_parent() as Node3D
	return result


static func _surface_material(mesh: MeshInstance3D, surface: int) -> Material:
	if mesh.material_override != null:
		return mesh.material_override
	var overridden := mesh.get_surface_override_material(surface)
	if overridden != null:
		return overridden
	return mesh.mesh.surface_get_material(surface)


static func _merge_pivot(pivot: Node3D) -> void:
	var sources: Array[MeshInstance3D] = []
	_gather_sources(pivot, sources)
	if sources.size() < 2:
		return
	var batches: Dictionary = {}
	var batch_order: Array = []
	for source in sources:
		var key := str(source.get_instance_shader_parameter(SKIN_TINT_PARAM))
		if not batches.has(key):
			var fresh: Array[MeshInstance3D] = []
			batches[key] = fresh
			batch_order.append(key)
		var bucket: Array[MeshInstance3D] = batches[key]
		bucket.append(source)
	var batch_index := 0
	for key in batch_order:
		var batch: Array[MeshInstance3D] = batches[key]
		if batch.size() >= 2:
			_merge_batch(pivot, batch, batch_index)
		batch_index += 1


static func _merge_batch(
	pivot: Node3D, sources: Array[MeshInstance3D], batch_index: int
) -> void:
	var groups: Dictionary = {}
	var order: Array = []
	for source in sources:
		var local := _relative_transform(source, pivot)
		var mesh: Mesh = source.mesh
		var array_mesh := mesh as ArrayMesh
		for surface in mesh.get_surface_count():
			if (
				array_mesh != null
				and array_mesh.surface_get_primitive_type(surface) != Mesh.PRIMITIVE_TRIANGLES
			):
				return
			var material := _surface_material(source, surface)
			var key := "0" if material == null else str(material.get_instance_id())
			if not groups.has(key):
				var tool := SurfaceTool.new()
				tool.begin(Mesh.PRIMITIVE_TRIANGLES)
				groups[key] = {"tool": tool, "material": material}
				order.append(key)
			(groups[key]["tool"] as SurfaceTool).append_from(mesh, surface, local)

	if order.is_empty():
		return

	var merged_mesh := ArrayMesh.new()
	for key in order:
		var tool := groups[key]["tool"] as SurfaceTool
		tool.index()
		tool.commit(merged_mesh)
		var index := merged_mesh.get_surface_count() - 1
		if index >= 0:
			merged_mesh.surface_set_material(index, groups[key]["material"] as Material)
	if merged_mesh.get_surface_count() == 0:
		return

	var merged := MeshInstance3D.new()
	merged.name = "%s%d" % [MERGED_NAME, batch_index]
	merged.mesh = merged_mesh
	merged.cast_shadow = sources[0].cast_shadow
	merged.layers = sources[0].layers
	var tint: Variant = sources[0].get_instance_shader_parameter(SKIN_TINT_PARAM)
	if tint != null:
		merged.set_instance_shader_parameter(SKIN_TINT_PARAM, tint)
	pivot.add_child(merged)

	for source in sources:
		source.set_meta(MERGED_FLAG, true)
		source.visible = false
