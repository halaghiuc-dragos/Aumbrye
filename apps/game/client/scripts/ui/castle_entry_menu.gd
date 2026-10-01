extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const TowerBoardScript := preload("res://scripts/ui/tower_board_ui.gd")
const RunContractLabelScript := preload("res://scripts/ui/run_contract_label.gd")
const AlternateModeRowScript := preload("res://scripts/ui/alternate_mode_row.gd")

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
@onready var _contract_label: Label = $MainPanel/Margin/VBox/ContractLabel
@onready var _alt_mode_row: VBoxContainer = $MainPanel/Margin/VBox/AltModeRow

const LADDER_COLUMNS := 2

var _selected_dungeon := DungeonCatalog.DEFAULT_DUNGEON_ID
var _selected_difficulty := 1
var _ladder_grid: GridContainer
var _tier_buttons: Dictionary = {}
var _tier_rows: Dictionary = {}
var _tier_detail_label: Label
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
	_build_dungeon_dropdown()
	_build_board_entry()


func _build_board_entry() -> void:
	var vbox := _new_button.get_parent() as VBoxContainer
	if vbox == null or vbox.has_node("BoardButton"):
		return
	var button := GameUISkinScript.make_button(tr("ENTRY_THE_BOARD"))
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
	_build_tier_ladder()


func _build_tier_ladder() -> void:
	_ensure_ladder_container()
	if _ladder_grid == null:
		return
	for child in _ladder_grid.get_children():
		child.queue_free()
	_tier_buttons.clear()
	_tier_rows.clear()
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
		_tier_rows[tier_num] = row
		button.focus_entered.connect(_show_tier_detail.bind(tier_num))
		button.mouse_entered.connect(_show_tier_detail.bind(tier_num))
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
	var parent := _dungeon_dropdown.get_parent() as Container
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
	parent.add_child(_ladder_grid)
	parent.move_child(_ladder_grid, _dungeon_dropdown.get_index() + 1)
	_tier_detail_label = Label.new()
	_tier_detail_label.name = "TierDetail"
	_tier_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	GameUISkinScript.style_hint_label(_tier_detail_label)
	parent.add_child(_tier_detail_label)
	parent.move_child(_tier_detail_label, _ladder_grid.get_index() + 1)


## What a tier does, written out, for a controller that has no hover to read a tooltip with.
func _show_tier_detail(tier: int) -> void:
	if _tier_detail_label != null and _tier_rows.has(tier):
		_tier_detail_label.text = _ladder_tooltip(_tier_rows[tier])


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
			tr("ENTRY_TIER_HARM")
			% [
				float(row.get("hpMult", 1.0)),
				float(row.get("damageMult", 1.0)),
				int(round(float(row.get("lootBonus", 0.0)) * 100.0)),
			]
		)
	)
	var modifiers: Array = row.get("modifiers", [])
	if modifiers.is_empty():
		lines.append(tr("ENTRY_TIER_NO_RULES"))
	else:
		lines.append(RunModifierService.describe_all(modifiers))
	var clears := int(row.get("clears", 0))
	if clears > 0:
		lines.append(
			tr("ENTRY_TIER_CLEARED") % [clears, _format_time(float(row.get("bestSeconds", 0.0)))]
		)
	elif str(row.get("state", "")) == "locked":
		lines.append(tr("ENTRY_TIER_LOCKED_HINT"))
	else:
		lines.append(tr("ENTRY_TIER_NEVER"))
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
	_show_tier_detail(tier)
	_refresh_contract_label()


func _on_dungeon_selected(index: int) -> void:
	if _dungeon_dropdown == null:
		return
	_selected_dungeon = str(_dungeon_dropdown.get_item_metadata(index))
	CharacterService.set_flag(LAST_DUNGEON_FLAG, _selected_dungeon)
	_build_tier_ladder()
	if _seed_panel.visible:
		_refresh_seed_hint()
	_refresh_contract_label()


func _refresh_contract_label() -> void:
	RunContractLabelScript.refresh(
		_contract_label, RunModeConfig.MODE_CASTLE, _selected_dungeon, _selected_difficulty
	)


func open_menu() -> void:
	_close_board()
	_build_dungeon_dropdown()
	_refresh_continue_state()
	_refresh_alt_modes()
	_show_main_panel()
	MenuStack.show_modal(self)
	_new_button.grab_focus()


## Boss_rush and gauntlet are castle-mode rule sets, listed here as well as on the tower board.
## Rebuilt every open so a mode unlocked mid-session shows up without reopening.
func _refresh_alt_modes() -> void:
	if _alt_mode_row == null:
		return
	for child in _alt_mode_row.get_children():
		child.queue_free()
	AlternateModeRowScript.build_into(_alt_mode_row, RunModeConfig.MODE_CASTLE, _on_alt_mode_pressed)


func _on_alt_mode_pressed(mode_id: String) -> void:
	close_menu()
	RunFlow.start_alternate_mode_run(mode_id)


func close_menu() -> void:
	_close_board()
	MenuStack.hide_modal(self)
	menu_closed.emit()


func is_open() -> bool:
	return visible


func _on_cancel_requested() -> void:
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
			tr("ENTRY_CONTINUE_STATUS")
			% [
				dungeon_name,
				diff_tier,
				floor_num,
				run_seed_value,
			]
		)
	else:
		_status_label.text = (
			tr("ENTRY_CLEAR_TENTH")
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
			tr("ENTRY_SEED_HINT") % order
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
		_seed_hint_label.text = tr("ENTRY_SEED_TIER_LOCKED") % order
		_seed_input.grab_focus()
		return
	close_menu()
	seed_run_requested.emit(run_seed_value)


func get_selected_dungeon() -> String:
	return _selected_dungeon


func get_selected_difficulty_tier() -> int:
	return _selected_difficulty


func _castle_run_continuable() -> bool:
	if not LocalSave.has_continuable_run():
		return false
	var run_mode := str(LocalSave.get_active_run().get("runMode", "castle"))
	return run_mode in ["castle", ""]
