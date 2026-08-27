class_name CombatFacing
extends RefCounted


## The one place the project's facing convention lives: rig forward is **+basis.z**, not -Z.
## Every hitbox, VFX aim and telegraph heading goes through here so the convention cannot fork.
static func forward_of(facing: Node3D) -> Vector3:
	if facing == null:
		return Vector3(0.0, 0.0, 1.0)
	return facing.global_transform.basis.z


## An actor's aim direction, preferring whatever it reports for itself. Used wherever a system needs
## the direction a body is *fighting* in rather than the raw node basis.
static func aim_forward_of(body: Node3D) -> Vector3:
	if body == null:
		return Vector3.FORWARD
	if body.has_method("get_facing_direction"):
		return body.call("get_facing_direction")
	return forward_of(body)
