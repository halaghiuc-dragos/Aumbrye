extends Node
class_name Mana

signal mana_changed(current: float, max_value: float)
signal depleted
signal insufficient

## CB-07: mirrors `Stamina.RegenState` exactly so callers look the same -- `BLOCKING` slows regen
## rather than stopping it, the way holding a shield slows stamina recovery without halting it.
enum RegenState { NORMAL, BLOCKING, SUPPRESSED }

const MAX_MANA := 100.0
const REGEN_DELAY := 0.7
const REGEN_RATE := 20.0
const REGEN_RATE_BLOCKING := 6.0

var current: float = MAX_MANA
var max_mana: float = MAX_MANA
var _regen_timer := 0.0
var _regen_multiplier := 1.0
var _regen_state := RegenState.NORMAL


func _ready() -> void:
	set_process(false)
	set_physics_process(true)
	mana_changed.emit(current, max_mana)


func configure(
	max_value: float, regen_multiplier: float = 1.0, preserve_ratio: bool = false
) -> void:
	var old_max := max_mana
	max_mana = maxf(1.0, max_value)
	if preserve_ratio and old_max > 0.0:
		current = clampf((current / old_max) * max_mana, 0.0, max_mana)
	else:
		current = minf(current, max_mana)
	_regen_multiplier = maxf(0.1, regen_multiplier)
	if not preserve_ratio:
		_regen_timer = 0.0
	mana_changed.emit(current, max_mana)


func set_regen_state(state: RegenState) -> void:
	_regen_state = state


func _physics_process(delta: float) -> void:
	if _regen_timer > 0.0:
		_regen_timer -= delta
		return
	if _regen_state == RegenState.SUPPRESSED:
		return
	if current < max_mana:
		var rate := REGEN_RATE * _regen_multiplier
		if _regen_state == RegenState.BLOCKING:
			rate = REGEN_RATE_BLOCKING
		current = minf(max_mana, current + rate * delta)
		mana_changed.emit(current, max_mana)


func restore(amount: float) -> void:
	if amount <= 0.0 or current >= max_mana:
		return
	current = minf(max_mana, current + amount)
	mana_changed.emit(current, max_mana)


func consume(amount: float, notify_insufficient: bool = true) -> bool:
	if current < amount:
		if notify_insufficient:
			insufficient.emit()
		return false
	current -= amount
	_regen_timer = REGEN_DELAY
	mana_changed.emit(current, max_mana)
	if current <= 0.0:
		depleted.emit()
	return true


func drain(amount: float) -> bool:
	return consume(amount, false)


func has(amount: float) -> bool:
	return current >= amount


func reset_mana() -> void:
	current = max_mana
	_regen_timer = 0.0
	_regen_state = RegenState.NORMAL
	mana_changed.emit(current, max_mana)
