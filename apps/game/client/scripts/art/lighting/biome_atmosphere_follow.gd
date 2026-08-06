class_name BiomeAtmosphereFollow
extends Node3D

## Snaps atmosphere holder to a follow target on a coarse grid so motes stay local.

const SNAP_GRID := 4.0

var _follow: Node3D


func set_follow(target: Node3D) -> void:
	_follow = target
	set_process(target != null)


func _process(_delta: float) -> void:
	if _follow == null or not is_instance_valid(_follow):
		return
	var pos := _follow.global_position
	pos.x = snapped(pos.x, SNAP_GRID)
	pos.z = snapped(pos.z, SNAP_GRID)
	pos.y = 0.0
	global_position = pos
