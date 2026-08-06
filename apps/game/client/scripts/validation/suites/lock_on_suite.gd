extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "lock_on"


func run() -> void:
	await _test_lock_on_aim_runtime()
	await _test_fp_lock_policy()
	await _test_lock_on_behavior()
	await _test_lock_on_advance_on_death()
	_test_lock_on_movement()
	await _test_lock_on_camera()


func _test_lock_on_aim_runtime() -> void:
	var grunt_scene: PackedScene = load("res://scenes/enemies/training_grunt.tscn")
	if grunt_scene == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.center_aim_api",
			get_category(),
			false,
			"missing training_grunt scene for lock-on aim test",
			start,
			"M3.lock_on.aim_api"
		)
		return

	var enemy := grunt_scene.instantiate() as CharacterBody3D
	ctx.owner.add_child(enemy)
	enemy.global_position = Vector3(3.0, 0.0, 0.0)
	await ctx.await_physics(2)
	var aim_point := LockOn.get_target_aim_point(enemy)
	var start := Time.get_ticks_msec()
	ctx.assert_true(
		"lock_on.center_aim_api",
		get_category(),
		_aim_point_in_visual_bounds(enemy, aim_point),
		"lock aim point lies inside target visual bounds",
		start,
		"M3.lock_on.aim_api"
	)
	enemy.queue_free()


func _test_fp_lock_policy() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var enemy: CharacterBody3D = (
		load("res://scenes/enemies/training_grunt.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	ctx.owner.add_child(enemy)
	player.global_position = Vector3.ZERO
	enemy.global_position = Vector3(4.0, 0.0, 0.0)
	enemy.add_to_group("lockable")
	await ctx.await_physics(2)

	var spring := player.get_node_or_null("CameraPivot/SpringArm3D")
	var lock_on := player.get_node_or_null("LockOn") as LockOn
	var start := Time.get_ticks_msec()
	if spring == null or lock_on == null:
		ctx.timed_record(
			"lock_on.fp_policy",
			get_category(),
			false,
			"player missing camera spring or LockOn node",
			start,
			"B05.lock_on.fp"
		)
		player.queue_free()
		enemy.queue_free()
		return

	if spring.has_method("apply_state"):
		spring.call("apply_state", {"firstPerson": true})
	lock_on.request_lock(enemy)
	for _i in 30:
		await ctx.await_physics()
	var camera := spring.get_node_or_null("Camera3D") as Camera3D
	var tracks_target := false
	if camera:
		var aim := LockOn.get_target_aim_point(enemy)
		var to_target := aim - camera.global_position
		var cam_forward := -camera.global_transform.basis.z
		if to_target.length_squared() > 0.01 and cam_forward.length_squared() > 0.01:
			tracks_target = rad_to_deg(cam_forward.angle_to(to_target.normalized())) <= 2.0
	ctx.assert_true(
		"lock_on.fp_policy",
		get_category(),
		tracks_target,
		"first-person lock-on camera tracks target within 2 degrees",
		start,
		"B05.lock_on.fp"
	)
	player.queue_free()
	enemy.queue_free()


func _test_lock_on_behavior() -> void:
	var grunt_scene: PackedScene = load("res://scenes/enemies/training_grunt.tscn")
	if grunt_scene == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.reticle_uses_center.missing_scene",
			get_category(),
			false,
			"missing training_grunt scene for lock-on test",
			start,
			"M3.lock_on.reticle"
		)
	else:
		var enemy := grunt_scene.instantiate() as CharacterBody3D
		ctx.owner.add_child(enemy)
		enemy.global_position = Vector3(3.0, 0.0, 0.0)
		await ctx.await_physics(2)
		var start := Time.get_ticks_msec()
		var aim_point := LockOn.get_target_aim_point(enemy)
		var uses_mesh_center := (
			aim_point.distance_to(enemy.global_position + Vector3(0.0, 1.5, 0.0)) > 0.05
		)
		ctx.timed_record(
			"lock_on.reticle_uses_center.mesh_center",
			get_category(),
			uses_mesh_center,
			"lock aim point uses enemy visual center",
			start,
			"M3.lock_on.reticle"
		)
		enemy.queue_free()


func _test_lock_on_advance_on_death() -> void:
	var grunt_scene: PackedScene = load("res://scenes/enemies/castle_grunt.tscn")
	if grunt_scene == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.auto_advance_on_death.missing_scene",
			get_category(),
			false,
			"missing castle_grunt scene for lock-on test",
			start,
			"M3.lock_on.advance"
		)
		return

	var player: Node3D = load("res://scenes/player/player.tscn").instantiate() as Node3D
	ctx.owner.add_child(player)
	player.global_position = Vector3.ZERO
	var lock_on := player.get_node_or_null("LockOn") as LockOn
	var enemy_a: CharacterBody3D = grunt_scene.instantiate() as CharacterBody3D
	var enemy_b: CharacterBody3D = grunt_scene.instantiate() as CharacterBody3D
	ctx.owner.add_child(enemy_a)
	ctx.owner.add_child(enemy_b)
	enemy_a.global_position = Vector3(3.0, 0.0, 0.0)
	enemy_b.global_position = Vector3(5.0, 0.0, 0.0)
	enemy_a.add_to_group("lockable")
	enemy_b.add_to_group("lockable")
	await ctx.await_physics(2)

	if lock_on == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.auto_advance_on_death.missing_lock_on",
			get_category(),
			false,
			"player missing LockOn node",
			start,
			"M3.lock_on.advance"
		)
		player.queue_free()
		enemy_a.queue_free()
		enemy_b.queue_free()
		return

	lock_on.request_lock(enemy_a)
	var health := enemy_a.get_node_or_null("Health") as Health
	if health == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.auto_advance_on_death.missing_health",
			get_category(),
			false,
			"enemy missing Health node",
			start,
			"M3.lock_on.advance"
		)
	else:
		health.take_damage(health.max_health + 10.0)
		await ctx.await_physics(2)
		await ctx.await_physics(1)
		var start := Time.get_ticks_msec()
		var advanced := lock_on.is_locked and lock_on.current_target == enemy_b
		ctx.timed_record(
			"lock_on.auto_advance_on_death.advances",
			get_category(),
			advanced,
			"lock advances to nearby enemy when current target dies",
			start,
			"M3.lock_on.advance"
		)

	player.queue_free()
	enemy_a.queue_free()
	enemy_b.queue_free()


