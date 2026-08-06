extends Node
class_name LockOn

const LOCK_ACQUIRE_RANGE := 18.0
const LOCK_BREAK_RANGE := 22.0
const LOCK_BREAK_GRACE := 0.4
const LOCK_VERTICAL_LIMIT := 8.0
const SCORE_DISTANCE_WEIGHT := 1.0
const SCORE_ANGLE_WEIGHT := 0.75
const SCORE_THREAT_WEIGHT := 0.5
const SWITCH_COOLDOWN_STICK := 0.15
const SWITCH_COOLDOWN_WHEEL := 0.05
const ORBIT_RADIUS := 1.75
const SWITCH_THRESHOLD := 0.55
const TOGGLE_COOLDOWN := 0.2

var _prev_stick_x := 0.0
var _switch_blend_boost := 0.0
var _break_grace_timer := 0.0
const LOS_GRACE_TIME := 0.75
const LOCK_PICK_CONE_DEG := 75.0

signal lock_changed(target: Node3D, locked: bool)
signal lock_occluded(occluded: bool)

@export var player_path: NodePath
@export var facing_path: NodePath = NodePath("Facing")

var is_locked := false
var current_target: Node3D

var _player: Node3D
var _facing: Node3D
var _switch_cooldown := 0.0
var _toggle_cooldown := 0.0
var _target_health: Health
var _los_grace_timer := 0.0
var _was_occluded := false
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
	if get_tree().paused or _is_ui_focused():
		return
	if event.is_action_pressed("lock_on"):
		_toggle_lock()
		get_viewport().set_input_as_handled()
	if is_locked and event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			if _switch_target(1):
				get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			if _switch_target(-1):
				get_viewport().set_input_as_handled()


func _physics_process(delta: float) -> void:
	if get_tree().paused:
		return
	if PlayerInput.has_method("is_gameplay_blocked") and PlayerInput.call("is_gameplay_blocked"):
		return
	if _switch_cooldown > 0.0:
		_switch_cooldown -= delta
	if _toggle_cooldown > 0.0:
		_toggle_cooldown -= delta
	if _switch_blend_boost > 0.0:
		_switch_blend_boost = maxf(0.0, _switch_blend_boost - delta)
	if is_locked:
		_update_lock(delta)
		_handle_target_switch()
		_update_lock_camera(delta)


func get_orbit_radius() -> float:
	return LockOnMovement.get_orbit_radius(self, current_target)


func break_lock() -> void:
	if is_locked:
		_break_lock()


func request_lock(target: Node3D = null) -> bool:
	if target != null and is_instance_valid(target):
		_set_lock(target)
		return true
	var best := _find_best_target(true)
	if best == null:
		best = _find_best_target(false)
	if best:
		_set_lock(best)
		return true
	return false


func cycle_target(direction: int) -> bool:
	if not is_locked or direction == 0:
		return false
	var before := current_target
	_switch_target(direction)
	return current_target != before and current_target != null


func _toggle_lock() -> void:
	if _toggle_cooldown > 0.0:
		return
	if is_locked:
		_break_lock()
		_toggle_cooldown = TOGGLE_COOLDOWN
		return
	var target := _find_best_target(true)
	if target == null:
		target = _find_best_target(false)
	if target:
		_set_lock(target)
		_toggle_cooldown = TOGGLE_COOLDOWN


func _set_lock(target: Node3D) -> void:
	_resolve_player()
	_resolve_camera_spring()
	_disconnect_target_death()
	current_target = target
	is_locked = true
	_los_grace_timer = 0.0
	_was_occluded = false
	_target_health = target.get_node_or_null("Health") as Health
	if _target_health and not _target_health.died.is_connected(_on_lock_target_died):
		_target_health.died.connect(_on_lock_target_died)
	_push_lock_target_height(target)
	_set_camera_lock_on_active(true)
	lock_changed.emit(target, true)


