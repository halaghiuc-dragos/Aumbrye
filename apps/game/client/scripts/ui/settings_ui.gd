extends Control

## Tabbed settings overlay driven by SettingsSchema (SET-01..SET-17).

signal closed
signal cancel_requested

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const SettingsSchemaScript := preload("res://scripts/ui/settings_schema.gd")
const SettingsRowScene := preload("res://scenes/ui/settings_row.tscn")
const BindingCaptureModalScript := preload("res://scripts/ui/binding_capture_modal.gd")
const PrivacySettingsScript := preload("res://scripts/platform/privacy_settings.gd")

var _backdrop: ColorRect
var _open := false
var _content_vbox: VBoxContainer
var _tab_bar: HBoxContainer
var _tab_buttons: Array[Button] = []
var _scroll: ScrollContainer
var _page_host: VBoxContainer
var _active_page_idx := 0
var _pixel_disclosure_open := false
var _pixel_host: VBoxContainer
var _rows_by_page: Dictionary = {}
var _binding_modal: BindingCaptureModalScript
var _footer_hint: Control


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameUISkinScript.ensure_full_rect(self)


func _build_ui_if_needed() -> void:
	if _page_host != null and is_instance_valid(_page_host):
		return
	GameUISkinScript.ensure_full_rect(self)
	for child in get_children():
		child.queue_free()
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		tr("SETTINGS_TITLE"),
		GameUISkinScript.SETTINGS_HALF_W + 120.0,
		GameUISkinScript.SETTINGS_HALF_H + 80.0,
		false
	)
	_backdrop = shell["backdrop"]
	_content_vbox = shell["content_vbox"]
	_build_tab_bar()
	_scroll = ScrollContainer.new()
	_scroll.name = "Scroll"
	_scroll.custom_minimum_size = Vector2(0, 380)
	_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.follow_focus = true
	_content_vbox.add_child(_scroll)
	_page_host = VBoxContainer.new()
	_page_host.name = "PageHost"
	_page_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_scroll.add_child(_page_host)
	_build_footer()
	_rebuild_active_page()


func _build_tab_bar() -> void:
	_tab_bar = HBoxContainer.new()
	_tab_bar.name = "TabBar"
	_tab_bar.add_theme_constant_override("separation", 6)
	_tab_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_content_vbox.add_child(_tab_bar)
	_tab_buttons.clear()
	for i in SettingsSchemaScript.PAGES.size():
		var page := SettingsSchemaScript.PAGES[i]
		var btn := GameUISkinScript.make_button(tr(SettingsSchemaScript.page_name_key(page)))
		btn.toggle_mode = true
		btn.focus_mode = Control.FOCUS_ALL
		var page_idx := i
		btn.pressed.connect(func() -> void: _select_page(page_idx))
		GameUISkinScript.wire_button_sfx(btn)
		_tab_bar.add_child(btn)
		_tab_buttons.append(btn)
	if not _tab_buttons.is_empty():
		_tab_buttons[0].button_pressed = true


func _build_footer() -> void:
	var footer := HBoxContainer.new()
	footer.name = "FooterRow"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", 16)
	var reset_btn := GameUISkinScript.make_button(tr("SETTINGS_RESET_PAGE"))
	reset_btn.pressed.connect(_on_reset_page)
	GameUISkinScript.wire_button_sfx(reset_btn)
	footer.add_child(reset_btn)
	var back_btn := GameUISkinScript.make_button(tr("SETTINGS_BACK"))
	back_btn.pressed.connect(close_settings)
	GameUISkinScript.wire_button_sfx(back_btn)
	footer.add_child(back_btn)
	_content_vbox.add_child(footer)
	_footer_hint = GameUISkinScript.make_symbol_caption_row(
		InputGlyphService.get_action_glyph("ui_cancel"), tr("SETTINGS_HINT_BACK")
	)
	_content_vbox.add_child(_footer_hint)


func _select_page(idx: int) -> void:
	_active_page_idx = clampi(idx, 0, SettingsSchemaScript.PAGES.size() - 1)
	for i in _tab_buttons.size():
		_tab_buttons[i].button_pressed = i == _active_page_idx
	_rebuild_active_page()
	if _tab_buttons.size() > _active_page_idx:
		_tab_buttons[_active_page_idx].grab_focus()


func _rebuild_active_page() -> void:
	if _page_host == null:
		return
	for child in _page_host.get_children():
		child.queue_free()
	_rows_by_page.clear()
	var page := SettingsSchemaScript.PAGES[_active_page_idx]
	match page:
		"controls":
			_build_controls_page()
		"advanced":
			_build_advanced_page()
		"display":
			_build_schema_page(page)
			_build_pixel_disclosure()
		_:
			_build_schema_page(page)
	_wire_row_focus_neighbors()