func _aim_point_in_visual_bounds(enemy: Node3D, aim_point: Vector3) -> bool:
	var visual := enemy.get_node_or_null("DioramaVisual") as Node3D
	if visual == null:
		return false
	var combined := AABB()
	var found := false
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh := node as MeshInstance3D
		if mesh == null or not mesh.visible:
			continue
		var local_aabb := mesh.get_aabb()
		if local_aabb.size.length_squared() < 0.0001:
			continue
		var global_aabb := mesh.global_transform * local_aabb
		if not found:
			combined = global_aabb
			found = true
		else:
			combined = combined.merge(global_aabb)
	if not found:
		return false
	return combined.has_point(aim_point)


func _test_lock_on_movement() -> void:
	_test_lock_on_movement_retreat_not_corrected()
	_test_lock_on_movement_orbit_correction_deadband()
	_test_lock_on_movement_orbit_correction_outward_scaled()
	_test_lock_on_movement_analog_orbit_magnitude()
	_test_lock_on_movement_approach_is_radial()
	_test_lock_on_movement_orbit_radius_per_target()
	_test_lock_on_movement_locked_speed_scales()
	_test_lock_on_movement_sprint_breaks_lock()
	_test_lock_on_movement_facing_turn_rate()
	_test_lock_on_movement_world_direction_round_trip()