func _break_lock() -> void:
	if not is_locked:
		return
	_disconnect_target_death()
	current_target = null
	is_locked = false
	_los_grace_timer = 0.0
	_was_occluded = false
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
	var next := _find_best_target(false, true)
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
	var planar := _planar_distance_to(current_target)
	if planar > LOCK_BREAK_RANGE:
		_break_grace_timer -= delta
		if _break_grace_timer <= 0.0:
			_break_lock()
		return
	_break_grace_timer = LOCK_BREAK_GRACE
	if _has_line_of_sight_to(current_target):
		if _was_occluded:
			_was_occluded = false
			lock_occluded.emit(false)
		_los_grace_timer = LOS_GRACE_TIME
	elif _los_grace_timer > 0.0:
		if not _was_occluded:
			_was_occluded = true
			lock_occluded.emit(true)
		_los_grace_timer -= delta
	else:
		if _was_occluded:
			lock_occluded.emit(false)
		_break_lock()


func _update_lock_camera(delta: float) -> void:
	if _camera_spring == null or current_target == null or _player == null:
		return
	var aim := get_target_aim_point(current_target)
	var player_eye := _get_player_eye_position()
	if _camera_spring.has_method("update_lock_on_frame"):
		var blend_boost := 1.0 + _switch_blend_boost * 3.0
		_camera_spring.call("update_lock_on_frame", aim, player_eye, delta * blend_boost)
	elif _camera_spring.has_method("blend_look_direction"):
		var to_focus := aim - player_eye
		to_focus.y = 0.0
		if to_focus.length_squared() > 0.01:
			_camera_spring.call("blend_look_direction", to_focus.normalized(), 8.0 * delta)


func _get_player_eye_position() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	if (
		_camera_spring
		and _camera_spring.has_method("is_first_person")
		and _camera_spring.call("is_first_person")
	):
		var camera := _camera_spring.get_node_or_null("Camera3D") as Camera3D
		if camera:
			return camera.global_position
	return _player.global_position + Vector3(0.0, 1.6, 0.0)


func _set_camera_lock_on_active(active: bool) -> void:
	_resolve_camera_spring()
	if _camera_spring == null:
		return
	if _camera_spring.has_method("set_lock_on_active"):
		_camera_spring.call("set_lock_on_active", active)
	if active:
		if not lock_occluded.is_connected(_on_lock_occluded_camera):
			lock_occluded.connect(_on_lock_occluded_camera)
	else:
		if lock_occluded.is_connected(_on_lock_occluded_camera):
			lock_occluded.disconnect(_on_lock_occluded_camera)
		if _was_occluded:
			_was_occluded = false
			lock_occluded.emit(false)


func _on_lock_occluded_camera(occluded: bool) -> void:
	if _camera_spring and _camera_spring.has_method("on_lock_occluded"):
		_camera_spring.call("on_lock_occluded", occluded)


func _push_lock_target_height(target: Node3D) -> void:
	_resolve_camera_spring()
	if _camera_spring and _camera_spring.has_method("set_lock_target_height"):
		_camera_spring.call("set_lock_target_height", get_target_height(target))


func _handle_target_switch() -> void:
	if get_tree().paused:
		return
	if _switch_cooldown > 0.0:
		return
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if _prev_stick_x < SWITCH_THRESHOLD and stick.x >= SWITCH_THRESHOLD:
		_switch_target(1)
	elif _prev_stick_x > -SWITCH_THRESHOLD and stick.x <= -SWITCH_THRESHOLD:
		_switch_target(-1)
	elif absf(stick.y) >= SWITCH_THRESHOLD and absf(stick.x) < 0.2:
		_switch_target_vertical(stick.y)
	_prev_stick_x = stick.x


