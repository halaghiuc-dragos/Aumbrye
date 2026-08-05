extends RefCounted
class_name MaterialFlash

## Brief albedo flash on hit via the pixel_diorama_surface flash_amount uniform.

const FLASH_PARAM := &"flash_amount"
const FLASH_DURATION := 0.25
const META_SAVED_OVERRIDE := &"material_flash_saved_override"
const META_ACTIVE_TWEEN := &"material_flash_tween"


static func flash(node: Node3D, strength: float = 1.0) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in _gather_meshes(node):
		_flash_mesh(mesh, strength)


static func _gather_meshes(root: Node) -> Array[MeshInstance3D]:
	var out: Array[MeshInstance3D] = []
	if root is MeshInstance3D:
		out.append(root)
	for child in root.get_children():
		out.append_array(_gather_meshes(child))
	return out


static func _flash_mesh(mesh: MeshInstance3D, strength: float) -> void:
	if mesh.has_meta(META_ACTIVE_TWEEN):
		var active_tween := mesh.get_meta(META_ACTIVE_TWEEN) as Tween
		if active_tween and active_tween.is_valid():
			active_tween.kill()
	else:
		mesh.set_meta(META_SAVED_OVERRIDE, mesh.material_override)

	var base_mat := mesh.get_active_material(0)
	if base_mat == null or not (base_mat is ShaderMaterial):
		return
	var shader_mat := base_mat as ShaderMaterial
	if not shader_mat.shader:
		return
	var dup := shader_mat.duplicate() as ShaderMaterial
	mesh.material_override = dup
	dup.set_shader_parameter(FLASH_PARAM, clampf(strength, 0.0, 1.0))
	var tree := mesh.get_tree()
	if tree == null:
		return
	var tween := tree.create_tween()
	mesh.set_meta(META_ACTIVE_TWEEN, tween)
	tween.tween_method(
		func(v: float) -> void:
			if is_instance_valid(dup):
				dup.set_shader_parameter(FLASH_PARAM, v),
		strength,
		0.0,
		FLASH_DURATION
	)
	tween.tween_callback(func() -> void:
		if not is_instance_valid(mesh):
			return
		if mesh.has_meta(META_SAVED_OVERRIDE):
			mesh.material_override = mesh.get_meta(META_SAVED_OVERRIDE)
			mesh.remove_meta(META_SAVED_OVERRIDE)
		elif is_instance_valid(dup):
			dup.set_shader_parameter(FLASH_PARAM, 0.0)
		mesh.remove_meta(META_ACTIVE_TWEEN)
	)


static func restore_all(node: Node3D) -> void:
	if node == null or not is_instance_valid(node):
		return
	for mesh in _gather_meshes(node):
		if mesh.has_meta(META_ACTIVE_TWEEN):
			var active_tween := mesh.get_meta(META_ACTIVE_TWEEN) as Tween
			if active_tween and active_tween.is_valid():
				active_tween.kill()
			mesh.remove_meta(META_ACTIVE_TWEEN)
		if mesh.has_meta(META_SAVED_OVERRIDE):
			mesh.material_override = mesh.get_meta(META_SAVED_OVERRIDE)
			mesh.remove_meta(META_SAVED_OVERRIDE)
		elif mesh.material_override is ShaderMaterial:
			(mesh.material_override as ShaderMaterial).set_shader_parameter(FLASH_PARAM, 0.0)
