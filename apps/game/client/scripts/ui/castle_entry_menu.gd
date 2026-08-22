extends Control

## Hub castle portal menu — dungeon dropdown, difficulty tier, continue, seed (FLOW-3.1).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const TowerBoardScript := preload("res://scripts/ui/tower_board_ui.gd")

const LAST_DUNGEON_FLAG := "castle_menu_last_dungeon_id"
const LAST_DIFFICULTY_FLAG := "castle_menu_last_difficulty_tier"

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

const LADDER_COLUMNS := 2

var _selected_dungeon := DungeonCatalog.DEFAULT_DUNGEON_ID
var _selected_difficulty := 1
var _ladder_grid: GridContainer
var _tier_buttons: Dictionary = {}
var _board_ui: Control


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
	_build_board_entry()


func _build_board_entry() -> void:
	var vbox := _new_button.get_parent() as VBoxContainer
	if vbox == null or vbox.has_node("BoardButton"):
		return
	var button := GameUISkinScript.make_button("The Board")
	button.name = "BoardButton"
	button.pressed.connect(_on_board_pressed)
	vbox.add_child(button)
	if _seed_button and _seed_button.get_parent() == vbox:
		vbox.move_child(button, _seed_button.get_index() + 1)


func _on_board_pressed() -> void:
	if _board_ui == null or not is_instance_valid(_board_ui):
		_board_ui = Control.new()
		_board_ui.name = "TowerBoardUI"
		_board_ui.set_script(TowerBoardScript)
		_board_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
		_board_ui.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(_board_ui)
		_board_ui.connect("closed", _on_board_closed)
	_main_panel.visible = false
	_seed_panel.visible = false
	_board_ui.call("open")


func _close_board() -> void:
	if _board_ui and is_instance_valid(_board_ui) and _board_ui.has_method("close"):
		_board_ui.call("close")


func _on_board_closed() -> void:
	if not visible:
		return
	_show_main_panel()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_new_button.grab_focus()


func _build_dungeon_dropdown() -> void:
	if _dungeon_dropdown == null:
		return
	_dungeon_dropdown.clear()
	var tier := DungeonTierService.get_max_unlocked_tier()
	if _title_label:
		_title_label.text = DungeonTierService.get_menu_title(tier)
	var last_dungeon_id := str(CharacterService.get_flag(LAST_DUNGEON_FLAG, ""))
	var restore_index := -1
	for entry in DungeonCatalog.ENTRIES:
		var dungeon_id := str(entry.get("id", ""))
		if not DungeonTierService.is_dungeon_unlocked(dungeon_id):
			continue
		var label := DungeonCatalog.get_display_name(dungeon_id)
		_dungeon_dropdown.add_item(label)
		_dungeon_dropdown.set_item_metadata(_dungeon_dropdown.item_count - 1, dungeon_id)
		if dungeon_id == last_dungeon_id:
			restore_index = _dungeon_dropdown.item_count - 1
	if _dungeon_dropdown.item_count > 0:
		var select_index := restore_index if restore_index >= 0 else 0
		_dungeon_dropdown.select(select_index)
		_selected_dungeon = str(_dungeon_dropdown.get_item_metadata(select_index))
	_build_difficulty_dropdown()


func _build_difficulty_dropdown() -> void:
	_build_tier_ladder()


## The ladder replaces the difficulty dropdown: one card per rung, showing whether it is cleared,
## available or still shut, what rules it brings, what it pays, and the player's own best run on it.
func _build_tier_ladder() -> void:
	if _difficulty_dropdown:
		_difficulty_dropdown.visible = false
	_ensure_ladder_container()
	if _ladder_grid == null:
		return
	for child in _ladder_grid.get_children():
		child.queue_free()
	_tier_buttons.clear()
	var rows := DungeonTierService.get_difficulty_ladder(_selected_dungeon)
	var last_difficulty := int(CharacterService.get_flag(LAST_DIFFICULTY_FLAG, 1))
	var selectable: Array[int] = []
	for row in rows:
		var tier_num := int(row.get("tier", 1))
		var state := str(row.get("state", "locked"))
		var button := GameUISkinScript.make_button(_ladder_card_text(row))
		button.toggle_mode = true
		button.disabled = state == "locked"
		button.tooltip_text = _ladder_tooltip(row)
		GameUISkinScript.style_ladder_button(button, StringName(state))
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if state != "locked":
			selectable.append(tier_num)
			button.pressed.connect(_on_tier_card_pressed.bind(tier_num))
		_ladder_grid.add_child(button)
		_tier_buttons[tier_num] = button
	if selectable.is_empty():
		_selected_difficulty = 1
		return
	var chosen := selectable[0]
	if last_difficulty in selectable:
		chosen = last_difficulty
	_select_tier(chosen)


