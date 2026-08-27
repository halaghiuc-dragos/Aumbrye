extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const CharacterCreateUIScript := preload("res://scripts/ui/character_create_ui.gd")
const CHARACTER_CREATE_SCENE := preload("res://scenes/ui/character_create.tscn")
const ContinueMenuScript := preload("res://scripts/ui/continue_menu.gd")
const LOADING_SCENE := "res://scenes/ui/loading_screen.tscn"

const PANEL_DROP_FRACTION := 0.14
const WORDMARK_GAP := 36.0

const INTRO_RISE_SEC := 0.7
const INTRO_FADE_SEC := 0.5
const PROMPT_GAP := 56.0

static var _intro_shown := false

var _character_create: Control
var _continue_menu: Control
var _menu_panel: PanelContainer
var _quit_overlay: Control
var _wordmark: TitleWordmark
var _prompt: Label
var _intro_active := false
var _intro_ready := false
var _panel_base_offsets := Vector2.ZERO


func _ready() -> void:
	add_to_group("front_end")
	process_mode = Node.PROCESS_MODE_ALWAYS
	AccessibilitySettings.load_from_save()
	AudioSettings.load_from_save()
	PixelDioramaBootstrap.prime()
	AudioDirector.play_menu_music()
	_intro_active = not _intro_shown
	_intro_shown = true
	_build_ui()
	_connect_global_settings()
	LocaleSettings.connect_changed(_on_locale_changed)
	_character_create = CHARACTER_CREATE_SCENE.instantiate() as Control
	_character_create.name = "CharacterCreateUI"
	add_child(_character_create)
	_character_create.completed.connect(_on_character_created)
	_character_create.cancelled.connect(_on_character_create_cancelled)
	_continue_menu = ContinueMenuScript.new()
	_continue_menu.name = "ContinueMenu"
	add_child(_continue_menu)
	_continue_menu.slot_selected.connect(_on_continue_slot_selected)
	_continue_menu.cancelled.connect(_on_continue_cancelled)
	_continue_menu.slot_deleted.connect(_on_continue_slot_deleted)
	await get_tree().process_frame
	_layout_front_end()
	get_viewport().size_changed.connect(_on_viewport_resized)
	if _intro_active:
		_begin_intro()


func _on_viewport_resized() -> void:
	_apply_panel_drop()
	if _wordmark == null or not is_instance_valid(_wordmark):
		return
	_wordmark.build()
	_wordmark.set_glow_pulsing(_intro_active and _intro_ready)
	await get_tree().process_frame
	_layout_front_end()


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := get_node_or_null("Backdrop") as ColorRect
	if backdrop == null:
		backdrop = GameUISkinScript.make_backdrop(self)
		backdrop.color = Color(0.02, 0.02, 0.06, 1.0)
		move_child(backdrop, 0)
	_menu_panel = GameUISkinScript.make_center_panel(
		self, GameUISkinScript.MENU_HALF_W + 60.0, GameUISkinScript.MENU_HALF_H - 40.0
	)
	_menu_panel.name = "MenuPanel"
	_panel_base_offsets = Vector2(_menu_panel.offset_top, _menu_panel.offset_bottom)
	_apply_panel_drop()
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_menu_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	vbox.add_child(_menu_button(tr("MENU_NEW_GAME"), _on_new_game))
	var continue_btn := _menu_button(tr("MENU_CONTINUE"), _on_continue)
	continue_btn.name = "ContinueButton"
	vbox.add_child(continue_btn)
	vbox.add_child(_menu_button(tr("MENU_SETTINGS"), _on_settings))
	vbox.add_child(_menu_button(tr("MENU_QUIT"), _on_quit_pressed))
	_refresh_continue_button()
	_build_wordmark()


func _apply_panel_drop() -> void:
	if _menu_panel == null or not is_instance_valid(_menu_panel):
		return
	var drop := get_viewport_rect().size.y * PANEL_DROP_FRACTION
	_menu_panel.offset_top = _panel_base_offsets.x + drop
	_menu_panel.offset_bottom = _panel_base_offsets.y + drop


