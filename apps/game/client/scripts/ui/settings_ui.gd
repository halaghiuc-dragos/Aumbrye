extends Control

## Settings overlay with save backup restore (SAVE-4.2).

signal closed

var _hint_label: Label

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const LocaleSettingsScript := preload("res://scripts/ui/locale_settings.gd")
const PrivacySettingsScript := preload("res://scripts/platform/privacy_settings.gd")

var _backdrop: ColorRect
var _open := false
var _scroll_vbox: VBoxContainer
var _pixel_section: VBoxContainer
var _controls_section: VBoxContainer
var _capturing_action: StringName = &""
var _conflict_label: Label


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	GameUISkinScript.ensure_full_rect(self)
	AccessibilitySettings.load_from_save()
	DisplaySettings.apply()
	LeaderboardSettings.load_from_save()
	PrivacySettingsScript.load_from_save()
	AudioSettings.load_from_save()
	PixelDioramaSettings.load_from_save()
	LocaleSettingsScript.load_from_save()


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
	_build_platform_section(_scroll_vbox)
	_build_controls_section(_scroll_vbox)
	_build_audio_section(_scroll_vbox)
	_build_cloud_section(_scroll_vbox)
	_build_privacy_section(_scroll_vbox)
	_build_pixel_diorama_section(_scroll_vbox)
	_build_advanced_save_section(_scroll_vbox)
	_refresh_run_mode_section()


