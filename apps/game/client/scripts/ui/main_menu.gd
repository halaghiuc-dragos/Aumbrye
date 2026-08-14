extends Control

## Front-end hub — New Game, Continue, Settings, Quit.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const CharacterCreateUIScript := preload("res://scripts/ui/character_create_ui.gd")
const CHARACTER_CREATE_SCENE := preload("res://scenes/ui/character_create.tscn")
const ContinueMenuScript := preload("res://scripts/ui/continue_menu.gd")
const LOADING_SCENE := "res://scenes/ui/loading_screen.tscn"

var _character_create: Control
var _continue_menu: Control
var _menu_panel: PanelContainer
var _quit_overlay: Control


func _ready() -> void:
	add_to_group("front_end")
	process_mode = Node.PROCESS_MODE_ALWAYS
	AccessibilitySettings.load_from_save()
	AudioSettings.load_from_save()
	AudioDirector.play_menu_music()
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


func _build_ui() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	# Named and reused: _build_ui() runs again on a language change, and an unnamed backdrop would
	# stack a fresh opaque rect over the menu every time.
	var backdrop := get_node_or_null("Backdrop") as ColorRect
	if backdrop == null:
		backdrop = GameUISkinScript.make_backdrop(self)
		# The title screen is the one backdrop that is not laid over a live world, so it stays
		# fully opaque; everything else about it — the vignette, the edge tint — is shared with
		# every other menu rather than being a second, slightly different dark rectangle.
		backdrop.color = Color(0.02, 0.02, 0.06, 1.0)
		move_child(backdrop, 0)
	# The half-size is a floor, not a fixed size — a PanelContainer still grows to fit whatever it
	# holds. Asking for 540px of height around ~330px of buttons left a third of the first screen
	# in the game as empty framed void under the last button.
	_menu_panel = GameUISkinScript.make_center_panel(
		self, GameUISkinScript.MENU_HALF_W + 60.0, GameUISkinScript.MENU_HALF_H - 40.0
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
	subtitle.text = tr("MENU_SUBTITLE")
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(subtitle)
	vbox.add_child(subtitle)
	vbox.add_child(_menu_button(tr("MENU_NEW_GAME"), _on_new_game))
	var continue_btn := _menu_button(tr("MENU_CONTINUE"), _on_continue)
	continue_btn.name = "ContinueButton"
	vbox.add_child(continue_btn)
	vbox.add_child(_menu_button(tr("MENU_SETTINGS"), _on_settings))
	vbox.add_child(_menu_button(tr("MENU_QUIT"), _on_quit_pressed))
	var hint := Label.new()
	hint.text = tr("MENU_HINT_QUIT")
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_hint_label(hint)
	vbox.add_child(hint)
	_refresh_continue_button()


func _exit_tree() -> void:
	LocaleSettings.disconnect_changed(_on_locale_changed)


## The front end is built once from translated literals, so a language chosen in Settings would
## otherwise leave this menu in the old language until the game restarted.
func _on_locale_changed() -> void:
	if _menu_panel and is_instance_valid(_menu_panel):
		_menu_panel.queue_free()
	_menu_panel = null
	_build_ui()


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
	SceneTransition.goto(get_tree(), LOADING_SCENE)


func _on_character_create_cancelled() -> void:
	_show_main_panel(true)


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
