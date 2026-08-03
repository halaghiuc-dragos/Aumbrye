class_name CharacterFloorSnap
extends RefCounted

## Align CharacterBody3D collision feet and diorama visuals to floor height.


static func collision_bottom_local(body: Node3D) -> float:
	var collision := body.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if collision == null or collision.shape == null:
		return 0.0
	var bottom_y := collision.position.y
	if collision.shape is CapsuleShape3D:
		bottom_y -= (collision.shape as CapsuleShape3D).height * 0.5
	elif collision.shape is BoxShape3D:
		bottom_y -= (collision.shape as BoxShape3D).size.y * 0.5
	elif collision.shape is CylinderShape3D:
		bottom_y -= (collision.shape as CylinderShape3D).height * 0.5
	return bottom_y


static func snap_feet_to_floor(body: CharacterBody3D, floor_y: float = 0.0) -> void:
	var bottom_y := collision_bottom_local(body)
	body.position.y = floor_y - bottom_y


static func align_diorama_visual(body: Node3D, visual: Node3D, profile: String) -> void:
	if visual == null:
		return
	var feet_y := DioramaCharacterSkin.feet_local_y(profile)
	visual.position.y = -body.position.y - feet_y
