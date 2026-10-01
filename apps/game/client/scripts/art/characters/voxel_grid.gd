extends RefCounted
class_name VoxelGrid


const EDGE := 0.04


static func joint_to_metres(joint: Array) -> Vector3:
	if joint.size() < 3:
		return Vector3.ZERO
	return Vector3(float(joint[0]), float(joint[1]), float(joint[2])) * EDGE


static func scale_is_uniform(node: Node3D) -> bool:
	var s := node.scale
	return is_equal_approx(s.x, s.y) and is_equal_approx(s.y, s.z)


static func _collect_non_uniform_scales_recursive(node: Node, root: Node, offenders: PackedStringArray) -> void:
	if node is Node3D:
		var n3 := node as Node3D
		if not scale_is_uniform(n3):
			offenders.append(String(root.get_path_to(n3)))
	for child in node.get_children():
		_collect_non_uniform_scales_recursive(child, root, offenders)
