extends "res://scripts/validation/validation_suite.gd"

const PixelCameraSnapScript := preload("res://scripts/art/pipeline/pixel_camera_snap.gd")


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_disabled_is_identity()
	_test_origin_on_world_grid()
	_test_rotation_invariance()
	_test_depth_axis_snapped()
	_test_step_scales_with_height()
	_test_step_scales_with_distance()
	_test_step_floors()
	_test_basis_yaw_quantized()
	_test_default_enabled()


func _test_disabled_is_identity() -> void:
	var start := Time.get_ticks_msec()
	var samples: Array[Transform3D] = [
		Transform3D(Basis.from_euler(Vector3(0.1, 0.2, 0.3)), Vector3(1.2, -0.4, 3.7)),
		Transform3D(Basis.from_euler(Vector3(-0.5, 1.1, 0.0)), Vector3(-2.0, 0.8, 0.1)),
		Transform3D(Basis.from_euler(Vector3(0.0, 0.7, 0.15)), Vector3(0.0, 5.0, -1.5)),
	]
	var ok := true
	for sample in samples:
		var result := PixelCameraSnapScript.snap_transform(sample, 75.0, 5.0, false)
		if not result.is_equal_approx(sample):
			ok = false
			break
	ctx.timed_record(
		"camera_snap.disabled_is_identity",
		get_category(),
		ok,
		"snap_transform with enabled=false returns input unchanged",
		start,
		"PCS-06"
	)


func _test_origin_on_world_grid() -> void:
	var start := Time.get_ticks_msec()
	var step := 0.0284
	var ok := true
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	for _i in 64:
		var origin := Vector3(
			rng.randf_range(-12.0, 12.0),
			rng.randf_range(-3.0, 8.0),
			rng.randf_range(-12.0, 12.0)
		)
		var snapped := PixelCameraSnapScript.snap_origin(origin, step)
		for component in [snapped.x, snapped.y, snapped.z]:
			if not _on_grid(component, step):
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"camera_snap.origin_on_world_grid",
		get_category(),
		ok,
		"snap_origin lands every component on the world grid",
		start,
		"PCS-01"
	)


func _test_rotation_invariance() -> void:
	var start := Time.get_ticks_msec()
	var origin := Vector3(2.5, 1.0, -3.25)
	var step := 0.0284
	var reference := PixelCameraSnapScript.snap_origin(origin, step)
	var ok := true
	for yaw_idx in 36:
		var yaw := deg_to_rad(float(yaw_idx) * 10.0)
		var basis := Basis.from_euler(Vector3(0.2, yaw, 0.0))
		var xform := Transform3D(basis, origin)
		var snapped := PixelCameraSnapScript.snap_transform(xform, 75.0, 5.0, true)
		if not snapped.origin.is_equal_approx(reference):
			ok = false
			break
	ctx.timed_record(
		"camera_snap.rotation_invariance",
		get_category(),
		ok,
		"world-axis snap_origin is identical under camera yaw rotation",
		start,
		"PCS-01"
	)


func _test_depth_axis_snapped() -> void:
	var start := Time.get_ticks_msec()
	var step := 0.0284
	var origin := Vector3.ZERO
	var seen: Dictionary = {}
	for _i in 9:
		var snapped := PixelCameraSnapScript.snap_origin(origin, step)
		seen[snapped.z] = true
		origin.z -= step * 0.4
	var ok := seen.size() == 3
	ctx.timed_record(
		"camera_snap.depth_axis_snapped",
		get_category(),
		ok,
		"eight depth advances yield exactly three snapped z values",
		start,
		"PCS-02"
	)


func _test_step_scales_with_height() -> void:
	var start := Time.get_ticks_msec()
	var prior_height := PixelDioramaSettings.active_render_height
	var targets := {180: 0.0426, 270: 0.0284, 1080: 0.0071}
	var ok := true
	for height in targets.keys():
		PixelDioramaSettings.active_render_height = height
		var step := PixelDioramaSettings.camera_snap_step(75.0, 5.0)
		var expected: float = targets[height]
		if absf(step - expected) / expected > 0.01:
			ok = false
			break
	PixelDioramaSettings.active_render_height = prior_height
	ctx.timed_record(
		"camera_snap.step_scales_with_height",
		get_category(),
		ok,
		"camera_snap_step scales inversely with active_render_height",
		start,
		"PCS-03"
	)


func _test_step_scales_with_distance() -> void:
	var start := Time.get_ticks_msec()
	var near_step := PixelDioramaSettings.camera_snap_step(75.0, 2.0)
	var far_step := PixelDioramaSettings.camera_snap_step(75.0, 5.0)
	var ok := absf(near_step - 0.4 * far_step) / (0.4 * far_step) <= 0.01
	ctx.timed_record(
		"camera_snap.step_scales_with_distance",
		get_category(),
		ok,
		"camera_snap_step scales linearly with focus distance",
		start,
		"PCS-04"
	)


func _test_step_floors() -> void:
	var start := Time.get_ticks_msec()
	var step := PixelDioramaSettings.camera_snap_step(5.0, 0.1)
	var ok := step >= 0.001
	ctx.timed_record(
		"camera_snap.step_floors",
		get_category(),
		ok,
		"camera_snap_step clamps fov and distance and returns at least 0.001",
		start,
		"PCS-04"
	)


func _test_basis_yaw_quantized() -> void:
	var start := Time.get_ticks_msec()
	PixelDioramaSettings.snap_fov_hint = 75.0
	var basis := Basis.from_euler(Vector3(0.31, 1.17, 0.08))
	var snapped_basis := PixelCameraSnapScript.snap_basis(basis)
	var rot_step := PixelCameraSnapScript.rotation_step_radians(75.0)
	var snapped_euler := snapped_basis.get_euler()
	var input_euler := basis.get_euler()
	var yaw_rem := fposmod(snapped_euler.y, rot_step)
	var yaw_ok := yaw_rem < 1e-5 or absf(yaw_rem - rot_step) < 1e-5
	var roll_ok := is_equal_approx(snapped_euler.z, input_euler.z)
	ctx.timed_record(
		"camera_snap.basis_yaw_quantized",
		get_category(),
		yaw_ok and roll_ok,
		"snap_basis quantizes yaw and leaves roll unchanged",
		start,
		"PCS-05"
	)


func _test_default_enabled() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string("res://scripts/art/pipeline/pixel_diorama_settings.gd")
	var ok := (
		PixelDioramaSettings.DEFAULT_CAMERA_SNAP
		and 'data.get("camera_snap_enabled", DEFAULT_CAMERA_SNAP)' in text
		and "camera_snap_enabled = DEFAULT_CAMERA_SNAP" in text
	)
	ctx.timed_record(
		"camera_snap.default_enabled",
		get_category(),
		ok,
		"DEFAULT_CAMERA_SNAP is true and settings wire the default through",
		start,
		"PCS-03"
	)


func _on_grid(value: float, step: float) -> bool:
	var rem := fposmod(value, step)
	return rem < 1e-5 or absf(rem - step) < 1e-5
