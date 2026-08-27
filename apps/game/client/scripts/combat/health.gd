extends Node
class_name Health

signal health_changed(current: float, max_value: float)
signal died

const MAX_HEALTH := 100.0

var max_health: float = MAX_HEALTH
var current: float = MAX_HEALTH
var _dead := false


func _ready() -> void:
	health_changed.emit(current, max_health)


func configure(max_hp: float, preserve_ratio: bool = false) -> void:
	var old_max := max_health
	max_health = max_hp
	if preserve_ratio and old_max > 0.0:
		current = clampf((current / old_max) * max_health, 0.0, max_health)
	else:
		current = max_health
		_dead = false
	health_changed.emit(current, max_health)


func is_dead() -> bool:
	return _dead


func take_damage(amount: float) -> void:
	if _dead:
		return
	current = maxf(0.0, current - amount)
	health_changed.emit(current, max_health)
	if current <= 0.0:
		_dead = true
		died.emit()


func heal(amount: float) -> void:
	if _dead:
		return
	current = minf(max_health, current + amount)
	health_changed.emit(current, max_health)


func reset_health() -> void:
	_dead = false
	current = max_health
	health_changed.emit(current, max_health)


func restore_current(value: float) -> void:
	if _dead:
		return
	current = clampf(value, 0.0, max_health)
	health_changed.emit(current, max_health)


func force_dead() -> void:
	if _dead:
		return
	_dead = true
	current = 0.0
	health_changed.emit(current, max_health)
