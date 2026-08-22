extends Node3D

## One bird on a slow circle over the plaza.
##
## Position is recomputed from elapsed time rather than integrated, so a frame spike cannot make a
## bird drift off its ring, and nothing accumulates over a long session in the hub.

const BOB_HEIGHT := 0.55
const BOB_SPEED := 0.9
const FLAP_SPEED := 7.0
const FLAP_ANGLE := 0.55

var _centre := Vector3.ZERO
var _radius := 12.0
var _height := 14.0
var _period := 24.0
var _phase := 0.0
var _wings: Array = []
var _time := 0.0


func setup(
	centre: Vector3,
	radius: float,
	height: float,
	period: float,
	phase: float,
	wings: Array
) -> void:
	_centre = centre
	_radius = radius
	_height = height
	_period = maxf(period, 1.0)
	_phase = phase
	_wings = wings
	# `set_script()` on a node that is already inside the tree does not turn the process callback
	# on — Godot decides that when the script is attached, and by then this node had been added
	# already. Every bird and every stray stood perfectly still. Asking for it explicitly is the
	# fix, and it is why `is_processing()` is what the hub probe asserts on.
	set_process(true)
	_apply(0.0)


func _process(delta: float) -> void:
	_time += delta
	_apply(_time)


func _apply(time: float) -> void:
	var angle := _phase + TAU * time / _period
	position = Vector3(
		_centre.x + cos(angle) * _radius,
		_height + sin(time * BOB_SPEED + _phase) * BOB_HEIGHT,
		_centre.z + sin(angle) * _radius
	)
	# Facing along the tangent of the circle. The project's forward is +Z, which is what
	# `atan2(x, z)` produces (see `CombatFacing`).
	var heading := Vector3(-sin(angle), 0.0, cos(angle))
	rotation.y = atan2(heading.x, heading.z)
	var flap := sin(time * FLAP_SPEED + _phase) * FLAP_ANGLE
	for i in _wings.size():
		var wing := _wings[i] as Node3D
		if wing == null or not is_instance_valid(wing):
			continue
		# Mirrored: the left wing rolls the other way, or the bird rows sideways.
		wing.rotation.z = flap if i == 0 else -flap
