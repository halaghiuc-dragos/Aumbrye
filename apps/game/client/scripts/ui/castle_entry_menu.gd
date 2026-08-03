extends Control

## Hub castle portal menu — dungeon dropdown, tier runs, continue, seed (FLOW-3.1).

signal continue_requested
signal seed_run_requested(seed: int)
signal dungeon_run_requested(dungeon_id: String)
signal menu_closed

@onready var _main_panel: PanelContainer = $MainPanel
@onready var _seed_panel: PanelContainer = $SeedPanel
@onready var _title_label: Label = $MainPanel/Margin/VBox/Title
@onready var _new_button: Button = $MainPanel/Margin/VBox/NewButton
@onready var _continue_button: Button = $MainPanel/Margin/VBox/ContinueButton
@onready var _seed_button: Button = $MainPanel/Margin/VBox/SeedButton
@onready var _seed_input: LineEdit = $SeedPanel/Margin/VBox/SeedInput
@onready var _seed_start_button: Button = $SeedPanel/Margin/VBox/SeedStartButton
@onready var _seed_back_button: Button = $SeedPanel/Margin/VBox/SeedBackButton
@onready var _status_label: Label = $MainPanel/Margin/VBox/StatusLabel
@onready var _dungeon_dropdown: OptionButton = $MainPanel/Margin/VBox/DungeonDropdown

var _selected_dungeon := DungeonCatalog.DEFAULT_DUNGEON_ID


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
	if _dungeon_dropdown:
		_dungeon_dropdown.item_selected.connect(_on_dungeon_selected)
	_build_dungeon_dropdown()


func _build_dungeon_dropdown() -> void:
	if _dungeon_dropdown == null:
		return
	_dungeon_dropdown.clear()
	var tier := DungeonTierService.get_max_unlocked_tier()
	if _title_label:
		_title_label.text = DungeonTierService.get_menu_title(tier)
	for entry in DungeonCatalog.ENTRIES:
		var dungeon_id := str(entry.get("id", ""))
		if not DungeonTierService.is_dungeon_unlocked(dungeon_id):
			continue
		var label := str(entry.get("name", dungeon_id))
		_dungeon_dropdown.add_item(label)
		_dungeon_dropdown.set_item_metadata(_dungeon_dropdown.item_count - 1, dungeon_id)
	if _dungeon_dropdown.item_count > 0:
		_dungeon_dropdown.select(0)
		_selected_dungeon = str(_dungeon_dropdown.get_item_metadata(0))


func _on_dungeon_selected(index: int) -> void:
	if _dungeon_dropdown == null:
		return
	_selected_dungeon = str(_dungeon_dropdown.get_item_metadata(index))


func open_menu() -> void:
	_build_dungeon_dropdown()
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
		var saved := LocalSave.get_active_run()
		var dungeon_id := str(saved.get("dungeonId", saved.get("biomeId", DungeonCatalog.DEFAULT_DUNGEON_ID)))
		var dungeon_name := DungeonCatalog.get_display_name(dungeon_id)
		var tier := int(saved.get("dungeonTier", 1))
		var floor_num := int(saved.get("currentFloor", 1))
		var run_seed_value := int(saved.get("seed", 0))
		_status_label.text = "Continue Tier %d — %s floor %d (seed %d)." % [
			tier, dungeon_name, floor_num, run_seed_value,
		]
	else:
		_status_label.text = "Clear 10 floors to unlock the next tier."


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
	dungeon_run_requested.emit(_selected_dungeon)


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


func get_selected_dungeon() -> String:
	return _selected_dungeon


func get_selected_biome() -> String:
	return DungeonCatalog.get_biome_id(_selected_dungeon)
