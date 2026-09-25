extends Node3D


const PLAYER_SCENE := preload("res://scenes/player/player.tscn")
const PixelDioramaSettingsScript := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")
const DisplayServiceScript := preload("res://scripts/app/display_service.gd")
const SettingsSchemaScript := preload("res://scripts/ui/settings_schema.gd")

var _camera: Node


func _ready() -> void:
	var display_failures := _audit_full_hd_pixel_default()
	display_failures += _audit_pixel_fit()
	var player := PLAYER_SCENE.instantiate()
	add_child(player)
	if PixelDioramaSettingsScript.low_res_viewport_enabled:
		PixelDioramaViewport.attach_to_scene(self)
	await get_tree().process_frame
	display_failures += _audit_live_pixel_container()
	_camera = player.get_node_or_null("CameraPivot/SpringArm3D")
	if _camera == null:
		print("ZOOM FAIL: no SpringArm3D under CameraPivot")
		get_tree().quit(1)
		return
	var fails := display_failures
	if _camera.is_first_person():
		_action("toggle_camera")
		await _settle()
	_report("start")

	var before := _target()
	_wheel("zoom_in", 3)
	await _settle()
	_report("after 3x zoom_in")
	if is_equal_approx(_target(), before):
		print("ZOOM FAIL: scrolling in did not move the target")
		fails += 1
	fails += _assert_arm_follows("zoom in")

	before = _target()
	_wheel("zoom_out", 6)
	await _settle()
	_report("after 6x zoom_out")
	if is_equal_approx(_target(), before):
		print("ZOOM FAIL: scrolling out did not move the target")
		fails += 1
	fails += _assert_arm_follows("zoom out")

	_wheel("zoom_in", 2)
	await _settle()
	var parked := _target()
	_action("toggle_camera")
	await _settle()
	_report("first person")
	if not _camera.is_first_person():
		print("ZOOM FAIL: toggle did not enter first person")
		fails += 1
	_action("toggle_camera")
	await _settle()
	_report("back to third (parked at %.2f)" % parked)
	if _camera.is_first_person():
		print("ZOOM FAIL: toggle did not leave first person")
		fails += 1
	if _target() <= 0.5:
		print("ZOOM FAIL: third person came back at the first-person target")
		fails += 1
	fails += _assert_arm_follows("leaving first person")
	print("ZOOM RESULT %d failures" % fails)
	get_tree().quit(1 if fails > 0 else 0)


func _audit_full_hd_pixel_default() -> int:
	var scaling_option_found := false
	for entry in SettingsSchemaScript.entries():
		if str(entry.get("id", "")) == "integer_pixel_scaling":
			scaling_option_found = str(entry.get("page", "")) == "display"
			break
	if not scaling_option_found:
		print("ZOOM FAIL: integer pixel scaling is not exposed in Display settings")
		return 1
	if PixelDioramaSettingsScript.DEFAULT_VIEWPORT_WIDTH != 1920:
		print("ZOOM FAIL: default pixel viewport width is not Full HD")
		return 1
	if PixelDioramaSettingsScript.DEFAULT_VIEWPORT_HEIGHT != 1080:
		print("ZOOM FAIL: default pixel viewport height is not Full HD")
		return 1
	var default_found := false
	for preset in PixelDioramaSettingsScript.RESOLUTION_PRESETS:
		if bool(preset.get("default", false)):
			default_found = (
				int(preset.get("width", 0)) == 1920
				and int(preset.get("height", 0)) == 1080
			)
			break
	if not default_found:
		print("ZOOM FAIL: default resolution preset is not 1920 x 1080")
		return 1
	return 0


