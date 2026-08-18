extends CastleEnemyBase

## Ranged castle archer — charge telegraph, fixed shot on release (ENEMY-2.2).

const PROJECTILE_SCENE := preload("res://scenes/combat/enemy_projectile.tscn")

var _locked_shot_direction := Vector3.FORWARD
var _locked_shot_speed := 12.0


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
	super._start_windup()


## Keeps the shot aimed for exactly as long as the body may still turn, then freezes with it.
##
## The trajectory used to be resolved once at wind-up start while the archer went on rotating
## for the whole telegraph, so the arrow left along a heading the archer was no longer facing.
func _on_windup_tick(committed: bool) -> void:
	if committed:
		return
	_lock_shot_trajectory()


func _show_attack_telegraph(duration: float) -> void:
	var radius := float(
		_current_attack_data.get("telegraph_radius", _data.get("telegraph_radius", 1.6))
	) * 1.4
	var shape := String(
		_current_attack_data.get("telegraph_shape", _data.get("telegraph_shape", "circle"))
	)
	var tint := Color(0.95, 0.34, 0.28)
	if _data.has("telegraph_tint"):
		tint = Color(_data["telegraph_tint"])
	var forward := -global_transform.basis.z
	VfxService.play_telegraph(global_position, radius, duration, tint, shape, forward)


func _lock_shot_trajectory() -> void:
	_locked_shot_speed = _data.get("projectile_speed", 12.0)
	if _player == null:
		_locked_shot_direction = -global_transform.basis.z
		return
	var spawn_pos := global_position + Vector3(0, 1.2, 0)
	var target_pos := _player.global_position + Vector3(0, 1.0, 0)
	var to_target := target_pos - spawn_pos
	to_target.y = 0.0
	if to_target.length_squared() < 0.01:
		_locked_shot_direction = -global_transform.basis.z
	else:
		_locked_shot_direction = to_target.normalized()


func _start_attack() -> void:
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
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3(0, 1.2, 0)
	if not projectile.has_method("launch"):
		return
	projectile.call(
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
		)
	)