func _switch_target_vertical(stick_y: float) -> void:
	var candidates := _get_lockable_targets()
	if candidates.size() < 2 or current_target == null:
		return
	var current_y := get_target_aim_point(current_target).y
	var best: Node3D
	var best_score := INF
	for enemy in candidates:
		if enemy == current_target:
			continue
		var y := get_target_aim_point(enemy).y
		var score := y - current_y if stick_y < 0.0 else current_y - y
		if score <= 0.0:
			continue
		if score < best_score:
			best_score = score
			best = enemy
	if best:
		_set_lock(best)
		_switch_cooldown = SWITCH_COOLDOWN_STICK
		_switch_blend_boost = 1.0


func _planar_distance_to(target: Node3D) -> float:
	if _player == null or target == null:
		return INF
	var offset := target.global_position - _player.global_position
	offset.y = 0.0
	return offset.length()


func _vertical_delta_to(target: Node3D) -> float:
	return absf(get_target_aim_point(target).y - _player.global_position.y)


func _switch_target(direction: int) -> bool:
	if direction == 0:
		return false
	var candidates := _get_lockable_targets()
	if candidates.size() < 2:
		return false
	var ordered := candidates.duplicate()
	ordered.sort_custom(
		func(a: Node3D, b: Node3D) -> bool:
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
		_switch_cooldown = SWITCH_COOLDOWN_WHEEL
		_switch_blend_boost = 1.0
		return true
	return false


func _resolve_player() -> void:
	if _player == null and player_path:
		_player = get_node_or_null(player_path) as Node3D
	if _player == null and get_parent() is Node3D:
		_player = get_parent() as Node3D


func _resolve_camera_spring() -> void:
	if _camera_spring == null and _player:
		_camera_spring = _player.get_node_or_null("CameraPivot/SpringArm3D")


func _find_best_target(require_los: bool = true, ignore_cone: bool = false) -> Node3D:
	_resolve_player()
	if not _player:
		return null
	var aim_dir := _get_lock_search_direction()
	var best: Node3D
	var best_score := INF
	for enemy in _get_lockable_targets():
		var offset := enemy.global_position - _player.global_position
		offset.y = 0.0
		var distance := offset.length()
		if distance > LOCK_ACQUIRE_RANGE or distance < 0.01:
			continue
		if _vertical_delta_to(enemy) > LOCK_VERTICAL_LIMIT:
			continue
		if require_los and not _has_line_of_sight_to(enemy):
			continue
		var angle := 0.0
		if not ignore_cone:
			var dir := offset / distance
			angle = rad_to_deg(aim_dir.angle_to(dir))
			if angle > LOCK_PICK_CONE_DEG:
				continue
		var threat := 0.0
		if enemy.has_method("get_lock_threat"):
			threat = float(enemy.call("get_lock_threat"))
		var score := (
			SCORE_DISTANCE_WEIGHT * (distance / LOCK_ACQUIRE_RANGE)
			+ SCORE_ANGLE_WEIGHT * (angle / LOCK_PICK_CONE_DEG)
			- SCORE_THREAT_WEIGHT * threat
		)
		if score < best_score:
			best_score = score
			best = enemy
	return best


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
			if node.has_method("get_lock_priority"):
				if float(node.call("get_lock_priority")) < 0.0:
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


static func get_target_height(target: Node3D) -> float:
	if target == null or not is_instance_valid(target):
		return 1.8
	var visual := target.get_node_or_null("DioramaVisual") as Node3D
	var aabb := _mesh_aabb_from_root(visual if visual else target)
	if aabb.size.y > 0.01:
		return aabb.size.y
	return 1.8


static func _mesh_aabb_from_root(root: Node) -> AABB:
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
		return combined
	return AABB()


static func _aim_point_from_meshes(root: Node) -> Vector3:
	var combined := _mesh_aabb_from_root(root)
	if combined.size.length_squared() > 0.0001:
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


func _is_ui_focused() -> bool:
	if PlayerControls and PlayerControls.is_inventory_open():
		return true
	var focus := get_viewport().gui_get_focus_owner()
	return focus != null and focus is Control
