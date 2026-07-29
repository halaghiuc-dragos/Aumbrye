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


func configure(max_hp: float) -> void:
	max_health = max_hp
	current = max_hp
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
