extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "lock_on"


func run() -> void:
	_test_lock_on_api()
	await _test_lock_on_behavior()


func _test_lock_on_api() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"lock_on.center_aim_api",
		get_category(),
		ctx.file_contains("res://scripts/camera/lock_on.gd", "func get_target_aim_point"),
		"LockOn exposes centered aim point helper",
		start,
		"M3.lock_on.aim_api"
	)


func _test_lock_on_behavior() -> void:
	var grunt_scene: PackedScene = load("res://scenes/enemies/training_grunt.tscn")
	if grunt_scene == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.auto_advance_on_death",
			get_category(),
			false,
			"missing training_grunt scene for lock-on test",
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
	await ctx.await_physics(2)

	if lock_on == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.auto_advance_on_death",
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

	var start := Time.get_ticks_msec()
	var aim_point := LockOn.get_target_aim_point(enemy_a)
	var uses_mesh_center := aim_point.distance_to(enemy_a.global_position + Vector3(0.0, 1.5, 0.0)) > 0.05
	ctx.timed_record(
		"lock_on.reticle_uses_center",
		get_category(),
		uses_mesh_center,
		"lock aim point uses enemy visual center",
		start,
		"M3.lock_on.reticle"
	)

	lock_on._set_lock(enemy_a)
	var health := enemy_a.get_node_or_null("Health") as Health
	if health == null:
		start = Time.get_ticks_msec()
		ctx.timed_record(
			"lock_on.auto_advance_on_death",
			get_category(),
			false,
			"shield missing Health node",
			start,
			"M3.lock_on.advance"
		)
	else:
		health.take_damage(health.max_health + 10.0)
		await ctx.await_physics(2)
		if lock_on.current_target == enemy_a:
			lock_on._update_lock()
		await ctx.await_physics(1)
		start = Time.get_ticks_msec()
		var advanced := lock_on.is_locked and lock_on.current_target == enemy_b
		ctx.timed_record(
			"lock_on.auto_advance_on_death",
			get_category(),
			advanced,
			"lock advances to nearby enemy when current target dies",
			start,
			"M3.lock_on.advance"
		)

	player.queue_free()
	enemy_a.queue_free()
	enemy_b.queue_free()
