extends RefCounted
class_name VoxelGrid

## Global voxel edge and rig pivot contract for authored character meshes.

const EDGE := 0.04

const REQUIRED_PIVOTS := {
	"biped":
	[
		"LegL",
		"LegR",
		"Torso",
		"Head",
		"ArmL",
		"ArmR",
		"WeaponMount",
		"ShieldMount",
	],
	"quadruped":
	[
		"LegL",
		"LegR",
		"LegBL",
		"LegBR",
		"Torso",
		"Head",
		"Tail",
	],
}


static func voxel_to_metres(voxel: Vector3i) -> Vector3:
	return Vector3(voxel.x, voxel.y, voxel.z) * EDGE


static func joint_to_metres(joint: Array) -> Vector3:
	if joint.size() < 3:
		return Vector3.ZERO
	return Vector3(float(joint[0]), float(joint[1]), float(joint[2])) * EDGE


const SNAP_EPSILON := 1e-4


static func snap_metres(value: float) -> float:
	return snapped(value, EDGE)


static func vertex_on_grid(vertex: Vector3) -> bool:
	for axis in range(3):
		var snapped_axis := snap_metres(vertex[axis])
		if absf(vertex[axis] - snapped_axis) > SNAP_EPSILON:
			return false
	return true


static func scale_is_uniform(node: Node3D) -> bool:
	var s := node.scale
	return is_equal_approx(s.x, s.y) and is_equal_approx(s.y, s.z)


static func collect_non_uniform_scales(root: Node3D) -> PackedStringArray:
	var offenders: PackedStringArray = []
	_collect_non_uniform_scales_recursive(root, root, offenders)
	return offenders


static func color_matches_palette(c: Color) -> bool:
	for row in PixelDioramaStyle.PALETTES:
		for slot_color in row:
			var pc := slot_color as Color
			if is_equal_approx(c.r, pc.r) and is_equal_approx(c.g, pc.g) and is_equal_approx(c.b, pc.b):
				return true
	return false


static func mesh_vertex_colors_valid(mesh: ArrayMesh) -> bool:
	if mesh == null:
		return false
	for surface_idx in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_idx)
		if arrays.size() <= Mesh.ARRAY_COLOR:
			continue
		var colors: PackedColorArray = arrays[Mesh.ARRAY_COLOR]
		for color in colors:
			if not color_matches_palette(color):
				return false
	return true


static func mesh_vertices_on_grid(mesh: ArrayMesh) -> bool:
	if mesh == null:
		return false
	for surface_idx in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(surface_idx)
		if arrays.size() <= Mesh.ARRAY_VERTEX:
			continue
		var vertices: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		for vertex in vertices:
			if not vertex_on_grid(vertex):
				return false
	return true


static func _collect_non_uniform_scales_recursive(node: Node, root: Node, offenders: PackedStringArray) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		if not scale_is_uniform(n3):
			offenders.append(String(root.get_path_to(n3)))
	for child in node.get_children():
		_collect_non_uniform_scales_recursive(child, root, offenders)
