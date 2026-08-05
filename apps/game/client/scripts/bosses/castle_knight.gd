extends CastleEnemyBase

## 2-phase Castle Knight boss (BOSS-2.1 / BOSS-2.2).

signal boss_defeated
signal phase_changed(phase: int)

const HAZARD_SCENE := preload("res://scenes/bosses/arena_hazard.tscn")

enum BossAttack { SLASH, THRUST, SWEEP, GROUND_SLAM }

var _phase := 1
var _phase_transition_done := false
var _current_attack := BossAttack.SLASH
var _hazards: Array[Node3D] = []
var _arena_bounds := Rect2(-12, -12, 24, 24)


func get_enemy_id() -> String:
	return "castle_knight"


func get_hp_bar_height() -> float:
	return 2.8


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 1.9, 0.0)


var _arena_center := Vector3.ZERO


func _ready() -> void:
	super._ready()
	_arena_center = global_position
	if _health:
		_health.health_changed.connect(_on_health_changed)
	AudioDirector.play_boss_music()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _state != State.DEAD:
		_clamp_to_arena()


func _process_chase(delta: float) -> void:
	if not _has_aggro():
		return
	if _can_attack():
		_pick_attack()
		_start_windup()
		return
	_apply_chase_velocity(delta, 1.0)


func _pick_attack() -> void:
	if _phase == 2:
		var roll := randi() % 4
		_current_attack = roll as BossAttack
	else:
		_current_attack = (randi() % 3) as BossAttack


func _start_windup() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.WINDUP
	match _current_attack:
		BossAttack.SLASH:
			_state_timer = _data.get("windup_duration", 0.6)
		BossAttack.THRUST:
			_state_timer = _data.get("windup_duration", 0.6) * 0.8
		BossAttack.SWEEP:
			_state_timer = _data.get("windup_duration", 0.6) * 1.2
		BossAttack.GROUND_SLAM:
			_state_timer = 0.55
	if _mesh:
		_mesh.scale = Vector3(1.15, 1.15, 1.15)
	begin_attack_windup_bar(_state_timer)
	attack_telegraph_started.emit()


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.ATTACK
	if _current_attack == BossAttack.GROUND_SLAM:
		_state_timer = 0.5
		_spawn_ground_hazard()
	else:
		_state_timer = _data.get("active_duration", 0.2)
	hide_attack_windup_bar()
	if _hitbox:
		var dmg_mult := 1.3 if _phase == 2 else 1.0
		_hitbox.set_attack_values(
			_data.get("attack_damage", 22.0) * dmg_mult,
			_data.get("attack_poise_damage", 25.0) * dmg_mult
		)
		_hitbox.enable()
	attack_active.emit()
	_try_parry_check()


func _on_health_changed(current: float, max_value: float) -> void:
	if _phase_transition_done:
		return
	var threshold: float = _data.get("phase2_threshold", 0.5)
	if current / max_value <= threshold:
		_enter_phase_2()


func _enter_phase_2() -> void:
	_phase_transition_done = true
	_phase = 2
	phase_changed.emit(2)
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "scale", Vector3(1.25, 1.25, 1.25), 0.3)
		tween.tween_property(_mesh, "scale", Vector3.ONE, 0.2)
	apply_stagger(0.0) # brief pause
	_state = State.CHASE
	if _poise:
		_poise.configure(_data.get("poise", 120.0) * 1.2)


func _spawn_ground_hazard() -> void:
	var hazard := HAZARD_SCENE.instantiate()
	get_parent().add_child(hazard)
	var offset := Vector3(randf_range(-6, 6), 0.05, randf_range(-6, 6))
	hazard.global_position = global_position + offset
	_hazards.append(hazard)


func _on_died() -> void:
	super._on_died()
	boss_defeated.emit()
	for h in _hazards:
		if is_instance_valid(h):
			h.queue_free()


func apply_state(state: Dictionary) -> void:
	if state.get("alive", true):
		if _health:
			_health.reset_health()
		_phase = 1
		_phase_transition_done = false
		if _mesh:
			_mesh.scale = Vector3.ONE
		_state = State.PATROL
		return
	super.apply_state(state)


func _clamp_to_arena() -> void:
	var offset := global_position - _arena_center
	offset.x = clampf(offset.x, _arena_bounds.position.x, _arena_bounds.position.x + _arena_bounds.size.x)
	offset.z = clampf(offset.z, _arena_bounds.position.y, _arena_bounds.position.y + _arena_bounds.size.y)
	global_position = _arena_center + offset
