extends Node
class_name Poise

signal poise_changed(current: float, max_value: float)
signal poise_broken

const MAX_POISE := 50.0
const REGEN_RATE := 20.0
const REGEN_DELAY := 2.0

var max_poise: float = MAX_POISE
var current: float = MAX_POISE
var _broken := false
var _regen_timer := 0.0


func _ready() -> void:
	poise_changed.emit(current, max_poise)


func configure(max_value: float) -> void:
	max_poise = max_value
	current = max_value
	_broken = false
	poise_changed.emit(current, max_poise)


func _process(delta: float) -> void:
	if _broken or _regen_timer > 0.0:
		_regen_timer -= delta
		return
	if current < max_poise:
		current = minf(max_poise, current + REGEN_RATE * delta)
		poise_changed.emit(current, max_poise)


func is_broken() -> bool:
	return _broken


func take_poise_damage(amount: float) -> void:
	if _broken:
		return
	current = maxf(0.0, current - amount)
	_regen_timer = REGEN_DELAY
	poise_changed.emit(current, max_poise)
	if current <= 0.0:
		_broken = true
		poise_broken.emit()


func reset_poise() -> void:
	_broken = false
	current = max_poise
	_regen_timer = 0.0
	poise_changed.emit(current, max_poise)
