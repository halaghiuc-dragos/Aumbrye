extends Control

## Front-end hub — New Game, Continue, Settings, Quit.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const CharacterCreateUIScript := preload("res://scripts/ui/character_create_ui.gd")
const ContinueMenuScript := preload("res://scripts/ui/continue_menu.gd")
const LOADING_SCENE := "res://scenes/ui/loading_screen.tscn"

var _character_create: Control
var _continue_menu: Control
var _menu_panel: PanelContainer
var _quit_overlay: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	AccessibilitySettings.load_from_save()
	DisplaySettings.apply()
	AudioSettings.load_from_save()
	AudioDirector.play_menu_music()
	_build_ui()
	_connect_global_settings()
	_character_create = CharacterCreateUIScript.new()
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


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	var backdrop := ColorRect.new()
	backdrop.color = Color(0.02, 0.02, 0.06, 1.0)
	backdrop.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)
	_menu_panel = GameUISkinScript.make_center_panel(
		self, GameUISkinScript.MENU_HALF_W + 60.0, GameUISkinScript.MENU_HALF_H + 120.0
	)
	_menu_panel.name = "MenuPanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 24)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 24)
	_menu_panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 14)
	margin.add_child(vbox)
	var title := Label.new()
	title.text = "Aumbrye"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)
	var subtitle := Label.new()
	subtitle.text = "Echo of the Fallen Warden"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(subtitle)
	vbox.add_child(subtitle)
	vbox.add_child(_menu_button("New Game", _on_new_game))
	var continue_btn := _menu_button("Continue", _on_continue)
	continue_btn.name = "ContinueButton"
	vbox.add_child(continue_btn)
	vbox.add_child(_menu_button("Settings", _on_settings))
	vbox.add_child(_menu_button("Quit Game", _on_quit_pressed))
	var hint := Label.new()
	hint.text = "Esc: quit"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(hint)
	vbox.add_child(hint)
	_refresh_continue_button()


func _menu_button(text: String, on_pressed: Callable) -> Button:
	return MenuShellScript.make_menu_button(text, on_pressed)


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
	if LocalSave.has_playable_character():
		MenuShellScript.show_confirmation(
			self,
			"New Warden",
			"Create a new warden? Existing wardens stay on disk — pick any of them from Continue.",
			func() -> void:
				_show_main_panel(false)
				_character_create.open_creation()
				_character_create.move_to_front(),
			Callable(),
			"Create Warden",
			"Cancel"
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
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_character_create_cancelled() -> void:
	_show_main_panel(true)


func _on_continue_slot_selected(character_id: String) -> void:
	if character_id == "":
		return
	LocalSave.queue_boot_continue_character(character_id)
	get_tree().change_scene_to_file(LOADING_SCENE)


func _on_continue_cancelled() -> void:
	_show_main_panel(true)


func _on_continue_slot_deleted(_character_id: String) -> void:
	_refresh_continue_button()


func _input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _quit_overlay != null and is_instance_valid(_quit_overlay):
		_quit_overlay.queue_free()
		_quit_overlay = null
		get_viewport().set_input_as_handled()
		return
	if _character_create != null and _character_create.is_open():
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