func _build_accessibility_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Accessibility"
	parent.add_child(title)
	var on_ui_scale := func(v: float) -> void:
		AccessibilitySettings.ui_scale = v
		AccessibilitySettings.save()
		DisplaySettings.apply()
	parent.add_child(
		_accessibility_scale_row("UI scale", 0.8, 1.5, 0.05, AccessibilitySettings.ui_scale, on_ui_scale)
	)
	var shake := CheckBox.new()
	shake.text = "Reduce camera shake"
	shake.button_pressed = AccessibilitySettings.reduce_camera_shake
	shake.toggled.connect(
		func(on: bool) -> void:
			AccessibilitySettings.reduce_camera_shake = on
			AccessibilitySettings.save()
	)
	parent.add_child(shake)
	var on_subtitle_scale := func(v: float) -> void:
		AccessibilitySettings.subtitle_scale = v
		AccessibilitySettings.save()
		_refresh_open_dialogue_subtitles()
	parent.add_child(
		_accessibility_scale_row(
			"Subtitle scale",
			0.8,
			1.6,
			0.05,
			AccessibilitySettings.subtitle_scale,
			on_subtitle_scale
		)
	)
	var on_vibration := func(v: float) -> void:
		AccessibilitySettings.vibration_intensity = v
		AccessibilitySettings.save()
	parent.add_child(
		_accessibility_vibration_row(
			AccessibilitySettings.vibration_intensity,
			on_vibration
		)
	)
	var on_mouse_sens := func(v: float) -> void:
		AccessibilitySettings.camera_mouse_sensitivity = v
		AccessibilitySettings.save()
	parent.add_child(
		_accessibility_scale_row(
			"Mouse sensitivity",
			AccessibilitySettings.CAMERA_MOUSE_MIN,
			AccessibilitySettings.CAMERA_MOUSE_MAX,
			0.05,
			AccessibilitySettings.camera_mouse_sensitivity,
			on_mouse_sens
		)
	)
	var on_stick_sens := func(v: float) -> void:
		AccessibilitySettings.camera_stick_sensitivity = v
		AccessibilitySettings.save()
	parent.add_child(
		_accessibility_scale_row(
			"Stick sensitivity",
			AccessibilitySettings.CAMERA_STICK_MIN,
			AccessibilitySettings.CAMERA_STICK_MAX,
			0.05,
			AccessibilitySettings.camera_stick_sensitivity,
			on_stick_sens
		)
	)
	var on_fov := func(v: float) -> void:
		AccessibilitySettings.camera_fov = v
		AccessibilitySettings.save()
	parent.add_child(
		_accessibility_scale_row(
			"Camera FOV",
			AccessibilitySettings.CAMERA_FOV_MIN,
			AccessibilitySettings.CAMERA_FOV_MAX,
			1.0,
			AccessibilitySettings.camera_fov,
			on_fov
		)
	)
	var on_curve := func(v: float) -> void:
		AccessibilitySettings.camera_stick_curve = v
		AccessibilitySettings.save()
	parent.add_child(
		_accessibility_scale_row(
			"Stick response curve",
			AccessibilitySettings.CAMERA_STICK_CURVE_MIN,
			AccessibilitySettings.CAMERA_STICK_CURVE_MAX,
			0.1,
			AccessibilitySettings.camera_stick_curve,
			on_curve
		)
	)
	var on_deadzone := func(v: float) -> void:
		AccessibilitySettings.camera_stick_deadzone = v
		AccessibilitySettings.save()
	parent.add_child(
		_accessibility_scale_row(
			"Stick deadzone",
			AccessibilitySettings.CAMERA_STICK_DEADZONE_MIN,
			AccessibilitySettings.CAMERA_STICK_DEADZONE_MAX,
			0.01,
			AccessibilitySettings.camera_stick_deadzone,
			on_deadzone
		)
	)
	var invert_y := CheckBox.new()
	invert_y.text = "Invert look Y"
	invert_y.button_pressed = AccessibilitySettings.camera_invert_y
	invert_y.toggled.connect(
		func(on: bool) -> void:
			AccessibilitySettings.camera_invert_y = on
			AccessibilitySettings.save()
	)
	parent.add_child(invert_y)
	var cb := OptionButton.new()
	cb.add_item("Default", 0)
	cb.add_item("Protanopia", 1)
	cb.add_item("Deuteranopia", 2)
	cb.add_item("Tritanopia", 3)
	match AccessibilitySettings.colorblind_mode:
		"protanopia":
			cb.selected = 1
		"deuteranopia":
			cb.selected = 2
		"tritanopia":
			cb.selected = 3
		_:
			cb.selected = 0
	cb.item_selected.connect(
		func(idx: int) -> void:
			var modes := ["default", "protanopia", "deuteranopia", "tritanopia"]
			AccessibilitySettings.colorblind_mode = modes[idx]
			AccessibilitySettings.save()
	)
	parent.add_child(cb)
	var lb := CheckBox.new()
	lb.text = "Submit clear times to leaderboards (opt-in)"
	lb.button_pressed = LeaderboardSettings.opt_in
	lb.toggled.connect(
		func(on: bool) -> void:
			LeaderboardSettings.opt_in = on
			LeaderboardSettings.save()
	)
	parent.add_child(lb)


func _build_platform_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Platform"
	GameUISkinScript.style_section_title(title)
	parent.add_child(title)
	var steam_label := Label.new()
	if SteamService and SteamService.is_stub_mode:
		steam_label.text = "Steam: unavailable (dev stub)"
	else:
		steam_label.text = "Steam: connected"
	GameUISkinScript.style_body_label(steam_label)
	parent.add_child(steam_label)
	var achievements_btn := Button.new()
	achievements_btn.text = "View achievements"
	achievements_btn.pressed.connect(
		func() -> void:
			if PlayerControls:
				PlayerControls.open_achievements()
	)
	parent.add_child(achievements_btn)


func _build_controls_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Controls"
	GameUISkinScript.style_section_title(title)
	parent.add_child(title)

	var locale_row := HBoxContainer.new()
	var locale_label := Label.new()
	locale_label.text = "Language"
	locale_label.custom_minimum_size.x = 120.0
	locale_row.add_child(locale_label)
	var locale_opts := OptionButton.new()
	locale_opts.add_item("English", 0)
	locale_opts.add_item("Română", 1)
	locale_opts.selected = 0 if LocaleSettingsScript.locale == "en" else 1
	locale_opts.item_selected.connect(
		func(idx: int) -> void: LocaleSettingsScript.set_locale_code("en" if idx == 0 else "ro")
	)
	locale_row.add_child(locale_opts)
	parent.add_child(locale_row)

	_conflict_label = Label.new()
	_conflict_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_conflict_label.visible = false
	GameUISkinScript.style_body_label(_conflict_label)
	parent.add_child(_conflict_label)

	_controls_section = VBoxContainer.new()
	_controls_section.name = "ControlsSection"
	parent.add_child(_controls_section)
	_populate_controls_section()

	var reset_all := Button.new()
	reset_all.text = "Reset all bindings"
	reset_all.pressed.connect(
		func() -> void:
			InputRebindService.reset_all()
			_populate_controls_section()
			_conflict_label.visible = false
	)
	GameUISkinScript.wire_button_sfx(reset_all)
	parent.add_child(reset_all)


