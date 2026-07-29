extends RefCounted
class_name CombatCollisionDebug

const HITBOX_COLOR := Color(1.0, 0.15, 0.15, 1.0)
const HURTBOX_COLOR := Color(0.2, 0.55, 1.0, 1.0)
const DEBUG_SCALE := Vector3(1.05, 1.05, 1.05)


static func set_debug_draw(area: Area3D, enabled: bool, color: Color) -> void:
	var mesh_node := area.get_node_or_null("DebugDraw") as MeshInstance3D
	if mesh_node == null:
		mesh_node = _create_debug_mesh(area, color)
		if mesh_node == null:
			push_warning("CombatCollisionDebug: no collision shape on %s" % area.get_path())
			return
	mesh_node.visible = enabled


static func _create_debug_mesh(area: Area3D, color: Color) -> MeshInstance3D:
	var collision := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.shape == null:
		return null
	var mesh := _mesh_from_shape(collision.shape)
	if mesh == null:
		return null
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "DebugDraw"
	mesh_instance.mesh = mesh
	mesh_instance.transform = collision.transform
	mesh_instance.scale = DEBUG_SCALE
	mesh_instance.material_override = _make_debug_material(color)
	mesh_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mesh_instance.gi_mode = GeometryInstance3D.GI_MODE_DISABLED
	area.add_child(mesh_instance)
	return mesh_instance


static func _mesh_from_shape(shape: Shape3D) -> Mesh:
	if shape is BoxShape3D:
		var box_shape := shape as BoxShape3D
		var box_mesh := BoxMesh.new()
		box_mesh.size = box_shape.size
		return box_mesh
	if shape is CapsuleShape3D:
		var capsule_shape := shape as CapsuleShape3D
		var capsule_mesh := CapsuleMesh.new()
		capsule_mesh.radius = capsule_shape.radius
		capsule_mesh.height = capsule_shape.height
		return capsule_mesh
	if shape is SphereShape3D:
		var sphere_shape := shape as SphereShape3D
		var sphere_mesh := SphereMesh.new()
		sphere_mesh.radius = sphere_shape.radius
		sphere_mesh.height = sphere_shape.radius * 2.0
		return sphere_mesh
	return shape.get_debug_mesh()


static func _make_debug_material(color: Color) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	material.albedo_color = color
	material.emission_enabled = true
	material.emission = color
	material.emission_energy_multiplier = 2.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	material.disable_fog = true
	material.no_depth_test = true
	return material
