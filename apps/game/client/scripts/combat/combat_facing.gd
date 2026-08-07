class_name CombatFacing
extends RefCounted

## Single source of truth for "forward": this project treats a Facing node's
## +Z axis as forward (see Locomotion.get_facing_direction()). Every combat
## script that needs a facing vector must route through here rather than
## re-deriving -basis.z, so the convention cannot silently fork again.


static func forward_of(facing: Node3D) -> Vector3:
	if facing == null:
		return Vector3(0.0, 0.0, 1.0)
	return facing.global_transform.basis.z
