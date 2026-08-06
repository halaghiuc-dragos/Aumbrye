extends "res://scripts/validation/validation_suite.gd"

const GameUISkin := preload("res://scripts/ui/game_ui_skin.gd")
const PixelDioramaSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")


func get_category() -> String:
	return "ui"


func run() -> void:
	_test_skin_theme_resource()
	_test_skin_theme_registered()
	_test_skin_variations_present()
	_test_skin_font_default()
	_test_skin_pixel_panel_square()
	_test_skin_hd_panel_rounded()
	_test_skin_focus_styleboxes()
	_test_skin_no_label_walk()
	_test_skin_no_dead_constants()
	_test_skin_button_sfx_coverage()
	_test_skin_paperdoll_texture()
	await _test_main_menu_focus_ring()
	await _test_interactive_controls_named()


func _collect_focusables(root: Control) -> Array[Control]:
	var out: Array[Control] = []
	if root.focus_mode != Control.FOCUS_NONE:
		out.append(root)
	for child in root.get_children():
		if child is Control:
			out.append_array(_collect_focusables(child as Control))
	return out


func _test_main_menu_focus_ring() -> void:
	var start := Time.get_ticks_msec()
	var scene := load("res://scenes/ui/main_menu.tscn") as PackedScene
	if scene == null or ctx.owner == null:
		ctx.timed_record(
			"ui.main_menu.focus_ring",
			get_category(),
			false,
			"main_menu scene missing",
			start,
			"VSU-14"
		)
		return
	var menu := scene.instantiate() as Control
	ctx.owner.add_child(menu)
	await ctx.await_frame()
	var focusables := _collect_focusables(menu)
	var ok := focusables.size() >= 2
	if ok:
		focusables[0].grab_focus()
		var first := focusables[0]
		for _i in focusables.size():
			var ev := InputEventAction.new()
			ev.action = &"ui_down"
			ev.pressed = true
			Input.parse_input_event(ev)
			await ctx.await_frame()
		ok = menu.get_viewport().gui_get_focus_owner() == first
	menu.queue_free()
	ctx.timed_record(
		"ui.main_menu.focus_ring",
		get_category(),
		ok,
		"main menu focus cycles back to first control",
		start,
		"VSU-14"
	)


func _test_skin_theme_resource() -> void:
	var start := Time.get_ticks_msec()
	if not ResourceLoader.exists(GameUISkin.THEME_PATH):
		var err := ResourceSaver.save(GameUISkin.build_theme(), GameUISkin.THEME_PATH)
		if err != OK:
			ctx.timed_record(
				"ui.skin.theme_resource",
				get_category(),
				false,
				"failed to generate aumbrye_ui.tres",
				start,
				"SKN-01"
			)
			return
	var theme := load(GameUISkin.THEME_PATH)
	ctx.timed_record(
		"ui.skin.theme_resource",
		get_category(),
		theme is Theme,
		"aumbrye_ui.tres loads as Theme",
		start,
		"SKN-01"
	)


func _test_skin_theme_registered() -> void:
	var start := Time.get_ticks_msec()
	var path: String = str(ProjectSettings.get_setting("gui/theme/custom", ""))
	ctx.timed_record(
		"ui.skin.theme_registered",
		get_category(),
		path == GameUISkin.THEME_PATH,
		"project gui/theme/custom points at aumbrye_ui.tres",
		start,
		"SKN-01"
	)


func _test_skin_variations_present() -> void:
	var start := Time.get_ticks_msec()
	var theme := load(GameUISkin.THEME_PATH) as Theme
	var ok := theme != null
	if ok:
		for variation in GameUISkin.LABEL_VARIATIONS:
			ok = ok and theme.get_font_size("font_size", variation) > 0
	ctx.timed_record(
		"ui.skin.variations_present",
		get_category(),
		ok,
		"theme defines all seven label variations",
		start,
		"SKN-02"
	)


func _test_skin_font_default() -> void:
	var start := Time.get_ticks_msec()
	var theme := load(GameUISkin.THEME_PATH) as Theme
	var font_path: String = ""
	if theme and theme.default_font:
		font_path = theme.default_font.resource_path
	ctx.timed_record(
		"ui.skin.font_default",
		get_category(),
		font_path.ends_with("aumbrye_pixel.ttf"),
		"default theme font is aumbrye_pixel.ttf",
		start,
		"SKN-03"
	)


func _test_skin_pixel_panel_square() -> void:
	var start := Time.get_ticks_msec()
	var prev := PixelDioramaSettings.low_res_viewport_enabled
	PixelDioramaSettings.low_res_viewport_enabled = true
	var style := GameUISkin.make_panel_style()
	var ok := style.corner_radius_top_left == 0 and style.shadow_size == 0
	PixelDioramaSettings.low_res_viewport_enabled = prev
	ctx.timed_record(
		"ui.skin.pixel_panel_square",
		get_category(),
		ok,
		"pixel mode panel has zero radius and shadow",
		start,
		"SKN-05"
	)


