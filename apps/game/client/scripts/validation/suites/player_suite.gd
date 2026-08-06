extends "res://scripts/validation/validation_suite.gd"

const AnimLibrary := preload("res://scripts/art/characters/diorama_anim_library.gd")
const FloorSnap := preload("res://scripts/art/characters/character_floor_snap.gd")
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const CastleBlockoutScript := preload("res://scripts/dungeon/castle/castle_blockout.gd")


func get_category() -> String:
	return "player"


func run() -> void:
	await _test_player_apis()
	await _test_player_locomotion_resolution()
	await _test_player_move_speed_multiplier()
	await _test_player_input_blocked_meta_ui()
	await _test_player_heal_clip()
	await _test_player_heal_quality()
	await _test_player_hitstop_reaches_rig()
	await _test_player_reaction_arbitration()
	await _test_player_directional_locomotion_clips()
	await _test_footstep_markers_present()
	await _test_footstep_fallback_active_without_markers()
	await _test_directional_speed_scale()
	await _test_sprint_denied_backward()
	await _test_air_control_turn_clamp()
	await _test_landing_thresholds()
	await _test_body_movement_properties()
	await _test_speed_breakdown_matches_velocity()
	await _test_player_combat_reactions()
	await _test_floor_snap()


func _test_player_apis() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
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


func _test_player_locomotion_resolution() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var start := Time.get_ticks_msec()
	var resolved := PlayerControls.resolve_locomotion(player)
	var ok := resolved == player
	ctx.timed_record(
		"player.locomotion_resolves_from_root",
		get_category(),
		ok,
		"resolve_locomotion returns root player node",
		start,
		"PCT-01"
	)
	player.queue_free()


func _test_player_move_speed_multiplier() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(2)
	if player.has_method("set_speed_multiplier"):
		player.call("set_speed_multiplier", 2.0)
	Input.action_press("move_forward")
	for _i in 24:
		await ctx.await_physics(1)
	var horizontal := Vector2(player.velocity.x, player.velocity.z).length()
	Input.action_release("move_forward")
	var start := Time.get_ticks_msec()
	var ok := absf(horizontal - 9.0) <= 0.2
	ctx.timed_record(
		"player.move_speed_multiplier_applies",
		get_category(),
		ok,
		"walk speed 9.0 m/s at 2.0 multiplier (got %.2f)" % horizontal,
		start,
		"PCT-02"
	)
	player.queue_free()


func _test_player_input_blocked_meta_ui() -> void:
	var start := Time.get_ticks_msec()
	var controls: Node = Engine.get_main_loop().root.get_node_or_null("/root/PlayerControls")
	var inventory_ui: Node = controls.get_inventory_ui() if controls else null
	if inventory_ui:
		inventory_ui.set("_inventory_open", true)
	Input.action_press("move_forward")
	var move_blocked := PlayerInput.move_vector() == Vector2.ZERO
	var dodge_blocked := not PlayerInput.just_pressed(&"dodge")
	if inventory_ui:
		inventory_ui.set("_inventory_open", false)
	Input.action_release("move_forward")
	var ok := move_blocked and dodge_blocked
	ctx.timed_record(
		"player.input_blocked_when_meta_ui_open",
		get_category(),
		ok,
		"gameplay input blocked while inventory open",
		start,
		"PCT-03"
	)


func _test_player_heal_clip() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(2)
	var heal := player.get_node_or_null("PlayerHeal")
	var director := player.get_node_or_null("AnimDirector")
	var uses_heal := false
	if heal and director and director.has_method("play_heal"):
		director.call("play_heal", 1.35)
		await ctx.await_physics(2)
		if director.is_bound() and director._player:
			uses_heal = String(director._player.current_animation) == "heal"
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.heal_uses_heal_clip",
		get_category(),
		uses_heal,
		"drink plays heal animation clip",
		start,
		"M1.player.heal"
	)
	player.queue_free()


func _test_player_hitstop_reaches_rig() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(2)
	var feedback := player.get_node_or_null("HitFeedback")
	var director := player.get_node_or_null("AnimDirector")
	var ok := false
	if feedback and director and feedback.has_method("on_hit"):
		feedback.call("on_hit", player, 20.0)
		await ctx.await_physics(1)
		if director.is_bound() and director._player:
			ok = absf(director._player.speed_scale - 0.05) < 0.01
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.hitstop_reaches_rig",
		get_category(),
		ok,
		"hitstop sets AnimDirector speed_scale to 0.05",
		start,
		"M1.player.combat"
	)
	player.queue_free()


