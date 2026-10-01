class_name Teleport
extends RefCounted

## Every position jump goes through here. With physics interpolation on, a body that changes
## `global_position` without a reset renders sliding across the room for a frame. The player's
## camera rig is a child of the body, so resetting the body resets it too.


static func to(body: Node3D, position: Vector3) -> void:
	body.global_position = position
	body.reset_physics_interpolation()