func _build_wordmark() -> void:
	_wordmark = TitleWordmark.new()
	_wordmark.name = "Wordmark"
	add_child(_wordmark)
	_wordmark.build()
	_wordmark.set_glow_pulsing(false)

	if not _intro_active:
		return
	_prompt = Label.new()
	_prompt.name = "IntroPrompt"
	_prompt.text = tr("TITLE_PRESS_ANY_KEY")
	_prompt.set_anchors_preset(Control.PRESET_TOP_WIDE)
	_prompt.offset_left = 0.0
	_prompt.offset_right = 0.0
	_prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.style_hint_label(_prompt)
	_prompt.modulate.a = 0.0
	add_child(_prompt)


func _exit_tree() -> void:
	LocaleSettings.disconnect_changed(_on_locale_changed)


func _on_locale_changed() -> void:
	if _menu_panel and is_instance_valid(_menu_panel):
		_menu_panel.queue_free()
	_menu_panel = null
	for node in [_wordmark, _prompt]:
		if node != null and is_instance_valid(node):
			node.queue_free()
	_wordmark = null
	_prompt = null
	_build_ui()
	await get_tree().process_frame
	if _menu_panel == null or not is_instance_valid(_menu_panel):
		return
	_menu_panel.visible = not _intro_active
	_menu_panel.modulate.a = 0.0 if _intro_active else 1.0
	_layout_front_end()
	if _intro_active and _prompt != null:
		_prompt.modulate.a = 1.0 if _intro_ready else 0.0
	if _wordmark != null:
		_wordmark.set_glow_pulsing(_intro_active and _intro_ready)


func _layout_front_end() -> void:
	if _wordmark == null or not is_instance_valid(_wordmark):
		return
	var block_h := _wordmark.block_height()
	var y := _intro_wordmark_y(block_h) if _intro_active else _docked_wordmark_y(block_h)
	_wordmark.place_at(y)
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.offset_top = y + block_h + PROMPT_GAP
		_prompt.offset_bottom = _prompt.offset_top + _prompt.get_combined_minimum_size().y


func _intro_wordmark_y(block_h: float) -> float:
	return maxf(24.0, (get_viewport_rect().size.y - block_h - PROMPT_GAP) * 0.5)


func _docked_wordmark_y(block_h: float) -> float:
	var panel_top := get_viewport_rect().size.y * 0.5
	if _menu_panel != null and is_instance_valid(_menu_panel):
		panel_top = _menu_panel.position.y
	return maxf(16.0, panel_top - block_h - WORDMARK_GAP)


func _begin_intro() -> void:
	_menu_panel.visible = false
	_menu_panel.modulate.a = 0.0
	if LocalSave and LocalSave.recovery_required:
		_show_recovery_prompt()
		return
	_open_intro_prompt()


func _open_intro_prompt() -> void:
	_intro_ready = true
	if _wordmark != null and is_instance_valid(_wordmark):
		_wordmark.set_glow_pulsing(true)
	if _prompt == null or not is_instance_valid(_prompt):
		return
	if AccessibilitySettings.reduced_motion:
		_prompt.modulate.a = 1.0
		return
	create_tween().tween_property(_prompt, "modulate:a", 1.0, 0.6)


func _finish_intro() -> void:
	if not _intro_active:
		return
	_intro_active = false
	_intro_ready = false
	if _wordmark != null and is_instance_valid(_wordmark):
		_wordmark.set_glow_pulsing(false)
	_menu_panel.visible = true
	var block_h := _wordmark.block_height()
	var dock_y := _docked_wordmark_y(block_h)
	if AccessibilitySettings.reduced_motion:
		_wordmark.place_at(dock_y)
		_menu_panel.modulate.a = 1.0
		_on_intro_finished()
		return
	var tween := create_tween()
	tween.set_parallel(true)
	for edge: String in ["offset_top", "offset_bottom"]:
		var target: float = dock_y if edge == "offset_top" else dock_y + block_h
		tween.tween_property(_wordmark, edge, target, INTRO_RISE_SEC).set_trans(
			Tween.TRANS_CUBIC
		).set_ease(Tween.EASE_OUT)
	if _prompt != null and is_instance_valid(_prompt):
		tween.tween_property(_prompt, "modulate:a", 0.0, 0.25)
	tween.tween_property(_menu_panel, "modulate:a", 1.0, INTRO_FADE_SEC).set_delay(0.25)
	tween.finished.connect(_on_intro_finished)