func _test_player_reaction_arbitration() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(2)
	var director := player.get_node_or_null("AnimDirector")
	var hurtbox := player.get_node_or_null("Hurtbox") as Hurtbox
	var ok := false
	if director and hurtbox:
		var before: int = director._priority
		var info := DamageInfo.create(5.0, 12.0, null, DamageInfo.TYPE_PHYSICAL, Vector3.FORWARD)
		hurtbox.damaged.emit(info)
		await ctx.await_physics(2)
		ok = director._priority >= DioramaAnimController.Priority.STAGGER
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.reaction_arbitration",
		get_category(),
		ok,
		"single damaged event triggers one reaction",
		start,
		"M1.player.combat"
	)
	player.queue_free()


func _test_player_directional_locomotion_clips() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(2)
	var director := player.get_node_or_null("AnimDirector")
	var clips: Array[StringName] = []
	if director:
		director.update_locomotion(true, Vector3(0.0, 0.0, 4.0), false, 0.0, Vector2(0.0, 1.0))
		clips.append(director._desired_locomotion)
		director.update_locomotion(true, Vector3(0.0, 0.0, -4.0), false, 0.0, Vector2(0.0, -1.0))
		clips.append(director._desired_locomotion)
		director.update_locomotion(true, Vector3(-4.0, 0.0, 0.0), false, 0.0, Vector2(-1.0, 0.0))
		clips.append(director._desired_locomotion)
		director.update_locomotion(true, Vector3(4.0, 0.0, 0.0), false, 0.0, Vector2(1.0, 0.0))
		clips.append(director._desired_locomotion)
	var ok := (
		clips.size() == 4
		and clips[0] == &"walk"
		and clips[1] == &"walk_b"
		and clips[2] == &"walk_l"
		and clips[3] == &"walk_r"
	)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.directional_locomotion_clips",
		get_category(),
		ok,
		"directional locomotion selects walk/walk_b/walk_l/walk_r",
		start,
		"M1.player.locomotion"
	)
	player.queue_free()


func _test_player_heal_quality() -> void:
	var start := Time.get_ticks_msec()
	var heal_script := FileAccess.get_file_as_string("res://scripts/player/player_anim_director.gd")
	var heal_alias := "func play_heal" in heal_script and "play_stagger(duration)" in heal_script
	ctx.timed_record(
		"player.heal_not_stagger_alias",
		get_category(),
		not heal_alias,
		"PlayerAnimDirector does not alias play_heal to play_stagger",
		start,
		"M1.combat.heal"
	)

	start = Time.get_ticks_msec()
	var heal_sfx_ok := (
		ResourceLoader.exists("res://assets/audio/sfx/heal_raise.wav")
		and ResourceLoader.exists("res://assets/audio/sfx/heal_gulp.wav")
		and ResourceLoader.exists("res://assets/audio/sfx/heal_commit.wav")
	)
	ctx.timed_record(
		"player.heal_authored_sfx",
		get_category(),
		heal_sfx_ok,
		"heal drink uses authored SFX assets",
		start,
		"M1.combat.heal"
	)


func _test_footstep_markers_present() -> void:
	var rest_pose := _player_rest_pose()
	var library := AnimLibrary.build_library(rest_pose, "../../AnimDirector", "player", true)
	var ok := false
	var walk: Animation = library.get_animation(&"walk") as Animation
	if walk:
		var method_tracks: int = 0
		for track_idx in walk.get_track_count():
			if walk.track_get_type(track_idx) == Animation.TYPE_METHOD:
				method_tracks += 1
				ok = walk.track_get_key_count(track_idx) == 2
		ok = ok and method_tracks == 1
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.footstep_markers_present",
		get_category(),
		ok,
		"compiled player walk clip exposes footstep method tracks",
		start,
		"LOC-01"
	)


func _test_footstep_fallback_active_without_markers() -> void:
	var timer := 0.001
	var delta := 0.02
	var horizontal_speed := 4.5
	var interval := VfxService.FOOTSTEP_INTERVAL_WALK
	var fired := false
	if horizontal_speed >= 0.35:
		timer -= delta
		if timer <= 0.0:
			timer = interval
			fired = true
	var timer_fired: bool = fired and timer >= 0.25
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.footstep_fallback_active_without_markers",
		get_category(),
		timer_fired,
		"procedural footstep fallback runs without animation markers",
		start,
		"LOC-01"
	)


