extends Node
class_name Guard

## Hold-to-block guard with a parry window at the start of each guard.
## Bindings: keyboard Q, gamepad LT (DEC-G10 — do not rebind without user request).

const CombatStatModifiersScript := preload("res://scripts/combat/combat_stat_modifiers.gd")

const BLOCK_STAMINA_PER_POISE := 0.55
const BLOCK_DAMAGE_REDUCTION := 0.55
const BLOCK_POISE_TRANSFER := 0.35
const GUARD_BREAK_STAGGER := 0.8
const BLOCK_ARC_DEGREES := 120.0
const PARRY_WINDOW := 0.18
const PARRY_STAMINA_COST := 10.0
const PARRY_COOLDOWN := 0.4
const BLOCK_DISPLAY_MAX := 9.99
const PARRY_STAGGER_ENEMY := 1.2
const RIPOSTE_WINDOW := 1.4
const RIPOSTE_DAMAGE_MULT := 2.0
const DEFAULT_ELEMENTAL_REDUCTION := 0.35
const DEFAULT_GUARD_BREAK_POISE := 0.0

enum GuardState { IDLE, GUARDING, GUARD_BROKEN }

signal guard_broken
signal block_state_changed(blocking: bool)
signal parry_success(target: Node)
signal riposte_ready

var is_blocking := false
var guard_broken_state := false
var parry_window_active := false
var is_guard_active := false
var riposte_active := false
var parried_target: Node = null

var _body: CharacterBody3D
var _stamina: Stamina
var _poise: Poise
var _weapon: WeaponController
var _stagger_timer := 0.0
var _state := GuardState.IDLE
var _parry_timer := 0.0
var _riposte_timer := 0.0
var _block_reduction_bonus := 0.0
var _block_reduction_by_type: Dictionary = {}
var _guard_break_poise := DEFAULT_GUARD_BREAK_POISE
var _block_stability := 1.0
var _last_block_cost := 0.0
var _parry_cooldown_timer := 0.0


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	_stamina = _body.get_node_or_null("Stamina") as Stamina
	_poise = _body.get_node_or_null("Poise") as Poise
	_weapon = _body.get_node_or_null("WeaponController") as WeaponController


func _physics_process(delta: float) -> void:
	if _parry_cooldown_timer > 0.0:
		_parry_cooldown_timer -= delta
	if _stagger_timer > 0.0:
		_stagger_timer -= delta
		if _stagger_timer <= 0.0:
			guard_broken_state = false
		_reset_guard_state()
		return

	if _riposte_timer > 0.0:
		_riposte_timer -= delta
		if _riposte_timer <= 0.0:
			riposte_active = false
			parried_target = null
	if parried_target != null and not is_instance_valid(parried_target):
		riposte_active = false
		parried_target = null

	match _state:
		GuardState.IDLE:
			is_blocking = false
			parry_window_active = false
			is_guard_active = false
			if (
				PlayerInput.just_pressed(&"block")
				and not guard_broken_state
				and _parry_cooldown_timer <= 0.0
				and (_weapon == null or _weapon.allows_cancel_into("guard"))
			):
				_enter_guard()
		GuardState.GUARDING:
			_parry_timer -= delta
			parry_window_active = _parry_timer > 0.0
			is_blocking = true
			is_guard_active = true
			if not PlayerInput.pressed(&"block"):
				_end_guard()
		GuardState.GUARD_BROKEN:
			_reset_guard_state()


func _enter_guard() -> void:
	_state = GuardState.GUARDING
	_parry_timer = PARRY_WINDOW
	_parry_cooldown_timer = PARRY_COOLDOWN
	is_guard_active = true
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.BLOCKING)
		_stamina.consume(PARRY_STAMINA_COST)
	block_state_changed.emit(true)


func _end_guard() -> void:
	if _stamina:
		_stamina.set_regen_state(Stamina.RegenState.NORMAL)
	_reset_guard_state()
	block_state_changed.emit(false)


func _reset_guard_state() -> void:
	_state = GuardState.IDLE
	_parry_timer = 0.0
	is_blocking = false
	parry_window_active = false
	is_guard_active = false


func set_combat_stat_modifiers(
	equipment_stats: Dictionary, talent_stats: Dictionary, block_data: Dictionary = {}
) -> void:
	_block_reduction_bonus = (
		CombatStatModifiersScript.block_reduction_bonus(talent_stats)
		+ float(equipment_stats.get("blockReduction", 0.0))
	)
	_block_stability = maxf(
		0.1, float(block_data.get("stability", 1.0)) + ClassPerks.bulwark_stability_bonus(_body)
	)
	_guard_break_poise = maxf(0.0, float(block_data.get("guardBreakPoise", DEFAULT_GUARD_BREAK_POISE)))
	_block_reduction_by_type = _parse_block_reduction(block_data.get("reduction"))


func _parse_block_reduction(value: Variant) -> Dictionary:
	var table: Dictionary = {}
	if value is Dictionary:
		for damage_type in DamageInfo.ALL_TYPES:
			if (value as Dictionary).has(damage_type):
				table[damage_type] = clampf(float((value as Dictionary)[damage_type]), 0.0, 0.95)
	elif value != null:
		var flat := clampf(float(value), 0.0, 0.95)
		for damage_type in DamageInfo.ALL_TYPES:
			table[damage_type] = flat
	return table


