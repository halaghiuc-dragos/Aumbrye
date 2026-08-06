extends "res://scripts/validation/validation_suite.gd"

const SETTINGS_PATH := "res://scripts/art/pipeline/pixel_diorama_settings.gd"
const FINISH_SHADER_PATH := "res://assets/shared/pixel_screen_finish.gdshader"


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_preset_tuning_not_destructive()
	_test_preset_tuning_applied_on_select()
	_test_no_project_settings_writes()
	_test_render_quality_applied()
	_test_biome_materials_are_copies()
	_test_restamp_tracked()
	_test_screen_finish_full_coverage()
	_test_defaults_are_pixel_honest()
	_test_snap_step_scales()
	_test_meta_migration_v0()
	_test_no_dead_legacy_branch()
	_test_shadow_quality_matrix()


func _test_preset_tuning_not_destructive() -> void:
	var start := Time.get_ticks_msec()
	var meta := LocalSave.get_meta_data()
	var prior_pixel := PixelDioramaSettings.pixel_scale
	meta[PixelDioramaSettings.SAVE_KEY] = {
		"version": 1,
		"pixel_scale": 9.5,
		"viewport_width": 1920,
		"viewport_height": 1080,
		"tuning_is_preset_default": false,
	}
	LocalSave.patch_meta(meta)
	PixelDioramaSettings.load_from_save()
	var ok := is_equal_approx(PixelDioramaSettings.pixel_scale, 9.5)
	PixelDioramaSettings.pixel_scale = prior_pixel
	ctx.timed_record(
		"pixel_settings.preset_tuning_not_destructive",
		get_category(),
		ok,
		"load_from_save preserves user pixel_scale at native preset size",
		start,
		"PDS-01"
	)


func _test_preset_tuning_applied_on_select() -> void:
	var start := Time.get_ticks_msec()
	var prior_scale := PixelDioramaSettings.pixel_scale
	var prior_flag := PixelDioramaSettings.tuning_is_preset_default
	PixelDioramaSettings.set_resolution_preset(5)
	var ok := (
		is_equal_approx(PixelDioramaSettings.pixel_scale, 2.0)
		and PixelDioramaSettings.tuning_is_preset_default
	)
	PixelDioramaSettings.pixel_scale = prior_scale
	PixelDioramaSettings.tuning_is_preset_default = prior_flag
	ctx.timed_record(
		"pixel_settings.preset_tuning_applied_on_select",
		get_category(),
		ok,
		"set_resolution_preset(5) applies HD tuning and preset flag",
		start,
		"PDS-01"
	)


func _test_no_project_settings_writes() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	ctx.timed_record(
		"pixel_settings.no_project_settings_writes",
		get_category(),
		not ("ProjectSettings.set_setting" in text),
		"pixel_diorama_settings.gd has no ProjectSettings.set_setting",
		start,
		"PDS-02"
	)


func _test_render_quality_applied() -> void:
	var start := Time.get_ticks_msec()
	var prior_aa := PixelDioramaSettings.anti_aliasing_off
	PixelDioramaSettings.anti_aliasing_off = true
	var vp := SubViewport.new()
	PixelDioramaSettings.apply_render_quality([vp])
	var ok := (
		vp.msaa_3d == Viewport.MSAA_DISABLED
		and vp.screen_space_aa == Viewport.SCREEN_SPACE_AA_DISABLED
	)
	vp.free()
	PixelDioramaSettings.anti_aliasing_off = prior_aa
	ctx.timed_record(
		"pixel_settings.render_quality_applied",
		get_category(),
		ok,
		"apply_render_quality disables MSAA and screen-space AA on viewport",
		start,
		"PDS-02"
	)


func _test_biome_materials_are_copies() -> void:
	var start := Time.get_ticks_msec()
	BiomeRegistry.warm_index()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var a := BiomeRegistry.get_wall_material(biome_id)
		var b := BiomeRegistry.get_wall_material(biome_id)
		if a == null or b == null or a == b:
			ok = false
			break
	ctx.timed_record(
		"pixel_settings.biome_materials_are_copies",
		get_category(),
		ok,
		"get_wall_material returns distinct instances for every biome",
		start,
		"PDS-03"
	)


func _test_restamp_tracked() -> void:
	var start := Time.get_ticks_msec()
	var prior_pattern := PixelDioramaSettings.pattern_strength
	PixelDioramaSettings.pattern_strength = 0.42
	var mat := ShaderMaterial.new()
	mat.shader = load("res://assets/shared/pixel_diorama_surface.gdshader") as Shader
	PixelDioramaSettings.track(mat)
	PixelDioramaSettings.restamp_tracked()
	var stamped := is_equal_approx(float(mat.get_shader_parameter("pattern_strength")), 0.42)
	PixelDioramaSettings.pattern_strength = 0.88
	PixelDioramaSettings.restamp_tracked()
	var restamped := is_equal_approx(float(mat.get_shader_parameter("pattern_strength")), 0.88)
	var count_before := PixelDioramaSettings._tracked.size()
	mat = null
	PixelDioramaSettings.restamp_tracked()
	var pruned := PixelDioramaSettings._tracked.size() < count_before
	PixelDioramaSettings.pattern_strength = prior_pattern
	ctx.timed_record(
		"pixel_settings.restamp_tracked",
		get_category(),
		stamped and restamped and pruned,
		"restamp_tracked updates live materials and prunes freed refs",
		start,
		"PDS-03"
	)


