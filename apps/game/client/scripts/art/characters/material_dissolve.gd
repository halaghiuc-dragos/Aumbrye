extends RefCounted
class_name MaterialDissolve

## Death dissolve via dither-clip on pixel_diorama_surface materials.

const DISSOLVE_PARAM := &"dissolve_clip"
const FLASH_PARAM := &"flash_amount"
const DISSOLVE_DURATION := 0.65  # Matches VfxService.DEATH_BURST_LIFETIME
const META_SAVED_OVERRIDE := &"material_dissolve_saved_override"


static func dissolve(node: Node3D, duration: float = DISSOLVE_DURATION) -> void:
	if node == null or not is_instance_valid(node):
		return
	var meshes := _gather_meshes(node)
	if meshes.is_empty():
		return
	var overrides: Array[ShaderMaterial] = []
	for mesh in meshes:
		if not mesh.has_meta(META_SAVED_OVERRIDE):
			mesh.set_meta(META_SAVED_OVERRIDE, mesh.material_override)
		var base_mat := mesh.get_active_material(0)
		if base_mat == null or not (base_mat is ShaderMaterial):
			continue
		var dup := (base_mat as ShaderMaterial).duplicate() as ShaderMaterial
		dup.set_shader_parameter(DISSOLVE_PARAM, 1.0)
		dup.set_shader_parameter(FLASH_PARAM, 0.0)
		mesh.material_override = dup
		overrides.append(dup)
	if overrides.is_empty():
		return
	var tree := node.get_tree()
	if tree == null:
		return
	var tween := tree.create_tween()
	tween.set_parallel(true)
	for mat in overrides:
		tween.tween_method(
			func(v: float) -> void:
				if is_instance_valid(mat):
					mat.set_shader_parameter(DISSOLVE_PARAM, v),
			1.0,
			0.0,
			duration
		)


static func restore(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in _gather_meshes(node):
		_restore_mesh(mesh)


static func _restore_mesh(mesh: MeshInstance3D) -> void:
	if mesh.has_meta(META_SAVED_OVERRIDE):
		mesh.material_override = mesh.get_meta(META_SAVED_OVERRIDE)
		mesh.remove_meta(META_SAVED_OVERRIDE)
	elif mesh.material_override is ShaderMaterial:
		var mat := mesh.material_override as ShaderMaterial
		mat.set_shader_parameter(DISSOLVE_PARAM, 1.0)
		mat.set_shader_parameter(FLASH_PARAM, 0.0)


static func _gather_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_gather_meshes(child))
	return out
