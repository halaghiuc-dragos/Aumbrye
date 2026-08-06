extends CastleEnemyBase

## Swamp hag miniboss — poison phase escalation (BOSS-5.2).

signal phase_changed(phase: int)

var _phase := 1
var _phase_transition_done := false


func _resolve_enemy_id() -> String:
	return "swamp_hag"


func get_hp_bar_height() -> float:
	return 2.5


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.32, 0.28, 0.15, 1.0))
	scale = Vector3(1.15, 1.15, 1.15)
	if _health:
		_health.health_changed.connect(_on_health_changed)


func _on_health_changed(current: float, max_value: float) -> void:
	if _phase_transition_done:
		return
	var threshold: float = _data.get("phase2_threshold", 0.45)
	if current / max_value <= threshold:
		_enter_phase_2()


func _enter_phase_2() -> void:
	_phase_transition_done = true
	_phase = 2
	phase_changed.emit(2)
	apply_stagger(0.0)
	_state = State.CHASE
	if _poise:
		_poise.configure(_data.get("poise", 85.0) * 1.1)


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.ATTACK
	_state_timer = _data.get("active_duration", 0.16)
	var stacks := 2 if _phase == 2 else int(_data.get("status_stacks_on_hit", 1))
	if _hitbox:
		_hitbox.set_attack_values(
			_data.get("attack_damage", 19.0) * (1.15 if _phase == 2 else 1.0),
			_data.get("attack_poise_damage", 20.0),
			_data.get("damage_type", DamageInfo.TYPE_PHYSICAL),
			_data.get("status_on_hit", ""),
			stacks
		)
		_hitbox.enable()
	attack_active.emit()
	_try_parry_check()
