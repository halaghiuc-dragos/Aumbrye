extends Node

const BLOCK_STAMINA_DRAIN_PER_HIT := 12.0
const BLOCK_DAMAGE_REDUCTION := 0.75
const GUARD_BREAK_STAGGER := 0.8
const BLOCK_ARC_DEGREES := 120.0

signal guard_broken
signal block_state_changed(blocking: bool)

var is_blocking := false
var guard_broken_state := false

var _body: CharacterBody3D
var _stamina: Stamina
var _poise: Poise
var _stagger_timer := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_poise = _body.get_node_or_null("Poise") as Poise


func _physics_process(delta: float) -> void:
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		return
	is_blocking = Input.is_action_pressed("block") and not guard_broken_state
	block_state_changed.emit(is_blocking)


func modify_incoming_hit(info: DamageInfo) -> Dictionary:
	if _stagger_timer > 0.0 or not is_blocking:
		return {"amount": info.amount, "poise": info.poise_damage}
	if not _is_frontal_hit(info.direction):
		return {"amount": info.amount, "poise": info.poise_damage}
	if not _stamina.consume(BLOCK_STAMINA_DRAIN_PER_HIT):
		_trigger_guard_break()
		return {"amount": info.amount, "poise": info.poise_damage}
	return {
		"amount": info.amount * (1.0 - BLOCK_DAMAGE_REDUCTION),
		"poise": info.poise_damage * 0.5,
	}


func _is_frontal_hit(direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return true
	var facing := -_body.global_transform.basis.z
	var angle := rad_to_deg(facing.angle_to(-direction.normalized()))
	return angle <= BLOCK_ARC_DEGREES * 0.5


func _trigger_guard_break() -> void:
	guard_broken_state = true
	is_blocking = false
	_stagger_timer = GUARD_BREAK_STAGGER
	if _poise:
		_poise.take_poise_damage(_poise.MAX_POISE)
	guard_broken.emit()
	await get_tree().create_timer(GUARD_BREAK_STAGGER).timeout
	guard_broken_state = false
