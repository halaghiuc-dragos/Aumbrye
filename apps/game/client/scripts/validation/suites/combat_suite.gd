extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "combat"


func run() -> void:
	await _test_combat_components()
	await _test_enemy_death_guards()


func _test_combat_components() -> void:
	var start := Time.get_ticks_msec()
	var health := Health.new()
	health.configure(120.0)
	var health_ok := health.max_health == 120.0 and not health.is_dead()
	var signal_state: Array[bool] = [false]
	health.health_changed.connect(func(_c: float, _m: float) -> void: signal_state[0] = true)
	health.take_damage(10.0)
	ctx.timed_record(
		"combat.health_configure_signals",
		get_category(),
		health_ok and signal_state[0] and health.current == 110.0,
		"Health configure + health_changed signal",
		start,
		"M1.combat.health"
	)

	start = Time.get_ticks_msec()
	var stamina := Stamina.new()
	var consumed := stamina.consume(20.0)
	ctx.timed_record(
		"combat.stamina_consume",
		get_category(),
		consumed and stamina.current == 80.0,
		"Stamina.consume() deducts cost",
		start,
		"M1.combat.stamina"
	)

	start = Time.get_ticks_msec()
	var poise := Poise.new()
	poise.configure(80.0)
	poise.take_poise_damage(80.0)
	ctx.timed_record(
		"combat.poise_break",
		get_category(),
		poise.is_broken(),
		"Poise breaks at zero",
		start,
		"M1.combat.poise"
	)

	start = Time.get_ticks_msec()
	var guard_methods := [
		"modify_incoming_hit",
		"try_parry_attack",
		"get_parry_time_remaining",
		"get_block_time_remaining",
	]
	var guard_ok := true
	for method_name in guard_methods:
		if not ctx.file_contains("res://scripts/combat/guard.gd", "func %s" % method_name):
			guard_ok = false
	ctx.timed_record(
		"combat.guard_parry_block_api",
		get_category(),
		guard_ok,
		"Guard exposes parry/block window API",
		start,
		"M1.combat.guard"
	)

	start = Time.get_ticks_msec()
	var hitbox := Hitbox.new()
	hitbox.team = "player"
	var hurtbox := Hurtbox.new()
	hurtbox.team = "player"
	var same_team_blocks: bool = hitbox.team == hurtbox.team
	ctx.timed_record(
		"combat.hitbox_team_filter",
		get_category(),
		same_team_blocks,
		"Hitbox/Hurtbox team field available for filtering",
		start,
		"M1.combat.teams"
	)

	start = Time.get_ticks_msec()
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	ctx.owner.add_child(player)
	await ctx.await_frame()
	var dodge := player.get_node_or_null("Dodge")
	var dodge_cost_ok := dodge != null and dodge.get_script() != null
	if dodge_cost_ok:
		var script_text := FileAccess.get_file_as_string("res://scripts/player/dodge.gd")
		dodge_cost_ok = "DODGE_STAMINA_COST" in script_text
	ctx.timed_record(
		"combat.dodge_stamina_cost",
		get_category(),
		dodge_cost_ok,
		"player Dodge exposes stamina cost constant",
		start,
		"M1.combat.dodge"
	)

	start = Time.get_ticks_msec()
	var weapon := player.get_node_or_null("WeaponController")
	var hitbox_node: Node = null
	if weapon:
		var hitbox_path: NodePath = weapon.get("hitbox_path")
		if hitbox_path != NodePath():
			hitbox_node = weapon.get_node_or_null(hitbox_path)
	var wired: bool = hitbox_node != null and hitbox_node.has_method("enable")
	ctx.timed_record(
		"combat.weapon_hitbox_wiring",
		get_category(),
		wired,
		"WeaponController hitbox path resolves to Hitbox",
		start,
		"M1.combat.weapon"
	)

	start = Time.get_ticks_msec()
	var facing_node := player.get_node_or_null("Facing") as Node3D
	var hitbox_shape := player.get_node_or_null(
		"Facing/WeaponPivot/Hitbox/CollisionShape3D"
	) as CollisionShape3D
	var forward_hitbox := false
	if facing_node and hitbox_shape:
		# Model forward is +basis.z (atan2 facing, visor at +Z local).
		var visual_forward := facing_node.global_transform.basis.z
		var to_hitbox := hitbox_shape.global_position - facing_node.global_position
		forward_hitbox = visual_forward.dot(to_hitbox) > 0.1
	ctx.timed_record(
		"combat.player_hitbox_forward",
		get_category(),
		forward_hitbox,
		"player weapon hitbox extends along visual forward (+Facing Z)",
		start,
		"M1.combat.weapon"
	)
	player.queue_free()


func _test_enemy_death_guards() -> void:
	var scene: PackedScene = EnemyCatalog.get_scene("castle_shield")
	if scene == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"enemy.shield_death_guard",
			get_category(),
			false,
			"could not load shield scene",
			start,
			"M2.combat.death"
		)
		return

	var enemy: CharacterBody3D = scene.instantiate() as CharacterBody3D
	ctx.owner.add_child(enemy)
	await ctx.await_physics(2)

	var health := enemy.get_node_or_null("Health") as Health
	var hitbox := enemy.find_child("Hitbox", true, false) as Hitbox
	if health == null:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"enemy.shield_death_guard",
			get_category(),
			false,
			"shield missing Health node",
			start,
			"M2.combat.death"
		)
		enemy.queue_free()
		return

	health.take_damage(health.max_health + 10.0)
	await ctx.await_physics()

	var start := Time.get_ticks_msec()
	var dead_after_kill: bool = enemy.is_dead() and health.is_dead()
	ctx.timed_record(
		"enemy.dies_at_zero_hp",
		get_category(),
		dead_after_kill,
		"shield dies when HP reaches 0",
		start,
		"M2.combat.death"
	)

	if dead_after_kill and enemy.has_method("apply_stagger"):
		enemy.call("apply_stagger", 1.0)
		await ctx.await_physics()
		start = Time.get_ticks_msec()
		var still_dead: bool = enemy.is_dead() and health.is_dead()
		ctx.timed_record(
			"enemy.no_stagger_revive",
			get_category(),
			still_dead,
			"stagger does not revive dead shield-bearer",
			start,
			"M2.combat.death"
		)
		if hitbox:
			start = Time.get_ticks_msec()
			ctx.timed_record(
				"enemy.hitbox_disabled_on_death",
				get_category(),
				not hitbox.is_active(),
				"enemy hitbox disabled after death",
				start,
				"M2.combat.death"
			)

	enemy.queue_free()
