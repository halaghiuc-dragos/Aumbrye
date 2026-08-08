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
var _stake_label: Label
var _preview_seed := 0


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
	var best := ProgressionService.get_endless_best_floor()
	var record := (
		"Deepest descent: floor %d." % best if best > 0 else "No descent recorded yet."
	)
	var tokens := ProgressionService.get_descent_tokens()
	if tokens > 0:
		record = "%s Descent tokens: %d." % [record, tokens]
	if can_continue:
		var saved_floor := int(saved.get("currentFloor", 1))
		_status_label.text = "Continue endless run (floor %d). %s" % [saved_floor, record]
	else:
		_status_label.text = "The stair does not end. %s" % record


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
	_stake_label = null
	var skips: Array[Dictionary] = SkipFloorSvc.get_available_skips(InventoryService.inventory)
	for entry in skips:
		var item_id: String = str(entry.get("itemId", ""))
		var item_name: String = str(ItemCatalog.get_definition(item_id).get("name", item_id))
		var info := SkipFloorSvc.describe_skip(item_id, _preview_seed)
		var btn := GameUISkinScript.make_button(
			(
				"%s x%d → floor %d (%s)"
				% [
					item_name,
					int(entry.get("quantity", 1)),
					int(entry.get("startFloor", 1)),
					str(info.get("biomeName", "")),
				]
			)
		)
		btn.pressed.connect(_on_skip_selected.bind(item_id, btn))
		_skip_box.add_child(btn)
	for offer in SkipFloorSvc.available_conversions(InventoryService.inventory):
		var from_id: String = str(offer.get("from", ""))
		var to_id: String = str(offer.get("to", ""))
		var convert_btn := GameUISkinScript.make_button(
			(
				"Bind %d %s into one %s (held %d)"
				% [
					int(offer.get("cost", 0)),
					str(offer.get("fromName", from_id)),
					str(offer.get("toName", to_id)),
					int(offer.get("held", 0)),
				]
			)
		)
		convert_btn.disabled = not bool(offer.get("affordable", false))
		convert_btn.pressed.connect(_on_convert_pressed.bind(from_id, to_id))
		_skip_box.add_child(convert_btn)
	_stake_label = Label.new()
	_stake_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	if skips.is_empty():
		_stake_label.text = "Nothing here will carry you deeper. Begin at floor 1."
	else:
		_stake_label.text = "Choose a stair. Nothing you have earned this run comes with you."
	GameUISkinScript.style_body_label(_stake_label)
	_skip_box.add_child(_stake_label)
	_skip_start_button.disabled = true


func _on_skip_selected(item_id: String, pressed_btn: Button) -> void:
	_selected_skip = item_id
	for child in _skip_box.get_children():
		if child is Button:
			(child as Button).button_pressed = child == pressed_btn
	if _stake_label:
		_stake_label.text = SkipFloorSvc.describe_stake(item_id, _preview_seed)
	_skip_start_button.disabled = false
	_skip_start_button.text = "Descend to floor %d" % SkipFloorSvc.start_floor_for_item(item_id)


func _on_convert_pressed(from_id: String, to_id: String) -> void:
	if SkipFloorSvc.convert(InventoryService.inventory, from_id, to_id):
		_build_skip_buttons()


func _on_new_pressed() -> void:
	_preview_seed = RunFlow.next_endless_preview_seed()
	var skips: Array[Dictionary] = SkipFloorSvc.get_available_skips(InventoryService.inventory)
	if skips.is_empty():
		close_menu()
		endless_run_requested.emit(1, "")
	else:
		_show_skip_panel()


func _on_skip_start_pressed() -> void:
	if _selected_skip == "":
		return
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
