extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "player"


func run() -> void:
	await _test_player_apis()


func _test_player_apis() -> void:
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	ctx.owner.add_child(player)
	await ctx.await_physics(2)

	var start := Time.get_ticks_msec()
	var locomotion := player as CharacterBody3D
	var has_facing_yaw := locomotion.has_method("get_facing_yaw")
	var yaw := 0.0
	if has_facing_yaw:
		yaw = locomotion.call("get_facing_yaw")
	ctx.timed_record(
		"player.facing_yaw_api",
		get_category(),
		has_facing_yaw and is_finite(yaw),
		"player locomotion exposes get_facing_yaw()",
		start,
		"M1.player.locomotion"
	)

	start = Time.get_ticks_msec()
	var has_facing_dir := locomotion.has_method("get_facing_direction")
	ctx.timed_record(
		"player.facing_direction_api",
		get_category(),
		has_facing_dir,
		"player locomotion exposes get_facing_direction()",
		start,
		"M1.player.locomotion"
	)

	start = Time.get_ticks_msec()
	var script_text := FileAccess.get_file_as_string("res://scripts/player/locomotion.gd")
	var sprint_ok := "SPRINT_SPEED" in script_text and "SPRINT_STAMINA_DRAIN" in script_text
	ctx.timed_record(
		"player.sprint_constants",
		get_category(),
		sprint_ok,
		"locomotion defines sprint speed and stamina drain",
		start,
		"M1.player.sprint"
	)

	start = Time.get_ticks_msec()
	var reactions := player.get_node_or_null("CombatReactions")
	var reactions_ok := reactions != null and reactions.has_method("can_act")
	ctx.timed_record(
		"player.combat_reactions_api",
		get_category(),
		reactions_ok,
		"player has CombatReactions with can_act()",
		start,
		"M1.player.reactions"
	)

	start = Time.get_ticks_msec()
	var weapon := player.get_node_or_null("WeaponController")
	var weapon_data_ok := weapon != null and weapon.has_method("get_debug_state")
	ctx.timed_record(
		"player.weapon_controller_api",
		get_category(),
		weapon_data_ok,
		"WeaponController exposes debug/state API",
		start,
		"M1.combat.weapon"
	)

	player.queue_free()
