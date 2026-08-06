extends "res://scripts/validation/validation_suite.gd"

const PixelDioramaSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")
const PlayerScene := preload("res://scenes/player/player.tscn")


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_pipeline_paths()
	_test_autoload_paths()
	_test_shader_assets()
	_test_default_preset()
	_test_integer_shrink()
	await _test_render_camera_current()
	_test_finish_material_bound()
	_test_focus_distance_tracks_boom()
	_test_no_dead_accessors()
	await _test_screen_pulse_params()
	_test_debug_dump_gated()


func _test_pipeline_paths() -> void:
	var paths: Array[String] = [
		"res://scripts/art/pipeline/pixel_diorama_viewport.gd",
		"res://scripts/art/pipeline/pixel_diorama_bootstrap.gd",
		"res://scripts/art/pipeline/pixel_camera_snap.gd",
		"res://scripts/art/pipeline/pixel_diorama_settings.gd",
		"res://scripts/art/style/pixel_diorama_style.gd",
		"res://scripts/art/lighting/visual_lighting.gd",
		"res://scripts/art/characters/material_flash.gd",
		"res://scripts/art/characters/material_dissolve.gd",
		"res://scripts/art/vfx/vfx_service.gd",
		"res://scenes/art/diorama_character_rig_player.tscn",
		"res://assets/audio/default_bus_layout.tres",
	]
	for path in paths:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"pixel_pipeline.%s" % path.get_file().get_basename(),
			get_category(),
			FileAccess.file_exists(path),
			"pipeline asset exists: %s" % path,
			start,
			"M7.graphics.pipeline"
		)


func _test_autoload_paths() -> void:
	var checks: Dictionary = {
		"VfxService": "res://scripts/art/vfx/vfx_service.gd",
		"PixelDioramaViewport": "res://scripts/art/pipeline/pixel_diorama_viewport.gd",
	}
	for autoload_name in checks:
		var expected: String = checks[autoload_name]
		var setting_path: String = ProjectSettings.get_setting("autoload/%s" % autoload_name, "")
		var actual := setting_path.split("*")[-1] if "*" in setting_path else setting_path
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"pixel_pipeline.autoload_%s" % autoload_name,
			get_category(),
			actual == expected,
			"%s -> %s" % [autoload_name, actual],
			start,
			"M7.graphics.autoloads"
		)


func _test_shader_assets() -> void:
	var start := Time.get_ticks_msec()
	var shader_path := "res://assets/shared/pixel_diorama_surface.gdshader"
	var exists := FileAccess.file_exists(shader_path)
	var has_flash := false
	var has_dissolve := false
	if exists:
		var text := FileAccess.get_file_as_string(shader_path)
		has_flash = "flash_amount" in text
		has_dissolve = "dissolve_clip" in text
	ctx.timed_record(
		"pixel_pipeline.surface_shader_flash",
		get_category(),
		exists and has_flash and has_dissolve,
		"surface shader exposes flash_amount and dissolve_clip",
		start,
		"M7.graphics.shader"
	)


func _test_default_preset() -> void:
	var start := Time.get_ticks_msec()
	var saved_width := PixelDioramaSettings.viewport_width
	var saved_height := PixelDioramaSettings.viewport_height
	PixelDioramaSettings.apply_beauty_defaults()
	var preset_idx := PixelDioramaSettings.current_resolution_preset()
	var preset: Dictionary = PixelDioramaSettings.RESOLUTION_PRESETS[preset_idx]
	var ok := (
		preset_idx >= 0
		and bool(preset.get("default", false))
		and PixelDioramaSettings.viewport_height == 270
	)
	PixelDioramaSettings.viewport_width = saved_width
	PixelDioramaSettings.viewport_height = saved_height
	ctx.timed_record(
		"pixel_pipeline.default_preset",
		get_category(),
		ok,
		"beauty defaults select the preset flagged default at height 270",
		start,
		"PDP-01"
	)


func _test_integer_shrink() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for preset in PixelDioramaSettings.RESOLUTION_PRESETS:
		if bool(preset.get("native", false)):
			continue
		var height := int(preset.get("height", 0))
		if height <= 0 or 1080 % height != 0:
			ok = false
			break
	ctx.timed_record(
		"pixel_pipeline.integer_shrink",
		get_category(),
		ok,
		"non-native presets divide 1080 evenly at reference window height",
		start,
		"PDP-01"
	)


func _test_render_camera_current() -> void:
	var start := Time.get_ticks_msec()
	var fixture := Node3D.new()
	fixture.name = "PixelPipelineFixture"
	ctx.owner.add_child(fixture)
	var player := PlayerScene.instantiate()
	fixture.add_child(player)
	player.add_to_group("player")
	PixelDioramaViewport.attach_to_scene(fixture)
	await ctx.owner.get_tree().process_frame
	await ctx.owner.get_tree().process_frame
	var gameplay_cam := PixelDioramaViewport.get_gameplay_camera()
	var ok := (
		gameplay_cam != null
		and gameplay_cam.current
		and gameplay_cam.name == "PixelRenderCamera"
	)
	PixelDioramaViewport.detach()
	fixture.queue_free()
	ctx.timed_record(
		"pixel_pipeline.render_camera_current",
		get_category(),
		ok,
		"render camera is current after attach_to_scene",
		start,
		"PDP-02"
	)