func _test_lock_on_movement_retreat_not_corrected() -> void:
	var player := Node3D.new()
	var enemy := Node3D.new()
	var lock_on := LockOn.new()
	lock_on.current_target = enemy
	lock_on.is_locked = true
	player.global_position = Vector3(1.75, 0.0, 0.0)
	enemy.global_position = Vector3.ZERO
	var velocity := Vector3(-0.5, 0.0, 0.5)
	var start := Time.get_ticks_msec()
	var result := LockOnMovement.apply_orbit_radius_correction(
		player, lock_on, Vector2(-0.7, 0.7), velocity, 1.0 / 60.0
	)
	ctx.assert_eq(
		"lock_on_movement.retreat_not_corrected",
		get_category(),
		result,
		velocity,
		"retreat diagonal at orbit radius is not corrected",
		start,
		"LKM-01"
	)
	player.queue_free()
	enemy.queue_free()
	lock_on.queue_free()


func _test_lock_on_movement_orbit_correction_deadband() -> void:
	var player := Node3D.new()
	var enemy := Node3D.new()
	var lock_on := LockOn.new()
	lock_on.current_target = enemy
	lock_on.is_locked = true
	enemy.global_position = Vector3.ZERO
	var velocity := Vector3(1.0, 0.0, 0.0)
	var start := Time.get_ticks_msec()
	player.global_position = Vector3(1.9, 0.0, 0.0)
	var near := LockOnMovement.apply_orbit_radius_correction(
		player, lock_on, Vector2(1.0, 0.0), velocity, 1.0 / 60.0
	)
	ctx.assert_eq(
		"lock_on_movement.orbit_correction_deadband",
		get_category(),
		near,
		velocity,
		"radius error inside deadband applies no correction",
		start,
		"LKM-01"
	)
	player.global_position = Vector3(2.4, 0.0, 0.0)
	var far := LockOnMovement.apply_orbit_radius_correction(
		player, lock_on, Vector2(1.0, 0.0), velocity, 1.0 / 60.0
	)
	ctx.assert_true(
		"lock_on_movement.orbit_correction_inward",
		get_category(),
		far.x < velocity.x,
		"radius error outside deadband applies inward correction",
		start,
		"LKM-01"
	)
	player.queue_free()
	enemy.queue_free()
	lock_on.queue_free()


func _test_lock_on_movement_orbit_correction_outward_scaled() -> void:
	var player := Node3D.new()
	var enemy := Node3D.new()
	var lock_on := LockOn.new()
	lock_on.current_target = enemy
	lock_on.is_locked = true
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(1.2, 0.0, 0.0)
	var velocity := Vector3(1.0, 0.0, 0.0)
	var start := Time.get_ticks_msec()
	var outward := LockOnMovement.apply_orbit_radius_correction(
		player, lock_on, Vector2(1.0, 0.0), velocity, 1.0 / 60.0
	)
	player.global_position = Vector3(2.3, 0.0, 0.0)
	var inward := LockOnMovement.apply_orbit_radius_correction(
		player, lock_on, Vector2(1.0, 0.0), velocity, 1.0 / 60.0
	)
	var outward_delta := (outward - velocity).length()
	var inward_delta := (inward - velocity).length()
	ctx.assert_near(
		"lock_on_movement.orbit_correction_outward_scaled",
		get_category(),
		outward_delta,
		inward_delta * LockOnMovement.ORBIT_CORRECTION_OUTWARD_SCALE,
		0.02,
		"outward correction is quartered relative to mirrored inward correction",
		start,
		"LKM-08"
	)
	player.queue_free()
	enemy.queue_free()
	lock_on.queue_free()


