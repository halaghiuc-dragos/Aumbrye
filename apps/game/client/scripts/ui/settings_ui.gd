extends Control

## Settings overlay with save backup restore (SAVE-4.2).

signal closed

var _hint_label: Label

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

var _backdrop: ColorRect
var _open := false
var _scroll_vbox: VBoxContainer
var _pixel_section: VBoxContainer


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameUISkinScript.ensure_full_rect(self)
	AccessibilitySettings.load_from_save()
	DisplaySettings.apply()
	LeaderboardSettings.load_from_save()
	AudioSettings.load_from_save()
	PixelDioramaSettings.load_from_save()


func _build_ui_if_needed() -> void:
	if _scroll_vbox != null and is_instance_valid(_scroll_vbox):
		return
	GameUISkinScript.ensure_full_rect(self)
	for child in get_children():
		child.queue_free()
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		"Settings",
		GameUISkinScript.SETTINGS_HALF_W + 80.0,
		GameUISkinScript.SETTINGS_HALF_H + 40.0,
		false
	)
	_backdrop = shell["backdrop"]
	var content_vbox: VBoxContainer = shell["content_vbox"]
	_hint_label = MenuShellScript.add_hint(content_vbox, "Esc: back to main menu")
	var scroll := ScrollContainer.new()
	scroll.name = "Scroll"
	scroll.custom_minimum_size = Vector2(0, 380)
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_vbox.add_child(scroll)
	_scroll_vbox = VBoxContainer.new()
	_scroll_vbox.name = "ScrollVBox"
	_scroll_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_scroll_vbox)
	_build_accessibility_section(_scroll_vbox)
	_build_audio_section(_scroll_vbox)
	_build_pixel_diorama_section(_scroll_vbox)
	_refresh_run_mode_section()


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
		DisplaySettings.apply()
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
	var subtitle_scale := HSlider.new()
	subtitle_scale.name = "SubtitleScaleSlider"
	subtitle_scale.min_value = 0.8
	subtitle_scale.max_value = 1.6
	subtitle_scale.step = 0.05
	subtitle_scale.value = AccessibilitySettings.subtitle_scale
	subtitle_scale.value_changed.connect(func(v: float) -> void:
		AccessibilitySettings.subtitle_scale = v
		AccessibilitySettings.save()
	)
	parent.add_child(subtitle_scale)
	var vibration := HSlider.new()
	vibration.name = "VibrationSlider"
	vibration.min_value = 0.0
	vibration.max_value = 1.0
	vibration.step = 0.05
	vibration.value = AccessibilitySettings.vibration_intensity
	vibration.value_changed.connect(func(v: float) -> void:
		AccessibilitySettings.vibration_intensity = v
		AccessibilitySettings.save()
	)
	parent.add_child(vibration)
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


func _build_audio_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Audio"
	GameUISkinScript.style_section_title(title)
	parent.add_child(title)
	parent.add_child(_volume_slider("Master", AudioSettings.master_volume, func(v: float) -> void:
		AudioSettings.master_volume = v
		AudioSettings.save()
	))
	parent.add_child(_volume_slider("Music", AudioSettings.music_volume, func(v: float) -> void:
		AudioSettings.music_volume = v
		AudioSettings.save()
	))
	parent.add_child(_volume_slider("SFX", AudioSettings.sfx_volume, func(v: float) -> void:
		AudioSettings.sfx_volume = v
		AudioSettings.save()
	))
	parent.add_child(_volume_slider("Ambience", AudioSettings.ambience_volume, func(v: float) -> void:
		AudioSettings.ambience_volume = v
		AudioSettings.save()
	))
	parent.add_child(_volume_slider("UI", AudioSettings.ui_volume, func(v: float) -> void:
		AudioSettings.ui_volume = v
		AudioSettings.save()
	))


func _volume_slider(label_text: String, initial: float, on_changed: Callable) -> HBoxContainer:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = label_text
	label.custom_minimum_size.x = 90.0
	row.add_child(label)
	var slider := HSlider.new()
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(on_changed)
	row.add_child(slider)
	return row


func _build_pixel_diorama_section(parent: VBoxContainer) -> void:
	var section := VBoxContainer.new()
	section.name = "PixelDioramaSection"
	section.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	parent.add_child(section)
	_pixel_section = section
	_populate_pixel_diorama_section()


