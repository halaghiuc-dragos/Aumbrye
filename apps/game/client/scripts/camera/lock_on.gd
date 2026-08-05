extends Node
class_name LockOn

const LOCK_RANGE := 18.0
const ORBIT_RADIUS := 1.75
const SWITCH_DEADZONE := 0.45
const LOS_GRACE_TIME := 0.75
const LOCK_PICK_CONE_DEG := 75.0

signal lock_changed(target: Node3D, locked: bool)

@export var player_path: NodePath
@export var facing_path: NodePath = NodePath("Facing")

var is_locked := false
var current_target: Node3D

var _player: Node3D
var _facing: Node3D
var _switch_cooldown := 0.0
var _target_health: Health
var _los_grace_timer := 0.0
var _camera_spring: Node


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player_path:
		_player = get_node_or_null(player_path) as Node3D
	if _player == null and get_parent() is Node3D:
		_player = get_parent() as Node3D
	if facing_path and _player:
		_facing = _player.get_node_or_null(facing_path) as Node3D
	if _player:
		_camera_spring = _player.get_node_or_null("CameraPivot/SpringArm3D")


func _unhandled_input(event: InputEvent) -> void:
	if get_tree().paused:
		return
	if event.is_action_pressed("lock_on"):
		_toggle_lock()
		get_viewport().set_input_as_handled()
	if is_locked and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			_switch_target(1)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_switch_target(-1)
			get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if _switch_cooldown > 0.0:
		_switch_cooldown -= delta
	if is_locked:
		_update_lock(delta)
		_handle_target_switch()
		_update_lock_camera(delta)


func get_orbit_radius() -> float:
	return ORBIT_RADIUS


func _toggle_lock() -> void:
	if is_locked:
		_break_lock()
		return
	var target := _find_best_target(true)
	if target == null:
		target = _find_best_target(false)
	if target:
		_set_lock(target)


func _set_lock(target: Node3D) -> void:
	_resolve_player()
	_disconnect_target_death()
	current_target = target
	is_locked = true
	_los_grace_timer = 0.0
	_target_health = target.get_node_or_null("Health") as Health
	if _target_health and not _target_health.died.is_connected(_on_lock_target_died):
		_target_health.died.connect(_on_lock_target_died)
	_set_camera_lock_on_active(true)
	lock_changed.emit(target, true)


func _break_lock() -> void:
	_disconnect_target_death()
	current_target = null
	is_locked = false
	_los_grace_timer = 0.0
	_set_camera_lock_on_active(false)
	lock_changed.emit(null, false)


func _disconnect_target_death() -> void:
	if _target_health and _target_health.died.is_connected(_on_lock_target_died):
		_target_health.died.disconnect(_on_lock_target_died)
	_target_health = null


func _on_lock_target_died() -> void:
	if is_locked:
		_advance_lock_after_defeat()


func _advance_lock_after_defeat() -> void:
	var next := _find_best_target(false)
	if next:
		_set_lock(next)
	else:
		_break_lock()


func _update_lock(delta: float) -> void:
	if not is_instance_valid(current_target):
		_break_lock()
		return
	if _is_defeated(current_target):
		_advance_lock_after_defeat()
		return
	if not _player:
		return
	var distance := _player.global_position.distance_to(current_target.global_position)
	if distance > LOCK_RANGE:
		_break_lock()
		return
	if _has_line_of_sight_to(current_target):
		_los_grace_timer = LOS_GRACE_TIME
	elif _los_grace_timer > 0.0:
		_los_grace_timer -= delta
	else:
		_break_lock()


func _update_lock_camera(delta: float) -> void:
	if _camera_spring == null or current_target == null or _player == null:
		return
	var aim := get_target_aim_point(current_target)
	var player_eye := _player.global_position + Vector3(0.0, 1.6, 0.0)
	if _camera_spring.has_method("update_lock_on_frame"):
		_camera_spring.call("update_lock_on_frame", aim, player_eye, delta)
	elif _camera_spring.has_method("blend_look_direction"):
		var to_focus := aim - player_eye
		to_focus.y = 0.0
		if to_focus.length_squared() > 0.01:
			_camera_spring.call("blend_look_direction", to_focus.normalized(), 8.0 * delta)


func _set_camera_lock_on_active(active: bool) -> void:
	if _camera_spring and _camera_spring.has_method("set_lock_on_active"):
		_camera_spring.call("set_lock_on_active", active)


func _handle_target_switch() -> void:
	if _switch_cooldown > 0.0:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length() < SWITCH_DEADZONE:
		return
	_switch_target(1 if stick.x > SWITCH_DEADZONE else -1 if stick.x < -SWITCH_DEADZONE else 0)


func _switch_target(direction: int) -> void:
	if direction == 0:
		return
	var candidates := _get_lockable_targets()
	if candidates.size() < 2:
		return
	var ordered := candidates.duplicate()
	ordered.sort_custom(func(a: Node3D, b: Node3D) -> bool:
		var offset_a := a.global_position - _player.global_position
		var offset_b := b.global_position - _player.global_position
		offset_a.y = 0.0
		offset_b.y = 0.0
		var local_a := offset_a.rotated(Vector3.UP, -_get_facing_yaw())
		var local_b := offset_b.rotated(Vector3.UP, -_get_facing_yaw())
		return atan2(local_a.x, local_a.z) < atan2(local_b.x, local_b.z)
	)
	var current_idx := ordered.find(current_target)
	if current_idx < 0:
		current_idx = 0
	var next_idx := (current_idx + direction) % ordered.size()
	if next_idx < 0:
		next_idx = ordered.size() - 1
	var best: Node3D = ordered[next_idx]
	if best and best != current_target:
		_set_lock(best)
		_switch_cooldown = 0.25


