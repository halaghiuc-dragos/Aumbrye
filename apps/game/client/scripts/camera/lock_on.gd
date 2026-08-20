extends Node
class_name LockOn

const LOCK_ACQUIRE_RANGE := 18.0
const LOCK_BREAK_RANGE := 22.0
const LOCK_BREAK_GRACE := 0.4
const LOCK_VERTICAL_LIMIT := 8.0
const SCORE_DISTANCE_WEIGHT := 1.0
const SCORE_ANGLE_WEIGHT := 0.75
const SCORE_THREAT_WEIGHT := 0.5
const SCORE_PRIORITY_WEIGHT := 0.5
const SWITCH_COOLDOWN_STICK := 0.15

## Effective ranges, after the accessibility "Lock-On Range" multiplier.
##
## The constants below are the authored baseline; the setting scaled neither of them before, so
## the slider moved without effect. Acquire and break are scaled together so the lock does not
## become easier to gain than to keep.
static func acquire_range() -> float:
	return LOCK_ACQUIRE_RANGE * AccessibilitySettings.lock_on_range_scale()


static func break_range() -> float:
	return LOCK_BREAK_RANGE * AccessibilitySettings.lock_on_range_scale()
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
var _camera_spring: OrbitCamera


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	if player_path:
		_player = get_node_or_null(player_path) as Node3D
	if _player == null and get_parent() is Node3D:
		_player = get_parent() as Node3D
	if facing_path and _player:
		_facing = _player.get_node_or_null(facing_path) as Node3D
	if _player:
		_camera_spring = _player.get_node_or_null("CameraPivot/SpringArm3D") as OrbitCamera


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
	if PlayerInput.is_gameplay_blocked():
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
	# C-18: the explicit-target path used to call `_set_lock` with no range, vertical or
	# line-of-sight check at all, and `_set_lock` did not reset `_break_grace_timer` — so a
	# scripted lock (boss intro, camera state restore) onto a target outside `break_range()` broke
	# on the very first `_update_lock` tick with zero grace, because the timer was still 0 from the
	# previous break. The grace reset moved into `_set_lock`; the range check is here.
	if target != null and is_instance_valid(target):
		if not _is_lock_candidate_valid(target):
			return false
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
	# C-18: a fresh lock starts with a full break grace, not whatever the previous break left.
	_break_grace_timer = LOCK_BREAK_GRACE
	_los_grace_timer = 0.0
	_was_occluded = false
	_target_health = target.get_node_or_null("Health") as Health
	if _target_health and not _target_health.died.is_connected(_on_lock_target_died):
		_target_health.died.connect(_on_lock_target_died)
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
	if planar > break_range():
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
	var blend_boost := 1.0 + _switch_blend_boost * 3.0
	_camera_spring.update_lock_on_frame(aim, player_eye, delta * blend_boost)


func _get_player_eye_position() -> Vector3:
	if _player == null:
		return Vector3.ZERO
	if _camera_spring and _camera_spring.is_first_person():
		var camera := _camera_spring.get_node_or_null("Camera3D") as Camera3D
		if camera:
			return camera.global_position
	return _player.global_position + Vector3(0.0, 1.6, 0.0)


