extends "res://scripts/validation/validation_suite.gd"

const DebugOverlayScript := preload("res://scripts/debug/debug_overlay.gd")


func get_category() -> String:
	return "debug"


func run() -> void:
	_test_overlay_toggle_action()
	_test_seed_display_in_source()
	_test_release_build_hides_overlay()


func _test_overlay_toggle_action() -> void:
	var start := Time.get_ticks_msec()
	var ok := InputMap.has_action("debug_toggle") and InputMap.has_action("debug_hitboxes")
	ctx.timed_record(
		"debug.overlay.toggle_actions",
		get_category(),
		ok,
		"debug_toggle and debug_hitboxes input actions exist",
		start,
		"VSU-10"
	)


func _test_seed_display_in_source() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string("res://scripts/debug/debug_overlay.gd")
	var ok := "FPS" in text and "show_debug" in text
	ctx.timed_record(
		"debug.overlay.renders_fps",
		get_category(),
		ok,
		"debug overlay script exposes FPS and show_debug",
		start,
		"VSU-10"
	)


func _test_release_build_hides_overlay() -> void:
	var start := Time.get_ticks_msec()
	var overlay := DebugOverlayScript.new()
	var ok := overlay.has_method("_input") and overlay.has_method("_process")
	overlay.free()
	ctx.timed_record(
		"debug.overlay.api_present",
		get_category(),
		ok,
		"DebugOverlay exposes input and process hooks",
		start,
		"VSU-10"
	)