## Rebuilt wholesale when the beauty preset is restored, so every widget shows the
## value that was actually applied rather than the one the user last dragged.
func _populate_pixel_diorama_section() -> void:
	if _pixel_section == null:
		return
	for child in _pixel_section.get_children():
		child.queue_free()

	_pixel_section.add_child(HSeparator.new())
	var title := Label.new()
	title.text = "Pixel Diorama"
	GameUISkinScript.style_section_title(title)
	_pixel_section.add_child(title)

	var preset_row := HBoxContainer.new()
	var preset_label := Label.new()
	preset_label.text = "Render resolution"
	preset_row.add_child(preset_label)
	var preset_options := OptionButton.new()
	for i in PixelDioramaSettings.RESOLUTION_PRESETS.size():
		var preset: Dictionary = PixelDioramaSettings.RESOLUTION_PRESETS[i]
		preset_options.add_item(str(preset.get("label", "?")), i)
	var current_preset := PixelDioramaSettings.current_resolution_preset()
	if current_preset >= 0:
		preset_options.selected = current_preset
	else:
		preset_options.add_item(
			"Custom (%d x %d)" % [PixelDioramaSettings.viewport_width, PixelDioramaSettings.viewport_height]
		)
		preset_options.selected = preset_options.item_count - 1
	preset_options.item_selected.connect(func(idx: int) -> void:
		PixelDioramaSettings.set_resolution_preset(idx)
		PixelDioramaSettings.save_and_apply()
	)
	preset_row.add_child(preset_options)
	_pixel_section.add_child(preset_row)

	var low_res := CheckBox.new()
	low_res.text = "Low-res viewport upscale"
	low_res.button_pressed = PixelDioramaSettings.low_res_viewport_enabled
	low_res.toggled.connect(func(on: bool) -> void:
		PixelDioramaSettings.low_res_viewport_enabled = on
		PixelDioramaSettings.save_and_apply()
		if on and get_tree().current_scene:
			PixelDioramaViewport.attach_to_scene(get_tree().current_scene)
		elif not on:
			PixelDioramaViewport.detach()
	)
	_pixel_section.add_child(low_res)

	_pixel_section.add_child(_toggle(
		"Nearest texture filtering",
		PixelDioramaSettings.nearest_texture_filter,
		func(on: bool) -> void: PixelDioramaSettings.nearest_texture_filter = on
	))
	_pixel_section.add_child(_toggle(
		"Disable MSAA / screen AA",
		PixelDioramaSettings.anti_aliasing_off,
		func(on: bool) -> void: PixelDioramaSettings.anti_aliasing_off = on
	))

	_pixel_section.add_child(_subsection_label("Surfaces"))
	_pixel_section.add_child(_labeled_slider(
		"Pixel scale", 1.0, 32.0, 0.5, PixelDioramaSettings.pixel_scale,
		func(v: float) -> void: PixelDioramaSettings.pixel_scale = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Color levels", 4.0, 16.0, 1.0, PixelDioramaSettings.color_levels,
		func(v: float) -> void: PixelDioramaSettings.color_levels = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Pattern strength", 0.0, 1.0, 0.02, PixelDioramaSettings.pattern_strength,
		func(v: float) -> void: PixelDioramaSettings.pattern_strength = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Edge strength", 0.0, 1.0, 0.02, PixelDioramaSettings.edge_strength,
		func(v: float) -> void: PixelDioramaSettings.edge_strength = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Stitch strength", 0.0, 1.0, 0.02, PixelDioramaSettings.stitch_strength,
		func(v: float) -> void: PixelDioramaSettings.stitch_strength = v
	))

	_pixel_section.add_child(_subsection_label("Shading"))
	_pixel_section.add_child(_labeled_slider(
		"Light bands", 2.0, 16.0, 1.0, PixelDioramaSettings.shade_bands,
		func(v: float) -> void: PixelDioramaSettings.shade_bands = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Band dithering", 0.0, 1.0, 0.05, PixelDioramaSettings.shade_dither,
		func(v: float) -> void: PixelDioramaSettings.shade_dither = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Shadow softness (light wrap)", 0.0, 1.0, 0.05, PixelDioramaSettings.light_wrap,
		func(v: float) -> void: PixelDioramaSettings.light_wrap = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Silhouette rim", 0.0, 0.5, 0.01, PixelDioramaSettings.rim_strength,
		func(v: float) -> void: PixelDioramaSettings.rim_strength = v
	))
	_pixel_section.add_child(_toggle(
		"Linear tonemap (crisp)",
		PixelDioramaSettings.linear_tonemap,
		func(on: bool) -> void: PixelDioramaSettings.linear_tonemap = on
	))
	_pixel_section.add_child(_toggle(
		"Glow on emissives",
		PixelDioramaSettings.glow_enabled,
		func(on: bool) -> void: PixelDioramaSettings.glow_enabled = on
	))

	_pixel_section.add_child(_subsection_label("Performance"))
	var shadow_row := HBoxContainer.new()
	var shadow_label := Label.new()
	shadow_label.text = "Shadow quality"
	shadow_row.add_child(shadow_label)
	var shadow_opts := OptionButton.new()
	for i in PixelDioramaSettings.QUALITY_LABELS.size():
		shadow_opts.add_item(PixelDioramaSettings.QUALITY_LABELS[i], i)
	shadow_opts.selected = PixelDioramaSettings.shadow_quality
	shadow_opts.item_selected.connect(func(idx: int) -> void:
		PixelDioramaSettings.shadow_quality = idx
		PixelDioramaSettings.save_and_apply()
	)
	shadow_row.add_child(shadow_opts)
	_pixel_section.add_child(shadow_row)
	var particle_row := HBoxContainer.new()
	var particle_label := Label.new()
	particle_label.text = "Particle quality"
	particle_row.add_child(particle_label)
	var particle_opts := OptionButton.new()
	for i in PixelDioramaSettings.QUALITY_LABELS.size():
		particle_opts.add_item(PixelDioramaSettings.QUALITY_LABELS[i], i)
	particle_opts.selected = PixelDioramaSettings.particle_quality
	particle_opts.item_selected.connect(func(idx: int) -> void:
		PixelDioramaSettings.particle_quality = idx
		PixelDioramaSettings.save_and_apply()
	)
	particle_row.add_child(particle_opts)
	_pixel_section.add_child(particle_row)

	_pixel_section.add_child(_subsection_label("Screen finish"))
	_pixel_section.add_child(_toggle(
		"Enable screen finish pass",
		PixelDioramaSettings.screen_finish_enabled,
		func(on: bool) -> void: PixelDioramaSettings.screen_finish_enabled = on
	))
	_pixel_section.add_child(_labeled_slider(
		"Contrast", 0.5, 2.0, 0.01, PixelDioramaSettings.screen_contrast,
		func(v: float) -> void: PixelDioramaSettings.screen_contrast = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Saturation", 0.0, 2.0, 0.01, PixelDioramaSettings.screen_saturation,
		func(v: float) -> void: PixelDioramaSettings.screen_saturation = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Vignette", 0.0, 1.0, 0.02, PixelDioramaSettings.vignette_strength,
		func(v: float) -> void: PixelDioramaSettings.vignette_strength = v
	))
	_pixel_section.add_child(_labeled_slider(
		"Palette posterize (0 = off)", 0.0, 32.0, 1.0, PixelDioramaSettings.posterize_levels,
		func(v: float) -> void: PixelDioramaSettings.posterize_levels = v
	))

	var restore := Button.new()
	restore.text = "Restore recommended look"
	restore.pressed.connect(func() -> void:
		PixelDioramaSettings.apply_beauty_defaults()
		_populate_pixel_diorama_section()
	)
	_pixel_section.add_child(restore)

	var note := Label.new()
	note.text = "Filter and AA changes apply at runtime via project settings."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pixel_section.add_child(note)


