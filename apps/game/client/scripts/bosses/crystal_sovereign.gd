extends CastleEnemyBase

## 2-phase Crystal Sovereign boss — crystal pillar mechanic (BOSS-5.1).

signal boss_defeated
signal phase_changed(phase: int)

const PILLAR_SCENE := preload("res://scenes/bosses/crystal_pillar_hazard.tscn")

enum BossAttack { SLASH, ARCANE_BURST, PILLAR_CALL }

var _phase := 1
var _phase_transition_done := false
var _current_attack := BossAttack.SLASH
var _hazards: Array[Node3D] = []
var _arena_bounds := Rect2(-12, -12, 24, 24)
var _arena_center := Vector3.ZERO


func _resolve_enemy_id() -> String:
	return "crystal_sovereign"


func get_hp_bar_height() -> float:
	return 3.0


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 2.2, 0.0)


func _ready() -> void:
	super._ready()
	_arena_center = global_position
	_apply_mesh_tint(Color(0.5, 0.75, 1.0, 1.0))
	scale = Vector3(1.3, 1.3, 1.3)
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
		_current_attack = (randi() % 3) as BossAttack
	else:
		_current_attack = (randi() % 2) as BossAttack


func _start_windup() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.WINDUP
	match _current_attack:
		BossAttack.SLASH:
			_state_timer = _data.get("windup_duration", 0.5)
		BossAttack.ARCANE_BURST:
			_state_timer = _data.get("windup_duration", 0.5) * 0.9
		BossAttack.PILLAR_CALL:
			_state_timer = 0.7
	if _mesh:
		_mesh.scale = Vector3(1.18, 1.18, 1.18)
	begin_attack_windup_bar(_state_timer)
	attack_telegraph_started.emit()


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.ATTACK
	if _current_attack == BossAttack.PILLAR_CALL:
		_state_timer = 0.45
		_spawn_crystal_pillars()
	else:
		_state_timer = _data.get("active_duration", 0.2)
	hide_attack_windup_bar()
	if _hitbox:
		var dmg_mult := 1.35 if _phase == 2 else 1.0
		_hitbox.set_attack_values(
			_data.get("attack_damage", 24.0) * dmg_mult,
			_data.get("attack_poise_damage", 28.0) * dmg_mult,
			_data.get("damage_type", DamageInfo.TYPE_ARCANE),
			_data.get("status_on_hit", ""),
			int(_data.get("status_stacks_on_hit", 1))
		)
		if _current_attack != BossAttack.PILLAR_CALL:
			_hitbox.enable()
	attack_active.emit()
	if _current_attack != BossAttack.PILLAR_CALL:
		_try_parry_check()


func _on_health_changed(current: float, max_value: float) -> void:
	if _phase_transition_done:
		return
	var threshold: float = _data.get("phase2_threshold", 0.5)
	if max_value <= 0.0:
		return
	if current / max_value <= threshold:
		_enter_phase_2()


func _enter_phase_2() -> void:
	_phase_transition_done = true
	_phase = 2
	phase_changed.emit(2)
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "scale", Vector3(1.3, 1.3, 1.3), 0.3)
		tween.tween_property(_mesh, "scale", Vector3.ONE, 0.2)
	apply_stagger(0.0)
	_state = State.CHASE
	if _poise:
		_poise.configure(_data.get("poise", 130.0) * 1.2)


func _spawn_crystal_pillars() -> void:
	var count := 3 if _phase == 2 else 2
	for i in count:
		var hazard := PILLAR_SCENE.instantiate()
		get_parent().add_child(hazard)
		var angle := (TAU / float(count)) * float(i) + randf_range(-0.3, 0.3)
		var offset := Vector3(cos(angle) * randf_range(4, 8), 0.05, sin(angle) * randf_range(4, 8))
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
	offset.x = clampf(
		offset.x, _arena_bounds.position.x, _arena_bounds.position.x + _arena_bounds.size.x
	)
	offset.z = clampf(
		offset.z, _arena_bounds.position.y, _arena_bounds.position.y + _arena_bounds.size.y
	)
	global_position = _arena_center + offset