func _reduction_for(damage_type: String) -> float:
	if _block_reduction_by_type.has(damage_type):
		return float(_block_reduction_by_type[damage_type])
	if damage_type == DamageInfo.TYPE_PHYSICAL:
		return BLOCK_DAMAGE_REDUCTION
	return DEFAULT_ELEMENTAL_REDUCTION


func modify_incoming_hit(info: DamageInfo, arc: DamageInfo.HitArc = DamageInfo.HitArc.FRONT) -> Dictionary:
	if _stagger_timer > 0.0 or not is_guard_active:
		return {"amount": info.amount, "poise": info.poise_damage}
	if arc != DamageInfo.HitArc.FRONT:
		return {"amount": info.amount, "poise": info.poise_damage}
	if _guard_break_poise > 0.0 and info.poise_damage >= _guard_break_poise * _block_stability:
		_trigger_guard_break()
		return {"amount": info.amount, "poise": info.poise_damage, "blocked": false}
	var stamina_cost := info.poise_damage * BLOCK_STAMINA_PER_POISE / _block_stability
	_last_block_cost = stamina_cost
	if _stamina == null or not _stamina.consume(stamina_cost):
		_trigger_guard_break()
		return {"amount": info.amount, "poise": info.poise_damage, "blocked": false}
	var reduction := clampf(_reduction_for(info.damage_type) + _block_reduction_bonus, 0.0, 0.95)
	var poise_mult := BLOCK_POISE_TRANSFER / _block_stability
	if _body and CombatEvents:
		CombatEvents.dispatch(
			CombatEvents.ON_BLOCK,
			{
				"actor": _body,
				"target": info.source,
				"amount": info.amount * (1.0 - reduction),
				"damageType": info.damage_type,
			}
		)
	return {
		"amount": info.amount * (1.0 - reduction),
		"poise": info.poise_damage * poise_mult,
		"blocked": true,
	}


func try_parry_attack(attacker: Node) -> bool:
	if _state != GuardState.GUARDING or not parry_window_active:
		return false
	if _stamina and _stamina.is_exhausted():
		return false
	_stagger_attacker(attacker)
	parry_success.emit(attacker)
	riposte_active = true
	parried_target = attacker
	_riposte_timer = RIPOSTE_WINDOW
	riposte_ready.emit()
	if _body and CombatEvents:
		CombatEvents.dispatch(CombatEvents.ON_PARRY, {"actor": _body, "target": attacker})
	if _body:
		var anchor: Array = VfxService.resolve_combat_anchor(_body)
		VfxService.play_parry(anchor[0], anchor[1])
		VfxService.play_impact_decal(anchor[0], anchor[1])
	_end_guard()
	block_state_changed.emit(false)
	return true


func _stagger_attacker(attacker: Node) -> void:
	var target: Node = attacker
	if target and not target.has_method("apply_stagger"):
		if target.get_parent() and target.get_parent().has_method("apply_stagger"):
			target = target.get_parent()
	if target and target.has_method("apply_stagger"):
		target.call("apply_stagger", PARRY_STAGGER_ENEMY)
	if target and target.has_method("cancel_attack"):
		target.call("cancel_attack")
	elif attacker and attacker.has_method("disable"):
		attacker.call("disable")


func get_riposte_damage_multiplier() -> float:
	return RIPOSTE_DAMAGE_MULT if riposte_active else 1.0


func consume_riposte() -> void:
	riposte_active = false
	parried_target = null
	_riposte_timer = 0.0


func is_riposte_target(node: Node) -> bool:
	return riposte_active and node != null and node == parried_target


func get_parry_stagger_duration() -> float:
	return PARRY_STAGGER_ENEMY


func locks_movement() -> bool:
	return _stagger_timer > 0.0


func reset_after_revive() -> void:
	guard_broken_state = false
	_stagger_timer = 0.0
	_state = GuardState.IDLE
	riposte_active = false
	parried_target = null
	_riposte_timer = 0.0
	_reset_guard_state()


func get_parry_window_duration() -> float:
	return PARRY_WINDOW


func get_block_window_duration() -> float:
	return BLOCK_DISPLAY_MAX


func get_parry_time_remaining() -> float:
	if _state == GuardState.GUARDING and parry_window_active:
		return maxf(0.0, _parry_timer)
	return 0.0


func get_block_time_remaining() -> float:
	if _state != GuardState.GUARDING or _stamina == null:
		return 0.0
	if _last_block_cost <= 0.0:
		return 9.99
	return clampf(_stamina.current / _last_block_cost, 0.0, 9.99)


func _get_block_facing() -> Vector3:
	if _body.has_method("get_facing_direction"):
		return _body.call("get_facing_direction")
	return CombatFacing.forward_of(_body)


func _is_frontal_hit(direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return true
	var facing := _get_block_facing()
	var angle := rad_to_deg(facing.angle_to(-direction.normalized()))
	return angle <= BLOCK_ARC_DEGREES * 0.5


func _trigger_guard_break() -> void:
	guard_broken_state = true
	_state = GuardState.GUARD_BROKEN
	_reset_guard_state()
	_stagger_timer = GUARD_BREAK_STAGGER
	if _poise:
		_poise.take_poise_damage(_poise.max_poise)
	guard_broken.emit()
	block_state_changed.emit(false)