func _subsection_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	GameUISkinScript.style_section_title(label)
	return label


func _toggle(text: String, initial: bool, on_changed: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.button_pressed = initial
	box.toggled.connect(func(on: bool) -> void:
		on_changed.call(on)
		PixelDioramaSettings.save_and_apply()
	)
	return box


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
	GameUISkinScript.wire_button_sfx(leave)
	section.add_child(leave)


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
		PixelDioramaSettings.save_and_apply()
	)
	box.add_child(slider)
	return box


func is_open() -> bool:
	return _open


func open_settings() -> void:
	GameUISkinScript.ensure_full_rect(self)
	_build_ui_if_needed()
	_recenter_panel()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_refresh_run_mode_section()
	_open = true
	visible = true
	move_to_front()
	var panel := get_node_or_null("Panel") as PanelContainer
	if panel:
		panel.visible = true
		panel.move_to_front()
	if _backdrop:
		_backdrop.visible = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _recenter_panel() -> void:
	var panel := get_node_or_null("Panel") as PanelContainer
	if panel == null:
		return
	var clamped := GameUISkinScript.clamped_panel_half_size(
		GameUISkinScript.SETTINGS_HALF_W + 80.0,
		GameUISkinScript.SETTINGS_HALF_H + 40.0,
		self
	)
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -clamped.x
	panel.offset_top = -clamped.y
	panel.offset_right = clamped.x
	panel.offset_bottom = clamped.y


func close_settings() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	closed.emit()
	if get_tree().get_first_node_in_group("player"):
		Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close_settings()
		get_viewport().set_input_as_handled()
