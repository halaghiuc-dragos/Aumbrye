extends Control

## Hub castle portal menu — new run, continue, or seed (FLOW-3.1).

signal continue_requested
signal seed_run_requested(seed: int)
signal biome_run_requested(biome_id: String)
signal menu_closed

@onready var _main_panel: PanelContainer = $MainPanel
@onready var _seed_panel: PanelContainer = $SeedPanel
@onready var _new_button: Button = $MainPanel/Margin/VBox/NewButton
@onready var _continue_button: Button = $MainPanel/Margin/VBox/ContinueButton
@onready var _seed_button: Button = $MainPanel/Margin/VBox/SeedButton
@onready var _seed_input: LineEdit = $SeedPanel/Margin/VBox/SeedInput
@onready var _seed_start_button: Button = $SeedPanel/Margin/VBox/SeedStartButton
@onready var _seed_back_button: Button = $SeedPanel/Margin/VBox/SeedBackButton
@onready var _status_label: Label = $MainPanel/Margin/VBox/StatusLabel
@onready var _biome_box: VBoxContainer = $MainPanel/Margin/VBox/BiomeBox

var _selected_biome := BiomeRegistry.BIOME_CASTLE


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_new_button.pressed.connect(_on_new_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_seed_button.pressed.connect(_on_seed_menu_pressed)
	_seed_start_button.pressed.connect(_on_seed_start_pressed)
	_seed_back_button.pressed.connect(_show_main_panel)
	_seed_input.text_submitted.connect(_on_seed_submitted)
	_build_biome_buttons()


func _build_biome_buttons() -> void:
	if _biome_box == null:
		return
	for child in _biome_box.get_children():
		child.queue_free()
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var btn := Button.new()
		btn.text = BiomeRegistry.get_display_name(biome_id)
		btn.toggle_mode = true
		btn.button_pressed = biome_id == _selected_biome
		btn.pressed.connect(_on_biome_pressed.bind(biome_id, btn))
		_biome_box.add_child(btn)


func _on_biome_pressed(biome_id: String, pressed_btn: Button) -> void:
	_selected_biome = biome_id
	for child in _biome_box.get_children():
		if child is Button:
			(child as Button).button_pressed = child == pressed_btn


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
		if _seed_panel.visible:
			_show_main_panel()
		else:
			close_menu()


func _refresh_continue_state() -> void:
	var can_continue := LocalSave.has_continuable_run()
	_continue_button.disabled = not can_continue
	if can_continue:
		var run_seed_value := int(LocalSave.get_active_run().get("seed", 0))
		_status_label.text = "Saved run available (seed %d)." % run_seed_value
	else:
		_status_label.text = "Esc to close"


func _show_main_panel() -> void:
	_main_panel.visible = true
	_seed_panel.visible = false
	_status_label.visible = true


func _show_seed_panel() -> void:
	_main_panel.visible = false
	_seed_panel.visible = true
	_seed_input.text = ""
	_seed_input.grab_focus()


func _on_new_pressed() -> void:
	close_menu()
	biome_run_requested.emit(_selected_biome)


func _on_continue_pressed() -> void:
	if _continue_button.disabled:
		return
	close_menu()
	continue_requested.emit()


func _on_seed_menu_pressed() -> void:
	_show_seed_panel()


func _on_seed_submitted(text: String) -> void:
	_try_start_seed(text)


func _on_seed_start_pressed() -> void:
	_try_start_seed(_seed_input.text)


func _try_start_seed(text: String) -> void:
	var trimmed := text.strip_edges()
	if trimmed == "" or not trimmed.is_valid_int():
		_seed_input.placeholder_text = "Invalid — enter digits only"
		_seed_input.grab_focus()
		return
	var run_seed_value := int(trimmed)
	if run_seed_value < 1:
		_seed_input.placeholder_text = "Seed must be at least 1"
		_seed_input.grab_focus()
		return
	close_menu()
	seed_run_requested.emit(run_seed_value)


func get_selected_biome() -> String:
	return _selected_biome
