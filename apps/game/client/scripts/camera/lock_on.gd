extends Node

const LOCK_RANGE := 18.0
const ORBIT_RADIUS := 1.75
const SWITCH_DEADZONE := 0.7
const SOFT_ASSIST_ANGLE := deg_to_rad(55.0)

signal lock_changed(target: Node3D, locked: bool)

@export var player_path: NodePath
@export var facing_path: NodePath = NodePath("Facing")

var is_locked := false
var current_target: Node3D

var _player: Node3D
var _facing: Node3D
var _switch_cooldown := 0.0


func _ready() -> void:
	if player_path:
		_player = get_node(player_path) as Node3D
	if facing_path and _player:
		_facing = _player.get_node_or_null(facing_path) as Node3D


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_on"):
		_toggle_lock()


func _physics_process(delta: float) -> void:
	if _switch_cooldown > 0.0:
		_switch_cooldown -= delta
	if is_locked:
		_update_lock()
		_handle_target_switch()


func get_orbit_radius() -> float:
	return ORBIT_RADIUS


func _toggle_lock() -> void:
	if is_locked:
		_break_lock()
		return
	var target := _find_best_target()
	if target:
		_set_lock(target)


func _set_lock(target: Node3D) -> void:
	current_target = target
	is_locked = true
	lock_changed.emit(target, true)


func _break_lock() -> void:
	current_target = null
	is_locked = false
	lock_changed.emit(null, false)


func _update_lock() -> void:
	if not is_instance_valid(current_target):
		_break_lock()
		return
	if not _player:
		return
	var distance := _player.global_position.distance_to(current_target.global_position)
	if distance > LOCK_RANGE:
		_break_lock()
		return
	if current_target.has_method("is_dead") and current_target.call("is_dead"):
		_break_lock()


func _handle_target_switch() -> void:
	if _switch_cooldown > 0.0:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() < SWITCH_DEADZONE:
		return
	var candidates := _get_lockable_targets()
	if candidates.size() < 2:
		return
	var best: Node3D
	var best_score := -INF
	for enemy in candidates:
		if enemy == current_target:
			continue
		var offset := enemy.global_position - _player.global_position
		offset.y = 0.0
		var local := offset.rotated(Vector3.UP, -_get_facing_yaw())
		var score := local.x * stick.x + local.z * -stick.y
		if score > best_score:
			best_score = score
			best = enemy
	if best and best_score > 0.3:
		current_target = best
		_switch_cooldown = 0.25
		lock_changed.emit(current_target, true)


func _find_best_target() -> Node3D:
	var candidates := _get_lockable_targets()
	if candidates.is_empty():
		return null
	if candidates.size() == 1:
		var only := candidates[0]
		if _player.global_position.distance_to(only.global_position) <= LOCK_RANGE:
			return only
		return null
	var best: Node3D
	var best_score := INF
	for enemy in candidates:
		var score := _score_target(enemy)
		if score < best_score:
			best_score = score
			best = enemy
	return best


func _score_target(enemy: Node3D) -> float:
	if not _player:
		return INF
	var to_enemy := enemy.global_position - _player.global_position
	var distance := to_enemy.length()
	if distance > LOCK_RANGE:
		return INF
	var facing := _get_visual_forward()
	to_enemy.y = 0.0
	if to_enemy.length_squared() < 0.01:
		return distance
	var angle := facing.angle_to(to_enemy.normalized())
	if angle > SOFT_ASSIST_ANGLE:
		return INF
	return distance + angle * 2.0


func _get_lockable_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("lockable"):
		if node is Node3D and is_instance_valid(node):
			if node.has_method("is_dead") and node.call("is_dead"):
				continue
			result.append(node as Node3D)
	return result


func _get_visual_forward() -> Vector3:
	if _facing:
		return _facing.global_transform.basis.z.normalized()
	if _player:
		return _player.global_transform.basis.z.normalized()
	return Vector3.FORWARD


func _get_facing_yaw() -> float:
	if _player and _player.has_method("get_facing_yaw"):
		return _player.call("get_facing_yaw")
	if _facing:
		return _facing.rotation.y
	if _player:
		return _player.rotation.y
	return 0.0