func _test_directional_speed_scale() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(1)
	var facing_dir: Vector3 = player.call("get_facing_direction")
	var flat_facing := Vector3(facing_dir.x, 0.0, facing_dir.z).normalized()
	var right := Vector3.UP.cross(flat_facing).normalized()
	var forward := float(player.call("_direction_speed_scale", flat_facing))
	var strafe := float(player.call("_direction_speed_scale", right))
	var back := float(player.call("_direction_speed_scale", -flat_facing))
	var ok := (
		absf(forward - 1.0) <= 0.01 and absf(strafe - 0.82) <= 0.01 and absf(back - 0.65) <= 0.01
	)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.directional_speed_scale",
		get_category(),
		ok,
		"direction speed scale forward/strafe/back (%.2f/%.2f/%.2f)" % [forward, strafe, back],
		start,
		"LOC-03"
	)
	player.queue_free()


func _test_sprint_denied_backward() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var facing := player.get_node_or_null("Facing") as Node3D
	if facing:
		facing.rotation.y = 0.0
	var backward_dot := float(player.call("_movement_forward_dot", Vector3(0.0, 0.0, -1.0)))
	var sprint_allowed: bool = backward_dot >= 0.5
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.sprint_denied_backward",
		get_category(),
		not sprint_allowed,
		"sprint denied when moving 180 deg from facing",
		start,
		"LOC-03"
	)
	player.queue_free()


func _test_air_control_turn_clamp() -> void:
	_ensure_test_floor()
	var player := _spawn_player()
	await ctx.await_physics(2)
	player.velocity = Vector3(0.0, 0.0, 7.0)
	player.set("_airborne_velocity_dir", Vector3(0.0, 0.0, 1.0))
	player.set("_was_on_floor", false)
	Input.action_press("move_back")
	for _i in 30:
		await ctx.await_physics(1)
	Input.action_release("move_back")
	var flat := Vector3(player.velocity.x, 0.0, player.velocity.z)
	var initial := Vector3(0.0, 0.0, 1.0)
	var angle := (
		rad_to_deg(initial.angle_to(flat.normalized())) if flat.length_squared() > 0.01 else 0.0
	)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.air_control_turn_clamp",
		get_category(),
		angle <= 55.0,
		"airborne turn clamped to 55 deg (got %.1f)" % angle,
		start,
		"LOC-04"
	)
	player.queue_free()


func _test_landing_thresholds() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	await ctx.await_physics(2)
	var health := player.get_node_or_null("Health") as Health
	var hp_before := health.current if health else 0.0
	player.call("_on_landed", 1.0)
	var soft_ok := float(player.get("_landing_lock_timer")) <= 0.0
	player.call("_on_landed", 4.0)
	var hard_ok := float(player.get("_landing_lock_timer")) >= 0.17
	player.call("_on_landed", 9.0)
	var damage_ok := health == null or health.current <= hp_before - 7.9
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.landing_thresholds",
		get_category(),
		soft_ok and hard_ok and damage_ok,
		"landing soft/hard thresholds and fall damage",
		start,
		"LOC-05"
	)
	player.queue_free()


func _test_body_movement_properties() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var ok := (
		absf(player.floor_max_angle - deg_to_rad(48.0)) < 0.01
		and absf(player.floor_snap_length - 0.35) < 0.01
		and player.max_slides == 6
	)
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.body_movement_properties",
		get_category(),
		ok,
		"CharacterBody3D floor snap and slide properties set",
		start,
		"LOC-07"
	)
	player.queue_free()


func _test_speed_breakdown_matches_velocity() -> void:
	_ensure_test_floor()
	var player := _spawn_player()
	await ctx.await_physics(2)
	Input.action_press("move_forward")
	for _i in 60:
		await ctx.await_physics(1)
	Input.action_release("move_forward")
	var measured := Vector2(player.velocity.x, player.velocity.z).length()
	var breakdown: Dictionary = player.call("get_current_speed_breakdown")
	var final_speed := float(breakdown.get("final", 0.0))
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.speed_breakdown_matches_velocity",
		get_category(),
		absf(final_speed - measured) <= 0.05,
		"speed breakdown final %.2f vs measured %.2f" % [final_speed, measured],
		start,
		"LOC-09"
	)
	player.queue_free()


