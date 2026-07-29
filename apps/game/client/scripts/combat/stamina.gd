extends Node
class_name Stamina

signal stamina_changed(current: float, max_value: float)
signal depleted
signal insufficient

const MAX_STAMINA := 100.0
const REGEN_DELAY := 1.0
const REGEN_RATE := 25.0

var current: float = MAX_STAMINA
var _regen_timer := 0.0


func _ready() -> void:
	stamina_changed.emit(current, MAX_STAMINA)


func _process(delta: float) -> void:
	if _regen_timer > 0.0:
		_regen_timer -= delta
		return
	if current < MAX_STAMINA:
		current = minf(MAX_STAMINA, current + REGEN_RATE * delta)
		stamina_changed.emit(current, MAX_STAMINA)


func consume(amount: float) -> bool:
	if current < amount:
		insufficient.emit()
		return false
	current -= amount
	_regen_timer = REGEN_DELAY
	stamina_changed.emit(current, MAX_STAMINA)
	if current <= 0.0:
		depleted.emit()
	return true


func has(amount: float) -> bool:
	return current >= amount


func reset_stamina() -> void:
	current = MAX_STAMINA
	_regen_timer = 0.0
	stamina_changed.emit(current, MAX_STAMINA)