func _build_schema_page(page: String) -> void:
	var rows: Array[SettingsRow] = []
	for entry in SettingsSchemaScript.entries_for_page(page):
		var row := SettingsRowScene.instantiate() as SettingsRow
		row.configure(entry)
		_page_host.add_child(row)
		rows.append(row)
		if page == "audio":
			_add_audio_test_button(row, str(entry.get("id", "")))
	_rows_by_page[page] = rows


func _add_audio_test_button(row: SettingsRow, setting_id: String) -> void:
	var test := GameUISkinScript.make_button(tr("SETTINGS_AUDIO_TEST"))
	test.custom_minimum_size = Vector2(56, 28)
	test.pressed.connect(func() -> void: _play_audio_test(setting_id))
	GameUISkinScript.wire_button_sfx(test)
	var widget := row.get_widget()
	if widget and widget.get_parent():
		var host := widget.get_parent() as Control
		if host:
			host.add_child(test)


func _play_audio_test(setting_id: String) -> void:
	if AudioDirector == null:
		return
	match setting_id:
		"master_volume", "music_volume":
			AudioDirector.play_ui_sfx()
		"sfx_volume":
			AudioDirector.play_sfx("hit_light")
		"ambience_volume":
			AudioDirector.play_ui_sfx()
		_:
			AudioDirector.play_ui_sfx()


func _build_pixel_disclosure() -> void:
	var toggle := GameUISkinScript.make_button(
		tr("SETTINGS_PIXEL_ADVANCED") if not _pixel_disclosure_open else tr("SETTINGS_PIXEL_HIDE")
	)
	toggle.pressed.connect(
		func() -> void:
			_pixel_disclosure_open = not _pixel_disclosure_open
			_rebuild_active_page()
	)
	GameUISkinScript.wire_button_sfx(toggle)
	_page_host.add_child(toggle)
	if not _pixel_disclosure_open:
		return
	_pixel_host = VBoxContainer.new()
	_pixel_host.name = "PixelDioramaHost"
	_pixel_host.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_page_host.add_child(_pixel_host)
	_populate_pixel_section(_pixel_host)


func _populate_pixel_section(parent: VBoxContainer) -> void:
	for child in parent.get_children():
		child.queue_free()
	var title := Label.new()
	title.text = tr("SETTINGS_PIXEL_SECTION")
	title.theme_type_variation = GameUISkinScript.VAR_SECTION_TITLE
	parent.add_child(title)
	var preset_row := _pixel_preset_row()
	parent.add_child(preset_row)
	parent.add_child(
		_pixel_toggle(
			tr("SETTINGS_LOW_RES_VIEWPORT"),
			PixelDioramaSettings.low_res_viewport_enabled,
			func(on: bool) -> void:
				PixelDioramaSettings.low_res_viewport_enabled = on
				PixelDioramaSettings.save_and_apply()
				if on and get_tree().current_scene:
					PixelDioramaViewport.attach_to_scene(get_tree().current_scene)
				elif not on:
					PixelDioramaViewport.detach()))
	for slider_def in [
		["pixel_scale", 1.0, 32.0, 0.5, PixelDioramaSettings.pixel_scale],
		["color_levels", 4.0, 16.0, 1.0, PixelDioramaSettings.color_levels],
		["pattern_strength", 0.0, 1.0, 0.02, PixelDioramaSettings.pattern_strength],
	]:
		parent.add_child(_pixel_slider(slider_def[0], slider_def[1], slider_def[2], slider_def[3], slider_def[4]))
	var restore := GameUISkinScript.make_button(tr("SETTINGS_PIXEL_RESTORE"))
	restore.pressed.connect(
		func() -> void:
			PixelDioramaSettings.apply_beauty_defaults()
			_rebuild_active_page()
	)
	GameUISkinScript.wire_button_sfx(restore)
	parent.add_child(restore)


func _pixel_preset_row() -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = tr("SETTINGS_RENDER_RESOLUTION")
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(label)
	row.add_child(label)
	var opts := OptionButton.new()
	for i in PixelDioramaSettings.RESOLUTION_PRESETS.size():
		var preset: Dictionary = PixelDioramaSettings.RESOLUTION_PRESETS[i]
		opts.add_item(str(preset.get("label", "?")), i)
	var current := PixelDioramaSettings.current_resolution_preset()
	opts.selected = current if current >= 0 else opts.item_count - 1
	opts.item_selected.connect(
		func(idx: int) -> void:
			PixelDioramaSettings.set_resolution_preset(idx)
			PixelDioramaSettings.save_and_apply()
	)
	row.add_child(opts)
	return row


