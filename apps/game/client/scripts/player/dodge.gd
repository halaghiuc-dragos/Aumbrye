extends Node

## Dash (Space / gamepad B) and jump (F / gamepad A). Bindings locked per DEC-G07–DEC-G10.

const JUMP_VELOCITY := 4.8
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.15
const DODGE_SPEED := 9.0
const DODGE_BACK_SPEED := 6.0
const DODGE_DURATION := 0.45
const DODGE_RECOVERY := 0.25
const DODGE_STAMINA_COST := 32.0
const JUMP_STAMINA_COST := 18.0
const IFRAME_START := 0.05
const IFRAME_END := 0.30

signal dodge_started
signal dodge_ended
signal dash_started
signal dash_ended
signal iframes_changed(active: bool)

var is_dodging := false
var iframes_active := false

var _body: CharacterBody3D
var _stamina: Stamina
var _coyote_timer := 0.0
var _jump_buffer_timer := 0.0
var _dodge_timer := 0.0
var _recovery_timer := 0.0
var _dodge_direction := Vector3.ZERO
var _dodge_speed := DODGE_SPEED
var _was_on_floor := false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	dash_started.connect(func(): dodge_started.emit())
	dash_ended.connect(func(): dodge_ended.emit())


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_handle_jump_buffer()
	if _recovery_timer > 0.0:
		_recovery_timer -= delta


func process_dash_physics(delta: float) -> void:
	process_dodge_physics(delta)


func process_dodge_physics(delta: float) -> void:
	if is_dodging:
		_process_dash(delta)
		return
	if Input.is_action_just_pressed("dodge") and _can_dash():
		_start_dash()


func get_dash_progress() -> float:
	if not is_dodging:
		return 0.0
	return clampf(1.0 - (_dodge_timer / DODGE_DURATION), 0.0, 1.0)


func get_dash_direction() -> Vector3:
	return _dodge_direction


func locks_movement() -> bool:
	return _recovery_timer > 0.0


func _update_timers(delta: float) -> void:
	if _body and _body.is_on_floor():
		_coyote_timer = COYOTE_TIME
	elif _was_on_floor:
		_coyote_timer = maxf(0.0, _coyote_timer - delta)
	_was_on_floor = _body.is_on_floor() if _body else false

	if Input.is_action_just_pressed("jump"):
		_jump_buffer_timer = JUMP_BUFFER_TIME
	elif _jump_buffer_timer > 0.0:
		_jump_buffer_timer -= delta


func _handle_jump_buffer() -> void:
	if _jump_buffer_timer <= 0.0 or not _body:
		return
	if _coyote_timer > 0.0 and not is_dodging:
		if _stamina and not _stamina.consume(JUMP_STAMINA_COST):
			return
		_body.velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0


func _can_dash() -> bool:
	if is_dodging or _recovery_timer > 0.0:
		return false
	if _stamina and not _stamina.has(DODGE_STAMINA_COST):
		return false
	return true


func _start_dash() -> void:
	if not _stamina.consume(DODGE_STAMINA_COST):
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var lock_on := _body.get_node_or_null("LockOn")
	if LockOnMovement.is_active(lock_on):
		if input_dir.length_squared() > 0.01:
			_dodge_speed = DODGE_SPEED
			_dodge_direction = LockOnMovement.get_move_direction(
				_body, lock_on, input_dir, _get_camera_relative_direction
			)
		else:
			_dodge_speed = DODGE_BACK_SPEED
			_dodge_direction = _get_attack_backstep_direction()
	elif input_dir.length_squared() > 0.01:
		_dodge_speed = DODGE_SPEED
		_dodge_direction = _get_camera_relative_direction(input_dir)
	else:
		_dodge_speed = DODGE_BACK_SPEED
		_dodge_direction = _get_attack_backstep_direction()
	if _dodge_direction.length_squared() < 0.01:
		_dodge_direction = _get_attack_backstep_direction()
	is_dodging = true
	_dodge_timer = DODGE_DURATION
	dash_started.emit()
	dodge_started.emit()


func _get_attack_backstep_direction() -> Vector3:
	var facing := _body.get_node_or_null("Facing") as Node3D
	if facing:
		var back := -facing.global_transform.basis.z
		back.y = 0.0
		if back.length_squared() > 0.01:
			return back.normalized()
	var fallback := _get_facing_forward()
	fallback.y = 0.0
	if fallback.length_squared() > 0.01:
		return fallback.normalized()
	return Vector3.BACK


func _get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	if _body.has_method("get_camera_relative_direction"):
		return _body.call("get_camera_relative_direction", input_dir)
	return Vector3.ZERO


func _get_facing_forward() -> Vector3:
	if _body.has_method("get_facing_direction"):
		return _body.call("get_facing_direction")
	return -_body.global_transform.basis.z


func _process_dash(delta: float) -> void:
	_dodge_timer -= delta
	_body.velocity.x = _dodge_direction.x * _dodge_speed
	_body.velocity.z = _dodge_direction.z * _dodge_speed
	var elapsed := DODGE_DURATION - _dodge_timer
	var iframes := elapsed >= IFRAME_START and elapsed <= IFRAME_END
	if iframes != iframes_active:
		iframes_active = iframes
		iframes_changed.emit(iframes_active)
	_body.move_and_slide()
	if _dodge_timer <= 0.0:
		_end_dash()


func _end_dash() -> void:
	is_dodging = false
	iframes_active = false
	iframes_changed.emit(false)
	_recovery_timer = DODGE_RECOVERY
	_dodge_speed = DODGE_SPEED
	dash_ended.emit()
	dodge_ended.emit()