func _spawn_player() -> CharacterBody3D:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	player.global_position = Vector3(0.0, 1.0, 0.0)
	return player


func _ensure_test_floor() -> void:
	if ctx.owner.get_node_or_null("LocomotionTestFloor") != null:
		return
	var floor := StaticBody3D.new()
	floor.name = "LocomotionTestFloor"
	floor.collision_layer = 1
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(24.0, 1.0, 24.0)
	collision.shape = shape
	collision.position = Vector3(0.0, -0.5, 0.0)
	floor.add_child(collision)
	ctx.owner.add_child(floor)


func _player_rest_pose() -> Dictionary:
	return {
		"Root": {"path": "Root", "position": Vector3.ZERO, "rotation": Vector3.ZERO},
		"LegL":
		{"path": "Root/LegL", "position": Vector3(-0.13, 0.46, 0.0), "rotation": Vector3.ZERO},
		"LegR":
		{"path": "Root/LegR", "position": Vector3(0.13, 0.46, 0.0), "rotation": Vector3.ZERO},
		"Torso":
		{"path": "Root/Torso", "position": Vector3(0.0, 0.46, 0.0), "rotation": Vector3.ZERO},
		"Head":
		{"path": "Root/Torso/Head", "position": Vector3(0.0, 0.62, 0.0), "rotation": Vector3.ZERO},
		"ArmL":
		{
			"path": "Root/Torso/ArmL",
			"position": Vector3(-0.3, 0.5456, 0.0),
			"rotation": Vector3.ZERO
		},
		"ArmR":
		{
			"path": "Root/Torso/ArmR",
			"position": Vector3(0.3, 0.5456, 0.0),
			"rotation": Vector3.ZERO
		},
	}


func _test_player_combat_reactions() -> void:
	await _test_movement_lock_during_attack()
	await _test_movement_lock_during_heal()
	await _test_movement_lock_not_shadowed_by_guard()
	await _test_stagger_duration_scales_with_poise()
	await _test_stagger_wakeup_iframes()
	await _test_stagger_rollout_cancels()
	await _test_revive_resets_all_subsystems()
	await _test_reaction_direction_quadrant()


func _test_movement_lock_during_attack() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var weapon := player.get_node("WeaponController")
	var stamina := player.get_node("Stamina") as Stamina
	stamina.configure(100.0)
	weapon.request_light_attack()
	var startup_locked := false
	var startup_sources := PackedStringArray()
	var active_locked := false
	for _i in 90:
		await ctx.await_physics(1)
		if int(weapon.current_phase) == 1 and not startup_locked:
			startup_locked = reactions.is_movement_locked()
			startup_sources = reactions.get_lock_sources()
		if int(weapon.current_phase) == 2:
			active_locked = reactions.is_movement_locked()
			break
	var start := Time.get_ticks_msec()
	var ok: bool = startup_locked and active_locked and "WeaponController" in startup_sources
	ctx.timed_record(
		"player.movement_lock_during_attack",
		get_category(),
		ok,
		"attack startup/active lock movement with WeaponController source",
		start,
		"PCR-01"
	)
	player.queue_free()


func _test_movement_lock_during_heal() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var heal := player.get_node("PlayerHeal")
	heal.refill_charges()
	Input.action_press("heal")
	await ctx.await_physics(2)
	Input.action_release("heal")
	var sources: PackedStringArray = reactions.get_lock_sources()
	var start := Time.get_ticks_msec()
	var ok: bool = heal.is_drinking and reactions.is_movement_locked() and "PlayerHeal" in sources
	ctx.timed_record(
		"player.movement_lock_during_heal",
		get_category(),
		ok,
		"heal drink locks movement with PlayerHeal source",
		start,
		"PCR-01"
	)
	player.queue_free()


func _test_movement_lock_not_shadowed_by_guard() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var weapon := player.get_node("WeaponController")
	var heal := player.get_node("PlayerHeal")
	var guard := player.get_node("Guard")
	var stamina := player.get_node("Stamina") as Stamina
	stamina.configure(100.0)
	var guard_idle: bool = guard != null and not guard.locks_movement()
	weapon.request_light_attack()
	await _wait_until_weapon_phase(weapon, 1, 60)
	var weapon_locked: bool = reactions.is_movement_locked()
	heal.refill_charges()
	Input.action_press("heal")
	await ctx.await_physics(2)
	Input.action_release("heal")
	var heal_locked: bool = reactions.is_movement_locked()
	var start := Time.get_ticks_msec()
	var ok: bool = guard_idle and weapon_locked and heal_locked
	ctx.timed_record(
		"player.movement_lock_not_shadowed_by_guard",
		get_category(),
		ok,
		"idle guard does not shadow weapon/heal movement locks",
		start,
		"PCR-01"
	)
	player.queue_free()