func _populate_controls_section() -> void:
	if _controls_section == null:
		return
	for child in _controls_section.get_children():
		child.queue_free()
	for action in InputRebindService.get_rebindable_actions():
		var row := HBoxContainer.new()
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var name_label := Label.new()
		name_label.text = InputRebindService.get_action_label(action)
		name_label.custom_minimum_size.x = 140.0
		row.add_child(name_label)
		var binding_label := Label.new()
		binding_label.text = InputRebindService.get_action_binding_text(action)
		binding_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		binding_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		row.add_child(binding_label)
		var rebind_btn := Button.new()
		rebind_btn.text = "Rebind" if _capturing_action != action else "Press any key..."
		rebind_btn.pressed.connect(
			func() -> void:
				_capturing_action = action
				_conflict_label.text = (
					"Press a key, mouse button, or gamepad input for %s."
					% InputRebindService.get_action_label(action)
				)
				_conflict_label.visible = true
				_populate_controls_section()
		)
		GameUISkinScript.wire_button_sfx(rebind_btn)
		row.add_child(rebind_btn)
		var reset_btn := Button.new()
		reset_btn.text = "Reset"
		reset_btn.pressed.connect(
			func() -> void:
				InputRebindService.reset_action(action)
				_populate_controls_section()
		)
		GameUISkinScript.wire_button_sfx(reset_btn)
		row.add_child(reset_btn)
		_controls_section.add_child(row)
	_refresh_binding_conflicts()


func _refresh_binding_conflicts() -> void:
	if _conflict_label == null:
		return
	var conflicts := InputBindings.conflicts()
	if conflicts.is_empty():
		if _capturing_action == &"":
			_conflict_label.visible = false
		return
	var lines: PackedStringArray = []
	for signature in conflicts.keys():
		var actions: Array = conflicts[signature]
		lines.append("%s: %s" % [signature, ", ".join(actions)])
	_conflict_label.text = "Binding conflicts: %s" % ", ".join(lines)
	_conflict_label.visible = true