func _on_intro_finished() -> void:
	if _prompt != null and is_instance_valid(_prompt):
		_prompt.queue_free()
	_prompt = null
	if _menu_panel != null and is_instance_valid(_menu_panel):
		_menu_panel.modulate.a = 1.0


func _focus_first_menu_button() -> void:
	if _menu_panel == null or not is_instance_valid(_menu_panel):
		return
	for node in _menu_panel.find_children("*", "Button", true, false):
		var button := node as Button
		if button != null and not button.disabled:
			button.grab_focus()
			return


func _show_recovery_prompt() -> void:
	var panel := GameUISkinScript.make_center_panel(self, 420.0, 260.0, "SaveRecoveryPrompt")
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 10)
	panel.add_child(vbox)

	var title := Label.new()
	title.text = tr("RECOVERY_TITLE")
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)

	var body := Label.new()
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.text = tr("RECOVERY_BODY").format({"reason": LocalSave.recovery_reason})
	GameUISkinScript.style_body_label(body)
	vbox.add_child(body)

	if LocalSave.recovery_quarantine_path != "":
		var path_label := Label.new()
		path_label.autowrap_mode = TextServer.AUTOWRAP_ARBITRARY
		path_label.text = tr("RECOVERY_KEPT_AT").format(
			{"path": LocalSave.recovery_quarantine_path}
		)
		GameUISkinScript.style_hint_label(path_label)
		vbox.add_child(path_label)

	var keep_button := GameUISkinScript.make_button(tr("RECOVERY_KEEP"))
	keep_button.pressed.connect(_on_recovery_resolved.bind(panel, false))
	vbox.add_child(keep_button)

	var fresh_button := GameUISkinScript.make_button(tr("RECOVERY_START_FRESH"))
	fresh_button.pressed.connect(_on_recovery_resolved.bind(panel, true))
	vbox.add_child(fresh_button)

	keep_button.grab_focus()


func _on_recovery_resolved(panel: Control, start_fresh: bool) -> void:
	if start_fresh:
		LocalSave.resolve_recovery_start_fresh()
	else:
		LocalSave.resolve_recovery_dismiss()
	panel.queue_free()
	_refresh_continue_button()
	_open_intro_prompt()


static func _is_intro_advance(event: InputEvent) -> bool:
	if event is InputEventKey:
		var key := event as InputEventKey
		return key.pressed and not key.echo
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		return (
			mb.pressed
			and mb.button_index not in [
				MOUSE_BUTTON_WHEEL_UP,
				MOUSE_BUTTON_WHEEL_DOWN,
				MOUSE_BUTTON_WHEEL_LEFT,
				MOUSE_BUTTON_WHEEL_RIGHT,
			]
		)
	if event is InputEventJoypadButton:
		return (event as InputEventJoypadButton).pressed
	return false


func _menu_button(text: String, on_pressed: Callable) -> Button:
	var button := MenuShellScript.make_menu_button(text, on_pressed)
	_style_title_button(button)
	return button


func _style_title_button(button: Button) -> void:
	button.add_theme_stylebox_override(&"focus", StyleBoxEmpty.new())
	button.ready.connect(_apply_hover_highlight.bind(button), CONNECT_ONE_SHOT)


func _apply_hover_highlight(button: Button) -> void:
	if not is_instance_valid(button):
		return
	var base := button.get_theme_stylebox(&"hover")
	var hover := (base.duplicate() if base != null else StyleBoxFlat.new()) as StyleBoxFlat
	if hover == null:
		return
	hover.border_color = GameUISkinScript.ACCENT_BAR
	hover.set_border_width_all(2)
	button.add_theme_stylebox_override(&"hover", hover)