func _audit_pixel_fit() -> int:
	var failures := 0
	var source := Vector2(1920, 1080)
	var cases := [
		[Vector2(1920, 1080), true, Vector2(1920, 1080), Vector2.ZERO],
		[Vector2(2560, 1440), true, Vector2(1920, 1080), Vector2(320, 180)],
		[Vector2(3840, 2160), true, Vector2(3840, 2160), Vector2.ZERO],
		[Vector2(1280, 720), true, Vector2(1280, 720), Vector2.ZERO],
		[Vector2(1600, 900), false, Vector2(1600, 900), Vector2.ZERO],
		[Vector2(3440, 1440), true, Vector2(1920, 1080), Vector2(760, 180)],
		[Vector2(3440, 1440), false, Vector2(2560, 1440), Vector2(440, 0)],
	]
	for case in cases:
		var output_size: Vector2 = case[0]
		var use_integer := bool(case[1])
		var expected_size: Vector2 = case[2]
		var expected_position: Vector2 = case[3]
		var fitted := DisplayServiceScript.fit_pixel_render_rect(output_size, source, use_integer)
		if not fitted.size.is_equal_approx(expected_size) or not fitted.position.is_equal_approx(expected_position):
			print(
				"ZOOM FAIL: %s fit for %s was %s, expected %s"
				% ["integer" if use_integer else "fractional", output_size, fitted, Rect2(expected_position, expected_size)]
			)
			failures += 1
		if fitted.position.x < 0.0 or fitted.position.y < 0.0 or fitted.end.x > output_size.x or fitted.end.y > output_size.y:
			print("ZOOM FAIL: fitted render escapes output bounds at %s" % output_size)
			failures += 1
	print("PIXEL FIT RESULT %d failures across %d output/mode cases" % [failures, cases.size()])
	return failures


func _audit_live_pixel_container() -> int:
	var pixel_viewport := get_tree().root.get_node_or_null("PixelDioramaViewport")
	if pixel_viewport == null:
		print("ZOOM FAIL: pixel viewport autoload is missing")
		return 1
	var container := pixel_viewport.get("_container") as SubViewportContainer
	var viewport := pixel_viewport.get("_viewport") as SubViewport
	if container == null or viewport == null:
		print("ZOOM FAIL: pixel SubViewportContainer was not constructed")
		return 1
	if not PixelDioramaSettingsScript.low_res_viewport_enabled:
		return 0
	var target := PixelDioramaSettingsScript.viewport_internal_size()
	var output_size := get_viewport().get_visible_rect().size
	var expected := DisplayServiceScript.fit_pixel_render_rect(
		output_size, Vector2(target), DisplayService.integer_pixel_scaling
	)
	var actual_scale: Vector2 = container.scale
	var failures := 0
	if viewport.size != target or container.size != Vector2(target):
		print("ZOOM FAIL: live target=%s viewport=%s container=%s" % [target, viewport.size, container.size])
		failures += 1
	if not container.position.is_equal_approx(expected.position):
		print("ZOOM FAIL: live pixel position=%s expected=%s" % [container.position, expected.position])
		failures += 1
	var expected_scale := expected.size.x / float(target.x)
	if not is_equal_approx(actual_scale.x, expected_scale) or not is_equal_approx(actual_scale.y, expected_scale):
		print("ZOOM FAIL: live pixel scale=%s expected=%s" % [actual_scale, Vector2.ONE * expected_scale])
		failures += 1
	print("LIVE PIXEL FIT RESULT %d failures at %s" % [failures, output_size])
	return failures


func _assert_arm_follows(what: String) -> int:
	if absf(_camera.spring_length - _target()) <= 0.05:
		return 0
	print("ZOOM FAIL: after %s the arm is %.2f but the target is %.2f"
		% [what, _camera.spring_length, _target()])
	return 1


func _report(stage: String) -> void:
	print(
		"ZOOM %-28s target=%.2f  arm=%.2f  smoothed=%.2f  blend=%.2f  fp=%s  phys=%d"
		% [
			stage,
			_target(),
			_camera.spring_length,
			float(_camera.get("_smoothed_arm_length")),
			float(_camera.get("_fp_blend")),
			_camera.is_first_person(),
			Engine.get_physics_frames(),
		]
	)


func _target() -> float:
	return float(_camera.get("_target_zoom"))


func _settle() -> void:
	for i in 90:
		await get_tree().physics_frame


func _wheel(action: StringName, times: int) -> void:
	for i in times:
		_action(action)


func _action(action: StringName) -> void:
	var press := InputEventAction.new()
	press.action = action
	press.pressed = true
	Input.parse_input_event(press)
	var release := InputEventAction.new()
	release.action = action
	release.pressed = false
	Input.parse_input_event(release)
