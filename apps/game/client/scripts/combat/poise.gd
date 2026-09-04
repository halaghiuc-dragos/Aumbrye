extends Node
class_name Poise

signal poise_changed(current: float, max_value: float)
signal poise_broken
signal poise_damaged(amount: float, remaining: float)

const MAX_POISE := 50.0
const REGEN_RATE := 20.0
const REGEN_DELAY := 2.0
const REGEN_REFILL_TIME := 1.0

var max_poise: float = MAX_POISE
var current: float = MAX_POISE
var _broken := false
var _regen_timer := 0.0
var _break_timer := 0.0
var break_duration := 1.2
## CB-04: true for exactly one execution per break -- without it a fast weapon (a dagger's 4-hit
## chain) could execute the same stagger repeatedly before it ends.
var execution_available := false


func _ready() -> void:
	set_process(false)
	set_physics_process(true)
	poise_changed.emit(current, max_poise)


func configure(
	max_value: float, stagger_duration: float = 1.2, preserve_ratio: bool = false
) -> void:
	var old_max := max_poise
	max_poise = max_value
	if preserve_ratio and old_max > 0.0:
		current = clampf((current / old_max) * max_poise, 0.0, max_poise)
	else:
		current = max_value
		_broken = false
		_break_timer = 0.0
	if not preserve_ratio:
		_regen_timer = 0.0
	break_duration = maxf(0.1, stagger_duration)
	poise_changed.emit(current, max_poise)


func _physics_process(delta: float) -> void:
	if _broken:
		_break_timer -= delta
		if _break_timer <= 0.0:
			_broken = false
			execution_available = false
			current = max_poise
			poise_changed.emit(current, max_poise)
		return
	if _regen_timer > 0.0:
		_regen_timer -= delta
	if current >= max_poise:
		return
	if _regen_timer > 0.0:
		return
	var regen_rate := REGEN_RATE * ClassPerks.steadfast_poise_regen_multiplier(get_parent())
	current = minf(max_poise, current + regen_rate * delta)
	poise_changed.emit(current, max_poise)


func is_broken() -> bool:
	return _broken


func take_poise_damage(amount: float) -> void:
	if _broken:
		return
	current = maxf(0.0, current - amount)
	_regen_timer = REGEN_DELAY
	poise_damaged.emit(amount, current)
	poise_changed.emit(current, max_poise)
	if current <= 0.0:
		_broken = true
		_break_timer = break_duration
		execution_available = true
		poise_broken.emit()


func reset_poise() -> void:
	_broken = false
	_break_timer = 0.0
	execution_available = false
	current = max_poise
	_regen_timer = 0.0
	poise_changed.emit(current, max_poise)
