extends Control

## Umbral Waves portal menu — new run or continue saved waves progress.

signal waves_run_requested
signal continue_requested
signal menu_closed

@onready var _main_panel: PanelContainer = $MainPanel
@onready var _new_button: Button = $MainPanel/Margin/VBox/NewButton
@onready var _continue_button: Button = $MainPanel/Margin/VBox/ContinueButton
@onready var _status_label: Label = $MainPanel/Margin/VBox/StatusLabel


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_new_button.pressed.connect(_on_new_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)


func open_menu() -> void:
	_refresh_continue_state()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_new_button.grab_focus()


func close_menu() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	menu_closed.emit()


func is_open() -> bool:
	return visible


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()


func _refresh_continue_state() -> void:
	var can_continue := LocalSave.has_continuable_waves_run()
	_continue_button.disabled = not can_continue
	if can_continue:
		var wave := int(LocalSave.get_waves_active_run().get("currentWave", 0))
		_status_label.text = "Continue waves run (wave %d)." % wave
	else:
		_status_label.text = "Open 10 chests, survive 50 waves."


func _on_new_pressed() -> void:
	close_menu()
	waves_run_requested.emit()


func _on_continue_pressed() -> void:
	if _continue_button.disabled:
		return
	close_menu()
	continue_requested.emit()
