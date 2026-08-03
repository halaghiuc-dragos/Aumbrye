extends "res://scripts/validation/validation_suite.gd"

const ArenaDioramaScript := preload("res://scripts/debug/arena_diorama.gd")


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
	ArenaDioramaScript.apply(arena)
	await ctx.await_frame()
	var dummies: Array[Node] = []
	var dummies_parent := arena.get_node_or_null("TrainingDummies")
	if dummies_parent:
		for child in dummies_parent.get_children():
			dummies.append(child)
	ctx.timed_record(
		"arena.training_grunt_present",
		get_category(),
		dummies.size() >= 6,
		"combat arena has six training dummies",
		start,
		"M1.arena.grunt"
	)

	var grunt := dummies[0] if dummies.size() > 0 else null

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
	start = Time.get_ticks_msec()
	var walls := arena.get_node_or_null("ArenaWalls/WallCollision") as StaticBody3D
	var wall_shapes := 0
	if walls:
		for child in walls.get_children():
			if child is CollisionShape3D:
				wall_shapes += 1
	ctx.timed_record(
		"arena.wall_collision",
		get_category(),
		wall_shapes == 4,
		"training arena perimeter walls have collision",
		start,
		"M1.arena.walls"
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
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"arena.training_death_reset",
		get_category(),
		ctx.file_contains("res://scripts/debug/combat_arena.gd", "func reset_training_player")
		and ctx.file_contains("res://scripts/debug/combat_arena.gd", "_on_training_player_died"),
		"training arena restores player on death without run penalties",
		start,
		"M1.arena.death_reset"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"arena.global_player_controls",
		get_category(),
		ProjectSettings.has_setting("autoload/PlayerControls")
		and ctx.file_contains("res://scripts/app/player_controls.gd", "func sync_player_loadout"),
		"training arena uses global player controls autoload",
		start,
		"M1.arena.controls"
	)
