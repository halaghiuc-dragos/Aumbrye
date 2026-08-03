extends Control

## Settings overlay with save backup restore (SAVE-4.2).

signal closed

var _backup_list: ItemList
var _status_label: Label
var _hint_label: Label

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

var _backdrop: ColorRect
var _open := false
var _scroll_vbox: VBoxContainer


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui_if_needed()
	_refresh_backups()
	AccessibilitySettings.load_from_save()
	LeaderboardSettings.load_from_save()
	PixelDioramaSettings.load_from_save()


func _build_ui_if_needed() -> void:
	if _backup_list != null:
		return
	if has_node("Panel/Margin/VBox/BackupList"):
		_backup_list = $Panel/Margin/VBox/BackupList
		_status_label = $Panel/Margin/VBox/StatusLabel
		_hint_label = $Panel/Margin/VBox/HintLabel
		return
	for child in get_children():
		child.queue_free()
	_backdrop = GameUISkinScript.make_backdrop(self)
	var panel := GameUISkinScript.make_center_panel(
		self,
		GameUISkinScript.SETTINGS_HALF_W,
		GameUISkinScript.SETTINGS_HALF_H
	)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(520, 460)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	vbox.add_child(scroll)
	var scroll_vbox := VBoxContainer.new()
	scroll_vbox.name = "ScrollVBox"
	scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(scroll_vbox)
	_scroll_vbox = scroll_vbox
	var title := Label.new()
	title.text = "Settings"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	scroll_vbox.add_child(title)
	_backup_list = ItemList.new()
	_backup_list.name = "BackupList"
	_backup_list.custom_minimum_size = Vector2(480, 120)
	scroll_vbox.add_child(_backup_list)
	_status_label = Label.new()
	_status_label.name = "StatusLabel"
	scroll_vbox.add_child(_status_label)
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	_hint_label.text = "Enter: restore | Esc: close"
	GameUISkinScript.style_hint_label(_hint_label)
	scroll_vbox.add_child(_hint_label)
	_build_accessibility_section(scroll_vbox)
	_build_pixel_diorama_section(scroll_vbox)
	_build_run_mode_section(scroll_vbox)


func _build_accessibility_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Accessibility"
	parent.add_child(title)
	var ui_scale := HSlider.new()
	ui_scale.name = "UiScaleSlider"
	ui_scale.min_value = 0.8
	ui_scale.max_value = 1.5
	ui_scale.step = 0.05
	ui_scale.value = AccessibilitySettings.ui_scale
	ui_scale.value_changed.connect(func(v: float) -> void:
		AccessibilitySettings.ui_scale = v
		AccessibilitySettings.save()
	)
	parent.add_child(ui_scale)
	var shake := CheckBox.new()
	shake.text = "Reduce camera shake"
	shake.button_pressed = AccessibilitySettings.reduce_camera_shake
	shake.toggled.connect(func(on: bool) -> void:
		AccessibilitySettings.reduce_camera_shake = on
		AccessibilitySettings.save()
	)
	parent.add_child(shake)
	var cb := OptionButton.new()
	cb.add_item("Default", 0)
	cb.add_item("Protanopia", 1)
	cb.add_item("Deuteranopia", 2)
	cb.add_item("Tritanopia", 3)
	match AccessibilitySettings.colorblind_mode:
		"protanopia": cb.selected = 1
		"deuteranopia": cb.selected = 2
		"tritanopia": cb.selected = 3
		_: cb.selected = 0
	cb.item_selected.connect(func(idx: int) -> void:
		var modes := ["default", "protanopia", "deuteranopia", "tritanopia"]
		AccessibilitySettings.colorblind_mode = modes[idx]
		AccessibilitySettings.save()
	)
	parent.add_child(cb)
	var lb := CheckBox.new()
	lb.text = "Submit clear times to leaderboards (opt-in)"
	lb.button_pressed = LeaderboardSettings.opt_in
	lb.toggled.connect(func(on: bool) -> void:
		LeaderboardSettings.opt_in = on
		LeaderboardSettings.save()
	)
	parent.add_child(lb)