func _resolve_player() -> void:
	if _player == null and player_path:
		_player = get_node_or_null(player_path) as Node3D
	if _player == null and get_parent() is Node3D:
		_player = get_parent() as Node3D


func _find_best_target(require_los: bool = true) -> Node3D:
	_resolve_player()
	if not _player:
		return null
	var aim_dir := _get_lock_search_direction()
	var best: Node3D
	var best_score := INF
	var best_any: Node3D
	var best_any_distance := INF
	for enemy in _get_lockable_targets():
		var offset := enemy.global_position - _player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > LOCK_RANGE or distance < 0.01:
			continue
		if require_los and not _has_line_of_sight_to(enemy):
			continue
		if distance < best_any_distance:
			best_any_distance = distance
			best_any = enemy
		var dir := offset / distance
		var angle := rad_to_deg(aim_dir.angle_to(dir))
		if angle > LOCK_PICK_CONE_DEG:
			continue
		var score := distance + angle * 0.08
		if score < best_score:
			best_score = score
			best = enemy
	if best:
		return best
	return best_any


func _has_line_of_sight_to(target: Node3D) -> bool:
	if _player == null or target == null:
		return false
	var space := _player.get_world_3d().direct_space_state
	if space == null:
		return true
	var from := _player.global_position + Vector3(0.0, 1.0, 0.0)
	var to := get_target_aim_point(target)
	var params := PhysicsRayQueryParameters3D.create(from, to)
	params.collision_mask = 1
	params.collide_with_areas = false
	params.collide_with_bodies = true
	var excludes: Array[RID] = []
	if _player is CollisionObject3D:
		excludes.append((_player as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		excludes.append((target as CollisionObject3D).get_rid())
	for node in get_tree().get_nodes_in_group("lockable"):
		if node == target or not (node is CollisionObject3D):
			continue
		if _is_defeated(node):
			excludes.append((node as CollisionObject3D).get_rid())
	params.exclude = excludes
	return space.intersect_ray(params).is_empty()


func _get_lockable_targets() -> Array[Node3D]:
	var result: Array[Node3D] = []
	for node in get_tree().get_nodes_in_group("lockable"):
		if node is Node3D and is_instance_valid(node):
			if _is_defeated(node):
				continue
			result.append(node as Node3D)
	return result


func _is_defeated(node: Node) -> bool:
	if node.has_method("is_dead") and node.call("is_dead"):
		return true
	var health := node.get_node_or_null("Health") as Health
	return health != null and health.is_dead()


static func get_target_aim_point(target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if target.has_method("get_lock_aim_point"):
		return target.call("get_lock_aim_point")
	var visual := target.get_node_or_null("DioramaVisual") as Node3D
	if visual:
		var from_visual := _aim_point_from_meshes(visual)
		if from_visual != Vector3.INF:
			return from_visual
	var fallback := _aim_point_from_meshes(target)
	if fallback != Vector3.INF:
		return fallback
	return target.global_position + Vector3(0.0, 1.2, 0.0)


static func _aim_point_from_meshes(root: Node) -> Vector3:
	var combined := AABB()
	var found := false
	for node in root.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		if visual == null or not visual.visible:
			continue
		if _should_skip_lock_aim_mesh(visual):
			continue
		var local_aabb := visual.get_aabb()
		if local_aabb.size.length_squared() < 0.0001:
			continue
		var global_aabb := visual.global_transform * local_aabb
		if not found:
			combined = global_aabb
			found = true
		else:
			combined = combined.merge(global_aabb)
	if found:
		return combined.get_center()
	return Vector3.INF


static func _should_skip_lock_aim_mesh(mesh: MeshInstance3D) -> bool:
	match mesh.name:
		"TelegraphMesh", "MeshInstance3D":
			return true
	var parent := mesh.get_parent()
	while parent:
		if parent is Hitbox or parent is Hurtbox:
			return true
		if parent.name in ["AttackPivot", "Hitbox", "Hurtbox", "WeaponPivot"]:
			return true
		parent = parent.get_parent()
	return false


func _get_lock_search_direction() -> Vector3:
	if _camera_spring:
		var camera := _camera_spring.get_node_or_null("Camera3D") as Camera3D
		if camera:
			var dir := -camera.global_transform.basis.z
			dir.y = 0.0
			if dir.length_squared() > 0.01:
				return dir.normalized()
	var yaw := _get_facing_yaw()
	return Vector3(-sin(yaw), 0.0, -cos(yaw)).normalized()


func _get_facing_yaw() -> float:
	if _player and _player.has_method("get_facing_yaw"):
		return _player.call("get_facing_yaw")
	if _facing:
		return _facing.rotation.y
	if _player:
		return _player.rotation.y
	return 0.0
