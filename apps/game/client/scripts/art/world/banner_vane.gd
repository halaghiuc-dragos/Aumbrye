extends Node3D


const TURN_SPEED := 0.9


func _process(delta: float) -> void:
	var wind := WindService.direction()
	var target := atan2(wind.x, wind.z)
	rotation.y = _approach_angle(rotation.y, target, TURN_SPEED * delta)


static func _approach_angle(from: float, to: float, max_step: float) -> float:
	var diff := wrapf(to - from, -PI, PI)
	if absf(diff) <= max_step:
		return to
	return from + signf(diff) * max_step
