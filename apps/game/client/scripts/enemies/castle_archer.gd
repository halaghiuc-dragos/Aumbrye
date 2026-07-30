extends "res://scripts/enemies/castle_enemy_base.gd"

## Ranged castle archer — charge telegraph, fixed shot on release (ENEMY-2.2).

const DATA_RELATIVE := "content/enemies/castle_archer.json"
const PROJECTILE_SCENE := preload("res://scenes/combat/enemy_projectile.tscn")

var _draw_telegraph := false
var _locked_shot_direction := Vector3.FORWARD
var _locked_shot_speed := 12.0


func get_data_path() -> String:
	return DATA_RELATIVE


func _process_chase(delta: float) -> void:
	if not _has_aggro():
		_state = State.PATROL
		_pick_patrol_target()
		return
	if _can_attack():
		_start_windup()
		return
	var to_player := _player.global_position - global_position
	to_player.y = 0.0
	var dist := to_player.length()
	var preferred: float = _data.get("preferred_range", 10.0)
	var retreat: float = _data.get("retreat_range", 6.0)
	var move_dir := Vector3.ZERO
	if dist < retreat:
		move_dir = -to_player.normalized()
	elif dist > preferred:
		move_dir = to_player.normalized()
	velocity = move_dir * _data.get("move_speed", 3.0)
	if to_player.length_squared() > 0.01:
		_face_direction(to_player, delta)


func _start_windup() -> void:
	_lock_shot_trajectory()
	super._start_windup()
	_draw_telegraph = true
	if _telegraph:
		_telegraph.scale = Vector3(1.4, 1.4, 1.4)


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
	_state = State.ATTACK
	_state_timer = _data.get("active_duration", 0.05)
	_draw_telegraph = false
	if _telegraph:
		_telegraph.visible = false
		_telegraph.scale = Vector3.ONE
	_fire_projectile()
	attack_active.emit()


func _fire_projectile() -> void:
	var projectile: Node3D = PROJECTILE_SCENE.instantiate() as Node3D
	get_tree().current_scene.add_child(projectile)
	projectile.global_position = global_position + Vector3(0, 1.2, 0)
	if projectile.has_method("launch"):
		projectile.call(
			"launch",
			_locked_shot_direction,
			_locked_shot_speed,
			_data.get("attack_damage", 12.0),
			_data.get("attack_poise_damage", 8.0),
			self
		)


func _end_attack() -> void:
	if _mesh:
		_mesh.scale = Vector3.ONE
	_state = State.RECOVERY
	_state_timer = _data.get("recovery_duration", 1.1)