func _test_screen_finish_full_coverage() -> void:
	var start := Time.get_ticks_msec()
	var shader_text := FileAccess.get_file_as_string(FINISH_SHADER_PATH)
	var uniforms: Dictionary = {}
	var regex := RegEx.new()
	regex.compile("uniform\\s+\\w+\\s+(\\w+)")
	for match_result in regex.search_all(shader_text):
		uniforms[match_result.get_string(1)] = true
	var written := {
		"contrast": true,
		"saturation": true,
		"lift": true,
		"shadow_tint": true,
		"shadow_tint_amount": true,
		"highlight_tint": true,
		"highlight_tint_amount": true,
		"vignette_strength": true,
		"vignette_softness": true,
		"damage_pulse": true,
		"pulse_tint": true,
		"posterize_levels": true,
	}
	var ok := true
	for uniform_name in uniforms.keys():
		if not written.has(uniform_name):
			ok = false
			break
	ctx.timed_record(
		"pixel_settings.screen_finish_full_coverage",
		get_category(),
		ok,
		"apply_to_screen_finish covers every pixel_screen_finish uniform",
		start,
		"PDS-06"
	)


func _test_defaults_are_pixel_honest() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		PixelDioramaSettings.DEFAULT_NEAREST_TEXTURE_FILTER
		and PixelDioramaSettings.DEFAULT_POSTERIZE_LEVELS >= 16.0
	)
	ctx.timed_record(
		"pixel_settings.defaults_are_pixel_honest",
		get_category(),
		ok,
		"defaults enable nearest filtering and posterize >= 16",
		start,
		"PDS-07"
	)


func _test_snap_step_scales() -> void:
	var start := Time.get_ticks_msec()
	var prior_height := PixelDioramaSettings.active_render_height
	PixelDioramaSettings.active_render_height = 270
	var step_270 := PixelDioramaSettings.camera_snap_step(75.0, 5.0)
	PixelDioramaSettings.active_render_height = 1080
	var step_1080 := PixelDioramaSettings.camera_snap_step(75.0, 5.0)
	PixelDioramaSettings.active_render_height = prior_height
	var ok_270 := absf(step_270 - 0.0284) / 0.0284 <= 0.01
	var ok_1080 := absf(step_1080 - 0.0071) / 0.0071 <= 0.01
	ctx.timed_record(
		"pixel_settings.snap_step_scales",
		get_category(),
		ok_270 and ok_1080,
		"camera_snap_step scales inversely with active_render_height",
		start,
		"PDS-08"
	)


func _test_meta_migration_v0() -> void:
	var start := Time.get_ticks_msec()
	var block := {
		"pixel_scale": 7.25,
		"viewport_width": 640,
		"viewport_height": 360,
	}
	var migrated := PixelDioramaSettings._migrate_settings(block, 0)
	var ok := (
		int(migrated.get("version", 0)) == PixelDioramaSettings.SETTINGS_VERSION
		and bool(migrated.get("tuning_is_preset_default", false))
		and is_equal_approx(float(migrated.get("pixel_scale", 0.0)), 7.25)
	)
	ctx.timed_record(
		"pixel_settings.meta_migration_v0",
		get_category(),
		ok,
		"v0 meta blocks migrate with tuning_is_preset_default=true",
		start,
		"PDS-09"
	)


func _test_no_dead_legacy_branch() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(SETTINGS_PATH)
	ctx.timed_record(
		"pixel_settings.no_dead_legacy_branch",
		get_category(),
		not ("pixel_scale_for_pattern_type" in text),
		"legacy pattern_type scaling removed",
		start,
		"PDS-05"
	)


func _test_shadow_quality_matrix() -> void:
	var start := Time.get_ticks_msec()
	var prior_quality := PixelDioramaSettings.shadow_quality
	var results: Array[bool] = []
	for quality in [0, 1, 2]:
		PixelDioramaSettings.shadow_quality = quality
		var light := DirectionalLight3D.new()
		PixelDioramaSettings.configure_directional_shadow(light)
		match quality:
			0:
				results.append(not light.shadow_enabled)
			1:
				results.append(
					light.shadow_enabled
					and is_equal_approx(light.directional_shadow_max_distance, 24.0)
				)
			2:
				results.append(
					light.shadow_enabled
					and is_equal_approx(light.directional_shadow_max_distance, 32.0)
				)
		light.free()
	PixelDioramaSettings.shadow_quality = prior_quality
	ctx.timed_record(
		"pixel_settings.shadow_quality_matrix",
		get_category(),
		results.size() == 3 and not false in results,
		"configure_directional_shadow matches shadow_quality tiers",
		start,
		"PDS-10"
	)