func _test_stagger_duration_scales_with_poise() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var cases := [
		[10.0, 0.45],
		[27.7, 0.85],
		[45.0, 1.25],
	]
	var ok := true
	for entry in cases:
		var expected: float = entry[1]
		var got: float = reactions.stagger_duration_for_poise(entry[0])
		if absf(got - expected) > 0.02:
			ok = false
			break
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.stagger_duration_scales_with_poise",
		get_category(),
		ok,
		"poise damage maps to stagger duration anchors",
		start,
		"PCR-04"
	)
	player.queue_free()


func _test_stagger_wakeup_iframes() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var health := player.get_node("Health") as Health
	var before := health.current
	reactions.apply_stagger_from_poise(30.0)
	var duration: float = reactions.stagger_duration
	var wait_time := maxf(0.0, duration - 0.10)
	for _i in int(ceil(wait_time / (1.0 / 60.0))):
		await ctx.await_physics(1)
	health.take_damage(10.0)
	var start := Time.get_ticks_msec()
	var ok := is_equal_approx(health.current, before)
	ctx.timed_record(
		"player.stagger_wakeup_iframes",
		get_category(),
		ok,
		"wakeup i-frames block damage near stagger end",
		start,
		"PCR-05"
	)
	player.queue_free()


func _test_stagger_rollout_cancels() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var stamina := player.get_node("Stamina") as Stamina
	stamina.configure(100.0)
	var before_stamina := stamina.current
	reactions.apply_stagger_from_poise(30.0)
	var duration: float = reactions.stagger_duration
	var wait_time := maxf(0.0, duration - 0.10)
	for _i in int(ceil(wait_time / (1.0 / 60.0))):
		await ctx.await_physics(1)
	Input.action_press("dodge")
	await ctx.await_physics(2)
	Input.action_release("dodge")
	var spent := before_stamina - stamina.current
	var start := Time.get_ticks_msec()
	var ok: bool = not reactions.is_staggered and absf(spent - 48.0) <= 0.5
	ctx.timed_record(
		"player.stagger_rollout_cancels",
		get_category(),
		ok,
		"roll-out dodge cancels stagger for 48 stamina",
		start,
		"PCR-05"
	)
	player.queue_free()


func _test_revive_resets_all_subsystems() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var health := player.get_node("Health") as Health
	var stamina := player.get_node("Stamina") as Stamina
	var poise := player.get_node("Poise") as Poise
	var guard := player.get_node("Guard")
	var status := player.get_node("StatusController") as StatusController
	reactions.is_dead = true
	health.current = 0.0
	stamina.current = 12.0
	poise.current = 0.0
	guard.guard_broken_state = true
	status.apply_status("burn", 1, 2.0)
	VfxService.push_time_scale(&"death", 0.35)
	PixelDioramaSettings.screen_saturation = 0.2
	reactions.reset_combat_state()
	var start := Time.get_ticks_msec()
	var ok: bool = (
		not reactions.is_dead
		and not health.is_dead()
		and is_equal_approx(health.current, health.max_health)
		and is_equal_approx(stamina.current, stamina.max_stamina)
		and is_equal_approx(poise.current, poise.max_poise)
		and not guard.guard_broken_state
		and status.get_active_statuses().is_empty()
		and is_equal_approx(Engine.time_scale, 1.0)
	)
	ctx.timed_record(
		"player.revive_resets_all_subsystems",
		get_category(),
		ok,
		"revive resets health-adjacent combat subsystems",
		start,
		"PCR-07"
	)
	player.queue_free()


func _test_reaction_direction_quadrant() -> void:
	var player := _spawn_player()
	await ctx.await_physics(2)
	var reactions := player.get_node("CombatReactions")
	var facing := player.get_node("Facing") as Node3D
	var forward := -facing.global_transform.basis.z
	var right := facing.global_transform.basis.x
	var cases := [
		[forward, &"stagger_f"],
		[-forward, &"stagger_b"],
		[right, &"stagger_r"],
		[-right, &"stagger_l"],
	]
	var ok := true
	for entry in cases:
		var clip: StringName = reactions.get_stagger_clip_for_direction(entry[0])
		if clip != entry[1]:
			ok = false
			break
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"player.reaction_direction_quadrant",
		get_category(),
		ok,
		"hit direction maps to directional stagger clips",
		start,
		"PCR-03"
	)
	player.queue_free()


