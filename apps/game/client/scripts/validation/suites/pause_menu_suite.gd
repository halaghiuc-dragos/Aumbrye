extends "res://scripts/validation/validation_suite.gd"

const PauseMenuScript := preload("res://scripts/ui/pause_menu.gd")
const SettingsUIScript := preload("res://scripts/ui/settings_ui.gd")
const ConfirmSpecScript := preload("res://scripts/ui/confirm_spec.gd")
const InputGlyphScript := preload("res://scripts/ui/input_glyph_service.gd")
const RM := preload("res://scripts/app/run_mode_config.gd")


func get_category() -> String:
	return "ui"


func run() -> void:
	_test_abandon_present_in_run()
	_test_abandon_absent_in_hub()
	_test_waves_leave_present()
	_test_no_mouse_mode_in_pause_menu()
	_test_no_waves_section_in_settings()
	_test_restart_floor_api()
	_test_localized_keys_present()
	await _test_focus_on_open()
	await _test_settings_roundtrip_mouse()
	await _test_cancel_scoped()
	await _test_run_info_fields()
	await _test_seed_copyable()
	await _test_front_end_suppressed()
	_test_audio_mix_hooks()
	_test_hint_glyph()


func _make_pause_menu() -> Control:
	var menu := Control.new()
	menu.set_script(PauseMenuScript)
	menu.name = "PauseMenuTest"
	if ctx.owner:
		ctx.owner.add_child(menu)
	await ctx.await_frame()
	return menu


func _test_abandon_present_in_run() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		ctx.file_contains("res://scripts/ui/pause_menu.gd", "PAUSE_ABANDON")
		and ctx.file_contains("res://scripts/ui/pause_menu.gd", "RunFlow.is_run_active()")
		and ctx.script_has_method("res://scripts/ui/pause_menu.gd", "_rebuild_actions")
	)
	ctx.timed_record(
		"pause.abandon_present_in_run",
		get_category(),
		ok,
		"pause menu rebuilds abandon from live RunFlow state",
		start,
		"PSE-01"
	)


func _test_abandon_absent_in_hub() -> void:
	var start := Time.get_ticks_msec()
	var ok := ctx.file_contains(
		"res://scripts/ui/pause_menu.gd", "if RunFlow.is_run_active():"
	)
	ctx.timed_record(
		"pause.abandon_absent_in_hub",
		get_category(),
		ok,
		"run actions gated on is_run_active",
		start,
		"PSE-01"
	)


func _test_waves_leave_present() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		ctx.file_contains("res://scripts/ui/pause_menu.gd", "PAUSE_LEAVE_WAVES")
		and not ctx.file_contains("res://scripts/ui/settings_ui.gd", "WavesRunSection")
	)
	ctx.timed_record(
		"pause.waves_leave_present",
		get_category(),
		ok,
		"leave waves lives in pause menu only",
		start,
		"PSE-01"
	)


func _test_no_mouse_mode_in_pause_menu() -> void:
	var start := Time.get_ticks_msec()
	var ok := not ctx.file_contains("res://scripts/ui/pause_menu.gd", "Input.mouse_mode")
	ctx.timed_record(
		"pause.no_mouse_mode",
		get_category(),
		ok,
		"pause_menu.gd does not assign mouse mode",
		start,
		"PSE-03"
	)


func _test_no_waves_section_in_settings() -> void:
	var start := Time.get_ticks_msec()
	var ok := not ctx.file_contains("res://scripts/ui/settings_ui.gd", "WavesRunSection")
	ctx.timed_record(
		"pause.settings_no_waves_section",
		get_category(),
		ok,
		"settings overlay no longer builds WavesRunSection",
		start,
		"PSE-01"
	)


func _test_restart_floor_api() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		RunFlow.has_method("restart_current_floor")
		and RunFlow.has_method("can_restart_current_floor")
		and ctx.file_contains("res://scripts/ui/pause_menu.gd", "PAUSE_RESTART_FLOOR")
	)
	ctx.timed_record(
		"pause.restart_floor_api",
		get_category(),
		ok,
		"restart floor action and RunFlow API present",
		start,
		"PSE-10"
	)


func _test_localized_keys_present() -> void:
	var start := Time.get_ticks_msec()
	var keys := [
		"PAUSE_TITLE",
		"PAUSE_RESUME",
		"PAUSE_CONFIRM_ABANDON_BODY",
		"PAUSE_HINT_RESUME",
	]
	var ok := true
	for key in keys:
		if not ctx.file_contains("res://translations/strings.csv", key):
			ok = false
	ctx.timed_record(
		"pause.localized",
		get_category(),
		ok,
		"pause strings exist in strings.csv",
		start,
		"PSE-06"
	)


func _test_focus_on_open() -> void:
	var start := Time.get_ticks_msec()
	var menu := await _make_pause_menu()
	var ok := false
	if menu and menu.has_method("open_menu"):
		menu.call("open_menu")
		await ctx.await_frame()
		var focus := menu.get_viewport().gui_get_focus_owner()
		ok = focus != null and focus.name == "Resume"
	if menu:
		if menu.has_method("close_menu"):
			menu.call("close_menu")
		menu.queue_free()
	ctx.timed_record(
		"pause.focus_on_open",
		get_category(),
		ok,
		"opening pause menu focuses Resume",
		start,
		"PSE-02"
	)


