extends Node3D

const LockOnScript := preload("res://scripts/camera/lock_on.gd")
const TARGET_COUNTS := [10, 30, 60]
const FRAMES_PER_PROFILE := 30

var _failures := 0
var _lock_on: LockOn
var _player: Node3D
var _targets: Array[Node3D] = []


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error("Lock-on cache audit: %s" % message)


func _make_target(index: int) -> Node3D:
	var target := Node3D.new()
	target.name = "Lockable%d" % index
	target.position = Vector3(float(index % 8) * 0.3, 0.0, -4.0 - float(index) / 8.0 * 0.2)
	target.add_to_group("lockable")
	var visual := Node3D.new()
	visual.name = "DioramaVisual"
	target.add_child(visual)
	for mesh_index in 4:
		var mesh := MeshInstance3D.new()
		mesh.name = "Mesh%d" % mesh_index
		mesh.mesh = BoxMesh.new()
		mesh.position.y = float(mesh_index)
		visual.add_child(mesh)
	add_child(target)
	return target


func _clear_targets() -> void:
	for target in _targets:
		if is_instance_valid(target):
			target.queue_free()
	_targets.clear()
	await get_tree().physics_frame


func _ready() -> void:
	_player = Node3D.new()
	_player.name = "TargetingPlayer"
	add_child(_player)
	_lock_on = LockOnScript.new() as LockOn
	_lock_on.name = "LockOn"
	add_child(_lock_on)
	_lock_on._player = _player
	await get_tree().physics_frame

	for target_count in TARGET_COUNTS:
		await _clear_targets()
		for index in target_count:
			_targets.append(_make_target(index))
		await get_tree().physics_frame
		var query_usec_total := 0
		var start_mesh_scans := LockOn._aim_mesh_tree_scan_count
		var start_mesh_visits := LockOn._aim_mesh_node_visit_count
		var start_group_scans := int(_lock_on.get("_lockable_group_scan_count"))
		var start_rays := int(_lock_on.get("_line_of_sight_query_count"))
		for _frame in FRAMES_PER_PROFILE:
			await get_tree().physics_frame
			var query_start_usec := Time.get_ticks_usec()
			var selected := _lock_on._find_best_target(true, true)
			query_usec_total += Time.get_ticks_usec() - query_start_usec
			_check(selected != null, "%d-target probe must always select a visible candidate" % target_count)
		var mesh_scans := LockOn._aim_mesh_tree_scan_count - start_mesh_scans
		var mesh_visits := LockOn._aim_mesh_node_visit_count - start_mesh_visits
		var group_scans := int(_lock_on.get("_lockable_group_scan_count")) - start_group_scans
		var ray_queries := int(_lock_on.get("_line_of_sight_query_count")) - start_rays
		_check(mesh_scans == target_count, "%d-target probe scans each stable mesh hierarchy once" % target_count)
		_check(mesh_visits == target_count * 4, "%d-target probe visits each authored mesh once" % target_count)
		_check(group_scans >= 1 and group_scans <= 3, "%d-target probe refreshes lockable membership at the bounded rate" % target_count)
		_check(ray_queries == target_count * FRAMES_PER_PROFILE, "%d-target query performs one LOS ray per candidate" % target_count)
		_check(int(_lock_on.get("_candidate_score_count")) == target_count, "%d-target query scores every in-range candidate once" % target_count)
		print(
			"LOCK-ON PROFILE targets=%d frames=%d mean_query_cpu_us=%.1f mesh_tree_scans=%d mesh_nodes=%d group_scans=%d rays=%d scored=%d"
			% [target_count, FRAMES_PER_PROFILE, float(query_usec_total) / FRAMES_PER_PROFILE, mesh_scans, mesh_visits, group_scans, ray_queries, int(_lock_on.get("_candidate_score_count"))]
		)

	# Cheap cone rejection should happen before the LOS raycast.
	await _clear_targets()
	var on_axis := _make_target(0)
	var off_axis := _make_target(1)
	_targets.append(on_axis)
	_targets.append(off_axis)
	off_axis.global_position = Vector3(12.0, 0.0, -1.0)
	await get_tree().physics_frame
	var rays_before_cone := int(_lock_on.get("_line_of_sight_query_count"))
	var best_in_cone := _lock_on._find_best_target(true, false)
	_check(best_in_cone == on_axis, "off-cone candidates cannot displace the aimed target")
	_check(int(_lock_on.get("_line_of_sight_query_count")) - rays_before_cone == 1, "off-cone candidates are rejected before LOS raycasts")
	
	# Add and remove geometry under an existing target after the stable mesh list was cached.
	await _clear_targets()
	var mutable_target := _make_target(0)
	_targets.append(mutable_target)
	await get_tree().physics_frame
	LockOn.get_target_aim_point(mutable_target)
	await get_tree().physics_frame
	var scans_before_add := LockOn._aim_mesh_tree_scan_count
	var offset_before_add := LockOn.get_target_aim_point(mutable_target) - mutable_target.global_position
	var extra_mesh := MeshInstance3D.new()
	extra_mesh.name = "LateMesh"
	extra_mesh.mesh = BoxMesh.new()
	extra_mesh.position.y = 12.0
	mutable_target.get_node("DioramaVisual").add_child(extra_mesh)
	await get_tree().physics_frame
	var offset_after_add := LockOn.get_target_aim_point(mutable_target) - mutable_target.global_position
	_check(LockOn._aim_mesh_tree_scan_count == scans_before_add + 1, "runtime visual growth invalidates the cached descendant mesh list")
	_check(offset_after_add.y > offset_before_add.y, "newly added visible geometry moves the computed aim point")
	extra_mesh.queue_free()
	await get_tree().physics_frame
	var offset_after_remove := LockOn.get_target_aim_point(mutable_target) - mutable_target.global_position
	_check(offset_after_remove.y < offset_after_add.y, "removed visual geometry no longer affects the aim point")

	# A defeat clears aim data immediately, before lock switching can reuse the cache.
	var health := Health.new()
	health.name = "Health"
	mutable_target.add_child(health)
	await get_tree().physics_frame
	LockOn.get_target_aim_point(mutable_target)
	var previous_auto_switch := AccessibilitySettings.automatic_lock_switch
	AccessibilitySettings.automatic_lock_switch = false
	_lock_on._set_lock(mutable_target)
	health.died.emit()
	AccessibilitySettings.automatic_lock_switch = previous_auto_switch
	_check(not LockOn._aim_offset_cache.has(mutable_target.get_instance_id()), "target defeat immediately clears its cached aim offset")
	_check(not LockOn._aim_mesh_cache.has(mutable_target.get_node("DioramaVisual").get_instance_id()), "target defeat immediately clears its fallback mesh cache")

	await _clear_targets()
	_check(_lock_on._get_registered_lockables().is_empty(), "node removal invalidates cached lockable membership")
	print("LOCK-ON CACHE RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