func _build_pixel_diorama_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Pixel Diorama"
	parent.add_child(title)

	parent.add_child(_labeled_slider(
		"Pixel scale",
		1.0, 32.0, 0.5,
		PixelDioramaSettings.pixel_scale,
		func(v: float) -> void:
			PixelDioramaSettings.pixel_scale = v
			PixelDioramaSettings.save_and_apply()
	))

	parent.add_child(_labeled_slider(
		"Color levels",
		4.0, 16.0, 1.0,
		PixelDioramaSettings.color_levels,
		func(v: float) -> void:
			PixelDioramaSettings.color_levels = v
			PixelDioramaSettings.save_and_apply()
	))

	parent.add_child(_labeled_slider(
		"Edge strength",
		0.0, 1.0, 0.02,
		PixelDioramaSettings.edge_strength,
		func(v: float) -> void:
			PixelDioramaSettings.edge_strength = v
			PixelDioramaSettings.save_and_apply()
	))

	parent.add_child(_labeled_slider(
		"Stitch strength",
		0.0, 1.0, 0.02,
		PixelDioramaSettings.stitch_strength,
		func(v: float) -> void:
			PixelDioramaSettings.stitch_strength = v
			PixelDioramaSettings.save_and_apply()
	))

	parent.add_child(_labeled_slider(
		"Pattern strength",
		0.0, 1.0, 0.02,
		PixelDioramaSettings.pattern_strength,
		func(v: float) -> void:
			PixelDioramaSettings.pattern_strength = v
			PixelDioramaSettings.save_and_apply()
	))

	var linear_tonemap := CheckBox.new()
	linear_tonemap.text = "Linear tonemap (crisp)"
	linear_tonemap.button_pressed = PixelDioramaSettings.linear_tonemap
	linear_tonemap.toggled.connect(func(on: bool) -> void:
		PixelDioramaSettings.linear_tonemap = on
		PixelDioramaSettings.save_and_apply()
	)
	parent.add_child(linear_tonemap)

	var glow := CheckBox.new()
	glow.text = "Glow enabled"
	glow.button_pressed = PixelDioramaSettings.glow_enabled
	glow.toggled.connect(func(on: bool) -> void:
		PixelDioramaSettings.glow_enabled = on
		PixelDioramaSettings.save_and_apply()
	)
	parent.add_child(glow)

	var nearest := CheckBox.new()
	nearest.text = "Nearest texture filtering"
	nearest.button_pressed = PixelDioramaSettings.nearest_texture_filter
	nearest.toggled.connect(func(on: bool) -> void:
		PixelDioramaSettings.nearest_texture_filter = on
		PixelDioramaSettings.save_and_apply()
	)
	parent.add_child(nearest)

	var low_res := CheckBox.new()
	low_res.text = "Low-res viewport upscale (480x270)"
	low_res.button_pressed = PixelDioramaSettings.low_res_viewport_enabled
	low_res.toggled.connect(func(on: bool) -> void:
		PixelDioramaSettings.low_res_viewport_enabled = on
		PixelDioramaSettings.save_and_apply()
		if on and get_tree().current_scene:
			PixelDioramaViewport.attach_to_scene(get_tree().current_scene)
		elif not on:
			PixelDioramaViewport.detach()
	)
	parent.add_child(low_res)

	var cam_snap := CheckBox.new()
	cam_snap.text = "Camera pixel snap"
	cam_snap.button_pressed = PixelDioramaSettings.camera_snap_enabled
	cam_snap.toggled.connect(func(on: bool) -> void:
		PixelDioramaSettings.camera_snap_enabled = on
		PixelDioramaSettings.save_and_apply()
	)
	parent.add_child(cam_snap)

	var aa_off := CheckBox.new()
	aa_off.text = "Disable MSAA / screen AA"
	aa_off.button_pressed = PixelDioramaSettings.anti_aliasing_off
	aa_off.toggled.connect(func(on: bool) -> void:
		PixelDioramaSettings.anti_aliasing_off = on
		PixelDioramaSettings.save_and_apply()
	)
	parent.add_child(aa_off)

	var note := Label.new()
	note.text = "Filter and AA changes apply at runtime via project settings."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	parent.add_child(note)


func _refresh_run_mode_section() -> void:
	if _scroll_vbox == null:
		return
	var existing := _scroll_vbox.get_node_or_null("WavesRunSection")
	if existing:
		existing.queue_free()
	if RunFlow.run_mode != RunModeConfig.MODE_WAVES or not RunFlow.is_run_active():
		return
	var section := VBoxContainer.new()
	section.name = "WavesRunSection"
	_scroll_vbox.add_child(section)
	var sep := HSeparator.new()
	section.add_child(sep)
	var title := Label.new()
	title.text = "Waves Run"
	GameUISkinScript.style_section_title(title)
	section.add_child(title)
	var leave := Button.new()
	leave.text = "Leave Waves (hub, no rewards kept)"
	leave.pressed.connect(func() -> void:
		close_settings()
		RunFlow.quit_waves_run()
	)
	section.add_child(leave)


func _build_run_mode_section(_parent: VBoxContainer) -> void:
	pass


func _labeled_slider(
	label_text: String,
	min_v: float,
	max_v: float,
	step: float,
	initial: float,
	on_changed: Callable
) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "%s (%.3f)" % [label_text, initial]
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(func(v: float) -> void:
		label.text = "%s (%.3f)" % [label_text, v]
		on_changed.call(v)
	)
	box.add_child(slider)
	return box


func is_open() -> bool:
	return _open


func open_settings() -> void:
	_refresh_run_mode_section()
	_open = true
	visible = true
	_refresh_backups()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_settings() -> void:
	_open = false
	visible = false
	closed.emit()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close_settings()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_accept"):
		_restore_selected()
		get_viewport().set_input_as_handled()


func _refresh_backups() -> void:
	if _backup_list == null:
		return
	_backup_list.clear()
	var backups := LocalSave.list_backups()
	if backups.is_empty():
		_backup_list.add_item("No backups yet (autosave creates them)")
		if _status_label:
			_status_label.text = ""
		return
	for entry in backups:
		_backup_list.add_item(
			"Backup %d — Lv%d — %s" % [
				entry.get("index", 0),
				entry.get("level", 1),
				entry.get("savedAt", "?"),
			]
		)
	if _status_label:
		_status_label.text = "%d backup(s) available" % backups.size()


func _restore_selected() -> void:
	if _backup_list == null:
		return
	var selected := _backup_list.get_selected_items()
	if selected.is_empty():
		return
	var backups := LocalSave.list_backups()
	var row: int = selected[0]
	if row < 0 or row >= backups.size():
		return
	var index: int = int(backups[row].get("index", 0))
	if LocalSave.restore_backup(index):
		if _status_label:
			_status_label.text = "Restored backup %d" % index
		_refresh_backups()
	elif _status_label:
		_status_label.text = "Restore failed"
