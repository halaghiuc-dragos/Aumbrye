extends Node
class_name Mana

signal mana_changed(current: float, max_value: float)
signal depleted
signal insufficient

const MAX_MANA := 100.0
const REGEN_DELAY := 0.7
const REGEN_RATE := 20.0

var current: float = MAX_MANA
var max_mana: float = MAX_MANA
var _regen_timer := 0.0
var _regen_multiplier := 1.0


func _ready() -> void:
	mana_changed.emit(current, max_mana)


func configure(max_value: float, regen_multiplier: float = 1.0) -> void:
	max_mana = maxf(1.0, max_value)
	current = minf(current, max_mana)
	_regen_multiplier = maxf(0.1, regen_multiplier)
	_regen_timer = 0.0
	mana_changed.emit(current, max_mana)


func _process(delta: float) -> void:
	if _regen_timer > 0.0:
		_regen_timer -= delta
		return
	if current < max_mana:
		current = minf(max_mana, current + REGEN_RATE * _regen_multiplier * delta)
		mana_changed.emit(current, max_mana)


func consume(amount: float) -> bool:
	if current < amount:
		insufficient.emit()
		return false
	current -= amount
	_regen_timer = REGEN_DELAY
	mana_changed.emit(current, max_mana)
	if current <= 0.0:
		depleted.emit()
	return true


func drain(amount: float) -> bool:
	if current < amount:
		return false
	current -= amount
	_regen_timer = REGEN_DELAY
	mana_changed.emit(current, max_mana)
	if current <= 0.0:
		depleted.emit()
	return true


func has(amount: float) -> bool:
	return current >= amount


func reset_mana() -> void:
	current = max_mana
	_regen_timer = 0.0
	mana_changed.emit(current, max_mana)
