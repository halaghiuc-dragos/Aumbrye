extends "res://scripts/validation/validation_suite.gd"

const OrbitCameraScript := preload("res://scripts/camera/orbit_camera.gd")


func get_category() -> String:
	return "camera"


func run() -> void:
	_test_camera_api()
	_test_persisted_preference()
	_test_settings_defaults_present()
	_test_sensitivity_setting_applied()
	_test_invert_y_applied()
	_test_stick_curve_and_deadzone()
	await _test_first_person_parameters()
	await _test_mode_blend_duration()
	await _test_gameplay_camera_snaps()
	await _test_shoulder_offset_applied()
	await _test_effect_entry_points_exist()
	await _test_toggle_breaks_lock()
	await _test_state_round_trip_with_lock()


func _test_camera_api() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"camera.toggle_action",
		get_category(),
		InputMap.has_action("toggle_camera"),
		"toggle_camera input action exists",
		start,
		"M3.camera.toggle"
	)

	start = Time.get_ticks_msec()
	var player: Node3D = load("res://scenes/player/player.tscn").instantiate() as Node3D
	var spring := player.get_node_or_null("CameraPivot/SpringArm3D")
	var has_fp_api := spring != null and spring.has_method("is_first_person")
	ctx.timed_record(
		"camera.first_person_api",
		get_category(),
		has_fp_api,
		"orbit camera exposes is_first_person()",
		start,
		"M3.camera.fp_api"
	)
	player.free()

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"camera.debug_overlay_hint",
		get_category(),
		ctx.file_contains("res://scripts/debug/debug_overlay.gd", "camera:"),
		"debug overlay documents camera mode",
		start,
		"M3.debug.camera"
	)

	start = Time.get_ticks_msec()
	var has_pref_api := (
		LocalSave.has_method("is_first_person_camera")
		and LocalSave.has_method("set_first_person_camera")
	)
	ctx.timed_record(
		"camera.persisted_preference_api",
		get_category(),
		has_pref_api,
		"LocalSave exposes persisted first-person camera preference",
		start,
		"M3.camera.persist_api"
	)


func _test_persisted_preference() -> void:
	var backup: Dictionary = ctx.backup_save_file()
	var start := Time.get_ticks_msec()
	LocalSave.set_first_person_camera(true)
	var persisted := LocalSave.is_first_person_camera()
	ctx.restore_save_file(backup)
	ctx.timed_record(
		"camera.persisted_preference_roundtrip",
		get_category(),
		persisted,
		"first-person camera preference round-trips through LocalSave",
		start,
		"M3.camera.persist_roundtrip"
	)


func _test_settings_defaults_present() -> void:
	var start := Time.get_ticks_msec()
	var defaults := AccessibilitySettings.camera_settings_defaults()
	var ok := true
	for key in defaults:
		if not defaults.has(key):
			ok = false
	ctx.timed_record(
		"camera.settings_defaults_present",
		get_category(),
		ok and defaults.size() == 6,
		"all six camera settings defaults exist",
		start,
		"M3.camera.settings_defaults"
	)


func _test_sensitivity_setting_applied() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var spring := player.get_node("CameraPivot/SpringArm3D")
	var yaw_pivot := player.get_node("CameraPivot") as Node3D
	ctx.owner.add_child(player)
	var start_yaw := yaw_pivot.rotation.y
	AccessibilitySettings.camera_mouse_sensitivity = 1.0
	spring.call("_apply_look", 0.1, 0.0)
	var delta_full := yaw_pivot.rotation.y - start_yaw
	yaw_pivot.rotation.y = start_yaw
	AccessibilitySettings.camera_mouse_sensitivity = 0.5
	spring.call("_apply_look", 0.1, 0.0)
	var delta_half := yaw_pivot.rotation.y - start_yaw
	player.queue_free()
	var start := Time.get_ticks_msec()
	var ok := absf(delta_half - delta_full * 0.5) < 0.0005
	ctx.timed_record(
		"camera.sensitivity_setting_applied",
		get_category(),
		ok,
		"mouse sensitivity 0.5 yields half yaw change",
		start,
		"M3.camera.sensitivity"
	)


func _test_invert_y_applied() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var spring := player.get_node("CameraPivot/SpringArm3D")
	ctx.owner.add_child(player)
	AccessibilitySettings.camera_invert_y = false
	spring.set("_pitch", 0.0)
	spring.call("_apply_look", 0.0, 0.05)
	var pitch_normal := float(spring.get("_pitch"))
	spring.set("_pitch", 0.0)
	AccessibilitySettings.camera_invert_y = true
	spring.call("_apply_look", 0.0, 0.05)
	var pitch_inverted := float(spring.get("_pitch"))
	player.queue_free()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"camera.invert_y_applied",
		get_category(),
		pitch_normal * pitch_inverted < 0.0,
		"invert Y flips pitch sign",
		start,
		"M3.camera.invert_y"
	)


func _test_stick_curve_and_deadzone() -> void:
	var start := Time.get_ticks_msec()
	var deadzone := AccessibilitySettings.CAMERA_STICK_DEADZONE_DEFAULT
	var curve := AccessibilitySettings.CAMERA_STICK_CURVE_DEFAULT
	var low := OrbitCameraScript.stick_curve_magnitude(0.10, deadzone, curve)
	var mid := OrbitCameraScript.stick_curve_magnitude(0.30, deadzone, curve)
	var high := OrbitCameraScript.stick_curve_magnitude(1.00, deadzone, curve)
	var ok := low == 0.0 and absf(mid - 0.09) < 0.01 and absf(high - 1.0) < 0.01
	ctx.timed_record(
		"camera.stick_curve_and_deadzone",
		get_category(),
		ok,
		"stick curve table matches documented magnitudes",
		start,
		"M3.camera.stick_curve"
	)