func _build_audio_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Audio"
	GameUISkinScript.style_section_title(title)
	parent.add_child(title)
	var on_master := func(v: float) -> void:
		AudioSettings.master_volume = v
		AudioSettings.save()
	parent.add_child(_volume_slider("Master", AudioSettings.master_volume, on_master))
	var on_music := func(v: float) -> void:
		AudioSettings.music_volume = v
		AudioSettings.save()
	parent.add_child(_volume_slider("Music", AudioSettings.music_volume, on_music))
	var on_sfx := func(v: float) -> void:
		AudioSettings.sfx_volume = v
		AudioSettings.save()
	parent.add_child(_volume_slider("SFX", AudioSettings.sfx_volume, on_sfx))
	var on_ambience := func(v: float) -> void:
		AudioSettings.ambience_volume = v
		AudioSettings.save()
	parent.add_child(_volume_slider("Ambience", AudioSettings.ambience_volume, on_ambience))
	var on_ui := func(v: float) -> void:
		AudioSettings.ui_volume = v
		AudioSettings.save()
	parent.add_child(_volume_slider("UI", AudioSettings.ui_volume, on_ui))


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
	preset_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var preset_label := Label.new()
	preset_label.text = "Render resolution"
	preset_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	preset_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(preset_label)
	preset_row.add_child(preset_label)
	var preset_options := OptionButton.new()
	preset_options.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for i in PixelDioramaSettings.RESOLUTION_PRESETS.size():
		var preset: Dictionary = PixelDioramaSettings.RESOLUTION_PRESETS[i]
		preset_options.add_item(str(preset.get("label", "?")), i)
	var current_preset := PixelDioramaSettings.current_resolution_preset()
	if current_preset >= 0:
		preset_options.selected = current_preset
	else:
		preset_options.add_item(
			(
				"Custom (%d x %d)"
				% [PixelDioramaSettings.viewport_width, PixelDioramaSettings.viewport_height]
			)
		)
		preset_options.selected = preset_options.item_count - 1
	preset_options.item_selected.connect(
		func(idx: int) -> void:
			PixelDioramaSettings.set_resolution_preset(idx)
			PixelDioramaSettings.save_and_apply()
	)
	preset_row.add_child(preset_options)
	_pixel_section.add_child(preset_row)

	var low_res := CheckBox.new()
	low_res.text = "Low-res viewport upscale"
	low_res.button_pressed = PixelDioramaSettings.low_res_viewport_enabled
	low_res.toggled.connect(
		func(on: bool) -> void:
			PixelDioramaSettings.low_res_viewport_enabled = on
			PixelDioramaSettings.save_and_apply()
			if on and get_tree().current_scene:
				PixelDioramaViewport.attach_to_scene(get_tree().current_scene)
			elif not on:
				PixelDioramaViewport.detach()
	)
	_pixel_section.add_child(low_res)

	_pixel_section.add_child(
		_toggle(
			"Snap render camera to pixel grid",
			PixelDioramaSettings.camera_snap_enabled,
			func(on: bool) -> void: PixelDioramaSettings.camera_snap_enabled = on
		)
	)
	_pixel_section.add_child(
		_toggle(
			"Snap gameplay camera to pixel grid",
			PixelDioramaSettings.gameplay_camera_snap_enabled,
			func(on: bool) -> void: PixelDioramaSettings.gameplay_camera_snap_enabled = on
		)
	)

	_pixel_section.add_child(
		_toggle(
			"Nearest texture filtering",
			PixelDioramaSettings.nearest_texture_filter,
			func(on: bool) -> void: PixelDioramaSettings.nearest_texture_filter = on
		)
	)
	_pixel_section.add_child(
		_toggle(
			"Disable MSAA / screen AA",
			PixelDioramaSettings.anti_aliasing_off,
			func(on: bool) -> void: PixelDioramaSettings.anti_aliasing_off = on
		)
	)

	_pixel_section.add_child(_subsection_label("Surfaces"))
	_pixel_section.add_child(
		_shader_slider(
			"Pixel scale",
			1.0,
			32.0,
			0.5,
			PixelDioramaSettings.pixel_scale,
			func(v: float) -> void: PixelDioramaSettings.pixel_scale = v
		)
	)
	_pixel_section.add_child(
		_shader_slider(
			"Color levels",
			4.0,
			16.0,
			1.0,
			PixelDioramaSettings.color_levels,
			func(v: float) -> void: PixelDioramaSettings.color_levels = v
		)
	)
	_pixel_section.add_child(
		_shader_slider(
			"Pattern strength",
			0.0,
			1.0,
			0.02,
			PixelDioramaSettings.pattern_strength,
			func(v: float) -> void: PixelDioramaSettings.pattern_strength = v
		)
	)
	_pixel_section.add_child(
		_shader_slider(
			"Edge strength",
			0.0,
			1.0,
			0.02,
			PixelDioramaSettings.edge_strength,
			func(v: float) -> void: PixelDioramaSettings.edge_strength = v
		)
	)
	_pixel_section.add_child(
		_shader_slider(
			"Stitch strength",
			0.0,
			1.0,
			0.02,
			PixelDioramaSettings.stitch_strength,
			func(v: float) -> void: PixelDioramaSettings.stitch_strength = v
		)
	)

	_pixel_section.add_child(_subsection_label("Shading"))
	_pixel_section.add_child(
		_shader_slider(
			"Light bands",
			2.0,
			16.0,
			1.0,
			PixelDioramaSettings.shade_bands,
			func(v: float) -> void: PixelDioramaSettings.shade_bands = v
		)
	)
	_pixel_section.add_child(
		_shader_slider(
			"Band dithering",
			0.0,
			1.0,
			0.05,
			PixelDioramaSettings.shade_dither,
			func(v: float) -> void: PixelDioramaSettings.shade_dither = v
		)
	)
	_pixel_section.add_child(
		_shader_slider(
			"Shadow softness (light wrap)",
			0.0,
			1.0,
			0.05,
			PixelDioramaSettings.light_wrap,
			func(v: float) -> void: PixelDioramaSettings.light_wrap = v
		)
	)
	_pixel_section.add_child(
		_shader_slider(
			"Silhouette rim",
			0.0,
			0.5,
			0.01,
			PixelDioramaSettings.rim_strength,
			func(v: float) -> void: PixelDioramaSettings.rim_strength = v
		)
	)
	_pixel_section.add_child(
		_toggle(
			"Linear tonemap (crisp)",
			PixelDioramaSettings.linear_tonemap,
			func(on: bool) -> void: PixelDioramaSettings.linear_tonemap = on
		)
	)
	_pixel_section.add_child(
		_toggle(
			"Glow on emissives",
			PixelDioramaSettings.glow_enabled,
			func(on: bool) -> void: PixelDioramaSettings.glow_enabled = on
		)
	)

	_pixel_section.add_child(_subsection_label("Performance"))
	var shadow_row := HBoxContainer.new()
	var shadow_label := Label.new()
	shadow_label.text = "Shadow quality"
	shadow_row.add_child(shadow_label)
	var shadow_opts := OptionButton.new()
	for i in PixelDioramaSettings.QUALITY_LABELS.size():
		shadow_opts.add_item(PixelDioramaSettings.QUALITY_LABELS[i], i)
	shadow_opts.selected = PixelDioramaSettings.shadow_quality
	shadow_opts.item_selected.connect(
		func(idx: int) -> void:
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
	particle_opts.item_selected.connect(
		func(idx: int) -> void:
			PixelDioramaSettings.particle_quality = idx
			PixelDioramaSettings.save_and_apply()
	)
	particle_row.add_child(particle_opts)
	_pixel_section.add_child(particle_row)

	_pixel_section.add_child(_subsection_label("Screen finish"))
	_pixel_section.add_child(
		_toggle(
			"Enable screen finish pass",
			PixelDioramaSettings.screen_finish_enabled,
			func(on: bool) -> void: PixelDioramaSettings.screen_finish_enabled = on
		)
	)
	_pixel_section.add_child(
		_labeled_slider(
			"Contrast",
			0.5,
			2.0,
			0.01,
			PixelDioramaSettings.screen_contrast,
			func(v: float) -> void: PixelDioramaSettings.screen_contrast = v
		)
	)
	_pixel_section.add_child(
		_labeled_slider(
			"Saturation",
			0.0,
			2.0,
			0.01,
			PixelDioramaSettings.screen_saturation,
			func(v: float) -> void: PixelDioramaSettings.screen_saturation = v
		)
	)
	_pixel_section.add_child(
		_labeled_slider(
			"Vignette",
			0.0,
			1.0,
			0.02,
			PixelDioramaSettings.vignette_strength,
			func(v: float) -> void: PixelDioramaSettings.vignette_strength = v
		)
	)
	_pixel_section.add_child(
		_labeled_slider(
			"Lift",
			-0.2,
			0.2,
			0.01,
			PixelDioramaSettings.screen_lift,
			func(v: float) -> void: PixelDioramaSettings.screen_lift = v
		)
	)
	_pixel_section.add_child(
		_labeled_slider(
			"Shadow tint amount",
			0.0,
			1.0,
			0.02,
			PixelDioramaSettings.shadow_tint_amount,
			func(v: float) -> void: PixelDioramaSettings.shadow_tint_amount = v
		)
	)
	_pixel_section.add_child(
		_labeled_slider(
			"Highlight tint amount",
			0.0,
			1.0,
			0.02,
			PixelDioramaSettings.highlight_tint_amount,
			func(v: float) -> void: PixelDioramaSettings.highlight_tint_amount = v
		)
	)
	_pixel_section.add_child(
		_labeled_slider(
			"Palette posterize (0 = off)",
			0.0,
			32.0,
			1.0,
			PixelDioramaSettings.posterize_levels,
			func(v: float) -> void: PixelDioramaSettings.posterize_levels = v
		)
	)

	var restore := Button.new()
	restore.text = "Restore recommended look"
	restore.pressed.connect(
		func() -> void:
			PixelDioramaSettings.apply_beauty_defaults()
			_populate_pixel_diorama_section()
	)
	_pixel_section.add_child(restore)

	var note := Label.new()
	note.text = "Filtering and AA apply immediately."
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_pixel_section.add_child(note)


func _build_privacy_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Privacy"
	GameUISkinScript.style_section_title(title)
	parent.add_child(title)
	var crash_cb := CheckBox.new()
	crash_cb.text = "Send crash reports"
	crash_cb.button_pressed = PrivacySettingsScript.send_crash_reports
	crash_cb.toggled.connect(
		func(on: bool) -> void:
			PrivacySettingsScript.send_crash_reports = on
			PrivacySettingsScript.save()
	)
	parent.add_child(crash_cb)


func _build_cloud_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Cloud save"
	GameUISkinScript.style_section_title(title)
	parent.add_child(title)

	var status := Label.new()
	status.name = "CloudStatusLabel"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_body_label(status)
	parent.add_child(status)
	_refresh_cloud_status_label(status)
	if not ApiConfig.cloud_state_changed.is_connected(_on_cloud_state_changed):
		ApiConfig.cloud_state_changed.connect(_on_cloud_state_changed.bind(status))

	var email_row := HBoxContainer.new()
	var email_label := Label.new()
	email_label.text = "Email"
	email_label.custom_minimum_size.x = 120.0
	email_row.add_child(email_label)
	var email_edit := LineEdit.new()
	email_edit.name = "CloudEmailEdit"
	email_edit.placeholder_text = "you@example.com"
	email_edit.text = ApiConfig.session_email
	email_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	email_row.add_child(email_edit)
	parent.add_child(email_row)

	var password_row := HBoxContainer.new()
	var password_label := Label.new()
	password_label.text = "Password"
	password_label.custom_minimum_size.x = 120.0
	password_row.add_child(password_label)
	var password_edit := LineEdit.new()
	password_edit.name = "CloudPasswordEdit"
	password_edit.secret = true
	password_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	password_row.add_child(password_edit)
	parent.add_child(password_row)

	var message := Label.new()
	message.name = "CloudMessageLabel"
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	message.visible = false
	GameUISkinScript.style_body_label(message)
	parent.add_child(message)

	if SteamService and not SteamService.is_stub_mode:
		var steam_sign_in := Button.new()
		steam_sign_in.text = "Sign in with Steam"
		steam_sign_in.pressed.connect(
			func() -> void: await _steam_sign_in(message, status)
		)
		GameUISkinScript.wire_button_sfx(steam_sign_in)
		parent.add_child(steam_sign_in)

	var sign_in := Button.new()
	sign_in.text = "Sign in"
	sign_in.pressed.connect(
		func() -> void:
			_cloud_auth_action(
				message, email_edit.text.strip_edges(), password_edit.text, "login"
			)
	)
	GameUISkinScript.wire_button_sfx(sign_in)
	parent.add_child(sign_in)

	var sign_up := Button.new()
	sign_up.text = "Sign up"
	sign_up.pressed.connect(
		func() -> void:
			_cloud_auth_action(
				message, email_edit.text.strip_edges(), password_edit.text, "register"
			)
	)
	GameUISkinScript.wire_button_sfx(sign_up)
	parent.add_child(sign_up)

	var sign_out := Button.new()
	sign_out.text = "Sign out"
	sign_out.pressed.connect(
		func() -> void:
			await ApiClient.logout()
			password_edit.text = ""
			_refresh_cloud_status_label(status)
			_set_cloud_message(message, "Signed out.", false)
	)
	GameUISkinScript.wire_button_sfx(sign_out)
	parent.add_child(sign_out)


func _on_cloud_state_changed(_state: int, _detail: String, status_label: Label) -> void:
	_refresh_cloud_status_label(status_label)


func _refresh_cloud_status_label(status_label: Label) -> void:
	if status_label == null or not is_instance_valid(status_label):
		return
	match ApiConfig.cloud_state:
		ApiConfig.CloudState.DISABLED:
			status_label.text = "Cloud: offline (no API configured)"
		ApiConfig.CloudState.SIGNED_OUT:
			status_label.text = "Cloud: signed out"
		ApiConfig.CloudState.SYNCING:
			status_label.text = "Cloud: syncing..."
		ApiConfig.CloudState.SYNCED:
			var who := ApiConfig.session_email
			status_label.text = "Cloud: signed in as %s" % who if who != "" else "Cloud: signed in"
		ApiConfig.CloudState.ERROR:
			status_label.text = "Cloud: sync error"
		ApiConfig.CloudState.VERSION_MISMATCH:
			status_label.text = "Cloud: update required"
		_:
			status_label.text = "Cloud: unknown"


func _set_cloud_message(message_label: Label, text: String, is_error: bool) -> void:
	if message_label == null:
		return
	message_label.text = text
	message_label.visible = text != ""
	if is_error:
		message_label.modulate = Color(1.0, 0.55, 0.55)
	else:
		message_label.modulate = Color.WHITE


func _cloud_auth_action(
	message_label: Label, email: String, password: String, mode: String
) -> void:
	if email == "" or password == "":
		_set_cloud_message(message_label, "Enter email and password.", true)
		return
	ApiConfig.set_cloud_state(ApiConfig.CloudState.SYNCING, email)
	var result: Dictionary
	if mode == "register":
		result = await ApiClient.register(email, password)
	else:
		result = await ApiClient.login(email, password)
	if result.get("ok", false):
		_set_cloud_message(message_label, "Signed in.", false)
	else:
		ApiConfig.set_cloud_state(ApiConfig.CloudState.SIGNED_OUT, "")
		_set_cloud_message(
			message_label, str(result.get("error", "Authentication failed")), true
		)


func _steam_sign_in(message_label: Label, status_label: Label) -> void:
	if SteamService == null or SteamService.is_stub_mode:
		_set_cloud_message(message_label, "Steam is unavailable.", true)
		return
	ApiConfig.set_cloud_state(ApiConfig.CloudState.SYNCING, "Steam")
	var ticket: String = await SteamService.get_auth_ticket_hex()
	if ticket == "":
		ApiConfig.set_cloud_state(ApiConfig.CloudState.SIGNED_OUT, "")
		_set_cloud_message(message_label, "Steam ticket unavailable.", true)
		return
	var result := await ApiClient.login_steam(ticket, SteamService.app_id)
	if result.get("ok", false):
		_refresh_cloud_status_label(status_label)
		_set_cloud_message(message_label, "Signed in with Steam.", false)
	else:
		ApiConfig.set_cloud_state(ApiConfig.CloudState.SIGNED_OUT, "")
		_set_cloud_message(
			message_label, str(result.get("error", "Steam sign-in failed")), true
		)


func _build_advanced_save_section(parent: VBoxContainer) -> void:
	var sep := HSeparator.new()
	parent.add_child(sep)
	var title := Label.new()
	title.text = "Advanced / Corruption Recovery"
	GameUISkinScript.style_section_title(title)
	parent.add_child(title)
	var backups := LocalSave.list_backups()
	if backups.is_empty():
		var none := Label.new()
		none.text = "No rotating backups on disk."
		GameUISkinScript.style_body_label(none)
		parent.add_child(none)
		return
	for backup in backups:
		var index: int = int(backup.get("index", 0))
		var saved_at := str(backup.get("savedAt", "unknown"))
		var btn := Button.new()
		btn.text = "Restore backup %d (%s)" % [index, saved_at]
		btn.pressed.connect(
			func() -> void:
				MenuShellScript.show_confirmation(
					self,
					"Restore Backup",
					(
						"Replace current save with backup %d?\nCurrent save is copied to conflict backup first."
						% index
					),
					func() -> void:
						if LocalSave.restore_backup(index):
							close_settings(),
					Callable(),
					"Restore Backup",
					"Cancel"
				)
		)
		GameUISkinScript.wire_button_sfx(btn)
		parent.add_child(btn)


func _refresh_open_dialogue_subtitles() -> void:
	var dialogue_ui := get_tree().get_first_node_in_group("dialogue_ui")
	if dialogue_ui and dialogue_ui.has_method("refresh_accessibility"):
		dialogue_ui.call("refresh_accessibility")


func _accessibility_scale_row(
	label_text: String,
	min_v: float,
	max_v: float,
	step: float,
	initial: float,
	on_changed: Callable
) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "%s %.2fx" % [label_text, initial]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
			label.text = "%s %.2fx" % [label_text, v]
			on_changed.call(v)
	)
	box.add_child(slider)
	return box