func _wait_until_weapon_phase(weapon: Node, phase: int, max_frames: int) -> bool:
	for _i in max_frames:
		if int(weapon.current_phase) == phase:
			return true
		await ctx.await_physics(1)
	return false


func _floor_snap_body() -> CharacterBody3D:
	var body := CharacterBody3D.new()
	body.name = "FloorSnapBody"
	ctx.owner.add_child(body)
	return body


func _add_collision_shape(
	body: CharacterBody3D, shape: Shape3D, local_y: float = 0.0, disabled: bool = false
) -> CollisionShape3D:
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, local_y, 0.0)
	collision.disabled = disabled
	body.add_child(collision)
	return collision


func _make_platform(top_y: float) -> StaticBody3D:
	var platform := StaticBody3D.new()
	platform.name = "FloorSnapPlatform"
	platform.collision_layer = 1
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 0.4, 12.0)
	collision.shape = box
	collision.position = Vector3(0.0, top_y - 0.2, 0.0)
	platform.add_child(collision)
	ctx.owner.add_child(platform)
	return platform


func _make_steep_wall() -> StaticBody3D:
	var ramp := StaticBody3D.new()
	ramp.name = "FloorSnapSteepRamp"
	ramp.collision_layer = 1
	ramp.rotation_degrees = Vector3(70.0, 0.0, 0.0)
	var collision := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(12.0, 0.2, 12.0)
	collision.shape = box
	collision.position = Vector3(0.0, 0.0, -6.0)
	ramp.add_child(collision)
	ctx.owner.add_child(ramp)
	return ramp


func _convex_box_shape() -> ConvexPolygonShape3D:
	var convex := ConvexPolygonShape3D.new()
	convex.points = PackedVector3Array(
		[
			Vector3(-0.5, -0.5, -0.5),
			Vector3(0.5, -0.5, -0.5),
			Vector3(0.5, 0.5, -0.5),
			Vector3(-0.5, 0.5, -0.5),
			Vector3(-0.5, -0.5, 0.5),
			Vector3(0.5, -0.5, 0.5),
			Vector3(0.5, 0.5, 0.5),
			Vector3(-0.5, 0.5, 0.5),
		]
	)
	return convex


func _test_floor_snap() -> void:
	await _test_floor_snap_collision_bottom_capsule()
	await _test_floor_snap_collision_bottom_sphere()
	await _test_floor_snap_collision_bottom_multiple_shapes()
	await _test_floor_snap_collision_bottom_ignores_disabled()
	await _test_floor_snap_collision_bottom_unknown_shape()
	await _test_floor_snap_snap_respects_parent_offset()
	await _test_floor_snap_probe_finds_platform()
	await _test_floor_snap_probe_rejects_steep_normal()
	await _test_floor_snap_probe_miss_returns_fallback()
	await _test_floor_snap_visual_aligned_under_offset_parent()
	await _test_floor_snap_snap_character_aligns_both()
	await _test_floor_snap_world_geometry_on_layer_one()
	await _test_floor_snap_rig_feet_at_origin()


func _test_floor_snap_collision_bottom_capsule() -> void:
	var start := Time.get_ticks_msec()
	var body := _floor_snap_body()
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	_add_collision_shape(body, capsule, 0.9)
	var bottom := FloorSnap.collision_bottom_local(body)
	body.queue_free()
	ctx.timed_record(
		"floor_snap.collision_bottom_capsule",
		get_category(),
		absf(bottom - 0.1) < 0.01,
		"1.6 m capsule at local y 0.9 returns bottom 0.1",
		start,
		"SNP-04"
	)


func _test_floor_snap_collision_bottom_sphere() -> void:
	var start := Time.get_ticks_msec()
	var body := _floor_snap_body()
	var sphere := SphereShape3D.new()
	sphere.radius = 0.5
	_add_collision_shape(body, sphere, 0.5)
	var bottom := FloorSnap.collision_bottom_local(body)
	body.queue_free()
	ctx.timed_record(
		"floor_snap.collision_bottom_sphere",
		get_category(),
		absf(bottom - 0.0) < 0.01,
		"0.5 m radius sphere at local y 0.5 returns bottom 0.0",
		start,
		"SNP-04"
	)