func _test_finish_material_bound() -> void:
	var start := Time.get_ticks_msec()
	var was_finish := PixelDioramaSettings.screen_finish_enabled
	PixelDioramaSettings.screen_finish_enabled = true
	PixelDioramaViewport.apply_settings()
	var container: SubViewportContainer = (
		PixelDioramaViewport.get_node("PixelDioramaViewportLayer/PixelViewportContainer")
	)
	var mat := container.material
	var ok := false
	if mat is ShaderMaterial:
		var shader_mat := mat as ShaderMaterial
		var shader_path := ""
		if shader_mat.shader:
			shader_path = shader_mat.shader.resource_path
		ok = (
			shader_path.ends_with("pixel_screen_finish.gdshader")
			and is_equal_approx(
				float(shader_mat.get_shader_parameter("contrast")),
				PixelDioramaSettings.screen_contrast
			)
			and is_equal_approx(
				float(shader_mat.get_shader_parameter("saturation")),
				PixelDioramaSettings.screen_saturation
			)
			and is_equal_approx(
				float(shader_mat.get_shader_parameter("vignette_strength")),
				PixelDioramaSettings.vignette_strength
			)
		)
	PixelDioramaSettings.screen_finish_enabled = was_finish
	PixelDioramaViewport.apply_settings()
	ctx.timed_record(
		"pixel_pipeline.finish_material_bound",
		get_category(),
		ok,
		"screen finish ShaderMaterial matches PixelDioramaSettings statics",
		start,
		"PDP-02"
	)


func _test_focus_distance_tracks_boom() -> void:
	var start := Time.get_ticks_msec()
	var fixture := Node3D.new()
	fixture.name = "FocusDistanceFixture"
	ctx.owner.add_child(fixture)
	var player := Node3D.new()
	player.add_to_group("player")
	fixture.add_child(player)
	var pivot := Node3D.new()
	pivot.name = "CameraPivot"
	player.add_child(pivot)
	var arm := SpringArm3D.new()
	arm.name = "SpringArm3D"
	arm.spring_length = 2.5
	pivot.add_child(arm)
	var cam := Camera3D.new()
	cam.name = "Camera3D"
	arm.add_child(cam)
	PixelDioramaViewport.set("_spring_arm", arm)
	var distance: float = PixelDioramaViewport.call("_focus_distance")
	var ok := is_equal_approx(distance, 2.5)
	fixture.queue_free()
	ctx.timed_record(
		"pixel_pipeline.focus_distance_tracks_boom",
		get_category(),
		ok,
		"_focus_distance() tracks SpringArm3D.spring_length",
		start,
		"PDP-03"
	)


func _test_no_dead_accessors() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		not PixelDioramaViewport.has_method("get_subviewport")
		and not PixelDioramaViewport.has_method("get_render_camera")
		and not PixelDioramaViewport.has_method("get_world_root")
	)
	ctx.timed_record(
		"pixel_pipeline.no_dead_accessors",
		get_category(),
		ok,
		"removed unused PixelDioramaViewport accessors",
		start,
		"PDP-04"
	)


func _test_screen_pulse_params() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	PixelDioramaSettings.screen_finish_enabled = true
	PixelDioramaViewport.apply_settings()
	for kind in PixelDioramaViewport.ScreenPulse.values():
		PixelDioramaViewport.pulse_screen(kind, 1.0)
		var container: SubViewportContainer = (
			PixelDioramaViewport.get_node("PixelDioramaViewportLayer/PixelViewportContainer")
		)
		var mat := container.material as ShaderMaterial
		if mat == null:
			ok = false
			break
		var tuning: Dictionary = PixelDioramaViewport.PULSE_TUNING[kind]
		var pulse := float(mat.get_shader_parameter(tuning.param))
		var tint: Color = mat.get_shader_parameter("pulse_tint")
		if pulse <= 0.001 or tint == Color():
			ok = false
			break
		var decay := float(tuning.decay) + 0.05
		await ctx.owner.get_tree().create_timer(decay).timeout
		pulse = float(mat.get_shader_parameter(tuning.param))
		if pulse > 0.001:
			ok = false
			break
	ctx.timed_record(
		"pixel_pipeline.screen_pulse_params",
		get_category(),
		ok,
		"pulse_screen sets pulse_tint and decays damage_pulse to zero",
		start,
		"PDP-08"
	)


func _test_debug_dump_gated() -> void:
	var start := Time.get_ticks_msec()
	OS.unset_environment("AUMBRYE_GFX_DUMP")
	var state: Dictionary = PixelDioramaViewport.dump_render_state()
	var ok := (
		not state.is_empty()
		and state.has("cast_shadow_counts")
		and state.has("renderer")
		and OS.get_environment("AUMBRYE_GFX_DUMP") == ""
	)
	ctx.timed_record(
		"pixel_pipeline.debug_dump_gated",
		get_category(),
		ok,
		"dump_render_state returns data without scheduling _dbg_dump",
		start,
		"PDP-05"
	)