func _test_skin_hd_panel_rounded() -> void:
	var start := Time.get_ticks_msec()
	var prev_w := PixelDioramaSettings.viewport_width
	var prev_h := PixelDioramaSettings.viewport_height
	var prev_low := PixelDioramaSettings.low_res_viewport_enabled
	PixelDioramaSettings.viewport_width = 1280
	PixelDioramaSettings.viewport_height = 720
	PixelDioramaSettings.low_res_viewport_enabled = false
	var style := GameUISkin.make_panel_style()
	var ok := style.corner_radius_top_left == GameUISkin.PANEL_CORNER_RADIUS_HD
	PixelDioramaSettings.viewport_width = prev_w
	PixelDioramaSettings.viewport_height = prev_h
	PixelDioramaSettings.low_res_viewport_enabled = prev_low
	ctx.timed_record(
		"ui.skin.hd_panel_rounded",
		get_category(),
		ok,
		"native HD preset panel uses rounded corners",
		start,
		"SKN-05"
	)


func _test_skin_focus_styleboxes() -> void:
	var start := Time.get_ticks_msec()
	var theme := load(GameUISkin.THEME_PATH) as Theme
	var types := ["Button", "ItemList", "OptionButton", "CheckBox", "LineEdit"]
	var ok := theme != null
	if ok:
		for type_name in types:
			ok = ok and theme.get_stylebox("focus", type_name) != null
	ctx.timed_record(
		"ui.skin.focus_styleboxes",
		get_category(),
		ok,
		"focus styleboxes exist for five control classes",
		start,
		"SKN-10"
	)


func _test_skin_no_label_walk() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string("res://scripts/ui/game_ui_skin.gd")
	var modal_start := text.find("func apply_modal_menu")
	var modal_end := text.find("func build_paperdoll_backdrop", modal_start)
	var modal_body := text.substr(modal_start, modal_end - modal_start) if modal_start >= 0 and modal_end > modal_start else text
	ctx.timed_record(
		"ui.skin.no_label_walk",
		get_category(),
		'"Label", true' not in modal_body,
		"apply_modal_menu does not walk labels by substring",
		start,
		"SKN-02"
	)


func _test_skin_no_dead_constants() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string("res://scripts/ui/game_ui_skin.gd")
	ctx.timed_record(
		"ui.skin.no_dead_constants",
		get_category(),
		"const CELL_SIZE" not in text and "const EQUIP_CELL_SIZE" not in text,
		"dead CELL_SIZE constants removed",
		start,
		"SKN-08"
	)


func _test_skin_button_sfx_coverage() -> void:
	var start := Time.get_ticks_msec()
	var files := [
		"res://scripts/ui/stair_menu.gd",
		"res://scripts/ui/umbral_endless_menu.gd",
		"res://scripts/ui/blacksmith_ui.gd",
	]
	var ok := true
	for path in files:
		var text := FileAccess.get_file_as_string(path)
		if "Button.new()" in text:
			ok = false
	ctx.timed_record(
		"ui.skin.button_sfx_coverage",
		get_category(),
		ok,
		"stair, endless, and blacksmith avoid bare Button.new()",
		start,
		"SKN-07"
	)


func _test_skin_paperdoll_texture() -> void:
	var start := Time.get_ticks_msec()
	var ok := ResourceLoader.exists(GameUISkin.PAPERDOLL_TEXTURE_PATH)
	if ok:
		for path in ["inventory_ui.gd", "character_create_ui.gd"]:
			var text := FileAccess.get_file_as_string("res://scripts/ui/%s" % path)
			if "build_human_silhouette" in text:
				ok = false
	ctx.timed_record(
		"ui.skin.paperdoll_texture",
		get_category(),
		ok,
		"paperdoll texture exists and call sites use backdrop API",
		start,
		"SKN-04"
	)


func _test_interactive_controls_named() -> void:
	var start := Time.get_ticks_msec()
	var scene := load("res://scenes/ui/main_menu.tscn") as PackedScene
	var failures: PackedStringArray = []
	if scene and ctx.owner:
		var menu := scene.instantiate() as Control
		ctx.owner.add_child(menu)
		await ctx.await_frame()
		for node in _collect_focusables(menu):
			if node is Button or node is CheckBox or node is Slider or node is OptionButton:
				if str(node.accessible_name).strip_edges() == "":
					failures.append(node.name)
		menu.queue_free()
	ctx.timed_record(
		"ui.controls.accessible_names",
		get_category(),
		failures.is_empty(),
		(
			"interactive controls have accessible names"
			if failures.is_empty()
			else "missing names: %s" % ", ".join(failures)
		),
		start,
		"VSU-14"
	)
