extends Node3D

## A cat or a dog mooching around its patch of the plaza.
##
## Walks to a point, waits, picks another. Deliberately slow and often idle — an animal that never
## stops moving reads as a patrol, not as a stray.

const TURN_SPEED := 4.0
const ARRIVE_DIST := 0.25
const PAUSE_MIN := 1.6
const PAUSE_MAX := 5.5
const BOB_HEIGHT := 0.035
const BOB_SPEED := 7.0
const TAIL_SPEED := 2.4
const TAIL_ANGLE := 0.28

var _home := Vector3.ZERO
var _range := 3.0
var _speed := 1.2
var _tail: Node3D
var _body: Node3D
var _body_base_y := 0.0
var _target := Vector3.ZERO
var _wait := 0.0
var _walk_phase := 0.0
var _rng := RandomNumberGenerator.new()


func setup(home: Vector3, wander_range: float, speed: float, tail: Node3D, body: Node3D) -> void:
	_home = home
	_range = maxf(wander_range, 0.5)
	_speed = speed
	_tail = tail
	_body = body
	if _body:
		_body_base_y = _body.position.y
	_rng.randomize()
	position = home
	_target = home
	_wait = _rng.randf_range(0.0, PAUSE_MAX)
	# `set_script()` on a node that is already inside the tree does not turn the process callback
	# on — Godot decides that when the script is attached, and by then this node had been added
	# already. Every bird and every stray stood perfectly still. Asking for it explicitly is the
	# fix, and it is why `is_processing()` is what the hub probe asserts on.
	set_process(true)


func _process(delta: float) -> void:
	if _tail and is_instance_valid(_tail):
		_tail.rotation.x = sin(Time.get_ticks_msec() * 0.001 * TAIL_SPEED) * TAIL_ANGLE

	if _wait > 0.0:
		_wait -= delta
		if _wait <= 0.0:
			_pick_target()
		_settle_body()
		return

	var to_target := _target - position
	to_target.y = 0.0
	if to_target.length() <= ARRIVE_DIST:
		_wait = _rng.randf_range(PAUSE_MIN, PAUSE_MAX)
		_settle_body()
		return

	var dir := to_target.normalized()
	position += dir * _speed * delta
	rotation.y = lerp_angle(rotation.y, atan2(dir.x, dir.z), clampf(TURN_SPEED * delta, 0.0, 1.0))
	# A small vertical bob while walking, so the legs do not slide.
	_walk_phase = fmod(_walk_phase + delta * BOB_SPEED, TAU)
	if _body and is_instance_valid(_body):
		_body.position.y = _body_base_y + absf(sin(_walk_phase)) * BOB_HEIGHT


func _settle_body() -> void:
	if _body and is_instance_valid(_body):
		_body.position.y = _body_base_y


func _pick_target() -> void:
	var angle := _rng.randf_range(0.0, TAU)
	var dist := _rng.randf_range(0.4, _range)
	_target = _home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
