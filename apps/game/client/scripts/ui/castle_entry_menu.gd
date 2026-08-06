extends Control

## Hub castle portal menu — dungeon dropdown, difficulty tier, continue, seed (FLOW-3.1).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal continue_requested
signal seed_run_requested(seed: int)
signal dungeon_run_requested(dungeon_id: String, difficulty_tier: int)
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
@onready var _seed_hint_label: Label = $SeedPanel/Margin/VBox/SeedHintLabel
@onready var _status_label: Label = $MainPanel/Margin/VBox/StatusLabel
@onready var _dungeon_dropdown: OptionButton = $MainPanel/Margin/VBox/DungeonDropdown
@onready var _difficulty_dropdown: OptionButton = $MainPanel/Margin/VBox/DifficultyDropdown

var _selected_dungeon := DungeonCatalog.DEFAULT_DUNGEON_ID
var _selected_difficulty := 1


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkinScript.apply_modal_menu(self)
	GameUISkinScript.apply_modal_menu(self, "SeedPanel", "Dimmer")
	_new_button.pressed.connect(_on_new_pressed)
	_continue_button.pressed.connect(_on_continue_pressed)
	_seed_button.pressed.connect(_on_seed_menu_pressed)
	_seed_start_button.pressed.connect(_on_seed_start_pressed)
	_seed_back_button.pressed.connect(_show_main_panel)
	_seed_input.text_submitted.connect(_on_seed_submitted)
	_seed_input.text_changed.connect(func(_t): _refresh_seed_hint())
	if _dungeon_dropdown:
		_dungeon_dropdown.item_selected.connect(_on_dungeon_selected)
	if _difficulty_dropdown:
		_difficulty_dropdown.item_selected.connect(_on_difficulty_selected)
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
		var label := DungeonCatalog.get_display_name(dungeon_id)
		_dungeon_dropdown.add_item(label)
		_dungeon_dropdown.set_item_metadata(_dungeon_dropdown.item_count - 1, dungeon_id)
	if _dungeon_dropdown.item_count > 0:
		_dungeon_dropdown.select(0)
		_selected_dungeon = str(_dungeon_dropdown.get_item_metadata(0))
	_build_difficulty_dropdown()


func _build_difficulty_dropdown() -> void:
	if _difficulty_dropdown == null:
		return
	_difficulty_dropdown.clear()
	var cap := DungeonTierService.get_unlocked_difficulty_cap(_selected_dungeon)
	for tier_data in DungeonCatalog.get_difficulty_tiers(_selected_dungeon):
		if not tier_data is Dictionary:
			continue
		var tier_num := int(tier_data.get("tier", 1))
		if tier_num > cap:
			continue
		var label := "%d — %s" % [tier_num, str(tier_data.get("label", "Tier %d" % tier_num))]
		_difficulty_dropdown.add_item(label)
		_difficulty_dropdown.set_item_metadata(_difficulty_dropdown.item_count - 1, tier_num)
	if _difficulty_dropdown.item_count > 0:
		_difficulty_dropdown.select(0)
		_selected_difficulty = int(_difficulty_dropdown.get_item_metadata(0))
	else:
		_selected_difficulty = 1


func _on_dungeon_selected(index: int) -> void:
	if _dungeon_dropdown == null:
		return
	_selected_dungeon = str(_dungeon_dropdown.get_item_metadata(index))
	_build_difficulty_dropdown()
	if _seed_panel.visible:
		_refresh_seed_hint()


func _on_difficulty_selected(index: int) -> void:
	if _difficulty_dropdown == null:
		return
	_selected_difficulty = int(_difficulty_dropdown.get_item_metadata(index))


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
	var can_continue := _castle_run_continuable()
	_continue_button.disabled = not can_continue
	var weapon_id := InventoryService.inventory.get_equipped_weapon_id()
	var weapon_name := "None"
	if weapon_id != "":
		weapon_name = str(ItemCatalog.get_definition(weapon_id).get("name", weapon_id))
	_new_button.disabled = weapon_id == ""
	if can_continue:
		var saved := LocalSave.get_active_run()
		var dungeon_id := str(
			saved.get("dungeonId", saved.get("biomeId", DungeonCatalog.DEFAULT_DUNGEON_ID))
		)
		var dungeon_name := DungeonCatalog.get_display_name(dungeon_id)
		var diff_tier := int(saved.get("difficultyTier", 1))
		var floor_num := int(saved.get("currentFloor", 1))
		var run_seed_value := int(saved.get("seed", 0))
		_status_label.text = (
			"Continue %s tier %d — floor %d (seed %d)."
			% [
				dungeon_name,
				diff_tier,
				floor_num,
				run_seed_value,
			]
		)
	else:
		_status_label.text = "Clear 10 floors to unlock the next tier."
	if weapon_id == "":
		_status_label.text = "Equip a weapon before entering the dungeon."
	else:
		_status_label.text = "%s | Weapon: %s" % [_status_label.text, weapon_name]


func _show_main_panel() -> void:
	_main_panel.visible = true
	_seed_panel.visible = false
	_status_label.visible = true


func _show_seed_panel() -> void:
	_main_panel.visible = false
	_seed_panel.visible = true
	_seed_input.text = ""
	_refresh_seed_hint()
	_seed_input.grab_focus()


func _refresh_seed_hint() -> void:
	if _seed_hint_label == null:
		return
	var order := DungeonCatalog.get_order_for_dungeon(_selected_dungeon)
	if not DungeonSeedService.can_access_tier(order):
		_seed_hint_label.text = "Tier %d is locked." % order
		return
	var trimmed := _seed_input.text.strip_edges()
	if trimmed.is_valid_int() and int(trimmed) >= 1:
		_seed_hint_label.text = DungeonSeedService.describe_tier_seed(int(trimmed), order)
	else:
		_seed_hint_label.text = (
			"Enter a base run seed. Tier %d dungeons derive their layout seed from it." % order
		)


func _on_new_pressed() -> void:
	if InventoryService.inventory.get_equipped_weapon_id() == "":
		_status_label.text = "Equip a weapon before entering the dungeon."
		return
	close_menu()
	dungeon_run_requested.emit(_selected_dungeon, _selected_difficulty)


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
	var parsed: Variant = DungeonSeedService.parse_run_seed(text)
	if parsed == null:
		_seed_input.placeholder_text = "Invalid — enter digits only"
		_seed_input.grab_focus()
		return
	var run_seed_value := int(parsed)
	var order := DungeonCatalog.get_order_for_dungeon(_selected_dungeon)
	if not DungeonSeedService.can_access_tier(order):
		_seed_hint_label.text = "Tier %d is locked — clear the previous tier first." % order
		_seed_input.grab_focus()
		return
	close_menu()
	seed_run_requested.emit(run_seed_value)


func get_selected_dungeon() -> String:
	return _selected_dungeon


func get_selected_difficulty_tier() -> int:
	return _selected_difficulty


func get_selected_biome() -> String:
	return DungeonCatalog.get_biome_id(_selected_dungeon)


func _castle_run_continuable() -> bool:
	if not LocalSave.has_continuable_run():
		return false
	var run_mode := str(LocalSave.get_active_run().get("runMode", "castle"))
	return run_mode in ["castle", ""]
