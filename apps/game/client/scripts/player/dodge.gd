extends Node

const JUMP_VELOCITY := 4.8
const COYOTE_TIME := 0.12
const JUMP_BUFFER_TIME := 0.15
const DODGE_SPEED := 9.0
const DODGE_DURATION := 0.45
const DODGE_RECOVERY := 0.35
const DODGE_STAMINA_COST := 22.0
const IFRAME_START := 0.05
const IFRAME_END := 0.30

signal dodge_started
signal dodge_ended
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
var _was_on_floor := false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina


func _physics_process(delta: float) -> void:
	_update_timers(delta)
	_handle_jump_buffer()
	if _recovery_timer > 0.0:
		_recovery_timer -= delta


func process_dodge_physics(delta: float) -> void:
	if is_dodging:
		_process_dodge(delta)
		return
	if Input.is_action_just_pressed("dodge") and _can_dodge():
		_start_dodge()


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
		_body.velocity.y = JUMP_VELOCITY
		_jump_buffer_timer = 0.0
		_coyote_timer = 0.0


func _can_dodge() -> bool:
	if is_dodging or _recovery_timer > 0.0:
		return false
	if _stamina and not _stamina.has(DODGE_STAMINA_COST):
		return false
	return true


func _start_dodge() -> void:
	if not _stamina.consume(DODGE_STAMINA_COST):
		return
	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	if input_dir.length_squared() < 0.01:
		_dodge_direction = -_body.global_transform.basis.z
	else:
		var yaw := _body.rotation.y
		var basis := Basis(Vector3.UP, yaw)
		_dodge_direction = (basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	is_dodging = true
	_dodge_timer = DODGE_DURATION
	dodge_started.emit()


func _process_dodge(delta: float) -> void:
	_dodge_timer -= delta
	_body.velocity.x = _dodge_direction.x * DODGE_SPEED
	_body.velocity.z = _dodge_direction.z * DODGE_SPEED
	var elapsed := DODGE_DURATION - _dodge_timer
	var iframes := elapsed >= IFRAME_START and elapsed <= IFRAME_END
	if iframes != iframes_active:
		iframes_active = iframes
		iframes_changed.emit(iframes_active)
	_body.move_and_slide()
	if _dodge_timer <= 0.0:
		_end_dodge()


func _end_dodge() -> void:
	is_dodging = false
	iframes_active = false
	iframes_changed.emit(false)
	_recovery_timer = DODGE_RECOVERY
	dodge_ended.emit()
