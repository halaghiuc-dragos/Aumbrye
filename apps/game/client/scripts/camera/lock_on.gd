extends Node
class_name LockOn

const LOCK_RANGE := 18.0
const ORBIT_RADIUS := 1.75
const SWITCH_DEADZONE := 0.7

signal lock_changed(target: Node3D, locked: bool)

@export var player_path: NodePath
@export var facing_path: NodePath = NodePath("Facing")

var is_locked := false
var current_target: Node3D

var _player: Node3D
var _facing: Node3D
var _switch_cooldown := 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player_path:
		_player = get_node(player_path) as Node3D
	if facing_path and _player:
		_facing = _player.get_node_or_null(facing_path) as Node3D


func _input(event: InputEvent) -> void:
	if event.is_action_pressed("lock_on"):
		_toggle_lock()
		get_viewport().set_input_as_handled()


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
	if not _has_line_of_sight_to(current_target):
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
		if not _has_line_of_sight_to(enemy):
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
	if not _player:
		return null
	var best: Node3D
	var best_distance := INF
	for enemy in _get_lockable_targets():
		var distance := _player.global_position.distance_to(enemy.global_position)
		if distance > LOCK_RANGE:
			continue
		if not _has_line_of_sight_to(enemy):
			continue
		if distance < best_distance:
			best_distance = distance
			best = enemy
	return best


func _has_line_of_sight_to(target: Node3D) -> bool:
	if _player == null or target == null:
		return false
	var space := _player.get_world_3d().direct_space_state
	if space == null:
		return true
	var from := _player.global_position + Vector3(0.0, 1.0, 0.0)
	var to := target.global_position + Vector3(0.0, 1.2, 0.0)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var excludes: Array[RID] = []
	if _player is CollisionObject3D:
		excludes.append((_player as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		excludes.append((target as CollisionObject3D).get_rid())
	params.exclude = excludes
	return space.intersect_ray(params).is_empty()


func _get_lockable_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("lockable"):
		if node is Node3D and is_instance_valid(node):
			if node.has_method("is_dead") and node.call("is_dead"):
				continue
			result.append(node as Node3D)
	return result


func _get_facing_yaw() -> float:
	if _player and _player.has_method("get_facing_yaw"):
		return _player.call("get_facing_yaw")
	if _facing:
		return _facing.rotation.y
	if _player:
		return _player.rotation.y
	return 0.0
