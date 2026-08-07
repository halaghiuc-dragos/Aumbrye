extends Control

## Umbral Endless portal menu — new/continue + optional skip-floor consumables.

const SkipFloorSvc := preload("res://scripts/dungeon/skip_floor_service.gd")

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal endless_run_requested(start_floor: int, skip_item_id: String)
signal continue_requested
signal menu_closed

@onready var _main_panel: PanelContainer = $MainPanel
@onready var _skip_panel: PanelContainer = $SkipPanel
@onready var _new_button: Button = $MainPanel/Margin/VBox/NewButton
@onready var _continue_button: Button = $MainPanel/Margin/VBox/ContinueButton
@onready var _status_label: Label = $MainPanel/Margin/VBox/StatusLabel
@onready var _skip_box: VBoxContainer = $SkipPanel/Margin/VBox/SkipBox
@onready var _skip_start_button: Button = $SkipPanel/Margin/VBox/SkipStartButton
@onready var _skip_none_button: Button = $SkipPanel/Margin/VBox/SkipNoneButton
@onready var _skip_back_button: Button = $SkipPanel/Margin/VBox/SkipBackButton

var _selected_skip := ""


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self)
	_new_button.pressed.connect(_on_new_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_skip_start_button.pressed.connect(_on_skip_start_pressed)
	_skip_none_button.pressed.connect(_on_skip_none_pressed)
	_skip_back_button.pressed.connect(_show_main_panel)


func open_menu() -> void:
	_refresh_continue_state()
	_show_main_panel()
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
		if _skip_panel.visible:
			_show_main_panel()
		else:
			close_menu()


func _refresh_continue_state() -> void:
	var saved := LocalSave.get_active_run()
	var can_continue := (
		LocalSave.has_continuable_run() and str(saved.get("runMode", "")) == "endless"
	)
	_continue_button.disabled = not can_continue
	if can_continue:
		var saved_floor := int(saved.get("currentFloor", 1))
		_status_label.text = "Continue endless run (floor %d)." % saved_floor
	else:
		_status_label.text = "Infinite floors — difficulty rises every 10 tiers."


func _show_main_panel() -> void:
	_main_panel.visible = true
	_skip_panel.visible = false


func _show_skip_panel() -> void:
	_main_panel.visible = false
	_skip_panel.visible = true
	_build_skip_buttons()


func _build_skip_buttons() -> void:
	for child in _skip_box.get_children():
		child.queue_free()
	_selected_skip = ""
	var skips: Array[Dictionary] = SkipFloorSvc.get_available_skips(InventoryService.inventory)
	for entry in skips:
		var item_id: String = str(entry.get("itemId", ""))
		var item_name: String = str(ItemCatalog.get_definition(item_id).get("name", item_id))
		var btn := GameUISkinScript.make_button(
			"Use %s → floor %d" % [item_name, int(entry.get("startFloor", 1))]
		)
		btn.pressed.connect(_on_skip_selected.bind(item_id, btn))
		_skip_box.add_child(btn)
	if skips.is_empty():
		var label := Label.new()
		label.text = "No skip-floor items in inventory."
		GameUISkinScript.style_body_label(label)
		_skip_box.add_child(label)


func _on_skip_selected(item_id: String, pressed_btn: Button) -> void:
	_selected_skip = item_id
	for child in _skip_box.get_children():
		if child is Button:
			(child as Button).button_pressed = child == pressed_btn


func _on_new_pressed() -> void:
	var skips: Array[Dictionary] = SkipFloorSvc.get_available_skips(InventoryService.inventory)
	if skips.is_empty():
		close_menu()
		endless_run_requested.emit(1, "")
	else:
		_show_skip_panel()


func _on_skip_start_pressed() -> void:
	close_menu()
	endless_run_requested.emit(SkipFloorSvc.start_floor_for_item(_selected_skip), _selected_skip)


func _on_skip_none_pressed() -> void:
	close_menu()
	endless_run_requested.emit(1, "")


func _on_continue_pressed() -> void:
	if _continue_button.disabled:
		return
	close_menu()
	continue_requested.emit()
