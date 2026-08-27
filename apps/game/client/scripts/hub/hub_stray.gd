extends Node3D


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
var _player_near := false
var _rng := RandomNumberGenerator.new()
var _voice := &"stray_meow"
var _voice_timer := 0.0


const VOICE_MIN := 9.0
const VOICE_MAX := 26.0
const VOICE_NEAR_SCALE := 0.35


func set_voice(key: StringName) -> void:
	_voice = key


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
	_voice_timer = _rng.randf_range(VOICE_MIN, VOICE_MAX)
	set_process(true)


func set_player_near(value: bool) -> void:
	if value and not _player_near:
		_voice_timer = minf(_voice_timer, 0.6)
	_player_near = value


func _process(delta: float) -> void:
	_advance_voice(delta)
	if _tail and is_instance_valid(_tail):
		_tail.rotation.x = sin(Time.get_ticks_msec() * 0.001 * TAIL_SPEED) * TAIL_ANGLE

	if _player_near:
		_settle_body()
		return

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
	_walk_phase = fmod(_walk_phase + delta * BOB_SPEED, TAU)
	if _body and is_instance_valid(_body):
		_body.position.y = _body_base_y + absf(sin(_walk_phase)) * BOB_HEIGHT


func _advance_voice(delta: float) -> void:
	_voice_timer -= delta * (1.0 / VOICE_NEAR_SCALE if _player_near else 1.0)
	if _voice_timer > 0.0:
		return
	_voice_timer = _rng.randf_range(VOICE_MIN, VOICE_MAX)
	AudioDirector.play_sfx(str(_voice), global_position)


func _settle_body() -> void:
	if _body and is_instance_valid(_body):
		_body.position.y = _body_base_y


const TARGET_TRIES := 6
const CLEARANCE_Y := 0.5


func _pick_target() -> void:
	for i in TARGET_TRIES:
		var angle := _rng.randf_range(0.0, TAU)
		var dist := _rng.randf_range(0.4, _range)
		var candidate := _home + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		if _path_is_clear(candidate):
			_target = candidate
			return
	_target = _home


func _path_is_clear(candidate: Vector3) -> bool:
	var world := get_world_3d()
	if world == null:
		return true
	var lift := Vector3(0.0, CLEARANCE_Y, 0.0)
	var query := PhysicsRayQueryParameters3D.create(position + lift, candidate + lift)
	query.collide_with_areas = false
	return world.direct_space_state.intersect_ray(query).is_empty()