func _pixel_toggle(text: String, initial: bool, on_changed: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = initial
	box.toggled.connect(
		func(on: bool) -> void:
			on_changed.call(on)
			PixelDioramaSettings.apply_live()
			PixelDioramaSettings.request_save()
	)
	return box


func _pixel_slider(
	label_key: String, min_v: float, max_v: float, step: float, initial: float
) -> VBoxContainer:
	var box := VBoxContainer.new()
	var label := Label.new()
	label.text = "%s %s" % [tr("SETTINGS_%s_NAME" % label_key.to_upper()), str(initial)]
	GameUISkinScript.style_body_label(label)
	box.add_child(label)
	var slider := HSlider.new()
	slider.min_value = min_v
	slider.max_value = max_v
	slider.step = step
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(
		func(v: float) -> void:
			label.text = "%s %.2f" % [tr("SETTINGS_%s_NAME" % label_key.to_upper()), v]
			match label_key:
				"pixel_scale":
					PixelDioramaSettings.pixel_scale = v
				"color_levels":
					PixelDioramaSettings.color_levels = v
				"pattern_strength":
					PixelDioramaSettings.pattern_strength = v
			PixelDioramaSettings.mark_tuning_user_edited()
			PixelDioramaSettings.apply_live()
	)
	slider.drag_ended.connect(func(_changed: bool) -> void: PixelDioramaSettings.request_save())
	box.add_child(slider)
	return box


func _build_controls_page() -> void:
	for action in InputRebindService.get_rebindable_actions():
		var row := PanelContainer.new()
		row.focus_mode = Control.FOCUS_ALL
		var hbox := HBoxContainer.new()
		hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(hbox)
		var text := VBoxContainer.new()
		text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_lbl := Label.new()
		name_lbl.text = InputRebindService.get_action_label(action)
		name_lbl.theme_type_variation = GameUISkinScript.VAR_SECTION_TITLE
		text.add_child(name_lbl)
		var desc_lbl := Label.new()
		desc_lbl.text = tr("SETTINGS_BINDING_DESC")
		desc_lbl.theme_type_variation = GameUISkinScript.VAR_BODY_TEXT
		desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.add_child(desc_lbl)
		hbox.add_child(text)
		var kb_btn := GameUISkinScript.make_button(_binding_label(action, true))
		kb_btn.pressed.connect(func() -> void: _start_binding_capture(action, "keyboard"))
		GameUISkinScript.wire_button_sfx(kb_btn)
		hbox.add_child(kb_btn)
		var pad_btn := GameUISkinScript.make_button(_binding_label(action, false))
		pad_btn.pressed.connect(func() -> void: _start_binding_capture(action, "gamepad"))
		GameUISkinScript.wire_button_sfx(pad_btn)
		hbox.add_child(pad_btn)
		var reset_btn := GameUISkinScript.make_button(tr("SETTINGS_BINDING_RESET"))
		reset_btn.pressed.connect(
			func() -> void:
				InputRebindService.reset_action(action)
				_rebuild_active_page()
		)
		GameUISkinScript.wire_button_sfx(reset_btn)
		hbox.add_child(reset_btn)
		_page_host.add_child(row)
	var reset_all := GameUISkinScript.make_button(tr("SETTINGS_BINDING_RESET_ALL"))
	reset_all.pressed.connect(
		func() -> void:
			InputRebindService.reset_all()
			_rebuild_active_page()
	)
	GameUISkinScript.wire_button_sfx(reset_all)
	_page_host.add_child(reset_all)


func _binding_label(action: StringName, keyboard: bool) -> String:
	for event in InputRebindService.get_action_events(action):
		var is_kb := event is InputEventKey or event is InputEventMouseButton
		if keyboard == is_kb:
			return event.as_text()
	return tr("SETTINGS_BINDING_UNBOUND")


func _start_binding_capture(action: StringName, device_family: String) -> void:
	if _binding_modal != null and is_instance_valid(_binding_modal):
		_binding_modal.queue_free()
	_binding_modal = BindingCaptureModalScript.new()
	_binding_modal.open(self, action, device_family)
	_binding_modal.captured.connect(func(_a: StringName, _e: InputEvent) -> void: _rebuild_active_page())
	_binding_modal.cancelled.connect(func() -> void: _binding_modal = null)


func _build_advanced_page() -> void:
	var privacy := CheckBox.new()
	privacy.text = tr("SETTINGS_CRASH_REPORTS")
	privacy.button_pressed = PrivacySettingsScript.send_crash_reports
	privacy.toggled.connect(
		func(on: bool) -> void:
			PrivacySettingsScript.send_crash_reports = on
			PrivacySettingsScript.save()
	)
	_page_host.add_child(privacy)
	var backups := LocalSave.list_backups()
	if backups.is_empty():
		var none := Label.new()
		none.text = tr("SETTINGS_NO_BACKUPS")
		none.theme_type_variation = GameUISkinScript.VAR_BODY_TEXT
		_page_host.add_child(none)
	else:
		for backup in backups:
			var index: int = int(backup.get("index", 0))
			var saved_at := str(backup.get("savedAt", "unknown"))
			var btn := GameUISkinScript.make_button(
				tr("SETTINGS_RESTORE_BACKUP") % [index, saved_at]
			)
			btn.pressed.connect(
				func() -> void:
					_confirm_restore_backup(index)
			)
			GameUISkinScript.wire_button_sfx(btn)
			_page_host.add_child(btn)


func _confirm_restore_backup(index: int) -> void:
	MenuShellScript.show_confirmation(
		self,
		tr("SETTINGS_RESTORE_TITLE"),
		tr("SETTINGS_RESTORE_BODY") % index,
		func() -> void:
			if LocalSave.restore_backup(index):
				close_settings(),
		Callable(),
		tr("SETTINGS_RESTORE_CONFIRM"),
		tr("SETTINGS_BACK")
	)


func _wire_row_focus_neighbors() -> void:
	var focusables: Array[Control] = []
	_collect_focusables(_page_host, focusables)
	for i in focusables.size():
		var current := focusables[i]
		var prev := focusables[(i - 1 + focusables.size()) % focusables.size()]
		var next := focusables[(i + 1) % focusables.size()]
		current.focus_neighbor_top = prev.get_path()
		current.focus_neighbor_bottom = next.get_path()


func _collect_focusables(node: Node, out: Array[Control]) -> void:
	if node is Control:
		var ctrl := node as Control
		if ctrl.focus_mode != Control.FOCUS_NONE and ctrl.visible:
			out.append(ctrl)
	for child in node.get_children():
		_collect_focusables(child, out)


func _on_reset_page() -> void:
	var page := SettingsSchemaScript.PAGES[_active_page_idx]
	if _rows_by_page.has(page):
		for row in _rows_by_page[page]:
			if row is SettingsRow:
				(row as SettingsRow).reset_to_default()
	if page == "display" and _pixel_disclosure_open:
		PixelDioramaSettings.apply_beauty_defaults()
		_rebuild_active_page()


func is_open() -> bool:
	return _open


func open_settings() -> void:
	GameUISkinScript.ensure_full_rect(self)
	_build_ui_if_needed()
	_recenter_panel()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_open = true
	visible = true
	move_to_front()
	if _backdrop:
		_backdrop.visible = true
	var panel := get_node_or_null("Panel") as PanelContainer
	if panel:
		panel.visible = true
	if _menu_stack():
		_menu_stack().push(self)
	_rebuild_active_page()
	if _tab_buttons.size() > _active_page_idx:
		_tab_buttons[_active_page_idx].grab_focus()


func _recenter_panel() -> void:
	var panel := get_node_or_null("Panel") as PanelContainer
	if panel == null:
		return
	var clamped := GameUISkinScript.clamped_panel_half_size(
		GameUISkinScript.SETTINGS_HALF_W + 120.0, GameUISkinScript.SETTINGS_HALF_H + 80.0, self
	)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -clamped.x
	panel.offset_top = -clamped.y
	panel.offset_right = clamped.x
	panel.offset_bottom = clamped.y


func close_settings() -> void:
	if not _open:
		return
	AccessibilitySettings.commit()
	AudioSettings.commit()
	PixelDioramaSettings.save()
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _menu_stack():
		_menu_stack().pop(self)
	closed.emit()


func _menu_stack() -> Node:
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_node_or_null("/root/MenuStack")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_page_next") or (event is InputEventKey and event.pressed and event.keycode == KEY_E):
		_select_page((_active_page_idx + 1) % SettingsSchemaScript.PAGES.size())
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_page_prev") or (event is InputEventKey and event.pressed and event.keycode == KEY_Q):
		_select_page(
			(_active_page_idx - 1 + SettingsSchemaScript.PAGES.size())
			% SettingsSchemaScript.PAGES.size()
		)
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		if _menu_stack() and _menu_stack().handles_cancel(self):
			cancel_requested.emit()
			close_settings()
			get_viewport().set_input_as_handled()
