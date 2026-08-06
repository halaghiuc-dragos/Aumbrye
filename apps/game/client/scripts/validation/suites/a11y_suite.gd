extends "res://scripts/validation/validation_suite.gd"

const AccessibilitySettingsScript := preload("res://scripts/accessibility/accessibility_settings.gd")


func get_category() -> String:
	return "accessibility"


func run() -> void:
	_test_settings_class()
	_test_damage_colors()
	_test_ui_settings()
	_test_colorblind_consumer()
	_test_colorblind_protanopia()
	_test_no_hardcoded_hit_colors()
	await _test_subtitle_applies_on_line()


func _test_settings_class() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"a11y.settings_class",
		get_category(),
		ResourceLoader.exists("res://scripts/accessibility/accessibility_settings.gd"),
		"AccessibilitySettings loads",
		start,
		"A11-01"
	)


func _test_damage_colors() -> void:
	AccessibilitySettingsScript.load_from_save()
	var start := Time.get_ticks_msec()
	var color: Color = AccessibilitySettingsScript.get_damage_color("fire")
	ctx.timed_record(
		"a11y.damage_colors",
		get_category(),
		color != Color.WHITE,
		"colorblind damage color helper works",
		start,
		"A11-01"
	)


func _test_ui_settings() -> void:
	var start := Time.get_ticks_msec()
	AccessibilitySettingsScript.ui_scale = 1.25
	AccessibilitySettingsScript.subtitle_scale = 1.5
	AccessibilitySettingsScript.reduce_camera_shake = true
	var ok := (
		AccessibilitySettingsScript.ui_scale == 1.25
		and AccessibilitySettingsScript.subtitle_scale == 1.5
		and AccessibilitySettingsScript.reduce_camera_shake
	)
	ctx.timed_record(
		"a11y.ui_settings",
		get_category(),
		ok,
		"UI scale, subtitle scale, and camera shake settings writable",
		start,
		"A11-03"
	)


func _test_colorblind_consumer() -> void:
	var start := Time.get_ticks_msec()
	var has_consumer: bool = (
		ctx.file_contains("res://scripts/combat/damage_number.gd", "get_damage_color")
		or ctx.file_contains("res://scripts/ui/combat_hud.gd", "get_damage_color")
	)
	ctx.timed_record(
		"a11y.colorblind.has_consumer",
		get_category(),
		has_consumer,
		"get_damage_color called from combat or UI presentation",
		start,
		"A11-01"
	)


func _test_colorblind_protanopia() -> void:
	var start := Time.get_ticks_msec()
	AccessibilitySettingsScript.colorblind_mode = "default"
	var default_fire: Color = AccessibilitySettingsScript.get_damage_color("fire")
	AccessibilitySettingsScript.colorblind_mode = "protanopia"
	var protanopia_fire: Color = AccessibilitySettingsScript.get_damage_color("fire")
	ctx.timed_record(
		"a11y.colorblind.protanopia_fire_differs",
		get_category(),
		default_fire != protanopia_fire,
		"protanopia fire color differs from default",
		start,
		"A11-01"
	)


func _test_no_hardcoded_hit_colors() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = not ctx.file_contains(
		"res://scripts/combat/damage_number.gd", "Color(1.0, 0.35"
	)
	ctx.timed_record(
		"a11y.colorblind.no_hardcoded_hit_colors",
		get_category(),
		ok,
		"damage numbers use get_damage_color not hardcoded red",
		start,
		"A11-04"
	)


func _test_subtitle_applies_on_line() -> void:
	var dialogue_scene := load("res://scenes/ui/dialogue_ui.tscn") as PackedScene
	var start := Time.get_ticks_msec()
	if dialogue_scene == null or ctx.owner == null:
		ctx.timed_record(
			"a11y.subtitle.applies_on_line",
			get_category(),
			false,
			"dialogue_ui scene or validation owner missing",
			start,
			"A11-02"
		)
		return
	var dialogue_ui: Control = dialogue_scene.instantiate() as Control
	ctx.owner.add_child(dialogue_ui)
	await ctx.await_frame()
	AccessibilitySettingsScript.subtitle_scale = 1.5
	dialogue_ui.call("_on_line_changed", "Test", "Line", [])
	var speaker_label := dialogue_ui.get_node("Panel/Margin/VBox/SpeakerLabel") as Label
	var font_size := speaker_label.get_theme_font_size("font_size")
	dialogue_ui.queue_free()
	ctx.timed_record(
		"a11y.subtitle.applies_on_line",
		get_category(),
		font_size == 21,
		"subtitle_scale 1.5 yields speaker font size 21",
		start,
		"A11-02"
	)
