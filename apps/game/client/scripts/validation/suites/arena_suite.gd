extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "arena"


func run() -> void:
	await _test_training_arena()
	_test_arena_reset_api()


func _test_training_arena() -> void:
	var start := Time.get_ticks_msec()
	var arena: Node3D = load("res://scenes/debug/combat_arena.tscn").instantiate() as Node3D
	ctx.owner.add_child(arena)
	await ctx.await_frame()
	var grunt := arena.get_node_or_null("TrainingGrunt")
	ctx.timed_record(
		"arena.training_grunt_present",
		get_category(),
		grunt != null,
		"combat arena has training grunt",
		start,
		"M1.arena.grunt"
	)

	if grunt:
		start = Time.get_ticks_msec()
		await ctx.await_frame()
		ctx.timed_record(
			"arena.grunt_hp_bar",
			get_category(),
			grunt.get_node_or_null("HealthBar") != null,
			"training grunt has HealthBar node after _ready",
			start,
			"M1.arena.hp_bar"
		)

	start = Time.get_ticks_msec()
	var hub_return := arena.get_node_or_null("HubReturn/InteractArea")
	ctx.timed_record(
		"arena.hub_return_area",
		get_category(),
		hub_return != null,
		"combat arena has hub return interact area",
		start,
		"M1.arena.hub_return"
	)
	arena.queue_free()


func _test_arena_reset_api() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"arena.reset_duel_api",
		get_category(),
		ctx.file_contains("res://scripts/debug/debug_overlay.gd", "func reset_duel"),
		"debug overlay exposes reset_duel() for arena",
		start,
		"M1.arena.reset"
	)
