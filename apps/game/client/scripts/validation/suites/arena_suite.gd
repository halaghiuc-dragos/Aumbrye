extends "res://scripts/validation/validation_suite.gd"

const ArenaDioramaScript := preload("res://scripts/debug/arena_diorama.gd")


func get_category() -> String:
	return "arena"


func run() -> void:
	await _test_training_arena()
	await _test_arena_reset_api()
	await _test_training_death_reset()
	await _test_global_player_controls()


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
	var arena: Node3D = load("res://scenes/debug/combat_arena.tscn").instantiate() as Node3D
	ctx.owner.add_child(arena)
	await ctx.await_physics(2)
	var player := arena.get_node_or_null("Player") as CharacterBody3D
	var overlay := arena.get_node_or_null("DebugOverlay")
	var dummy := arena.get_node_or_null("TrainingDummies/TrainingGruntA") as CharacterBody3D
	if player and dummy:
		var player_health := player.get_node_or_null("Health") as Health
		var dummy_health := dummy.get_node_or_null("Health") as Health
		if player_health:
			player_health.take_damage(25.0)
		if dummy_health:
			dummy_health.take_damage(20.0)
		player.global_position = Vector3(2.0, 0.0, 2.0)
	if overlay and overlay.has_method("reset_duel"):
		overlay.call("reset_duel")
	await ctx.await_physics(2)
	var start := Time.get_ticks_msec()
	var reset_ok := false
	if player and dummy:
		var player_health := player.get_node_or_null("Health") as Health
		var dummy_health := dummy.get_node_or_null("Health") as Health
		reset_ok = (
			player_health != null
			and dummy_health != null
			and player_health.current == player_health.max_health
			and dummy_health.current == dummy_health.max_health
			and player.global_position.distance_to(Vector3(-0.02, 0.0, 9.5)) < 0.25
		)
	ctx.timed_record(
		"arena.reset_duel_api",
		get_category(),
		reset_ok,
		"reset_duel restores player and dummy health and position",
		start,
		"M1.arena.reset"
	)
	arena.queue_free()


func _test_training_death_reset() -> void:
	var arena: Node3D = load("res://scenes/debug/combat_arena.tscn").instantiate() as Node3D
	ctx.owner.add_child(arena)
	await ctx.await_physics(2)
	var player := arena.get_node_or_null("Player") as CharacterBody3D
	var start := Time.get_ticks_msec()
	var restored := false
	if player:
		var health := player.get_node_or_null("Health") as Health
		if health:
			health.take_damage(health.max_health + 10.0)
			for _i in 40:
				await ctx.await_physics()
				if not health.is_dead():
					restored = true
					break
	ctx.timed_record(
		"arena.training_death_reset",
		get_category(),
		restored,
		"training arena restores player after death without run penalties",
		start,
		"M1.arena.death_reset"
	)
	arena.queue_free()


func _test_global_player_controls() -> void:
	var start := Time.get_ticks_msec()
	var has_autoload := ProjectSettings.has_setting("autoload/PlayerControls")
	var sync_ok := false
	if has_autoload and PlayerControls:
		var arena: Node3D = load("res://scenes/debug/combat_arena.tscn").instantiate() as Node3D
		ctx.owner.add_child(arena)
		await ctx.await_physics(2)
		PlayerControls.sync_player_loadout()
		await ctx.await_frame()
		var player := arena.get_node_or_null("Player")
		sync_ok = player != null and player.get_node_or_null("WeaponController") != null
		arena.queue_free()
	ctx.timed_record(
		"arena.global_player_controls",
		get_category(),
		has_autoload and sync_ok,
		"training arena uses global player controls autoload",
		start,
		"M1.arena.controls"
	)