func _connect_global_settings() -> void:
	var settings := PlayerControls.get_settings_ui()
	if settings == null or not settings.has_signal("closed"):
		return
	if not settings.closed.is_connected(_on_settings_closed):
		settings.closed.connect(_on_settings_closed)


func _refresh_continue_button() -> void:
	var btn := _menu_panel.find_child("ContinueButton", true, false) as Button
	if btn:
		btn.disabled = not LocalSave.has_playable_character()


func _show_main_panel(show_menu: bool) -> void:
	_menu_panel.visible = show_menu


func _is_submenu_open() -> bool:
	if _character_create != null and _character_create.is_open():
		return true
	if _continue_menu != null and _continue_menu.is_open():
		return true
	if PlayerControls.is_settings_open():
		return true
	return false


func _on_new_game() -> void:
	if not LocalSave.can_create_character():
		MenuShellScript.show_confirmation(
			self,
			"No Room Left",
			(
				"All %d warden slots are taken. Retire one from Continue before starting another."
				% LocalSave.character_slot_limit()
			),
			func() -> void: pass,
			Callable(),
			"Very well",
			"Back"
		)
		return
	_show_main_panel(false)
	_character_create.open_creation()
	_character_create.move_to_front()


func _on_continue() -> void:
	if not LocalSave.has_playable_character():
		return
	_show_main_panel(false)
	_continue_menu.open_menu()
	_continue_menu.move_to_front()


func _on_settings() -> void:
	_show_main_panel(false)
	PlayerControls.open_settings()


func _on_quit_pressed() -> void:
	_prompt_quit()


func _prompt_quit() -> void:
	if _is_submenu_open():
		return
	if _quit_overlay != null and is_instance_valid(_quit_overlay):
		return
	_quit_overlay = MenuShellScript.show_confirmation(
		self,
		"Quit Game",
		"Close Aumbrye and return to your desktop?",
		func() -> void:
			_quit_overlay = null
			get_tree().quit(),
		func() -> void: _quit_overlay = null,
		"Quit Game",
		"Stay"
	)


func _on_settings_closed() -> void:
	_show_main_panel(true)
	_refresh_continue_button()


func _on_character_created(
	class_id: String, character_name: String, appearance: Dictionary
) -> void:
	LocalSave.queue_boot_new_game(class_id, character_name, appearance)
	SceneTransition.goto(get_tree(), LOADING_SCENE)


func _on_character_create_cancelled() -> void:
	_show_main_panel(true)
	_refresh_continue_button()


func _on_continue_slot_selected(character_id: String) -> void:
	if character_id == "":
		return
	LocalSave.queue_boot_continue_character(character_id)
	SceneTransition.goto(get_tree(), LOADING_SCENE)


func _on_continue_cancelled() -> void:
	_show_main_panel(true)


func _on_continue_slot_deleted(_character_id: String) -> void:
	_refresh_continue_button()


func _input(event: InputEvent) -> void:
	if (
		not _intro_active
		and not (event is InputEventMouse)
		and _menu_panel != null
		and is_instance_valid(_menu_panel)
		and _menu_panel.visible
		and get_viewport().gui_get_focus_owner() == null
	):
		_focus_first_menu_button()
	if _intro_active:
		if _intro_ready and _is_intro_advance(event):
			get_viewport().set_input_as_handled()
			_finish_intro()
		return
	if not event.is_action_pressed("ui_cancel"):
		return
	if _quit_overlay != null and is_instance_valid(_quit_overlay):
		_quit_overlay.queue_free()
		_quit_overlay = null
		get_viewport().set_input_as_handled()
		return
	if _character_create != null and _character_create.is_open():
		_character_create.request_cancel()
		get_viewport().set_input_as_handled()
		return
	if _continue_menu != null and _continue_menu.is_open():
		return
	if PlayerControls.is_settings_open():
		var settings := PlayerControls.get_settings_ui()
		if settings and settings.has_method("close_settings"):
			settings.call("close_settings")
		get_viewport().set_input_as_handled()
		return
	_prompt_quit()
	get_viewport().set_input_as_handled()
