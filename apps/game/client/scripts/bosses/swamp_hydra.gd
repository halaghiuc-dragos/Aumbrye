extends CastleEnemyBase

## 2-phase Swamp Hydra boss — poison phase with cleanse windows (BOSS-5.2).

signal boss_defeated
signal phase_changed(phase: int)

const CLEANSE_SCENE := preload("res://scenes/bosses/swamp_cleanse_zone.tscn")
const POISON_POOL_SCENE := preload("res://scenes/traps/poison_pool.tscn")
const HAZARD_SCENE := preload("res://scenes/bosses/arena_hazard.tscn")

enum BossAttack { BITE, TAIL_SWEEP, POISON_SPIT, MIRE_BURST }

var _phase := 1
var _phase_transition_done := false
var _current_attack := BossAttack.BITE
var _hazards: Array[Node3D] = []
var _cleanse_zones: Array[Node3D] = []
var _poison_phase_timer := 0.0
var _cleanse_cooldown := 0.0
var _arena_bounds := Rect2(-12, -12, 24, 24)
var _arena_center := Vector3.ZERO


func _resolve_enemy_id() -> String:
	return "swamp_hydra"


func get_hp_bar_height() -> float:
	return 3.0


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 2.4, 0.0)


func _ready() -> void:
	super._ready()
	_arena_center = global_position
	_apply_mesh_tint(Color(0.25, 0.4, 0.15, 1.0))
	scale = Vector3(1.35, 1.1, 1.35)
	if _health:
		_health.health_changed.connect(_on_health_changed)
	AudioDirector.play_boss_music()


func _physics_process(delta: float) -> void:
	super._physics_process(delta)
	if _state != State.DEAD:
		_clamp_to_arena()
	if _phase == 2:
		_poison_phase_timer -= delta
		_cleanse_cooldown -= delta
		if _cleanse_cooldown <= 0.0:
			_spawn_cleanse_window()
			_cleanse_cooldown = 8.0


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
		_current_attack = (randi() % 4) as BossAttack
	else:
		_current_attack = (randi() % 2) as BossAttack


func _start_windup() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.WINDUP
	match _current_attack:
		BossAttack.BITE:
			_state_timer = _data.get("windup_duration", 0.52)
		BossAttack.TAIL_SWEEP:
			_state_timer = _data.get("windup_duration", 0.52) * 1.1
		BossAttack.POISON_SPIT:
			_state_timer = 0.65
		BossAttack.MIRE_BURST:
			_state_timer = 0.75
	if _mesh:
		_mesh.scale = Vector3(1.15, 1.15, 1.15)
	begin_attack_windup_bar(_state_timer)
	attack_telegraph_started.emit()


func _start_attack() -> void:
	if is_dead() or (_health and _health.is_dead()):
		return
	_state = State.ATTACK
	if _current_attack == BossAttack.MIRE_BURST:
		_state_timer = 0.5
		_spawn_poison_pool()
	elif _current_attack == BossAttack.POISON_SPIT:
		_state_timer = 0.4
		_spawn_poison_pool()
	else:
		_state_timer = _data.get("active_duration", 0.2)
	hide_attack_windup_bar()
	if _hitbox:
		var dmg_mult := 1.3 if _phase == 2 else 1.0
		_hitbox.set_attack_values(
			_data.get("attack_damage", 23.0) * dmg_mult,
			_data.get("attack_poise_damage", 26.0) * dmg_mult,
			_data.get("damage_type", DamageInfo.TYPE_POISON),
			_data.get("status_on_hit", "poison"),
			int(_data.get("status_stacks_on_hit", 2))
		)
		if _current_attack in [BossAttack.BITE, BossAttack.TAIL_SWEEP]:
			_hitbox.enable()
	attack_active.emit()
	if _current_attack in [BossAttack.BITE, BossAttack.TAIL_SWEEP]:
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
	_poison_phase_timer = 999.0
	_cleanse_cooldown = 2.0
	phase_changed.emit(2)
	if _mesh:
		var tween := create_tween()
		tween.tween_property(_mesh, "scale", Vector3(1.2, 1.2, 1.2), 0.3)
		tween.tween_property(_mesh, "scale", Vector3.ONE, 0.2)
	apply_stagger(0.0)
	_state = State.CHASE
	if _poise:
		_poise.configure(_data.get("poise", 125.0) * 1.15)
	_spawn_cleanse_window()


func _spawn_poison_pool() -> void:
	var hazard := POISON_POOL_SCENE.instantiate()
	get_parent().add_child(hazard)
	var offset := Vector3(randf_range(-7, 7), 0.05, randf_range(-7, 7))
	hazard.global_position = global_position + offset
	_hazards.append(hazard)


func _spawn_cleanse_window() -> void:
	var zone := CLEANSE_SCENE.instantiate()
	get_parent().add_child(zone)
	var offset := Vector3(randf_range(-5, 5), 0.02, randf_range(-5, 5))
	zone.global_position = _arena_center + offset
	_cleanse_zones.append(zone)


func _on_died() -> void:
	super._on_died()
	boss_defeated.emit()
	for h in _hazards:
		if is_instance_valid(h):
			h.queue_free()
	for z in _cleanse_zones:
		if is_instance_valid(z):
			z.queue_free()


func apply_state(state: Dictionary) -> void:
	if state.get("alive", true):
		if _health:
			_health.reset_health()
		_phase = 1
		_phase_transition_done = false
		_poison_phase_timer = 0.0
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
