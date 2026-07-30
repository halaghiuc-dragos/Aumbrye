extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "camera"


func run() -> void:
	_test_camera_api()
	_test_persisted_preference()


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
