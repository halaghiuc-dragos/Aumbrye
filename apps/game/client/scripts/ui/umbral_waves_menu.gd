extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const RunContractLabelScript := preload("res://scripts/ui/run_contract_label.gd")

signal waves_run_requested
signal continue_requested
signal menu_closed

@onready var _new_button: Button = $MainPanel/Margin/VBox/NewButton
@onready var _continue_button: Button = $MainPanel/Margin/VBox/ContinueButton
@onready var _status_label: Label = $MainPanel/Margin/VBox/StatusLabel
@onready var _contract_label: Label = $MainPanel/Margin/VBox/ContractLabel


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self)
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
	PlayerControls.capture_mouse_if_allowed()
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
		_status_label.text = tr("WAVES_MENU_CONTINUE").format({"wave": wave})
	else:
		_status_label.text = tr("WAVES_MENU_INTRO")
	RunContractLabelScript.refresh(_contract_label, RunModeConfig.MODE_WAVES, "", 0)


func _on_new_pressed() -> void:
	close_menu()
	waves_run_requested.emit()


func _on_continue_pressed() -> void:
	if _continue_button.disabled:
		return
	close_menu()
	continue_requested.emit()
