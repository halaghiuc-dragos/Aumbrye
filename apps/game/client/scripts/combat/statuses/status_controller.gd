extends Node
class_name StatusController

## Applies burn, bleed, poison, freeze, stun from data (DMG-5.2).

signal statuses_changed

@export var health_path: NodePath
@export var team: String = "enemy"

var _health: Health
var _active: Dictionary = {}
var _slow_multiplier := 1.0
var _stunned := false


func _ready() -> void:
	if health_path:
		_health = get_node_or_null(health_path) as Health


func set_health(health: Health) -> void:
	_health = health


func _physics_process(delta: float) -> void:
	if _active.is_empty():
		return
	var expired: Array[String] = []
	for status_id in _active:
		var entry: Dictionary = _active[status_id]
		entry["remaining"] = float(entry.get("remaining", 0.0)) - delta
		entry["elapsed"] = float(entry.get("elapsed", 0.0)) + delta
		entry["tick_timer"] = float(entry.get("tick_timer", 0.0)) - delta
		if entry["tick_timer"] <= 0.0:
			_apply_tick(status_id, entry)
			var def := StatusCatalog.get_definition(status_id)
			entry["tick_timer"] = float(def.get("tickInterval", 1.0))
		if float(entry.get("remaining", 0.0)) <= 0.0:
			expired.append(status_id)
	for status_id in expired:
		_remove_status(status_id)
	_recalc_modifiers()


func apply_status(status_id: String, stacks: int = 1, duration_override: float = -1.0) -> void:
	if status_id == "":
		return
	var def := StatusCatalog.get_definition(status_id)
	if def.is_empty():
		return
	var max_stacks: int = int(def.get("maxStacks", 1))
	var duration := (
		duration_override if duration_override > 0.0 else float(def.get("duration", 4.0))
	)
	if _active.has(status_id):
		var entry: Dictionary = _active[status_id]
		entry["stacks"] = mini(int(entry.get("stacks", 1)) + stacks, max_stacks)
		entry["remaining"] = maxf(float(entry.get("remaining", 0.0)), duration)
	else:
		_active[status_id] = {
			"stacks": mini(stacks, max_stacks),
			"remaining": duration,
			"tick_timer": float(def.get("tickInterval", 1.0)),
			"elapsed": 0.0,
		}
	_recalc_modifiers()
	statuses_changed.emit()


func debug_apply(status_id: String) -> void:
	apply_status(status_id, 1)


func get_active_statuses() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for status_id in _active:
		var entry: Dictionary = _active[status_id]
		(
			out
			. append(
				{
					"id": status_id,
					"stacks": int(entry.get("stacks", 1)),
					"remaining": float(entry.get("remaining", 0.0)),
				}
			)
		)
	return out


func get_slow_multiplier() -> float:
	return _slow_multiplier


func is_stunned() -> bool:
	return _stunned


func clear_all() -> void:
	_active.clear()
	_slow_multiplier = 1.0
	_stunned = false
	statuses_changed.emit()


func _apply_tick(status_id: String, entry: Dictionary) -> void:
	var def := StatusCatalog.get_definition(status_id)
	var tick_dmg: float = float(def.get("tickDamage", 0.0)) * int(entry.get("stacks", 1))
	if tick_dmg <= 0.0 or _health == null or _health.is_dead():
		return
	var dmg_type: String = def.get("damageType", DamageInfo.TYPE_PHYSICAL)
	var tick_amount := DamageInfo.apply_resistance(tick_dmg, dmg_type, _get_resistances())
	var body := get_parent()
	if body:
		var hurtbox := body.get_node_or_null("Hurtbox") as Hurtbox
		if hurtbox:
			hurtbox.receive_periodic_damage(tick_amount, dmg_type)
			return
	_health.take_damage(tick_amount)


func _get_resistances() -> Dictionary:
	var body := get_parent()
	if body and body.has_method("get_enemy_id"):
		var enemy_id: String = body.call("get_enemy_id")
		if enemy_id != "":
			return EnemyCatalog.get_definition(enemy_id).get("resistances", {})
	return {}


func _remove_status(status_id: String) -> void:
	_active.erase(status_id)


func _recalc_modifiers() -> void:
	var prev_slow := _slow_multiplier
	var prev_stun := _stunned
	_slow_multiplier = 1.0
	_stunned = false
	for status_id in _active:
		var def := StatusCatalog.get_definition(status_id)
		_slow_multiplier = minf(_slow_multiplier, float(def.get("slowMultiplier", 1.0)))
		var stun_dur := float(def.get("stunDuration", 0.0))
		if stun_dur > 0.0 and float(_active[status_id].get("elapsed", 0.0)) < stun_dur:
			_stunned = true
	if not is_equal_approx(prev_slow, _slow_multiplier) or prev_stun != _stunned:
		statuses_changed.emit()