func _test_lock_on_movement_analog_orbit_magnitude() -> void:
	var start := Time.get_ticks_msec()
	ctx.assert_near(
		"lock_on_movement.analog_orbit_magnitude_partial",
		get_category(),
		LockOnMovement.orbit_component_magnitude(0.2),
		0.2,
		0.01,
		"20 percent stick tilt keeps 20 percent orbit magnitude",
		start,
		"LKM-05"
	)
	ctx.assert_near(
		"lock_on_movement.analog_orbit_magnitude_deadzone",
		get_category(),
		LockOnMovement.orbit_component_magnitude(0.1),
		0.0,
		0.001,
		"10 percent stick tilt is inside orbit deadzone",
		start,
		"LKM-05"
	)


func _test_lock_on_movement_approach_is_radial() -> void:
	var player := Node3D.new()
	var enemy := Node3D.new()
	var lock_on := LockOn.new()
	lock_on.current_target = enemy
	lock_on.is_locked = true
	enemy.global_position = Vector3.ZERO
	player.global_position = Vector3(0.0, 0.0, 2.0)
	var camera_yaw := Node3D.new()
	camera_yaw.rotation.y = deg_to_rad(40.0)
	player.add_child(camera_yaw)
	var direction := LockOnMovement.get_move_direction(
		player,
		lock_on,
		Vector2(0.0, 1.0),
		func(input_dir: Vector2) -> Vector3:
			var yaw_basis := Basis(Vector3.UP, camera_yaw.rotation.y)
			return (yaw_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	)
	var toward_target := (enemy.global_position - player.global_position).normalized()
	var start := Time.get_ticks_msec()
	ctx.assert_true(
		"lock_on_movement.approach_is_radial",
		get_category(),
		direction.dot(toward_target) > 0.99,
		"locked forward input tracks the target radially",
		start,
		"LKM-06"
	)
	player.queue_free()
	enemy.queue_free()
	lock_on.queue_free()


func _test_lock_on_movement_orbit_radius_per_target() -> void:
	var stub_script: Script = load("res://scripts/validation/suites/lock_on_orbit_radius_stub.gd")
	var stub: Node3D = stub_script.new() as Node3D
	var start := Time.get_ticks_msec()
	ctx.assert_near(
		"lock_on_movement.orbit_radius_per_target_custom",
		get_category(),
		LockOnMovement.get_orbit_radius(null, stub),
		4.8,
		0.001,
		"target get_lock_orbit_radius is respected",
		start,
		"LKM-04"
	)
	stub.queue_free()
	var fallback := Node3D.new()
	ctx.assert_near(
		"lock_on_movement.orbit_radius_per_target_default",
		get_category(),
		LockOnMovement.get_orbit_radius(null, fallback),
		LockOnMovement.DEFAULT_ORBIT_RADIUS,
		0.001,
		"targets without get_lock_orbit_radius use the default radius",
		start,
		"LKM-04"
	)
	fallback.queue_free()


func _test_lock_on_movement_locked_speed_scales() -> void:
	var start := Time.get_ticks_msec()
	ctx.assert_near(
		"lock_on_movement.locked_speed_approach",
		get_category(),
		LockOnMovement.get_locked_speed_scale(Vector2(0.0, 1.0)),
		LockOnMovement.LOCKED_SPEED_APPROACH,
		0.001,
		"locked approach uses approach scale",
		start,
		"LKM-03"
	)
	ctx.assert_near(
		"lock_on_movement.locked_speed_orbit",
		get_category(),
		LockOnMovement.get_locked_speed_scale(Vector2(1.0, 0.0)),
		LockOnMovement.LOCKED_SPEED_ORBIT,
		0.001,
		"locked orbit uses orbit scale",
		start,
		"LKM-03"
	)
	ctx.assert_near(
		"lock_on_movement.locked_speed_retreat",
		get_category(),
		LockOnMovement.get_locked_speed_scale(Vector2(0.0, -1.0)),
		LockOnMovement.LOCKED_SPEED_RETREAT,
		0.001,
		"locked retreat uses retreat scale",
		start,
		"LKM-03"
	)


func _test_lock_on_movement_sprint_breaks_lock() -> void:
	var lock_on := LockOn.new()
	lock_on.is_locked = true
	lock_on.current_target = Node3D.new()
	var start := Time.get_ticks_msec()
	var sprinting := LockOnMovement.break_lock_on_sprint(lock_on, true)
	ctx.assert_true(
		"lock_on_movement.sprint_breaks_lock",
		get_category(),
		not lock_on.is_locked and not sprinting,
		"sprint while locked breaks the lock",
		start,
		"LKM-03"
	)
	lock_on.queue_free()


func _test_lock_on_movement_facing_turn_rate() -> void:
	var body := Node3D.new()
	ctx.owner.add_child(body)
	var facing := Node3D.new()
	body.add_child(facing)
	var target := Node3D.new()
	ctx.owner.add_child(target)
	target.global_position = Vector3(0.0, 0.0, -1.0)
	facing.global_position = Vector3.ZERO
	facing.rotation.y = deg_to_rad(10.0)
	var start := Time.get_ticks_msec()
	for _i in 19:
		LockOnMovement.update_facing_toward_target(facing, target, 1.0 / 60.0)
	var aim := LockOn.get_target_aim_point(target)
	var to_target := aim - facing.global_position
	to_target.y = 0.0
	var target_angle := LockOnMovement.world_direction_to_local_facing_y(body, to_target)
	var error_deg := absf(rad_to_deg(angle_difference(facing.rotation.y, target_angle)))
	ctx.assert_true(
		"lock_on_movement.facing_turn_rate",
		get_category(),
		error_deg <= LockOnMovement.FACING_SNAP_DEG,
		"170 degree facing correction completes within 19 frames at 60 FPS",
		start,
		"LKM-07"
	)
	facing.queue_free()
	body.queue_free()
	target.queue_free()


func _test_lock_on_movement_world_direction_round_trip() -> void:
	var body := Node3D.new()
	body.rotation.y = 0.0
	var world_dir := Vector3(0.2, 0.0, 0.9).normalized()
	var start := Time.get_ticks_msec()
	var local_yaw := LockOnMovement.world_direction_to_local_facing_y(body, world_dir)
	var rebuilt := Vector3(sin(local_yaw), 0.0, cos(local_yaw))
	ctx.assert_near(
		"lock_on_movement.world_direction_to_local_facing_y",
		get_category(),
		rebuilt.dot(world_dir),
		1.0,
		0.01,
		"world direction converts to local facing yaw and back",
		start,
		"LKM-02"
	)
	body.rotation.y = PI / 3.0
	local_yaw = LockOnMovement.world_direction_to_local_facing_y(body, world_dir)
	rebuilt = Vector3(sin(local_yaw + body.rotation.y), 0.0, cos(local_yaw + body.rotation.y))
	ctx.assert_near(
		"lock_on_movement.world_direction_to_local_facing_y_yawed",
		get_category(),
		Vector3(rebuilt.x, 0.0, rebuilt.z).normalized().dot(world_dir),
		1.0,
		0.01,
		"world direction round-trip works with body yaw offset",
		start,
		"LKM-02"
	)
	body.queue_free()


func _test_lock_on_camera() -> void:
	await _test_lock_on_camera_first_person_yaw()
	await _test_lock_on_camera_third_person_yaw()
	await _test_lock_on_camera_fp_frame_method()
	await _test_lock_on_camera_zoom_tracks()
	await _test_lock_on_camera_framing_shift()
	await _test_lock_on_camera_pitch_bias()
	await _test_lock_on_camera_acquire_snap()
	await _test_lock_on_camera_occlusion_lift()
	await _test_lock_on_camera_paused_static()


func _spawn_lock_camera_player(enemy_offset: Vector3) -> Dictionary:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var enemy: CharacterBody3D = (
		load("res://scenes/enemies/training_grunt.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	ctx.owner.add_child(enemy)
	player.global_position = Vector3.ZERO
	enemy.global_position = enemy_offset
	enemy.add_to_group("lockable")
	await ctx.await_physics(2)
	return {
		"player": player,
		"enemy": enemy,
		"spring": player.get_node_or_null("CameraPivot/SpringArm3D"),
		"lock_on": player.get_node_or_null("LockOn") as LockOn,
	}


func _camera_faces_target(camera: Camera3D, enemy: Node3D) -> bool:
	if camera == null or enemy == null:
		return false
	var aim := LockOn.get_target_aim_point(enemy)
	var to_target := aim - camera.global_position
	var cam_forward := -camera.global_transform.basis.z
	if to_target.length_squared() <= 0.01 or cam_forward.length_squared() <= 0.01:
		return false
	return cam_forward.dot(to_target.normalized()) > 0.98


func _test_lock_on_camera_first_person_yaw() -> void:
	var setup := await _spawn_lock_camera_player(Vector3(-4.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	if setup.spring == null or setup.lock_on == null:
		ctx.timed_record(
			"lock_on_camera.first_person_yaw_faces_target",
			get_category(),
			false,
			"missing camera spring or LockOn",
			start,
			"LKC-01"
		)
		_cleanup_lock_camera_setup(setup)
		return
	if setup.spring.has_method("apply_state"):
		setup.spring.call("apply_state", {"firstPerson": true})
	setup.lock_on.request_lock(setup.enemy)
	for _i in 30:
		await ctx.await_physics()
	var camera := setup.spring.get_node_or_null("Camera3D") as Camera3D
	ctx.assert_true(
		"lock_on_camera.first_person_yaw_faces_target",
		get_category(),
		_camera_faces_target(camera, setup.enemy),
		"first-person lock-on yaw faces target",
		start,
		"LKC-01"
	)
	_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_third_person_yaw() -> void:
	var setup := await _spawn_lock_camera_player(Vector3(-4.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	if setup.spring == null or setup.lock_on == null:
		ctx.timed_record(
			"lock_on_camera.third_person_yaw_faces_target",
			get_category(),
			false,
			"missing camera spring or LockOn",
			start,
			"LKC-01"
		)
		_cleanup_lock_camera_setup(setup)
		return
	if setup.spring.has_method("apply_state"):
		setup.spring.call("apply_state", {"firstPerson": false})
	setup.lock_on.request_lock(setup.enemy)
	for _i in 30:
		await ctx.await_physics()
	var camera := setup.spring.get_node_or_null("Camera3D") as Camera3D
	ctx.assert_true(
		"lock_on_camera.third_person_yaw_faces_target",
		get_category(),
		_camera_faces_target(camera, setup.enemy),
		"third-person lock-on yaw faces target",
		start,
		"LKC-01"
	)
	_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_fp_frame_method() -> void:
	var script_text := FileAccess.get_file_as_string("res://scripts/camera/orbit_camera.gd")
	var start := Time.get_ticks_msec()
	var has_method := script_text.contains("func _update_lock_on_frame_fp(")
	ctx.assert_true(
		"lock_on_camera.fp_frame_method_exists",
		get_category(),
		has_method,
		"orbit_camera defines _update_lock_on_frame_fp",
		start,
		"LKC-02"
	)
	if not has_method:
		return
	var setup := await _spawn_lock_camera_player(Vector3(4.0, 0.0, 0.0))
	if setup.spring and setup.spring.has_method("apply_state"):
		setup.spring.call("apply_state", {"firstPerson": true})
	if setup.lock_on:
		setup.lock_on.request_lock(setup.enemy)
		await ctx.await_physics()
	var reached_fp := false
	if setup.spring and setup.spring.has_method("update_lock_on_frame"):
		setup.spring.call(
			"update_lock_on_frame",
			LockOn.get_target_aim_point(setup.enemy),
			setup.player.global_position + Vector3(0.0, 1.6, 0.0),
			1.0 / 60.0
		)
		reached_fp = setup.spring.get("_first_person")
	ctx.assert_true(
		"lock_on_camera.fp_frame_method_reached",
		get_category(),
		reached_fp,
		"first-person lock framing path is active",
		start,
		"LKC-02"
	)
	_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_zoom_tracks() -> void:
	var pairs := [[4.0, 1.8, 5.0], [8.0, 4.0, 6.6]]
	for pair in pairs:
		var planar_dist: float = pair[0]
		var target_height: float = pair[1]
		var expected_zoom: float = pair[2]
		var setup := await _spawn_lock_camera_player(Vector3(planar_dist, 0.0, 0.0))
		var start := Time.get_ticks_msec()
		if setup.spring == null or setup.lock_on == null:
			ctx.timed_record(
				"lock_on_camera.zoom_tracks_distance_and_size",
				get_category(),
				false,
				"missing camera spring or LockOn",
				start,
				"LKC-03"
			)
			_cleanup_lock_camera_setup(setup)
			continue
		if setup.spring.has_method("set_lock_target_height"):
			setup.spring.call("set_lock_target_height", target_height)
		if setup.spring.has_method("set_lock_on_active"):
			setup.spring.call("set_lock_on_active", true)
		var aim := LockOn.get_target_aim_point(setup.enemy)
		var eye: Vector3 = setup.player.global_position + Vector3(0.0, 1.6, 0.0)
		for _i in 60:
			setup.spring.call("update_lock_on_frame", aim, eye, 1.0 / 60.0)
			await ctx.await_physics()
		var settled := float(setup.spring.get("spring_length"))
		ctx.assert_near(
			"lock_on_camera.zoom_tracks_distance_and_size",
			get_category(),
			settled,
			expected_zoom,
			0.15,
			"lock zoom settles for dist %.1f height %.1f" % [planar_dist, target_height],
			start,
			"LKC-03"
		)
		_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_framing_shift() -> void:
	var setup := await _spawn_lock_camera_player(Vector3(6.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	if setup.spring == null:
		ctx.timed_record(
			"lock_on_camera.framing_shift_scales_with_height",
			get_category(),
			false,
			"missing camera spring",
			start,
			"LKC-04"
		)
		_cleanup_lock_camera_setup(setup)
		return
	var aim := LockOn.get_target_aim_point(setup.enemy)
	var eye: Vector3 = setup.player.global_position + Vector3(0.0, 1.6, 0.0)
	setup.spring.call("set_lock_on_active", true)
	setup.spring.call("set_lock_target_height", 1.8)
	for _i in 30:
		setup.spring.call("update_lock_on_frame", aim, eye, 1.0 / 60.0)
		await ctx.await_physics()
	var small_shift := (setup.spring.get("_lock_pivot_offset") as Vector3).length()
	setup.spring.call("set_lock_target_height", 4.0)
	for _i in 30:
		setup.spring.call("update_lock_on_frame", aim, eye, 1.0 / 60.0)
		await ctx.await_physics()
	var large_shift := (setup.spring.get("_lock_pivot_offset") as Vector3).length()
	ctx.assert_true(
		"lock_on_camera.framing_shift_scales_with_height",
		get_category(),
		large_shift > small_shift,
		"taller target gets larger framing shift at same distance",
		start,
		"LKC-04"
	)
	_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_pitch_bias() -> void:
	var setup := await _spawn_lock_camera_player(Vector3(4.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	if setup.spring == null:
		ctx.timed_record(
			"lock_on_camera.pitch_bias_single_clamp",
			get_category(),
			false,
			"missing camera spring",
			start,
			"LKC-08"
		)
		_cleanup_lock_camera_setup(setup)
		return
	setup.spring.call("set_lock_on_active", true)
	var max_bias := float(setup.spring.get("LOCK_PITCH_BIAS_MAX"))
	for _i in 120:
		setup.spring.call("_apply_lock_pitch_look", 0.05)
		await ctx.await_physics()
	var clamped := absf(float(setup.spring.get("_lock_pitch_bias"))) <= max_bias + 0.001
	for _i in 60:
		await ctx.await_physics()
	var decayed := absf(float(setup.spring.get("_lock_pitch_bias"))) < deg_to_rad(1.0)
	ctx.assert_true(
		"lock_on_camera.pitch_bias_single_clamp",
		get_category(),
		clamped and decayed,
		"mouse pitch bias uses single clamp and decays after release",
		start,
		"LKC-08"
	)
	_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_acquire_snap() -> void:
	var setup := await _spawn_lock_camera_player(Vector3(-6.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	if setup.spring == null or setup.lock_on == null:
		ctx.timed_record(
			"lock_on_camera.acquire_snap_window",
			get_category(),
			false,
			"missing camera spring or LockOn",
			start,
			"LKC-07"
		)
		_cleanup_lock_camera_setup(setup)
		return
	setup.lock_on.request_lock(setup.enemy)
	var frames := int(0.18 / (1.0 / 60.0))
	for _i in frames:
		await ctx.await_physics()
	var camera := setup.spring.get_node_or_null("Camera3D") as Camera3D
	var yaw_ok := _camera_faces_target(camera, setup.enemy)
	ctx.assert_true(
		"lock_on_camera.acquire_snap_window",
		get_category(),
		yaw_ok,
		"lock acquire swing completes within 0.18 s",
		start,
		"LKC-07"
	)
	_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_occlusion_lift() -> void:
	var setup := await _spawn_lock_camera_player(Vector3(4.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	if setup.spring == null or setup.lock_on == null:
		ctx.timed_record(
			"lock_on_camera.occlusion_lifts_before_break",
			get_category(),
			false,
			"missing camera spring or LockOn",
			start,
			"LKC-10"
		)
		_cleanup_lock_camera_setup(setup)
		return
	setup.lock_on.request_lock(setup.enemy)
	await ctx.await_physics()
	setup.spring.call("on_lock_occluded", true)
	for _i in 30:
		await ctx.await_physics()
	var lifted := float(setup.spring.get("_lock_occlusion_blend")) > 0.1
	var still_locked: bool = setup.lock_on.is_locked
	setup.spring.call("on_lock_occluded", false)
	for _i in 30:
		await ctx.await_physics()
	var cleared := float(setup.spring.get("_lock_occlusion_blend")) < 0.05
	ctx.assert_true(
		"lock_on_camera.occlusion_lifts_before_break",
		get_category(),
		lifted and still_locked and cleared,
		"occlusion recovery lifts camera and clears after line of sight returns",
		start,
		"LKC-10"
	)
	_cleanup_lock_camera_setup(setup)


func _test_lock_on_camera_paused_static() -> void:
	var setup := await _spawn_lock_camera_player(Vector3(4.0, 0.0, 0.0))
	var start := Time.get_ticks_msec()
	if setup.spring == null or setup.lock_on == null:
		ctx.timed_record(
			"lock_on_camera.paused_camera_static",
			get_category(),
			false,
			"missing camera spring or LockOn",
			start,
			"LKC-09"
		)
		_cleanup_lock_camera_setup(setup)
		return
	setup.lock_on.request_lock(setup.enemy)
	await ctx.await_physics()
	var before: Transform3D = setup.spring.global_transform
	ctx.owner.get_tree().paused = true
	for _i in 10:
		await ctx.await_physics()
	ctx.owner.get_tree().paused = false
	var after: Transform3D = setup.spring.global_transform
	var unchanged: bool = before.is_equal_approx(after)
	ctx.assert_true(
		"lock_on_camera.paused_camera_static",
		get_category(),
		unchanged,
		"locked camera transform is unchanged while paused",
		start,
		"LKC-09"
	)
	_cleanup_lock_camera_setup(setup)


func _cleanup_lock_camera_setup(setup: Dictionary) -> void:
	if setup.has("player") and is_instance_valid(setup.player):
		setup.player.queue_free()
	if setup.has("enemy") and is_instance_valid(setup.enemy):
		setup.enemy.queue_free()