func _accessibility_vibration_row(initial: float, on_changed: Callable) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = _format_vibration_label(initial)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(label)
	box.add_child(label)
	var slider := HSlider.new()
	slider.name = "VibrationSlider"
	slider.min_value = 0.0
	slider.max_value = 1.0
	slider.step = 0.05
	slider.value = initial
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.value_changed.connect(
		func(v: float) -> void:
			label.text = _format_vibration_label(v)
			on_changed.call(v)
	)
	box.add_child(slider)
	return box


func _format_vibration_label(intensity: float) -> String:
	if intensity <= 0.0:
		return "Controller vibration Off"
	return "Controller vibration %.0f%%" % [intensity * 100.0]


func _subsection_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_section_title(label)
	return label


func _toggle(text: String, initial: bool, on_changed: Callable) -> CheckBox:
	var box := CheckBox.new()
	box.text = text
	box.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.button_pressed = initial
	box.toggled.connect(
		func(on: bool) -> void:
			on_changed.call(on)
			PixelDioramaSettings.apply_live()
			PixelDioramaSettings.request_save()
	)
	return box


func _shader_slider(
	label_text: String,
	min_v: float,
	max_v: float,
	step: float,
	initial: float,
	on_changed: Callable
) -> VBoxContainer:
	return _labeled_slider(
		label_text,
		min_v,
		max_v,
		step,
		initial,
		func(v: float) -> void:
			PixelDioramaSettings.mark_tuning_user_edited()
			on_changed.call(v)
	)


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
	leave.pressed.connect(
		func() -> void:
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
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var label := Label.new()
	label.text = "%s (%.3f)" % [label_text, initial]
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
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
			label.text = "%s (%.3f)" % [label_text, v]
			on_changed.call(v)
			PixelDioramaSettings.apply_live()
			PixelDioramaSettings.request_save()
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
		GameUISkinScript.SETTINGS_HALF_W + 80.0, GameUISkinScript.SETTINGS_HALF_H + 40.0, self
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
	if (
		_capturing_action != &""
		and (
			event is InputEventKey
			or event is InputEventMouseButton
			or event is InputEventJoypadButton
			or event is InputEventJoypadMotion
		)
	):
		if event is InputEventKey and event.echo:
			return
		if not event.is_pressed():
			return
		var result: Dictionary = InputRebindService.rebind(_capturing_action, event)
		if bool(result.get("ok", false)):
			_conflict_label.visible = false
		else:
			var conflict := str(result.get("conflict", ""))
			_conflict_label.text = "Conflict with %s. Choose another input or cancel." % conflict
			_conflict_label.visible = true
		_capturing_action = &""
		_populate_controls_section()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		close_settings()
		get_viewport().set_input_as_handled()