func _ensure_ladder_container() -> void:
	if _ladder_grid != null and is_instance_valid(_ladder_grid):
		return
	if _difficulty_dropdown == null:
		return
	var parent := _difficulty_dropdown.get_parent() as Container
	if parent == null:
		return
	_ladder_grid = GridContainer.new()
	_ladder_grid.name = "TierLadder"
	_ladder_grid.columns = LADDER_COLUMNS
	_ladder_grid.add_theme_constant_override(
		"h_separation", GameUISkinScript.PIXEL_UNIT * 2
	)
	_ladder_grid.add_theme_constant_override(
		"v_separation", GameUISkinScript.PIXEL_UNIT * 2
	)
	_ladder_grid.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	parent.add_child(_ladder_grid)
	parent.move_child(_ladder_grid, _difficulty_dropdown.get_index() + 1)


func _ladder_card_text(row: Dictionary) -> String:
	var tier_num := int(row.get("tier", 1))
	var mark := "·"
	match str(row.get("state", "locked")):
		"cleared":
			mark = "✦"
		"available":
			mark = "▸"
		_:
			mark = "✕"
	return "%s %d — %s" % [mark, tier_num, str(row.get("label", "Tier %d" % tier_num))]


func _ladder_tooltip(row: Dictionary) -> String:
	var lines: Array[String] = []
	var description := str(row.get("description", ""))
	if description != "":
		lines.append(description)
	lines.append(
		(
			"Enemies x%.2f health, x%.2f harm. Loot +%d%%."
			% [
				float(row.get("hpMult", 1.0)),
				float(row.get("damageMult", 1.0)),
				int(round(float(row.get("lootBonus", 0.0)) * 100.0)),
			]
		)
	)
	var modifiers: Array = row.get("modifiers", [])
	if modifiers.is_empty():
		lines.append("No added rules.")
	else:
		lines.append(RunModifierService.describe_all(modifiers))
	var clears := int(row.get("clears", 0))
	if clears > 0:
		lines.append(
			"Cleared %d time(s), best %s." % [clears, _format_time(float(row.get("bestSeconds", 0.0)))]
		)
	elif str(row.get("state", "")) == "locked":
		lines.append("Clear the rung below to open this one.")
	else:
		lines.append("Never cleared.")
	return "\n".join(lines)


func _format_time(seconds: float) -> String:
	if seconds <= 0.0:
		return "—"
	var total := int(round(seconds))
	return "%d:%02d" % [int(total / 60.0), total % 60]


func _on_tier_card_pressed(tier: int) -> void:
	_select_tier(tier)


func _select_tier(tier: int) -> void:
	_selected_difficulty = tier
	CharacterService.set_flag(LAST_DIFFICULTY_FLAG, tier)
	for tier_num in _tier_buttons:
		var button: Button = _tier_buttons[tier_num]
		if button and is_instance_valid(button):
			button.button_pressed = int(tier_num) == tier


func _on_dungeon_selected(index: int) -> void:
	if _dungeon_dropdown == null:
		return
	_selected_dungeon = str(_dungeon_dropdown.get_item_metadata(index))
	CharacterService.set_flag(LAST_DUNGEON_FLAG, _selected_dungeon)
	_build_tier_ladder()
	if _seed_panel.visible:
		_refresh_seed_hint()


func _on_difficulty_selected(index: int) -> void:
	if _difficulty_dropdown == null or index >= _difficulty_dropdown.item_count:
		return
	_select_tier(int(_difficulty_dropdown.get_item_metadata(index)))


func open_menu() -> void:
	_close_board()
	_build_dungeon_dropdown()
	_refresh_continue_state()
	_show_main_panel()
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_new_button.grab_focus()


func close_menu() -> void:
	_close_board()
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Through PlayerControls: closing this panel must not grab the mouse back if another one is
	# still open behind it.
	PlayerControls.capture_mouse_if_allowed()
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
		_status_label.text = (
			"Clear the tenth floor to open the next rung of this dungeon's ladder."
		)
	if weapon_id == "":
		_status_label.text = tr("ENTRY_NEED_WEAPON")
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
		_seed_hint_label.text = tr("ENTRY_TIER_LOCKED") % order
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
		_status_label.text = tr("ENTRY_NEED_WEAPON")
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
		_seed_input.placeholder_text = tr("ENTRY_SEED_INVALID")
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
