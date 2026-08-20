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
	# See Stamina._ready: regen is a physics-tick system; set_process(false) disabled a callback
	# this class never implemented.
	set_process(false)
	set_physics_process(true)
	mana_changed.emit(current, max_mana)


## C-49: `Mana` was the one resource that never received the BUG-13 `preserve_ratio` parameter that
## `Health`, `Poise` and `Stamina` all carry, so the hardening against the equipment path — which
## fires on every inventory change — skipped it, and moving an item zeroed the 0.7 s mana delay.
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


func _physics_process(delta: float) -> void:
	if _regen_timer > 0.0:
		_regen_timer -= delta
		return
	if current < max_mana:
		current = minf(max_mana, current + REGEN_RATE * _regen_multiplier * delta)
		mana_changed.emit(current, max_mana)


func restore(amount: float) -> void:
	if amount <= 0.0 or current >= max_mana:
		return
	current = minf(max_mana, current + amount)
	mana_changed.emit(current, max_mana)


## C-57: `consume` and `drain` were byte-identical apart from the `insufficient` emit — two methods
## where one with a flag does. (`Stamina`'s pair was also flagged, but those two genuinely differ:
## `drain` clamps to zero and spends what is there, `consume` is all-or-nothing. Left alone.)
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
	mana_changed.emit(current, max_mana)
