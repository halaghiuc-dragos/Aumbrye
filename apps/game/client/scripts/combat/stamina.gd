extends Node
class_name Stamina

signal stamina_changed(current: float, max_value: float)
signal depleted
signal insufficient

enum RegenState { NORMAL, BLOCKING, SUPPRESSED }

const MAX_STAMINA := 100.0
const REGEN_DELAY := 0.7
const REGEN_RATE := 25.0
const REGEN_RATE_BLOCKING := 6.0
const REGEN_RATE_EXHAUSTED := 12.0
const EXHAUSTION_RECOVERY := 15.0
const INSUFFICIENT_EMIT_COOLDOWN := 0.4

var current: float = MAX_STAMINA
var max_stamina: float = MAX_STAMINA
var _regen_timer := 0.0
var _regen_multiplier := 1.0
var _exhausted := false
var _regen_state := RegenState.NORMAL
var _insufficient_cooldown := 0.0


func _ready() -> void:
	set_process(false)
	stamina_changed.emit(current, max_stamina)


func _emit_insufficient() -> void:
	if _insufficient_cooldown > 0.0:
		return
	_insufficient_cooldown = INSUFFICIENT_EMIT_COOLDOWN
	insufficient.emit()


func configure(
	max_value: float, regen_multiplier: float = 1.0, preserve_ratio: bool = false
) -> void:
	var old_max := max_stamina
	max_stamina = maxf(1.0, max_value)
	_regen_multiplier = maxf(0.1, regen_multiplier)
	if preserve_ratio and old_max > 0.0:
		current = (current / old_max) * max_stamina
	else:
		current = minf(current, max_stamina)
	_exhausted = false
	_regen_timer = 0.0
	stamina_changed.emit(current, max_stamina)


func set_regen_state(state: RegenState) -> void:
	_regen_state = state


func get_speed_multiplier() -> float:
	if _exhausted:
		return 0.75
	return 1.0


func _physics_process(delta: float) -> void:
	if _insufficient_cooldown > 0.0:
		_insufficient_cooldown -= delta
	if _exhausted and current >= EXHAUSTION_RECOVERY:
		_exhausted = false
	if _regen_timer > 0.0:
		_regen_timer -= delta
		return
	if _regen_state == RegenState.SUPPRESSED:
		return
	if current < max_stamina:
		var rate := REGEN_RATE * _regen_multiplier
		if _exhausted:
			rate = REGEN_RATE_EXHAUSTED
		elif _regen_state == RegenState.BLOCKING:
			rate = REGEN_RATE_BLOCKING
		current = minf(max_stamina, current + rate * delta)
		stamina_changed.emit(current, max_stamina)


func consume(amount: float) -> bool:
	if _exhausted:
		_emit_insufficient()
		return false
	if current < amount:
		_emit_insufficient()
		return false
	current -= amount
	_regen_timer = REGEN_DELAY
	stamina_changed.emit(current, max_stamina)
	if current <= 0.0:
		_exhausted = true
		depleted.emit()
	return true


func drain(amount: float) -> bool:
	if _exhausted:
		return false
	if current <= 0.0:
		_exhausted = true
		depleted.emit()
		return false
	current = maxf(0.0, current - amount)
	_regen_timer = REGEN_DELAY
	stamina_changed.emit(current, max_stamina)
	if current <= 0.0:
		_exhausted = true
		depleted.emit()
		return false
	return true


func restore(amount: float) -> void:
	if amount <= 0.0:
		return
	current = minf(max_stamina, current + amount)
	if current > 0.0:
		_exhausted = false
	stamina_changed.emit(current, max_stamina)


func has(amount: float) -> bool:
	if _exhausted:
		return false
	return current >= amount


func is_exhausted() -> bool:
	return _exhausted


func reset_stamina() -> void:
	current = max_stamina
	_exhausted = false
	_regen_timer = 0.0
	_regen_state = RegenState.NORMAL
	stamina_changed.emit(current, max_stamina)
