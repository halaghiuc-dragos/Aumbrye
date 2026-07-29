extends Node

const PARRY_WINDOW := 0.18
const PARRY_RECOVERY := 0.45
const PARRY_STAGGER_ENEMY := 1.2

signal parry_success(target: Node)
signal parry_failed

var is_parrying := false
var parry_window_active := false

var _body: CharacterBody3D
var _window_timer := 0.0
var _recovery_timer := 0.0
var _stamina: Stamina


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina


func _physics_process(delta: float) -> void:
	if _recovery_timer > 0.0:
		_recovery_timer -= delta
		return
	if _window_timer > 0.0:
		_window_timer -= delta
		parry_window_active = true
		if _window_timer <= 0.0:
			parry_window_active = false
			_start_recovery(true)
	if Input.is_action_just_pressed("parry") and _can_parry():
		_open_parry_window()


func _can_parry() -> bool:
	return _window_timer <= 0.0 and _recovery_timer <= 0.0


func _open_parry_window() -> void:
	is_parrying = true
	_window_timer = PARRY_WINDOW
	parry_window_active = true


func try_parry_attack(attacker: Node) -> bool:
	if not parry_window_active:
		return false
	_window_timer = 0.0
	parry_window_active = false
	is_parrying = false
	parry_success.emit(attacker)
	_start_recovery(false)
	return true


func _start_recovery(failed: bool) -> void:
	is_parrying = false
	parry_window_active = false
	_recovery_timer = PARRY_RECOVERY
	if failed:
		parry_failed.emit()


func get_parry_stagger_duration() -> float:
	return PARRY_STAGGER_ENEMY
