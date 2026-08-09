extends "res://scripts/validation/validation_suite.gd"

const AccessibilitySettingsScript := preload("res://scripts/accessibility/accessibility_settings.gd")


func get_category() -> String:
	return "accessibility"


func run() -> void:
	_test_settings_class()
	_test_damage_colors()
	_test_ui_settings()
	_test_colorblind_protanopia()
	await _test_damage_number_uses_accessibility_color()
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
	DisplayService.ui_scale = 1.25
	AccessibilitySettingsScript.subtitle_scale = 1.5
	AccessibilitySettingsScript.reduce_camera_shake = true
	var ok := (
		DisplayService.ui_scale == 1.25
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


func _damage_number_color(damage_type: String) -> Color:
	var scene := load("res://scenes/combat/damage_number.tscn") as PackedScene
	if scene == null:
		return Color.TRANSPARENT
	var node := scene.instantiate()
	ctx.owner.add_child(node)
	await ctx.await_frame()
	var label := node.get_node_or_null("Label3D") as Label3D
	if label == null:
		node.queue_free()
		return Color.TRANSPARENT
	node.call("show_amount", 12.0, damage_type)
	var tint := label.modulate
	node.queue_free()
	return Color(tint.r, tint.g, tint.b)


func _test_damage_number_uses_accessibility_color() -> void:
	var start := Time.get_ticks_msec()
	var previous_mode: String = AccessibilitySettingsScript.colorblind_mode
	AccessibilitySettingsScript.colorblind_mode = "none"
	var expected: Color = AccessibilitySettingsScript.get_damage_color("fire")
	var default_tint: Color = await _damage_number_color("fire")
	var matches_default := default_tint.is_equal_approx(
		Color(expected.r, expected.g, expected.b)
	)
	AccessibilitySettingsScript.colorblind_mode = "protanopia"
	var protanopia_tint: Color = await _damage_number_color("fire")
	AccessibilitySettingsScript.colorblind_mode = previous_mode
	var responds := not protanopia_tint.is_equal_approx(default_tint)
	ctx.timed_record(
		"a11y.colorblind.damage_number_tint",
		get_category(),
		matches_default and responds,
		"damage number tint comes from accessibility palette and follows colorblind mode",
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
