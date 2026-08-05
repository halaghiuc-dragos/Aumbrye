extends Control

## In-run pause overlay — resume, settings, abandon, quit to menu.

signal closed

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

var _open := false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func is_open() -> bool:
	return _open


func toggle() -> void:
	if _open:
		close_menu()
	else:
		open_menu()


func open_menu() -> void:
	if _open:
		return
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	get_tree().paused = true
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func close_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	get_tree().paused = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	closed.emit()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		"Paused",
		GameUISkinScript.MENU_HALF_W + 40.0,
		GameUISkinScript.MENU_HALF_H + 80.0
	)
	var vbox: VBoxContainer = shell["content_vbox"]
	vbox.add_child(MenuShellScript.make_menu_button("Resume", _on_resume))
	vbox.add_child(MenuShellScript.make_menu_button("Settings", _on_settings))
	if RunFlow.is_run_active():
		vbox.add_child(MenuShellScript.make_menu_button("Abandon run", _on_abandon))
	vbox.add_child(MenuShellScript.make_menu_button("Quit to menu", _on_quit_to_menu))
	MenuShellScript.add_hint(vbox, "Esc to resume")


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
		get_viewport().set_input_as_handled()
		close_menu()


func _on_resume() -> void:
	close_menu()


func _on_settings() -> void:
	if PlayerControls:
		PlayerControls.open_settings()


func _on_abandon() -> void:
	MenuShellScript.show_confirmation(
		self,
		"Abandon Run",
		"Leave this run and return to the hub?\nAll loot from this run will be lost.",
		func() -> void:
			close_menu()
			RunFlow.abandon_active_run(),
		Callable(),
		"Abandon",
		"Keep Playing"
	)


func _on_quit_to_menu() -> void:
	MenuShellScript.show_confirmation(
		self,
		"Quit to Menu",
		"Save progress and return to the main menu?\nYou can continue this run later from the hub.",
		func() -> void:
			close_menu()
			RunFlow.return_to_main_menu(),
		Callable(),
		"Quit to Menu",
		"Keep Playing"
	)
