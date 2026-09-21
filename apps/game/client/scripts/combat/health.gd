extends Node
class_name Health

signal health_changed(current: float, max_value: float)
signal died
## CB-06: `grant_barrier` rules effect -- a temporary absorb shield tracked here rather than as a
## status, since it needs to intercept `take_damage` before health itself is touched.
signal barrier_changed(current: float)

const MAX_HEALTH := 100.0

var max_health: float = MAX_HEALTH
var current: float = MAX_HEALTH
var barrier: float = 0.0
var _dead := false


func _ready() -> void:
	health_changed.emit(current, max_health)


func configure(max_hp: float, preserve_ratio: bool = false) -> void:
	var old_max := max_health
	max_health = maxf(1.0, max_hp) if is_finite(max_hp) else MAX_HEALTH
	if preserve_ratio and old_max > 0.0:
		current = clampf((current / old_max) * max_health, 0.0, max_health)
	else:
		current = max_health
		_dead = false
	_clear_barrier()
	health_changed.emit(current, max_health)


func is_dead() -> bool:
	return _dead


func take_damage(amount: float) -> Dictionary:
	var result := {"barrier_absorbed": 0.0, "health_lost": 0.0, "overkill": 0.0}
	if _dead or not is_finite(amount) or amount <= 0.0:
		return result
	if barrier > 0.0 and amount > 0.0:
		var absorbed := minf(barrier, amount)
		barrier -= absorbed
		amount -= absorbed
		result["barrier_absorbed"] = absorbed
		barrier_changed.emit(barrier)
		if amount <= 0.0:
			return result
	var lost := minf(current, amount)
	result["health_lost"] = lost
	result["overkill"] = maxf(0.0, amount - lost)
	current -= lost
	health_changed.emit(current, max_health)
	if current <= 0.0:
		_dead = true
		died.emit()
	return result


## CB-06: `grant_barrier` rules effect. Barriers stack rather than refresh -- two "on kill, grant a
## barrier" relics should be better together, not redundant.
func grant_barrier(amount: float) -> void:
	if _dead or not is_finite(amount) or amount <= 0.0:
		return
	barrier += amount
	barrier_changed.emit(barrier)


func heal(amount: float) -> void:
	if _dead or not is_finite(amount) or amount <= 0.0:
		return
	current = minf(max_health, current + amount)
	health_changed.emit(current, max_health)


func reset_health() -> void:
	_dead = false
	current = max_health
	_clear_barrier()
	health_changed.emit(current, max_health)


func restore_current(value: float) -> void:
	if not is_finite(value):
		return
	current = clampf(value, 0.0, max_health)
	_dead = current <= 0.0
	health_changed.emit(current, max_health)


func _clear_barrier() -> void:
	if barrier <= 0.0:
		return
	barrier = 0.0
	barrier_changed.emit(barrier)


func force_dead() -> void:
	if _dead:
		return
	_dead = true
	current = 0.0
	_clear_barrier()
	health_changed.emit(current, max_health)
