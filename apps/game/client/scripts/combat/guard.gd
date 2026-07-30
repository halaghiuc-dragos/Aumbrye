extends Node

## Tap-Q guard: parry window (0.18s) -> block phase (0.65s) -> idle.
## Bindings: keyboard Q, gamepad LT. See docs/design/M1_CONTROLS.md (do not rebind without user request).

const BLOCK_STAMINA_DRAIN_PER_HIT := 18.0
const BLOCK_DAMAGE_REDUCTION := 0.75
const GUARD_BREAK_STAGGER := 0.8
const BLOCK_ARC_DEGREES := 120.0
const PARRY_WINDOW := 0.18
const BLOCK_DURATION := 0.65
const PARRY_STAGGER_ENEMY := 1.2

enum GuardState { IDLE, PARRY_WINDOW, BLOCKING }

signal guard_broken
signal block_state_changed(blocking: bool)
signal parry_success(target: Node)

var is_blocking := false
var guard_broken_state := false
var parry_window_active := false
var is_guard_active := false

var _body: CharacterBody3D
var _stamina: Stamina
var _poise: Poise
var _stagger_timer := 0.0
var _state := GuardState.IDLE
var _state_timer := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_poise = _body.get_node_or_null("Poise") as Poise


func _physics_process(delta: float) -> void:
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		_reset_guard_state()
		return

	match _state:
		GuardState.IDLE:
			is_blocking = false
			parry_window_active = false
			is_guard_active = false
			if Input.is_action_just_pressed("block") and not guard_broken_state:
				_begin_guard_sequence()
		GuardState.PARRY_WINDOW:
			_state_timer -= delta
			parry_window_active = true
			is_blocking = false
			is_guard_active = true
			if _state_timer <= 0.0:
				_enter_block_phase()
		GuardState.BLOCKING:
			_state_timer -= delta
			parry_window_active = false
			is_blocking = true
			is_guard_active = true
			if _state_timer <= 0.0:
				_end_guard_sequence()


func _begin_guard_sequence() -> void:
	_state = GuardState.PARRY_WINDOW
	_state_timer = PARRY_WINDOW
	is_guard_active = true
	block_state_changed.emit(true)


func _enter_block_phase() -> void:
	_state = GuardState.BLOCKING
	_state_timer = BLOCK_DURATION
	is_blocking = true
	parry_window_active = false


func _end_guard_sequence() -> void:
	_reset_guard_state()
	block_state_changed.emit(false)


func _reset_guard_state() -> void:
	_state = GuardState.IDLE
	_state_timer = 0.0
	is_blocking = false
	parry_window_active = false
	is_guard_active = false


func modify_incoming_hit(info: DamageInfo) -> Dictionary:
	if _stagger_timer > 0.0 or not is_blocking:
		return {"amount": info.amount, "poise": info.poise_damage}
	if not _is_frontal_hit(info.direction):
		return {"amount": info.amount, "poise": info.poise_damage}
	if not _stamina.consume(BLOCK_STAMINA_DRAIN_PER_HIT):
		_trigger_guard_break()
		return {"amount": info.amount, "poise": info.poise_damage, "blocked": false}
	return {
		"amount": info.amount * (1.0 - BLOCK_DAMAGE_REDUCTION),
		"poise": info.poise_damage * 0.5,
		"blocked": true,
	}


func try_parry_attack(attacker: Node) -> bool:
	if _state != GuardState.PARRY_WINDOW:
		return false
	parry_success.emit(attacker)
	_end_guard_sequence()
	block_state_changed.emit(false)
	return true


func get_parry_stagger_duration() -> float:
	return PARRY_STAGGER_ENEMY


func locks_movement() -> bool:
	return _stagger_timer > 0.0


func get_parry_time_remaining() -> float:
	if _state == GuardState.PARRY_WINDOW:
		return maxf(0.0, _state_timer)
	return 0.0


func get_block_time_remaining() -> float:
	if _state == GuardState.BLOCKING:
		return maxf(0.0, _state_timer)
	return 0.0


func _get_block_facing() -> Vector3:
	if _body.has_method("get_facing_direction"):
		return _body.call("get_facing_direction")
	return -_body.global_transform.basis.z


func _is_frontal_hit(direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return true
	var facing := _get_block_facing()
	var angle := rad_to_deg(facing.angle_to(-direction.normalized()))
	return angle <= BLOCK_ARC_DEGREES * 0.5


func _trigger_guard_break() -> void:
	guard_broken_state = true
	_reset_guard_state()
	_stagger_timer = GUARD_BREAK_STAGGER
	if _poise:
		_poise.take_poise_damage(_poise.MAX_POISE)
	guard_broken.emit()
	block_state_changed.emit(false)
	await get_tree().create_timer(GUARD_BREAK_STAGGER).timeout
	guard_broken_state = false