func _test_first_person_parameters() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	var spring := player.get_node("CameraPivot/SpringArm3D")
	var camera := spring.get_node("Camera3D") as Camera3D
	spring.call("_apply_first_person", true)
	for _i in 15:
		await ctx.await_physics()
	var ok := (
		absf(camera.fov - 82.0) < 1.5
		and absf(camera.near - 0.02) < 0.01
		and float(spring.get("_fp_blend")) > 0.9
	)
	player.queue_free()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"camera.first_person_parameters",
		get_category(),
		ok,
		"first person settles near FOV 82 and near 0.02",
		start,
		"M3.camera.fp_params"
	)


func _test_mode_blend_duration() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	var spring := player.get_node("CameraPivot/SpringArm3D")
	var camera := spring.get_node("Camera3D") as Camera3D
	spring.call("_apply_first_person", true)
	var settled := false
	for _i in 30:
		await ctx.await_physics()
		if absf(camera.fov - 82.0) < 1.0 and spring.spring_length < 0.05:
			settled = true
			break
	player.queue_free()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"camera.mode_blend_duration",
		get_category(),
		settled,
		"FOV and arm length settle within blend window",
		start,
		"M3.camera.mode_blend"
	)


func _test_gameplay_camera_snaps() -> void:
	PixelDioramaSettings.gameplay_camera_snap_enabled = true
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	var spring := player.get_node("CameraPivot/SpringArm3D")
	var camera := spring.get_node("Camera3D") as Camera3D
	await ctx.await_physics(2)
	var before := camera.global_position
	player.global_position += Vector3(0.001, 0.0, 0.0)
	for _i in 3:
		await ctx.await_physics()
	var after := camera.global_position
	player.queue_free()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"camera.gameplay_camera_snaps",
		get_category(),
		before.distance_to(after) < 0.0005,
		"tiny player move does not crawl camera sub-pixel",
		start,
		"M3.camera.snap"
	)


func _test_shoulder_offset_applied() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	var spring := player.get_node("CameraPivot/SpringArm3D")
	var camera := spring.get_node("Camera3D") as Camera3D
	spring.call("_apply_first_person", false)
	for _i in 10:
		await ctx.await_physics()
	var third_x := camera.position.x
	spring.call("_apply_first_person", true)
	for _i in 10:
		await ctx.await_physics()
	var first_x := camera.position.x
	player.queue_free()
	var start := Time.get_ticks_msec()
	var ok := absf(third_x - 0.45) < 0.08 and absf(first_x) < 0.05
	ctx.timed_record(
		"camera.shoulder_offset_applied",
		get_category(),
		ok,
		"shoulder offset 0.45 in third person and zero in first person",
		start,
		"M3.camera.shoulder"
	)


func _test_effect_entry_points_exist() -> void:
	var start := Time.get_ticks_msec()
	var spring_script := OrbitCameraScript
	var methods := [
		"apply_shake",
		"apply_punch",
		"apply_landing_dip",
		"enter_death_framing",
		"exit_death_framing",
	]
	var ok := true
	for method_name in methods:
		if not spring_script.has_method(method_name):
			ok = false
	ok = ok and ctx.file_contains(
		"res://scripts/combat/hit_feedback.gd", "apply_punch"
	)
	ctx.timed_record(
		"camera.effect_entry_points_exist",
		get_category(),
		ok,
		"orbit camera effect APIs exist and hit_feedback uses them",
		start,
		"M3.camera.effects"
	)


func _test_toggle_breaks_lock() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var enemy: CharacterBody3D = (
		load("res://scenes/enemies/training_grunt.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	ctx.owner.add_child(enemy)
	enemy.global_position = Vector3(4.0, 0.0, 0.0)
	enemy.add_to_group("lockable")
	var spring := player.get_node("CameraPivot/SpringArm3D")
	var lock_on := player.get_node("LockOn") as LockOn
	spring.call("_apply_first_person", false)
	lock_on.request_lock(enemy)
	await ctx.await_physics(2)
	spring.call("_toggle_camera_mode")
	var ok := not lock_on.is_locked and spring.call("is_first_person")
	player.queue_free()
	enemy.queue_free()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"camera.toggle_breaks_lock",
		get_category(),
		ok,
		"toggle camera breaks lock and changes mode",
		start,
		"M3.camera.toggle_lock"
	)


func _test_state_round_trip_with_lock() -> void:
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	var enemy: CharacterBody3D = (
		load("res://scenes/enemies/training_grunt.tscn").instantiate() as CharacterBody3D
	)
	ctx.owner.add_child(player)
	ctx.owner.add_child(enemy)
	enemy.global_position = Vector3(4.0, 0.0, 0.0)
	enemy.add_to_group("lockable")
	var spring := player.get_node("CameraPivot/SpringArm3D")
	var lock_on := player.get_node("LockOn") as LockOn
	spring.call("_apply_first_person", false)
	lock_on.request_lock(enemy)
	await ctx.await_physics(2)
	var state: Dictionary = spring.call("capture_state")
	lock_on.break_lock()
	spring.call("apply_state", state)
	await ctx.await_physics(2)
	var ok := lock_on.is_locked and lock_on.current_target == enemy
	player.queue_free()
	enemy.queue_free()
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"camera.state_round_trip_with_lock",
		get_category(),
		ok,
		"capture_state restores lock on same target",
		start,
		"M3.camera.state_lock"
	)
