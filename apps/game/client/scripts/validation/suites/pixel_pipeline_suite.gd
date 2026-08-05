extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_pipeline_paths()
	_test_autoload_paths()
	_test_shader_assets()


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