func _set_camera_lock_on_active(active: bool) -> void:
	_resolve_camera_spring()
	if _camera_spring == null:
		return
	_camera_spring.set_lock_on_active(active)
	if not active and _was_occluded:
		_was_occluded = false
		lock_occluded.emit(false)


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
		_camera_spring = _player.get_node_or_null("CameraPivot/SpringArm3D") as OrbitCamera


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
		if distance > acquire_range() or distance < 0.01:
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
		var priority := 0.0
		if enemy.has_method("get_lock_priority"):
			priority = float(enemy.call("get_lock_priority"))
		var score := (
			SCORE_DISTANCE_WEIGHT * (distance / acquire_range())
			+ SCORE_ANGLE_WEIGHT * (angle / LOCK_PICK_CONE_DEG)
			- SCORE_THREAT_WEIGHT * threat
			- SCORE_PRIORITY_WEIGHT * priority
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
	# C-19: this walked the entire `lockable` group on every call to rebuild the defeated-enemy
	# exclude list. `_update_lock` calls it once per physics frame while locked, and
	# `_find_best_target` calls it per candidate, making acquisition O(n^2). The defeated set only
	# changes when something dies or the group changes, so it is cached and invalidated rather
	# than rebuilt.
	var excludes: Array[RID] = _defeated_exclude_rids().duplicate()
	if _player is CollisionObject3D:
		excludes.append((_player as CollisionObject3D).get_rid())
	if target is CollisionObject3D:
		excludes.erase((target as CollisionObject3D).get_rid())
		excludes.append((target as CollisionObject3D).get_rid())
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


## C-82: this ran `find_children("*", "MeshInstance3D", true, false)` — a full subtree walk of the
## enemy rig — on every call, and it is called from the camera's per-frame path *and* from
## `player_anim_director._update_head_look()` every frame: two full-subtree searches per locked
## target per frame. The rig does not change shape between frames, so the aim point is cached as a
## local offset from the target's origin and recomputed at most once per physics frame.
static var _aim_offset_cache: Dictionary = {}
static var _aim_offset_frame: Dictionary = {}


static func get_target_aim_point(target: Node3D) -> Vector3:
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	if target.has_method("get_lock_aim_point"):
		return target.call("get_lock_aim_point")
	var id := target.get_instance_id()
	var frame := Engine.get_physics_frames()
	if int(_aim_offset_frame.get(id, -1)) == frame:
		return target.global_position + (_aim_offset_cache[id] as Vector3)
	var offset := Vector3(0.0, 1.2, 0.0)
	var visual := target.get_node_or_null("DioramaVisual") as Node3D
	var point := Vector3.INF
	if visual:
		point = _aim_point_from_meshes(visual)
	if point == Vector3.INF:
		point = _aim_point_from_meshes(target)
	if point != Vector3.INF:
		offset = point - target.global_position
	_aim_offset_cache[id] = offset
	_aim_offset_frame[id] = frame
	_prune_aim_cache()
	return target.global_position + offset


## Instance ids are never reused within a session, so entries would otherwise accumulate one per
## enemy the player has ever locked. Trimmed when the table grows past a floor's worth.
static func _prune_aim_cache() -> void:
	if _aim_offset_cache.size() <= 64:
		return
	var frame := Engine.get_physics_frames()
	for id in _aim_offset_cache.keys():
		if frame - int(_aim_offset_frame.get(id, 0)) > 600:
			_aim_offset_cache.erase(id)
			_aim_offset_frame.erase(id)


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


## C-17: `"MeshInstance3D"` was in this skip list, but that is Godot's *default* node name and the
## project genuinely uses it (`final_boss_crystal.gd` looks up `get_node_or_null("MeshInstance3D")`).
## Any enemy whose mesh kept the default name was excluded from the aim-point AABB, so
## `get_target_aim_point` fell through to a flat `+1.2 y` offset — which for the small enemies
## (`swamp_leech` at scale 0.6, `crystal_slime` at 0.85) aimed the reticle well above the body.
## Only the telegraph mesh is genuinely not part of the silhouette.
static func _should_skip_lock_aim_mesh(mesh: MeshInstance3D) -> bool:
	match mesh.name:
		"TelegraphMesh":
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


## Cached RIDs of defeated lockables, rebuilt at most once per physics frame (see C-19).
var _defeated_rids: Array[RID] = []
var _defeated_rids_frame := -1


func _defeated_exclude_rids() -> Array[RID]:
	var frame := Engine.get_physics_frames()
	if frame == _defeated_rids_frame:
		return _defeated_rids
	_defeated_rids_frame = frame
	var rids: Array[RID] = []
	for node in get_tree().get_nodes_in_group("lockable"):
		if not (node is CollisionObject3D):
			continue
		if _is_defeated(node):
			rids.append((node as CollisionObject3D).get_rid())
	_defeated_rids = rids
	return _defeated_rids


## C-18: the same gate `_find_best_target` applies, reused for explicitly requested targets.
func _is_lock_candidate_valid(target: Node3D) -> bool:
	if _player == null:
		_resolve_player()
	if _player == null:
		return true
	if _is_defeated(target):
		return false
	var delta := target.global_position - _player.global_position
	var planar := Vector2(delta.x, delta.z).length()
	return planar <= break_range()