func _test_settings_roundtrip_mouse() -> void:
	var start := Time.get_ticks_msec()
	var menu := await _make_pause_menu()
	var ok := false
	if menu and menu.has_method("open_menu"):
		menu.call("open_menu")
		await ctx.await_frame()
		var settings := SettingsUIScript.new()
		settings.name = "SettingsTest"
		if ctx.owner:
			ctx.owner.add_child(settings)
		settings.open_settings()
		await ctx.await_frame()
		settings.close_settings()
		await ctx.await_frame()
		ok = Input.mouse_mode == Input.MOUSE_MODE_VISIBLE
		settings.queue_free()
	if menu:
		menu.call("close_menu")
		menu.queue_free()
	ctx.timed_record(
		"pause.settings_roundtrip_mouse",
		get_category(),
		ok,
		"settings close leaves mouse visible while pause is open",
		start,
		"PSE-03"
	)


func _test_cancel_scoped() -> void:
	var start := Time.get_ticks_msec()
	var menu := await _make_pause_menu()
	var ok := false
	if menu and menu.has_method("open_menu") and MenuStack:
		menu.call("open_menu")
		await ctx.await_frame()
		var spec := ConfirmSpecScript.new()
		spec.title_key = &"PAUSE_CONFIRM_ABANDON_TITLE"
		spec.message_key = &"PAUSE_CONFIRM_ABANDON_BODY"
		spec.message_args = [1, 0, 0]
		MenuStack.confirm(spec)
		await ctx.await_frame()
		var ev := InputEventAction.new()
		ev.action = &"ui_cancel"
		ev.pressed = true
		Input.parse_input_event(ev)
		await ctx.await_frame()
		ok = menu.call("is_open") and MenuStack.depth() == 1
		menu.call("close_menu")
	if menu:
		menu.queue_free()
	ctx.timed_record(
		"pause.cancel_scoped",
		get_category(),
		ok,
		"ui_cancel dismisses only the confirmation",
		start,
		"PSE-04"
	)


func _test_run_info_fields() -> void:
	var start := Time.get_ticks_msec()
	var menu := await _make_pause_menu()
	var ok := false
	if menu:
		var mode := menu.get_node_or_null("Panel/Margin/ContentVBox/RunInfo")
		var seed := menu.get_node_or_null("Panel/Margin/ContentVBox/RunInfo//SeedValue")
		if seed == null:
			seed = _find_node_named(menu, "SeedValue")
		ok = mode != null and seed != null
		menu.queue_free()
	ctx.timed_record(
		"pause.run_info_fields",
		get_category(),
		ok,
		"pause menu exposes run info panel and seed field",
		start,
		"PSE-05"
	)


func _test_seed_copyable() -> void:
	var start := Time.get_ticks_msec()
	var menu := await _make_pause_menu()
	var ok := false
	if menu:
		var seed := _find_node_named(menu, "SeedValue")
		if seed is LineEdit:
			ok = not seed.editable and seed.select_all_on_focus
		menu.queue_free()
	ctx.timed_record(
		"pause.seed_copyable",
		get_category(),
		ok,
		"SeedValue is a read-only LineEdit with select_all_on_focus",
		start,
		"PSE-05"
	)


func _test_front_end_suppressed() -> void:
	var start := Time.get_ticks_msec()
	var ok := false
	if PlayerControls.has_method("allows_player_ui") and ctx.owner:
		var front := Control.new()
		front.name = "FrontEndStub"
		front.add_to_group("front_end")
		ctx.owner.add_child(front)
		ctx.owner.get_tree().current_scene = front
		await ctx.await_frame()
		ok = not PlayerControls.allows_player_ui()
		var menu := await _make_pause_menu()
		if menu and menu.has_method("toggle"):
			menu.call("toggle")
			ok = ok and not menu.call("is_open")
			menu.queue_free()
		front.queue_free()
	ctx.timed_record(
		"pause.front_end_suppressed",
		get_category(),
		ok,
		"toggle respects allows_player_ui front-end gate",
		start,
		"PSE-11"
	)


func _test_audio_mix_hooks() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		ctx.file_contains("res://scripts/ui/pause_menu.gd", "set_pause_mix(true)")
		and ctx.file_contains("res://scripts/ui/pause_menu.gd", "set_pause_mix(false)")
		and AudioDirector.has_method("set_pause_mix")
	)
	ctx.timed_record(
		"pause.audio_mix",
		get_category(),
		ok,
		"pause open/close drives AudioDirector.set_pause_mix",
		start,
		"PSE-09"
	)


func _test_hint_glyph() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		ctx.file_contains("res://scripts/ui/pause_menu.gd", "get_action_glyph(\"pause\")")
		and not ctx.file_contains("res://scripts/ui/pause_menu.gd", "Esc to resume")
	)
	ctx.timed_record(
		"pause.hint_glyph",
		get_category(),
		ok,
		"resume hint uses pause glyph not literal Esc",
		start,
		"PSE-08"
	)


func _find_node_named(root: Node, node_name: String) -> Node:
	if root.name == node_name:
		return root
	for child in root.get_children():
		var found := _find_node_named(child, node_name)
		if found:
			return found
	return null
