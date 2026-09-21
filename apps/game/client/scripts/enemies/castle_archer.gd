extends CastleEnemyBase


const PROJECTILE_SCENE := preload("res://scenes/combat/enemy_projectile.tscn")
const ProjectileContainerScript := preload("res://scripts/combat/projectile_container.gd")
const ProjectileScript := preload("res://scripts/combat/enemy_projectile.gd")

var _locked_shot_direction := Vector3.FORWARD
var _locked_shot_speed := 12.0
var _locked_shot_target := Vector3.INF
var _shot_reachable := true


func _resolve_enemy_id() -> String:
	return "castle_archer"


func _process_chase(delta: float) -> void:
	if not _has_aggro():
		_state = State.INVESTIGATE
		_state_timer = 2.5
		return
	_last_known_player_pos = _player.global_position
	if _can_attack():
		_start_windup()
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var move_dir := Vector3.ZERO
	if dist < _retreat_range:
		move_dir = -to_player.normalized()
	elif dist > _preferred_range:
		move_dir = _direction_toward(_player.global_position, delta, true)
	velocity = move_dir * _move_speed
	if to_player.length_squared() > 0.01:
		_face_direction(to_player, delta)


func _start_windup() -> void:
	_lock_shot_trajectory()
	if not _shot_reachable:
		_state = State.CHASE
		return
	super._start_windup()


func _on_windup_tick(committed: bool) -> void:
	if committed:
		return
	_lock_shot_trajectory()
	if not _shot_reachable:
		hide_attack_windup_bar()
		_release_attack_token()
		_state = State.CHASE


func _telegraph_radius_scale() -> float:
	return 1.4


func _lock_shot_trajectory() -> void:
	_locked_shot_speed = _data.get("projectile_speed", 12.0)
	if _player == null:
		_locked_shot_direction = CombatFacing.forward_of(self)
		_locked_shot_target = Vector3.INF
		_shot_reachable = true
		return
	var spawn_pos := global_position + Vector3(0, 1.2, 0)
	var target_pos := _player.global_position + Vector3(0, 1.0, 0)
	_locked_shot_target = target_pos
	var to_target := target_pos - spawn_pos
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		_locked_shot_direction = CombatFacing.forward_of(self)
	else:
		_locked_shot_direction = to_target.normalized()
	var solution := ProjectileScript.solve_launch_velocity(
		_locked_shot_direction, _locked_shot_speed, spawn_pos, target_pos
	)
	_shot_reachable = bool(solution.get("reachable", false))
	if _shot_reachable:
		var space := get_world_3d().direct_space_state
		var excluded: Array[RID] = [get_rid()]
		_shot_reachable = ProjectileScript.trajectory_is_clear(
			space, spawn_pos, solution["velocity"], target_pos, excluded
		)


func _start_attack() -> void:
	if str(_current_attack_data.get("attackBehavior", "projectile")) != "projectile":
		super._start_attack()
		return
	if is_dead() or (_health and _health.is_dead()):
		_release_attack_token()
		return
	_state = State.ATTACK
	_state_timer = float(
		_current_attack_data.get("active_duration", _data.get("active_duration", 0.05))
	)
	hide_attack_windup_bar()
	_fire_projectile()
	attack_active.emit()


func _fire_projectile() -> void:
	var projectile: Node3D = PROJECTILE_SCENE.instantiate() as Node3D
	var container := ProjectileContainerScript.get_or_create(self)
	if container:
		container.add_child(projectile)
	else:
		get_tree().current_scene.add_child(projectile)
	projectile.global_position = _projectile_origin()
	if not projectile.has_method("launch"):
		projectile.queue_free()
		return
	var launched: Variant = projectile.call(
		"launch",
		_locked_shot_direction,
		float(_current_attack_data.get("projectile_speed", _locked_shot_speed)),
		float(_current_attack_data.get("attack_damage", _data.get("attack_damage", 12.0)))
		* _damage_multiplier,
		float(
			_current_attack_data.get("attack_poise_damage", _data.get("attack_poise_damage", 8.0))
		)
		* _damage_multiplier,
		self,
		_current_attack_data.get("damage_type", _data.get("damage_type", DamageInfo.TYPE_PHYSICAL)),
		_current_attack_data.get("status_on_hit", _data.get("status_on_hit", "")),
		int(
			_current_attack_data.get(
				"status_stacks_on_hit", _data.get("status_stacks_on_hit", 1)
			)
		),
		0.0,
		1.5,
		_current_attack_class(),
		float(_current_attack_data.get("knockback", _data.get("knockback", 0.0))),
		_locked_shot_target
	)
	if launched is bool and not launched:
		_shot_reachable = false


func _projectile_origin() -> Vector3:
	for anchor_name in ["ProjectileMuzzle", "Muzzle", "AimAnchor"]:
		var anchor := find_child(anchor_name, true, false) as Node3D
		if anchor:
			return anchor.global_position
	return global_position + Vector3(0.0, 1.2, 0.0)