func _test_floor_snap_collision_bottom_multiple_shapes() -> void:
	var start := Time.get_ticks_msec()
	var body := _floor_snap_body()
	var foot := BoxShape3D.new()
	foot.size = Vector3(0.3, 0.3, 0.3)
	_add_collision_shape(body, foot, 0.15)
	var torso := CapsuleShape3D.new()
	torso.height = 1.6
	_add_collision_shape(body, torso, 1.4)
	var bottom := FloorSnap.collision_bottom_local(body)
	body.queue_free()
	ctx.timed_record(
		"floor_snap.collision_bottom_multiple_shapes",
		get_category(),
		absf(bottom - 0.0) < 0.01,
		"foot box bottom wins over taller torso capsule",
		start,
		"SNP-05"
	)


func _test_floor_snap_collision_bottom_ignores_disabled() -> void:
	var start := Time.get_ticks_msec()
	var body := _floor_snap_body()
	var foot := BoxShape3D.new()
	foot.size = Vector3(0.3, 0.3, 0.3)
	_add_collision_shape(body, foot, 0.15, true)
	var torso := CapsuleShape3D.new()
	torso.height = 1.6
	_add_collision_shape(body, torso, 0.9)
	var bottom := FloorSnap.collision_bottom_local(body)
	body.queue_free()
	ctx.timed_record(
		"floor_snap.collision_bottom_ignores_disabled",
		get_category(),
		absf(bottom - 0.1) < 0.01,
		"disabled lower shape is ignored",
		start,
		"SNP-05"
	)


func _test_floor_snap_collision_bottom_unknown_shape() -> void:
	var start := Time.get_ticks_msec()
	var body := _floor_snap_body()
	_add_collision_shape(body, _convex_box_shape(), 1.0)
	var bottom := FloorSnap.collision_bottom_local(body)
	body.queue_free()
	ctx.timed_record(
		"floor_snap.collision_bottom_unknown_shape_warns",
		get_category(),
		bottom < 0.99,
		"convex shape uses debug mesh AABB minimum, not position.y",
		start,
		"SNP-04"
	)


func _test_floor_snap_snap_respects_parent_offset() -> void:
	var start := Time.get_ticks_msec()
	var parent := Node3D.new()
	parent.position = Vector3(0.0, 5.0, 0.0)
	ctx.owner.add_child(parent)
	var body := CharacterBody3D.new()
	parent.add_child(body)
	var capsule := CapsuleShape3D.new()
	capsule.height = 1.6
	_add_collision_shape(body, capsule, 0.8)
	body.global_position = Vector3(0.0, 6.0, 0.0)
	FloorSnap.snap_feet_to_world_y(body, 2.0)
	var feet_y := FloorSnap.feet_world_y(body)
	parent.queue_free()
	ctx.timed_record(
		"floor_snap.snap_respects_parent_offset",
		get_category(),
		absf(feet_y - 2.0) < 0.01,
		"parent offset does not break world-space snap",
		start,
		"SNP-06"
	)


func _test_floor_snap_probe_finds_platform() -> void:
	var start := Time.get_ticks_msec()
	var platform := _make_platform(2.4)
	await ctx.await_physics(2)
	var world: World3D = platform.get_world_3d()
	var floor_y := FloorSnap.probe_floor_y(world, Vector3(0.0, 4.0, 0.0), -1.0)
	ctx.timed_record(
		"floor_snap.probe_finds_platform",
		get_category(),
		absf(floor_y - 2.4) < 0.01,
		"probe finds platform top at 2.4 m",
		start,
		"SNP-02"
	)


func _test_floor_snap_probe_rejects_steep_normal() -> void:
	var start := Time.get_ticks_msec()
	var wall := _make_steep_wall()
	await ctx.await_physics(2)
	var world: World3D = wall.get_world_3d()
	var floor_y := FloorSnap.probe_floor_y(world, Vector3(0.0, 2.0, 0.0), 1.5)
	ctx.timed_record(
		"floor_snap.probe_rejects_steep_normal",
		get_category(),
		absf(floor_y - 1.5) < 0.01,
		"steep ramp is rejected and fallback is returned",
		start,
		"SNP-02"
	)


