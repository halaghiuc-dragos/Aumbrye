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

var current: float = MAX_STAMINA
var max_stamina: float = MAX_STAMINA
var _regen_timer := 0.0
var _regen_multiplier := 1.0
var _exhausted := false
var _regen_state := RegenState.NORMAL


func _ready() -> void:
	stamina_changed.emit(current, max_stamina)


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


func _process(delta: float) -> void:
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
		insufficient.emit()
		return false
	if current < amount:
		insufficient.emit()
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
		insufficient.emit()
		return false
	if current < amount:
		insufficient.emit()
		return false
	current -= amount
	_regen_timer = REGEN_DELAY
	stamina_changed.emit(current, max_stamina)
	if current <= 0.0:
		_exhausted = true
		depleted.emit()
	return true


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