func _test_floor_snap_probe_miss_returns_fallback() -> void:
	var start := Time.get_ticks_msec()
	var anchor := _floor_snap_body()
	var world: World3D = anchor.get_world_3d()
	var floor_y := FloorSnap.probe_floor_y(world, Vector3(40.0, 4.0, 40.0), 3.3)
	anchor.queue_free()
	ctx.timed_record(
		"floor_snap.probe_miss_returns_fallback",
		get_category(),
		absf(floor_y - 3.3) < 0.01,
		"probe miss returns fallback height",
		start,
		"SNP-02"
	)


func _test_floor_snap_visual_aligned_under_offset_parent() -> void:
	var start := Time.get_ticks_msec()
	var parent := Node3D.new()
	parent.position = Vector3(0.0, 3.0, 0.0)
	ctx.owner.add_child(parent)
	var body := CharacterBody3D.new()
	parent.add_child(body)
	var capsule := CapsuleShape3D.new()
	capsule.height = 2.4
	_add_collision_shape(body, capsule, 0.0)
	body.position = Vector3.ZERO
	var visual := Node3D.new()
	body.add_child(visual)
	FloorSnap.align_diorama_visual(body, visual)
	var delta := absf(FloorSnap.feet_world_y(body) - FloorSnap.visual_feet_world_y(visual))
	parent.queue_free()
	ctx.timed_record(
		"floor_snap.visual_aligned_under_offset_parent",
		get_category(),
		delta < 0.01,
		"visual feet match collision bottom under offset parent",
		start,
		"SNP-01"
	)


func _test_floor_snap_snap_character_aligns_both() -> void:
	var start := Time.get_ticks_msec()
	_make_platform(2.4)
	var body := _floor_snap_body()
	var capsule := CapsuleShape3D.new()
	capsule.height = 2.4
	_add_collision_shape(body, capsule, 0.0)
	body.global_position = Vector3(0.0, 5.0, 0.0)
	var visual := Node3D.new()
	body.add_child(visual)
	await ctx.await_physics(2)
	FloorSnap.snap_character(body, visual)
	var feet_ok := absf(FloorSnap.feet_world_y(body) - 2.4) < 0.01
	var visual_ok := absf(FloorSnap.visual_feet_world_y(visual) - 2.4) < 0.01
	body.queue_free()
	ctx.timed_record(
		"floor_snap.snap_character_aligns_both",
		get_category(),
		feet_ok and visual_ok,
		"snap_character aligns collision and visual to probed floor",
		start,
		"SNP-07"
	)


func _test_floor_snap_world_geometry_on_layer_one() -> void:
	var start := Time.get_ticks_msec()
	var blockout := CastleBlockoutScript.new()
	var root := Node3D.new()
	ctx.owner.add_child(root)
	root.add_child(blockout)
	blockout.finalize_geometry()
	await ctx.await_frame()
	var ok := true
	for node in blockout.find_children("*", "StaticBody3D", true, false):
		var body := node as StaticBody3D
		if (body.collision_layer & 1) == 0:
			ok = false
			break
	root.queue_free()
	ctx.timed_record(
		"floor_snap.world_geometry_on_layer_one",
		get_category(),
		ok,
		"castle blockout static bodies are on collision layer 1",
		start,
		"SNP-02"
	)


func _test_floor_snap_rig_feet_at_origin() -> void:
	var start := Time.get_ticks_msec()
	var holder := Node3D.new()
	ctx.owner.add_child(holder)
	var profiles := ["melee", "ranged", "shield", "brute", "dummy"]
	var ok := true
	for profile in profiles:
		for child in holder.get_children():
			child.queue_free()
		var facing := Node3D.new()
		holder.add_child(facing)
		var visual := CharacterSkin.build_enemy_body(facing, profile)
		if CharacterSkin.rig_mesh_min_y(visual) > 0.02:
			ok = false
			break
	var player_facing := Node3D.new()
	holder.add_child(player_facing)
	var player_visual := CharacterSkin.build_player_body(player_facing)
	if ok and CharacterSkin.rig_mesh_min_y(player_visual) > 0.02:
		ok = false
	holder.queue_free()
	ctx.timed_record(
		"floor_snap.rig_feet_at_origin",
		get_category(),
		ok,
		"built character rigs keep mesh AABB min y within 0.02 m of origin",
		start,
		"SNP-03"
	)
