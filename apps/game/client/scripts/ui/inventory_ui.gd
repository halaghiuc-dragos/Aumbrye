extends Control


const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const InventoryUILayoutScript := preload("res://scripts/ui/inventory_ui_layout.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const BlacksmithServiceScript := preload("res://scripts/hub/blacksmith_service.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const RunModeConfigScript := preload("res://scripts/app/run_mode_config.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")
const ConsumableServiceScript := preload("res://scripts/inventory/consumable_service.gd")
const ForgeServiceScript := preload("res://scripts/items/forge_service.gd")
const ItemCellScript := preload("res://scripts/ui/item_cell.gd")

const _NAV_DIRECTIONS := [
	[&"ui_left", Vector2i(-1, 0)],
	[&"ui_right", Vector2i(1, 0)],
	[&"ui_up", Vector2i(0, -1)],
	[&"ui_down", Vector2i(0, 1)],
]

const CELL_BASE_MODULATE := &"inv_base_modulate"
const CELL_HAS_ITEM := &"inv_has_item"
const CELL_HIGHLIGHT_TINT := Color(1.2, 1.2, 1.05)

const CELL_SIZE := InventoryUILayoutScript.CELL_SIZE
const EQUIP_CELL_SIZE := InventoryUILayoutScript.EQUIP_CELL_SIZE
const ITEM_MENU_EQUIP := 1
const ITEM_MENU_USE := 2
const ITEM_MENU_DROP := 3
const ITEM_MENU_BIND_BASE := 100
const QUICK_SLOT_BINDS := 4

const TOOLTIP_WIDTH := 380.0
const TOOLTIP_GAP := 12.0
const HINT_ROW_HEIGHT := 16

const GRID_GAP := InventoryUILayoutScript.GRID_GAP
const EQUIP_LAYOUT: Array = InventoryUILayoutScript.EQUIP_LAYOUT
const SLOT_LABELS: Dictionary = InventoryUILayoutScript.SLOT_LABELS

enum FocusArea { GRID, EQUIPMENT }

var _backdrop: ColorRect
var _grid: GridContainer
var _tooltip_panel: PanelContainer
var _tooltip_content: VBoxContainer
var _hint_row: HBoxContainer
var _item_menu: PopupMenu
var _filter_label: Label
var _search_edit: LineEdit
var _search_text := ""
var _equip_host: GridContainer
var _title_label: Label
var _drag_ghost: PanelContainer

var _inventory_open := false
var _cursor := Vector2i(0, 0)
var _equip_cursor := 0
var _focus_area := FocusArea.GRID
var _selected_index := -1
var _hover_grid_index := -1
var _hover_equip_slot := ""

## Which device is currently driving the panel.
##
## The tooltip used to be resolved from the hover *and* the keyboard cursor in one pass, falling
## back to the selection when nothing was hovered. With a mouse that reads as a bug: move the
## pointer off the grid and the description of the last item you clicked stays on screen, pointing
## at nothing. The two models want different answers to "what is the player looking at" -- a
## pointer is looking at what it is over, and nothing when it is over nothing; a cursor is always
## somewhere. Tracking which one is live lets each answer for itself.
enum InputMode { POINTER, CURSOR }

var _input_mode: InputMode = InputMode.CURSOR
var _cells: Array[PanelContainer] = []
var _equip_cells: Dictionary = {}
var _equip_nav_slots: Array[String] = []
var _visible_indices: Array[int] = []
var _drag_index := -1
var _drag_equip_slot := ""
var _mouse_dragging := false
# Where the pointer went down, so a release can tell a drag from a plain click.
var _drag_origin_cell := Vector2i(-1, -1)
var _sort_mode_idx := 0
var _type_filter_idx := 0
var _rarity_filter_idx := 0
var _equip_wrap: Control
var _stat_label: RichTextLabel
var _waves_mode := false
var _bound_grid_w := -1
var _bound_grid_h := -1
var _action_row: HBoxContainer
var _quick_slot_row: HBoxContainer
var _btn_equip: Button
var _btn_unequip: Button
var _btn_use: Button
var _btn_drop: Button
var _btn_salvage: Button
var _bind_target_index := -1


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui_shell()
	_build_equipment_panel()
	_bind_inventory_context()
	InventoryService.inventory_changed.connect(_on_main_inventory_changed)
	get_tree().scene_changed.connect(_on_scene_changed)
	if WavesRunService:
		WavesRunService.inventory_changed.connect(_on_waves_inventory_changed)
	var symbol_bus := get_node_or_null("/root/UISymbolBus")
	if symbol_bus and not symbol_bus.symbols_invalidated.is_connected(_on_symbols_invalidated):
		symbol_bus.symbols_invalidated.connect(_on_symbols_invalidated)
	InputGlyphServiceScript.connect_device_family_changed(_rebuild_footer_hints)
	_refresh_all()
	# HD-03: `make_center_panel()` only styles the panel shell -- the pixel-filter sweep needs to
	# run after the grid cells and equipment panel exist.
	GameUISkinScript.apply_pixel_theme(self)


func _inventory() -> GridInventory:
	if _waves_mode:
		return WavesRunService.waves_inventory
	return InventoryService.inventory


func _on_scene_changed() -> void:
	call_deferred("_bind_inventory_context")


func _bind_inventory_context() -> void:
	var was_waves := _waves_mode
	_waves_mode = RunFlow != null and RunFlow.get_run_mode() == RunModeConfigScript.MODE_WAVES
	if was_waves != _waves_mode and _inventory_open:
		hide_inventory()
	_ensure_grid_dimensions()
	_refresh_all()


func _on_main_inventory_changed() -> void:
	if not _waves_mode:
		_refresh_all()


func _on_waves_inventory_changed() -> void:
	if _waves_mode:
		_refresh_all()


func _ensure_grid_dimensions() -> void:
	var inv := _inventory()
	if inv.grid_width == _bound_grid_w and inv.grid_height == _bound_grid_h:
		return
	_bound_grid_w = inv.grid_width
	_bound_grid_h = inv.grid_height
	for cell in _cells:
		if is_instance_valid(cell):
			cell.queue_free()
	_cells.clear()
	_grid.columns = inv.grid_width
	for y in inv.grid_height:
		for x in inv.grid_width:
			var cell := _make_item_cell(CELL_SIZE, "common", 0)
			cell.gui_input.connect(_on_cell_gui_input.bind(x, y))
			cell.mouse_entered.connect(_on_cell_mouse_entered.bind(x, y))
			cell.mouse_exited.connect(_on_cell_mouse_exited)
			cell.focus_entered.connect(_on_cell_focus_entered.bind(x, y))
			_grid.add_child(cell)
			_cells.append(cell)
	_wire_grid_focus_neighbors()


func _on_cell_focus_entered(x: int, y: int) -> void:
	if not _inventory_open:
		return
	_cursor = Vector2i(x, y)
	_focus_area = FocusArea.GRID
	_selected_index = _inventory().find_slot_at(x, y)
	_highlight_cursor()
	_refresh_equipment()
	_update_detail()
	_update_action_buttons()


func _wire_grid_focus_neighbors() -> void:
	var inv := _inventory()
	for y in inv.grid_height:
		for x in inv.grid_width:
			var idx := y * inv.grid_width + x
			if idx >= _cells.size():
				continue
			var cell := _cells[idx]
			if x > 0:
				cell.focus_neighbor_left = _cells[idx - 1].get_path()
			if x < inv.grid_width - 1:
				cell.focus_neighbor_right = _cells[idx + 1].get_path()
			if y > 0:
				cell.focus_neighbor_top = _cells[idx - inv.grid_width].get_path()
			if y < inv.grid_height - 1:
				cell.focus_neighbor_bottom = _cells[idx + inv.grid_width].get_path()


func is_open() -> bool:
	return _inventory_open


func _build_ui_shell() -> void:
	for child in get_children():
		child.queue_free()
	_backdrop = GameUISkinScript.make_backdrop(self)
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	var panel := GameUISkinScript.make_center_panel(
		self, GameUISkinScript.INVENTORY_PANEL_HALF_W, GameUISkinScript.INVENTORY_PANEL_HALF_H
	)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", GameUISkinScript.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_top", GameUISkinScript.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_right", GameUISkinScript.PANEL_MARGIN)
	margin.add_theme_constant_override("margin_bottom", GameUISkinScript.PANEL_MARGIN)
	panel.add_child(margin)
	var root_hbox := HBoxContainer.new()
	root_hbox.add_theme_constant_override("separation", GameUISkinScript.SECTION_SEPARATION)
	margin.add_child(root_hbox)
	var grid_frame := GameUISkinScript.make_section_frame(tr("INV_TITLE_STASH"))
	# The stash and the paperdoll are the only two things in this window, so between them they take
	# all of it. Without these the two frames sat at their own minimum widths and left a wide empty
	# band down the right-hand side of the panel.
	grid_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_frame.size_flags_stretch_ratio = 1.9
	root_hbox.add_child(grid_frame)
	var grid_vbox := GameUISkinScript.section_content(grid_frame)
	_title_label = GameUISkinScript.section_header(grid_frame)
	_filter_label = Label.new()
	_filter_label.name = "FilterLabel"
	GameUISkinScript.style_hint_label(_filter_label)
	grid_vbox.add_child(_filter_label)
	_search_edit = LineEdit.new()
	_search_edit.name = "SearchEdit"
	_search_edit.placeholder_text = tr("INV_SEARCH_PLACEHOLDER")
	_search_edit.clear_button_enabled = true
	_search_edit.text_changed.connect(_on_search_changed)
	grid_vbox.add_child(_search_edit)
	_grid = GridContainer.new()
	_grid.name = "GridContainer"
	_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	grid_vbox.add_child(_grid)
	_build_tooltip_overlay()
	var grid_spacer := Control.new()
	grid_spacer.name = "GridSpacer"
	grid_spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	grid_spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	grid_vbox.add_child(grid_spacer)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	grid_vbox.add_child(footer)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	_btn_equip = MenuShellScript.make_menu_button(tr("INV_BTN_EQUIP"), _on_action_equip_pressed)
	_btn_unequip = MenuShellScript.make_menu_button(tr("INV_BTN_UNEQUIP"), _on_action_unequip_pressed)
	_btn_use = MenuShellScript.make_menu_button(tr("INV_BTN_USE"), _on_action_use_pressed)
	_btn_drop = MenuShellScript.make_menu_button(tr("INV_BTN_DROP"), _on_action_drop_pressed)
	_btn_salvage = MenuShellScript.make_menu_button(tr("SMITH_SALVAGE"), _on_action_salvage_pressed)
	_action_row.add_child(_btn_equip)
	_action_row.add_child(_btn_unequip)
	_action_row.add_child(_btn_use)
	_action_row.add_child(_btn_drop)
	_action_row.add_child(_btn_salvage)
	_pin_action_button_widths()
	_btn_equip.focus_neighbor_top = _grid.get_path()
	footer.add_child(_action_row)
	_reserve_action_row_width()
	_quick_slot_row = HBoxContainer.new()
	_quick_slot_row.add_theme_constant_override("separation", 10)
	footer.add_child(_quick_slot_row)
	# A plain `Control`, not a container: unlike a container it does not adopt its children's
	# minimum size, so a long hint is clipped instead of widening the panel. The window's
	# dimensions must never change — not on hover, not on selection, not on any action.
	var hint_clip := Control.new()
	hint_clip.name = "HintClip"
	hint_clip.clip_contents = true
	hint_clip.custom_minimum_size.y = HINT_ROW_HEIGHT
	hint_clip.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hint_clip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(hint_clip)
	_hint_row = HBoxContainer.new()
	_hint_row.name = "HintRow"
	_hint_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_hint_row.add_theme_constant_override("separation", 3)
	_hint_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.set_anchors_preset(Control.PRESET_FULL_RECT)
	hint_clip.add_child(_hint_row)
	var separator := VSeparator.new()
	separator.custom_minimum_size.x = 4
	root_hbox.add_child(separator)
	var equip_frame := GameUISkinScript.make_section_frame(tr("INV_TITLE_CHARACTER"))
	equip_frame.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	equip_frame.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_frame.size_flags_stretch_ratio = 1.0
	root_hbox.add_child(equip_frame)
	var equip_vbox := GameUISkinScript.section_content(equip_frame)
	_equip_wrap = Control.new()
	_equip_wrap.name = "EquipWrap"
	_equip_wrap.custom_minimum_size = Vector2(
		EQUIP_CELL_SIZE * 3 + GRID_GAP * 2 + 24, EQUIP_CELL_SIZE * 4 + GRID_GAP * 3 + 24
	)
	# Fills the character column rather than sitting at its minimum size in the top corner of it:
	# the paperdoll backdrop is anchored to this control, so growing it is what puts the figure
	# behind the slots instead of leaving a tall empty box underneath them.
	_equip_wrap.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_equip_wrap.size_flags_vertical = Control.SIZE_EXPAND_FILL
	equip_vbox.add_child(_equip_wrap)
	GameUISkinScript.build_paperdoll_backdrop(_equip_wrap, EQUIP_CELL_SIZE, GRID_GAP)
	_equip_host = GridContainer.new()
	_equip_host.name = "EquipGrid"
	_equip_host.columns = 3
	_equip_host.add_theme_constant_override("h_separation", GRID_GAP)
	_equip_host.add_theme_constant_override("v_separation", GRID_GAP)
	# A centring container rather than anchors on the grid itself: the grid's minimum size is not
	# known until its cells are in, so an anchor preset applied here would centre a zero-sized rect
	# and leave the paperdoll hanging off the corner of the frame.
	var equip_center := CenterContainer.new()
	equip_center.name = "EquipCenter"
	equip_center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	equip_center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_equip_wrap.add_child(equip_center)
	equip_center.add_child(_equip_host)
	_build_stat_panel(equip_vbox)
	_drag_ghost = _make_item_cell(CELL_SIZE, "common", 0)
	_drag_ghost.visible = false
	set_process(false)
	_drag_ghost.z_index = 100
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_ghost)


func _input(event: InputEvent) -> void:
	if not _inventory_open:
		return
	if event.is_action_pressed("inventory"):
		hide_inventory()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		if _drag_index >= 0 or _drag_equip_slot != "":
			_clear_drag()
			_refresh_all()
		else:
			hide_inventory()
		get_viewport().set_input_as_handled()
		return
	for direction in _NAV_DIRECTIONS:
		if event.is_action_pressed(direction[0]):
			_navigate(direction[1])
			get_viewport().set_input_as_handled()
			return
	if _try_quick_slot_bind_input(event):
		get_viewport().set_input_as_handled()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _inventory_open:
		return
	if event.is_action_pressed("ui_accept"):
		_confirm_action()
		get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_left"):
		_navigate(Vector2i(-1, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_right"):
		_navigate(Vector2i(1, 0))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_up"):
		_navigate(Vector2i(0, -1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("ui_down"):
		_navigate(Vector2i(0, 1))
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("sprint"):
		_cycle_sort()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("lock_on"):
		_cycle_type_filter()
		get_viewport().set_input_as_handled()
	elif event.is_action_pressed("interact"):
		_cycle_rarity_filter()
		get_viewport().set_input_as_handled()
		return
	elif event.is_action_pressed("inventory_split"):
		_split_selected_stack()
		get_viewport().set_input_as_handled()
		return
	if _try_quick_slot_bind_input(event):
		get_viewport().set_input_as_handled()


func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		set_process(false)


func _process(_delta: float) -> void:
	if not _inventory_open or not _drag_ghost.visible:
		set_process(false)
		return
	var half := Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	_drag_ghost.global_position = get_global_mouse_position() - half


func toggle() -> void:
	if _inventory_open:
		hide_inventory()
	else:
		show_inventory()


func show_inventory() -> void:
	move_to_front()
	_bind_inventory_context()
	_inventory_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if MenuStack:
		MenuStack.push(self)
	_focus_area = FocusArea.GRID
	_cursor = Vector2i(0, 0)
	_clear_drag()
	_rebuild_visible_indices()
	_refresh_all()
	_highlight_cursor.call_deferred()


func hide_inventory() -> void:
	_inventory_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_drag()
	if MenuStack:
		MenuStack.pop(self)


## Offence, defence and resistances for the live loadout. Without this the entire loot system is
## invisible: 264 items and 68 affixes mean nothing if the player cannot tell whether the thing
## they just picked up is better than the thing they are wearing.
const STAT_PANEL_UP := "#7fd67f"
const STAT_PANEL_DOWN := "#e07a7a"

const STAT_PANEL_OFFENCE: Array[String] = [
	"physicalDamage",
	"fireDamage",
	"frostDamage",
	"poisonDamage",
	"arcaneDamage",
	"damagePercent",
	"critChance",
	"poiseDamage",
	"attackSpeed",
	"lifesteal",
]
const STAT_PANEL_DEFENCE: Array[String] = [
	"maxHealth",
	"defense",
	"armor",
	"poise",
	"evasion",
	"blockReduction",
	"damageReduction",
]
const STAT_PANEL_UPKEEP: Array[String] = [
	"staminaMax",
	"staminaRegen",
	"staminaCostReduction",
	"manaMax",
	"manaRegen",
	"healthRegen",
	"moveSpeedPercent",
]
const STAT_PANEL_RESISTS: Array[String] = [
	"resistPhysical",
	"resistFire",
	"resistFrost",
	"resistPoison",
	"resistLightning",
	"resistArcane",
]


func _build_stat_panel(host: VBoxContainer) -> void:
	var frame := GameUISkinScript.make_section_frame(tr("INV_STATS_TITLE"))
	frame.name = "StatFrame"
	frame.size_flags_vertical = Control.SIZE_SHRINK_END
	host.add_child(frame)
	var content := GameUISkinScript.section_content(frame)
	_stat_label = RichTextLabel.new()
	_stat_label.name = "StatLabel"
	_stat_label.bbcode_enabled = true
	_stat_label.fit_content = true
	_stat_label.scroll_active = false
	_stat_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_stat_label.custom_minimum_size.y = 132.0
	_stat_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content.add_child(_stat_label)
	_refresh_stat_panel()


func _refresh_stat_panel() -> void:
	if _stat_label == null or not is_instance_valid(_stat_label):
		return
	# In the Vigil the panel must read the run's own loadout, not the character's hub gear.
	var stats := (
		Equipment.aggregate_stats(
			WavesRunService.waves_inventory.equipped, Callable(AffixRoller, "get_affix_stat")
		)
		if _waves_mode
		else InventoryService.get_combat_aggregate_stats()
	)
	var columns: Array[String] = []
	for group in [STAT_PANEL_OFFENCE, STAT_PANEL_DEFENCE, STAT_PANEL_UPKEEP, STAT_PANEL_RESISTS]:
		var lines := _stat_group_lines(stats, group)
		if not lines.is_empty():
			columns.append("\n".join(lines))
	_stat_label.text = (
		"\n\n".join(columns) if not columns.is_empty() else tr("INV_STATS_EMPTY")
	)


static func _bbcode_safe(text: String) -> String:
	return text.replace("[", "[lb]")


func _stat_group_lines(stats: Dictionary, group: Array[String]) -> Array[String]:
	var lines: Array[String] = []
	for stat in group:
		var value := float(stats.get(stat, 0.0))
		if is_zero_approx(value):
			continue
		lines.append(
			"%s  [color=%s]%s[/color]"
			% [
				_bbcode_safe(Equipment.stat_display_name(stat)),
				STAT_PANEL_UP if value > 0.0 else STAT_PANEL_DOWN,
				_bbcode_safe(Equipment.format_stat_value(stat, value)),
			]
		)
	return lines


func _build_equipment_panel() -> void:
	_equip_nav_slots.clear()
	for row in EQUIP_LAYOUT:
		for slot_name in row:
			if str(slot_name) == "":
				var spacer := Control.new()
				spacer.custom_minimum_size = Vector2(EQUIP_CELL_SIZE, EQUIP_CELL_SIZE)
				_equip_host.add_child(spacer)
				continue
			var slot_key: String = str(slot_name)
			_equip_nav_slots.append(slot_key)
			var cell := _make_equip_cell(slot_key)
			cell.gui_input.connect(_on_equip_gui_input.bind(slot_key))
			cell.mouse_entered.connect(_on_equip_mouse_entered.bind(slot_key))
			cell.mouse_exited.connect(_on_equip_mouse_exited)
			_equip_host.add_child(cell)
			_equip_cells[slot_key] = cell


func _make_equip_cell(slot_name: String) -> PanelContainer:
	var cell := _make_item_cell(EQUIP_CELL_SIZE, "common", 0)
	cell.set_meta("slot_name", slot_name)
	cell.focus_entered.connect(_on_equip_focus_entered.bind(slot_name))
	return cell


func _on_equip_focus_entered(slot_name: String) -> void:
	if not _inventory_open:
		return
	_focus_area = FocusArea.EQUIPMENT
	_equip_cursor = _equip_nav_slots.find(slot_name)
	_refresh_equipment()
	_update_detail()
	_update_action_buttons()


func _make_item_cell(cell_size: int, rarity: String, upgrade_level: int) -> PanelContainer:
	return ItemCellScript.make_cell(cell_size, rarity, upgrade_level)


func _set_cell_content(
	cell: PanelContainer,
	rarity: String,
	upgrade_level: int,
	slot: Dictionary = {},
	empty_slot_name: String = ""
) -> void:
	ItemCellScript.set_cell_content(cell, rarity, upgrade_level, slot, empty_slot_name)


func _refresh_all() -> void:
	_rebuild_visible_indices()
	_refresh_grid()
	_refresh_equipment()
	_update_filter_label()
	_update_detail()
	_refresh_quick_slot_row()
	_refresh_stat_panel()
	_update_action_buttons()


func _rebuild_visible_indices() -> void:
	_visible_indices.clear()
	var type_filter := GridInventory.FILTER_TYPES[_type_filter_idx]
	var rarity_filter := GridInventory.FILTER_RARITIES[_rarity_filter_idx]
	var inv := _inventory()
	for filtered in inv.filter_slots(type_filter, rarity_filter):
		var idx := int(filtered.get("_index", -1))
		if idx < 0:
			continue
		if _search_text.strip_edges() != "" and not _passes_search(inv.slots[idx]):
			continue
		_visible_indices.append(idx)


func _passes_search(slot: Dictionary) -> bool:
	var needle := _search_text.strip_edges().to_lower()
	if needle == "":
		return true
	return _inventory().get_slot_display_name(slot).to_lower().contains(needle)


func _refresh_grid() -> void:
	var inv := _inventory()
	for cell in _cells:
		_set_cell_content(cell, "common", 0)
		cell.self_modulate = Color.WHITE
		cell.set_meta(CELL_BASE_MODULATE, Color.WHITE)
		cell.set_meta(CELL_HAS_ITEM, false)
	var occupied: Dictionary = {}
	var visible_set: Dictionary = {}
	for idx in _visible_indices:
		visible_set[idx] = true
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		if slot.is_empty():
			continue
		var dimmed := _visible_indices.size() > 0 and not visible_set.has(i)
		var def := _item_def(slot.get("itemId", ""))
		var w: int = int(def.get("gridWidth", 1))
		var h: int = int(def.get("gridHeight", 1))
		var ox: int = int(slot.get("x", 0))
		var oy: int = int(slot.get("y", 0))
		var rarity := inv.get_slot_rarity(slot)
		var upgrade := BlacksmithServiceScript.get_slot_upgrade_level(slot)
		for dy in h:
			for dx in w:
				var gx := ox + dx
				var gy := oy + dy
				var idx := gy * inv.grid_width + gx
				if idx < 0 or idx >= _cells.size():
					continue
				occupied[idx] = true
				_cells[idx].set_meta(CELL_HAS_ITEM, true)
				var is_origin := dx == 0 and dy == 0
				_set_cell_content(
					_cells[idx], rarity, upgrade if is_origin else 0, slot if is_origin else {}
				)
				if dimmed:
					_cells[idx].self_modulate = Color(1, 1, 1, 0.35)
				elif i == _drag_index:
					_cells[idx].self_modulate = Color(1.1, 1.0, 0.55)
				elif _is_equipped_instance(slot):
					_cells[idx].self_modulate = Color(0.75, 0.85, 1.0)
				_cells[idx].set_meta(CELL_BASE_MODULATE, _cells[idx].self_modulate)
	_highlight_cursor()


func _refresh_equipment() -> void:
	var inv := _inventory()
	for slot_name in _equip_nav_slots:
		var cell: PanelContainer = _equip_cells.get(slot_name, null)
		if cell == null:
			continue
		var inst: Dictionary = inv.equipped.get(slot_name, {})
		if inst.is_empty():
			_set_cell_content(cell, "common", 0, {}, slot_name)
		else:
			var rarity := inv.get_slot_rarity(inst)
			var upgrade := BlacksmithServiceScript.get_slot_upgrade_level(inst)
			_set_cell_content(cell, rarity, upgrade, inst)
		var nav_idx := _equip_nav_slots.find(slot_name)
		var focused := _focus_area == FocusArea.EQUIPMENT and nav_idx == _equip_cursor
		var hovered := _hover_equip_slot == slot_name
		cell.self_modulate = Color(1.18, 1.15, 0.95) if focused or hovered else Color.WHITE
		if _drag_equip_slot == slot_name:
			cell.self_modulate = Color(1.1, 1.0, 0.55)


func _highlight_cursor() -> void:
	var inv := _inventory()
	var idx := _cursor.y * inv.grid_width + _cursor.x
	for i in _cells.size():
		var cell := _cells[i]
		var base: Color = cell.get_meta(CELL_BASE_MODULATE, Color.WHITE)
		var on_cell := _focus_area == FocusArea.GRID and (i == idx or _hover_grid_index == i)
		if on_cell and bool(cell.get_meta(CELL_HAS_ITEM, false)):
			cell.self_modulate = base * CELL_HIGHLIGHT_TINT
		else:
			cell.self_modulate = base
	_selected_index = inv.find_slot_at(_cursor.x, _cursor.y)


func _update_filter_label() -> void:
	var sort_mode := GridInventory.SORT_MODES[_sort_mode_idx]
	var type_f := GridInventory.FILTER_TYPES[_type_filter_idx]
	var rarity_f := GridInventory.FILTER_RARITIES[_rarity_filter_idx]
	_filter_label.text = (
		tr("INV_FILTER_ROW")
		% [tr("INV_SORT"), sort_mode, tr("INV_TYPE"), type_f, tr("INV_RARITY"), rarity_f]
	)
	if _title_label:
		_title_label.text = (
			tr("INV_TITLE_WAVES_STASH") if _waves_mode else tr("INV_TITLE_STASH")
		).to_upper()


## The description is a floating pop-up parented to the root, outside every container, so nothing
## it does can resize the panel. It is faded rather than hidden, because hiding a Control re-runs
## the layout it is deliberately outside of.
func _build_tooltip_overlay() -> void:
	_tooltip_panel = PanelContainer.new()
	_tooltip_panel.name = "TooltipPanel"
	_tooltip_panel.modulate.a = 0.0
	_tooltip_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_panel.z_index = 80
	_tooltip_panel.top_level = true
	_tooltip_panel.custom_minimum_size.x = TOOLTIP_WIDTH
	_tooltip_panel.add_theme_stylebox_override("panel", GameUISkinScript.make_panel_style())
	add_child(_tooltip_panel)
	var tooltip_margin := MarginContainer.new()
	tooltip_margin.add_theme_constant_override("margin_left", 10)
	tooltip_margin.add_theme_constant_override("margin_top", 8)
	tooltip_margin.add_theme_constant_override("margin_right", 10)
	tooltip_margin.add_theme_constant_override("margin_bottom", 8)
	_tooltip_panel.add_child(tooltip_margin)
	_tooltip_content = VBoxContainer.new()
	_tooltip_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tooltip_margin.add_child(_tooltip_content)


func _place_tooltip_near(anchor_rect: Rect2) -> void:
	if _tooltip_panel == null:
		return
	var wanted := _tooltip_panel.get_combined_minimum_size()
	wanted.x = maxf(wanted.x, TOOLTIP_WIDTH)
	_tooltip_panel.size = wanted
	var screen := get_viewport_rect().size
	var pos := Vector2(anchor_rect.end.x + TOOLTIP_GAP, anchor_rect.position.y)
	if pos.x + wanted.x > screen.x - TOOLTIP_GAP:
		pos.x = anchor_rect.position.x - TOOLTIP_GAP - wanted.x
	pos.x = clampf(pos.x, TOOLTIP_GAP, maxf(TOOLTIP_GAP, screen.x - wanted.x - TOOLTIP_GAP))
	pos.y = clampf(pos.y, TOOLTIP_GAP, maxf(TOOLTIP_GAP, screen.y - wanted.y - TOOLTIP_GAP))
	_tooltip_panel.global_position = pos


func _detail_anchor_rect() -> Rect2:
	var control: Control = null
	if _hover_equip_slot != "" and _equip_cells.has(_hover_equip_slot):
		control = _equip_cells[_hover_equip_slot] as Control
	elif _hover_grid_index >= 0 and _hover_grid_index < _cells.size():
		control = _cells[_hover_grid_index] as Control
	if control != null and control.is_inside_tree():
		return Rect2(control.global_position, control.size)
	var mouse := get_viewport().get_mouse_position()
	return Rect2(mouse, Vector2(8, 8))


func _set_tooltip_shown(shown: bool) -> void:
	if _tooltip_panel:
		_tooltip_panel.modulate.a = 1.0 if shown else 0.0


func _hide_tooltip() -> void:
	_set_tooltip_shown(false)


func _show_tooltip(
	header: String, body: String, hint: String = "", comparison: String = ""
) -> void:
	for child in _tooltip_content.get_children():
		_tooltip_content.remove_child(child)
		child.queue_free()
	if header != "":
		var title := Label.new()
		title.text = header
		title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		title.custom_minimum_size.x = TOOLTIP_WIDTH - 20.0
		GameUISkinScript.style_section_title(title)
		_tooltip_content.add_child(title)
	for text in [body, comparison]:
		if str(text) == "":
			continue
		var rich := RichTextLabel.new()
		rich.bbcode_enabled = true
		rich.fit_content = true
		rich.scroll_active = false
		rich.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		rich.custom_minimum_size.x = TOOLTIP_WIDTH - 20.0
		rich.text = str(text)
		_tooltip_content.add_child(rich)
	var has_content := header != "" or body != "" or comparison != ""
	_set_tooltip_shown(has_content)
	if has_content:
		_place_tooltip_near(_detail_anchor_rect())
	if hint != "":
		_set_hint_text(hint)


func _update_detail() -> void:
	var inv := _inventory()

	# Nothing is described while an item is in the hand. The tooltip would sit over the grid the
	# player is trying to drop into, and describe the thing they are already holding.
	if _is_dragging():
		_hide_tooltip()
		return

	var equip_slot := _described_equip_slot()
	if equip_slot != "":
		var equipped: Dictionary = inv.equipped.get(equip_slot, {})
		if equipped.is_empty():
			_show_tooltip(
				tr("INV_EMPTY_SLOT") % _slot_label(equip_slot), "", tr("INV_HINT_UNEQUIP")
			)
			return
		_show_tooltip(
			_build_tooltip_header(equipped),
			InventoryService.format_slot_tooltip_bbcode(equipped, false),
			""
		)
		_set_hint_text(tr("INV_HINT_UNEQUIP"))
		return

	var compare_index := _described_grid_index()
	if compare_index < 0:
		_hide_tooltip()
		_footer_hint_default()
		return
	var detail_slot: Dictionary = inv.slots[compare_index]
	_show_tooltip(
		_build_tooltip_header(detail_slot),
		InventoryService.format_slot_tooltip_bbcode(detail_slot, false),
		""
	)
	var def := _item_def(detail_slot.get("itemId", ""))
	var item_type: String = def.get("itemType", "")
	if item_type in ["weapon", "armor", "accessory"]:
		_set_hint_text(tr("INV_HINT_EQUIP"))
	elif item_type == "consumable":
		var in_run := RunFlow != null and RunFlow.is_run_active()
		var guard := ConsumableServiceScript.can_use(def, in_run, not in_run)
		if bool(guard.get("ok", false)):
			_set_hint_text(tr("INV_HINT_USE"))
		else:
			_set_hint_text(str(guard.get("reason", tr("INV_HINT_USE"))))
	else:
		_set_hint_text(tr("INV_HINT_MOVE"))


func _is_dragging() -> bool:
	return _mouse_dragging or _drag_index >= 0 or _drag_equip_slot != ""


## Which equipment slot the player is looking at, or "" for none. A pointer answers with what it is
## over; a cursor answers with where it sits.
func _described_equip_slot() -> String:
	if _input_mode == InputMode.POINTER:
		return _hover_equip_slot
	if _focus_area != FocusArea.EQUIPMENT:
		return ""
	return str(_equip_nav_slots[_equip_cursor])


## Which grid slot the player is looking at, or -1. Same split: off the grid, a pointer is looking
## at nothing, and saying so is the whole fix for the description that used to stay behind.
func _described_grid_index() -> int:
	if _input_mode == InputMode.POINTER:
		return _index_at_grid_cell(_hover_grid_index) if _hover_grid_index >= 0 else -1
	if _focus_area != FocusArea.GRID:
		return -1
	return _selected_index


func _navigate(delta: Vector2i) -> void:
	_input_mode = InputMode.CURSOR
	if _focus_area == FocusArea.EQUIPMENT:
		if delta.x < 0:
			_focus_area = FocusArea.GRID
		else:
			_equip_cursor = clampi(_equip_cursor + delta.y, 0, _equip_nav_slots.size() - 1)
	else:
		var inv := _inventory()
		_cursor.x = clampi(_cursor.x + delta.x, 0, inv.grid_width - 1)
		_cursor.y = clampi(_cursor.y + delta.y, 0, inv.grid_height - 1)
		if delta.x > 0 and _cursor.x == inv.grid_width - 1:
			_focus_area = FocusArea.EQUIPMENT
			_equip_cursor = clampi(_equip_cursor, 0, _equip_nav_slots.size() - 1)
	_highlight_cursor()
	_refresh_equipment()
	_update_detail()
	_update_action_buttons()


func _confirm_action() -> void:
	var inv := _inventory()
	if _focus_area == FocusArea.EQUIPMENT:
		_unequip_slot(_equip_nav_slots[_equip_cursor])
		return
	if _drag_index >= 0:
		_drop_on_grid(_cursor.x, _cursor.y)
		return
	if _drag_equip_slot != "":
		_drop_equip_on_grid(_drag_equip_slot, _cursor.x, _cursor.y)
		return
	if _selected_index < 0:
		return
	var slot: Dictionary = inv.slots[_selected_index]
	var def := _item_def(slot.get("itemId", ""))
	var item_type: String = def.get("itemType", "")
	if item_type in ["weapon", "armor", "accessory"]:
		if inv.equip_from_index(_selected_index):
			_apply_equipment()
			_refresh_all()
		return
	if item_type == "consumable":
		_use_selected_consumable()
		return
	_drag_index = _selected_index
	_show_drag_ghost_from_slot(slot)
	_refresh_all()


func _unequip_slot(slot_name: String) -> void:
	var inv := _inventory()
	if inv.unequip(slot_name):
		_apply_equipment()
		_clear_drag()
		_refresh_all()


func _drop_on_grid(x: int, y: int) -> void:
	var inv := _inventory()
	if not inv.move_slot(_drag_index, x, y):
		# The drop was refused -- the cells are taken, or the item overhangs the edge.
		# Nothing moved, but the drag still has to end: leaving it live kept the ghost on
		# screen and made the next click anywhere drop this item again instead of
		# selecting whatever was actually clicked.
		_set_hint_text(tr("INV_MOVE_FAILED"))
		_clear_drag()
		_refresh_all()
		return
	_clear_drag()
	_refresh_all()


func _drop_equip_on_grid(slot_name: String, x: int, y: int) -> void:
	var inv := _inventory()
	var instance: Dictionary = inv.equipped.get(slot_name, {})
	if instance.is_empty():
		# The slot emptied between picking the item up and letting go of it -- taken off
		# with the keyboard, say. End the drag rather than leaving it holding nothing.
		_clear_drag()
		_refresh_all()
		return
	var instance_id: String = instance.get("instanceId", "")
	if not inv.unequip(slot_name):
		# No room in the stash to take it off. Same trap as above: returning here left the
		# drag live, so the ghost stayed stuck to the cursor with the item still worn.
		_set_hint_text(tr("INV_STASH_FULL"))
		_clear_drag()
		_refresh_all()
		return
	var new_index := -1
	for i in inv.slots.size():
		if inv.slots[i].get("instanceId", "") == instance_id:
			new_index = i
			break
	if new_index >= 0 and inv.move_slot(new_index, x, y):
		_apply_equipment()
	_clear_drag()
	_refresh_all()


func _try_equip_dragged_to_slot(slot_name: String) -> bool:
	var inv := _inventory()
	if _drag_index < 0:
		return false
	var slot: Dictionary = inv.slots[_drag_index]
	var def := _item_def(slot.get("itemId", ""))
	if not Equipment.can_equip_in_slot(def, slot_name):
		return false
	if inv.equip_from_index(_drag_index, slot_name):
		_apply_equipment()
		_clear_drag()
		_refresh_all()
		return true
	return false


func _use_selected_consumable() -> void:
	if _waves_mode:
		_set_hint_text(tr("INV_USE_FAILED"))
		return
	var result := InventoryService.try_use_slot_index(_selected_index)
	if not bool(result.get("ok", false)):
		var reason := str(result.get("reason", ""))
		if reason != "":
			_set_hint_text(reason)
		return
	_refresh_all()


func _split_selected_stack() -> void:
	if _selected_index < 0:
		return
	if _inventory().split_stack(_selected_index):
		_refresh_all()


func _on_search_changed(text: String) -> void:
	_search_text = text
	_refresh_all()


func _cycle_sort() -> void:
	_sort_mode_idx = (_sort_mode_idx + 1) % GridInventory.SORT_MODES.size()
	_inventory().sort_slots(GridInventory.SORT_MODES[_sort_mode_idx])
	_refresh_all()


func _cycle_type_filter() -> void:
	_type_filter_idx = (_type_filter_idx + 1) % GridInventory.FILTER_TYPES.size()
	_refresh_all()


func _cycle_rarity_filter() -> void:
	_rarity_filter_idx = (_rarity_filter_idx + 1) % GridInventory.FILTER_RARITIES.size()
	_refresh_all()


func _on_cell_gui_input(event: InputEvent, x: int, y: int) -> void:
	if not _inventory_open:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_cursor = Vector2i(x, y)
		_focus_area = FocusArea.GRID
		_selected_index = _inventory().find_slot_at(x, y)
		if event.pressed:
			_handle_grid_press(x, y)
		elif _mouse_dragging:
			# Not `x, y`. Godot delivers a button release to whichever control took the *press*, so
			# these coordinates are always the cell the drag started from — which is why dropping an
			# item onto an equipment slot did nothing at all: the release resolved back onto the
			# source cell and the drag ended there. The pointer position is the only thing that says
			# where the item was actually let go.
			_finish_mouse_drag(event.global_position)
		_highlight_cursor()
		_refresh_equipment()
		_update_detail()
	elif (
		event is InputEventMouseButton
		and event.button_index == MOUSE_BUTTON_RIGHT
		and event.pressed
	):
		_cursor = Vector2i(x, y)
		_focus_area = FocusArea.GRID
		_selected_index = _inventory().find_slot_at(x, y)
		_highlight_cursor()
		_refresh_equipment()
		_update_detail()
		_open_item_menu((event as InputEventMouseButton).global_position)
	_update_action_buttons()


func _on_equip_gui_input(event: InputEvent, slot_name: String) -> void:
	if not _inventory_open:
		return
	if not (event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT):
		return
	var button := event as InputEventMouseButton
	if button.pressed:
		_focus_area = FocusArea.EQUIPMENT
		_equip_cursor = _equip_nav_slots.find(slot_name)
		_handle_equip_press(slot_name)
	elif _mouse_dragging:
		_finish_mouse_drag(button.global_position)


func _on_cell_mouse_entered(x: int, y: int) -> void:
	if not _inventory_open:
		return
	_input_mode = InputMode.POINTER
	_hover_grid_index = y * _inventory().grid_width + x
	_hover_equip_slot = ""
	_highlight_cursor()
	_update_detail()
	_update_action_buttons()


func _on_cell_mouse_exited() -> void:
	_input_mode = InputMode.POINTER
	_hover_grid_index = -1
	_highlight_cursor()
	_update_detail()
	_update_action_buttons()


func _on_equip_mouse_entered(slot_name: String) -> void:
	if not _inventory_open:
		return
	_input_mode = InputMode.POINTER
	_hover_equip_slot = slot_name
	_refresh_equipment()
	_update_detail()
	_update_action_buttons()


func _on_equip_mouse_exited() -> void:
	_input_mode = InputMode.POINTER
	_hover_equip_slot = ""
	_refresh_equipment()
	_update_detail()
	_update_action_buttons()


func _open_item_menu(at_screen: Vector2) -> void:
	if _item_menu != null and is_instance_valid(_item_menu):
		_item_menu.queue_free()
	_item_menu = null
	var inv := _inventory()
	if _selected_index < 0 or _selected_index >= inv.slots.size():
		return
	var slot: Dictionary = inv.slots[_selected_index]
	var item_id := str(slot.get("itemId", ""))
	if item_id == "":
		return
	var def := _item_def(item_id)
	var item_type := str(def.get("itemType", ""))

	var menu := PopupMenu.new()
	menu.name = "ItemMenu"
	if item_type in ["weapon", "armor", "accessory"]:
		menu.add_item(tr("INV_BTN_EQUIP"), ITEM_MENU_EQUIP)
	elif item_type == "consumable":
		menu.add_item(tr("INV_BTN_USE"), ITEM_MENU_USE)
	if item_type == "consumable" and not _waves_mode:
		for quick in QUICK_SLOT_BINDS:
			menu.add_item("Bind to %d" % (quick + 1), ITEM_MENU_BIND_BASE + quick)
	if menu.item_count > 0:
		menu.add_separator()
	menu.add_item(tr("INV_BTN_DROP"), ITEM_MENU_DROP)
	menu.id_pressed.connect(_on_item_menu_id)
	add_child(menu)
	_item_menu = menu
	menu.position = Vector2i(at_screen)
	menu.popup()


func _bind_selected_to_quick_slot(quick_index: int) -> void:
	if _waves_mode or _selected_index < 0:
		return
	var slots := _inventory().slots
	if _selected_index >= slots.size():
		return
	var slot: Dictionary = slots[_selected_index]
	InventoryService.set_quick_slot(quick_index, str(slot.get("instanceId", "")))
	_refresh_quick_slot_row()


func _on_item_menu_id(id: int) -> void:
	var inv := _inventory()
	if _selected_index < 0 or _selected_index >= inv.slots.size():
		return
	if id >= ITEM_MENU_BIND_BASE:
		_bind_selected_to_quick_slot(id - ITEM_MENU_BIND_BASE)
		return
	match id:
		ITEM_MENU_EQUIP:
			if inv.equip_from_index(_selected_index):
				_apply_equipment()
				_refresh_all()
		ITEM_MENU_USE:
			_use_selected_consumable()
		ITEM_MENU_DROP:
			_on_action_drop_pressed()


func _handle_grid_press(x: int, y: int) -> void:
	var inv := _inventory()
	if _drag_equip_slot != "":
		_drop_equip_on_grid(_drag_equip_slot, x, y)
		return
	if _drag_index >= 0:
		_drop_on_grid(x, y)
		return
	var idx := inv.find_slot_at(x, y)
	if idx < 0:
		return
	_selected_index = idx
	_drag_index = idx
	_mouse_dragging = true
	_drag_origin_cell = Vector2i(x, y)
	_show_drag_ghost_from_slot(_inventory().slots[idx])
	_refresh_all()


func _handle_equip_press(slot_name: String) -> void:
	if _drag_index >= 0:
		_try_equip_dragged_to_slot(slot_name)
		return
	# Picking an equipped item up rather than taking it off outright. A press that is released on
	# the same slot still reads as a click and unequips (see `_finish_mouse_drag`); one released
	# over the stash puts the item down there instead.
	if _inventory().equipped.get(slot_name, {}).is_empty():
		return
	_drag_equip_slot = slot_name
	_mouse_dragging = true
	_drag_origin_cell = Vector2i(-1, -1)
	_show_drag_ghost_from_slot(_inventory().equipped[slot_name])
	_refresh_all()


# Resolves a mouse drag against whatever sits under the pointer when the button comes up.
func _finish_mouse_drag(global_pos: Vector2) -> void:
	_mouse_dragging = false
	var equip_slot := _equip_slot_at(global_pos)
	if _drag_equip_slot != "":
		var from_slot := _drag_equip_slot
		if equip_slot == from_slot:
			# Pressed and released on the same slot with nothing in between: a click, so take it off.
			_clear_drag()
			_unequip_slot(from_slot)
			return
		var grid_cell := _grid_cell_at(global_pos)
		if grid_cell.x >= 0:
			_drop_equip_on_grid(from_slot, grid_cell.x, grid_cell.y)
			return
		_clear_drag()
		_refresh_all()
		return
	if _drag_index < 0:
		_clear_drag()
		return
	if equip_slot != "":
		if not _try_equip_dragged_to_slot(equip_slot):
			_set_hint_text(tr("INV_EQUIP_FAILED"))
			_clear_drag()
			_refresh_all()
		return
	var target := _grid_cell_at(global_pos)
	if target.x < 0 or target == _drag_origin_cell:
		# Dropped on nothing, or let go where it was picked up — leave the item where it is.
		_clear_drag()
		_refresh_all()
		return
	_drop_on_grid(target.x, target.y)


# The equipment slot under a screen position, or "" for none.
func _equip_slot_at(global_pos: Vector2) -> String:
	for slot_name in _equip_cells:
		var cell: PanelContainer = _equip_cells[slot_name]
		if is_instance_valid(cell) and cell.get_global_rect().has_point(global_pos):
			return str(slot_name)
	return ""


# The stash cell under a screen position, as grid coordinates, or (-1, -1) for none.
func _grid_cell_at(global_pos: Vector2) -> Vector2i:
	var width := _inventory().grid_width
	for i in _cells.size():
		var cell := _cells[i]
		if is_instance_valid(cell) and cell.get_global_rect().has_point(global_pos):
			@warning_ignore("integer_division")
			return Vector2i(i % width, i / width)
	return Vector2i(-1, -1)


func _show_drag_ghost_from_slot(slot: Dictionary) -> void:
	var inv := _inventory()
	var rarity := inv.get_slot_rarity(slot)
	var upgrade := BlacksmithServiceScript.get_slot_upgrade_level(slot)
	_set_cell_content(_drag_ghost, rarity, upgrade, slot)
	_drag_ghost.visible = true
	set_process(true)


func _clear_drag() -> void:
	_drag_index = -1
	_drag_equip_slot = ""
	_mouse_dragging = false
	_drag_origin_cell = Vector2i(-1, -1)
	_drag_ghost.visible = false
	set_process(false)
	# Putting the item down is the moment the description becomes useful again, and not every
	# caller of this remembers to refresh. Doing it here means none of them have to.
	if _inventory_open:
		_update_detail()


func _apply_equipment() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if _waves_mode:
		WavesRunService.apply_equipment_to_player(player)
	else:
		InventoryService.apply_equipment_to_player_node(player)


func _clear_hint_row() -> void:
	if _hint_row == null:
		return
	for child in _hint_row.get_children():
		child.queue_free()


func _set_hint_text(text: String) -> void:
	_clear_hint_row()
	var label := Label.new()
	label.text = text
	label.theme_type_variation = GameUISkinScript.VAR_HINT_TEXT
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.add_child(label)


func _append_hint_separator() -> void:
	var sep := Label.new()
	sep.text = " | "
	sep.theme_type_variation = GameUISkinScript.VAR_HINT_TEXT
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hint_row.add_child(sep)


## The footer hint row has to fit six entries (navigate, pick/equip, close, sort, type, rarity) in
## a fixed-width strip that is deliberately never allowed to resize the panel around it (see the
## comment on `hint_clip` above) -- a full item-cell-sized glyph next to a few words of hint text
## was spending width the row does not have to spare on an icon far bigger than the text next to it
## needs to be legible.
const FOOTER_HINT_ICON_SIZE := 12


func _append_action_hint(action: String, caption: String) -> void:
	_hint_row.add_child(
		GameUISkinScript.make_symbol_icon_caption_row(
			InputGlyphServiceScript.get_action_glyph_texture(action),
			caption,
			FOOTER_HINT_ICON_SIZE
		)
	)


func _append_navigate_hint() -> void:
	var size_px := FOOTER_HINT_ICON_SIZE
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.add_theme_constant_override("separation", 2)
	row.add_child(
		GameUISkinScript.make_symbol_rect(
			InputGlyphServiceScript.get_action_glyph_texture("ui_left"), size_px
		)
	)
	var slash := Label.new()
	slash.text = "/"
	slash.theme_type_variation = GameUISkinScript.VAR_HINT_TEXT
	slash.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(slash)
	row.add_child(
		GameUISkinScript.make_symbol_rect(
			InputGlyphServiceScript.get_action_glyph_texture("ui_up"), size_px
		)
	)
	var caption := Label.new()
	caption.text = "navigate"
	caption.theme_type_variation = GameUISkinScript.VAR_HINT_TEXT
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(caption)
	_hint_row.add_child(row)


func _rebuild_footer_hints() -> void:
	if _hint_row == null:
		return
	_clear_hint_row()
	_append_navigate_hint()
	_append_hint_separator()
	_append_action_hint("ui_accept", "pick/equip")
	_append_hint_separator()
	_append_action_hint("ui_cancel", "close")
	_append_hint_separator()
	_append_action_hint("sprint", "sort")
	_append_hint_separator()
	_append_action_hint("lock_on", "type")
	_append_hint_separator()
	_append_action_hint("interact", "rarity")


func _on_symbols_invalidated(reason: StringName) -> void:
	if reason in [&"device", &"rebind", &"preset"]:
		var compare_index := -1
		if _hover_grid_index >= 0:
			compare_index = _index_at_grid_cell(_hover_grid_index)
		elif _selected_index >= 0:
			compare_index = _selected_index
		if compare_index < 0 and _focus_area != FocusArea.EQUIPMENT and _hover_equip_slot == "":
			_rebuild_footer_hints()


func _footer_hint_default() -> void:
	_rebuild_footer_hints()


func _index_at_grid_cell(cell_index: int) -> int:
	var inv := _inventory()
	var gx := cell_index % inv.grid_width
	var gy := int(cell_index / float(inv.grid_width))
	return inv.find_slot_at(gx, gy)


func _is_equipped_instance(slot: Dictionary) -> bool:
	var inv := _inventory()
	var instance_id: String = slot.get("instanceId", "")
	if instance_id == "":
		return false
	for slot_name in Equipment.SLOT_ORDER:
		var eq: Dictionary = inv.equipped.get(slot_name, {})
		if eq.get("instanceId", "") == instance_id:
			return true
	return false


func _item_def(item_id: String) -> Dictionary:
	return ItemCatalog.get_definition(item_id)


func _slot_label(slot_name: String) -> String:
	return str(SLOT_LABELS.get(slot_name, slot_name))


func _build_tooltip_header(slot: Dictionary) -> String:
	return _inventory().get_slot_display_name(slot)


func _refresh_quick_slot_row() -> void:
	if _quick_slot_row == null:
		return
	for child in _quick_slot_row.get_children():
		child.queue_free()
	if _waves_mode:
		return
	for i in 4:
		var label := Label.new()
		GameUISkinScript.style_hint_label(label)
		label.text = "[%d] %s" % [i + 1, InventoryService.get_quick_slot_label(i)]
		_quick_slot_row.add_child(label)


func _reserve_action_row_width() -> void:
	if _action_row == null:
		return
	var separation := float(_action_row.get_theme_constant("separation"))
	var grid_side := 0.0
	var grid_count := 0
	for child in _action_row.get_children():
		var ctl := child as Control
		if ctl == null or ctl == _btn_unequip:
			continue
		grid_side += ctl.get_combined_minimum_size().x
		grid_count += 1
	if grid_count > 1:
		grid_side += separation * float(grid_count - 1)
	var row_height := 0.0
	for child in _action_row.get_children():
		var ctl := child as Control
		if ctl != null:
			row_height = maxf(row_height, ctl.get_combined_minimum_size().y)
	_action_row.custom_minimum_size.y = row_height
	var equip_side := _btn_unequip.get_combined_minimum_size().x if _btn_unequip != null else 0.0
	_action_row.custom_minimum_size.x = maxf(grid_side, equip_side)


func _pin_action_button_widths() -> void:
	for pinned in [
		{"button": _btn_drop, "keys": ["INV_BTN_DROP"]},
		{"button": _btn_equip, "keys": ["INV_BTN_EQUIP"]},
		{"button": _btn_unequip, "keys": ["INV_BTN_UNEQUIP"]},
		{"button": _btn_use, "keys": ["INV_BTN_USE"]},
		{"button": _btn_salvage, "keys": ["SMITH_SALVAGE"]},
	]:
		var button := pinned["button"] as Button
		if button == null:
			continue
		var was := button.text
		var widest := 0.0
		for key in pinned["keys"]:
			button.text = tr(str(key))
			widest = maxf(widest, button.get_combined_minimum_size().x)
		button.text = was
		button.custom_minimum_size.x = maxf(button.custom_minimum_size.x, widest)


func _update_action_buttons() -> void:
	if _btn_equip == null:
		return
	var inv := _inventory()
	var can_equip := false
	var can_use := false
	var can_unequip := false
	var can_salvage := false
	var bind_index := -1
	if _focus_area == FocusArea.EQUIPMENT or _hover_equip_slot != "":
		var slot_name := (
			_hover_equip_slot if _hover_equip_slot != "" else _equip_nav_slots[_equip_cursor]
		)
		can_unequip = not inv.equipped.get(slot_name, {}).is_empty()
	elif _selected_index >= 0:
		bind_index = _selected_index
		var slot: Dictionary = inv.slots[_selected_index]
		var def := _item_def(slot.get("itemId", ""))
		var item_type: String = def.get("itemType", "")
		can_equip = item_type in ["weapon", "armor", "accessory"]
		can_salvage = item_type in BlacksmithServiceScript.UPGRADEABLE_TYPES
		if item_type == "consumable":
			var in_run := RunFlow != null and RunFlow.is_run_active()
			can_use = bool(
				ConsumableServiceScript.can_use(def, in_run, not in_run).get("ok", false)
			)
	var can_drop := _selected_index >= 0 and _focus_area == FocusArea.GRID
	_btn_equip.visible = can_equip
	_btn_use.visible = can_use and not _waves_mode
	_btn_unequip.visible = can_unequip
	_btn_drop.visible = can_drop and not _waves_mode
	if _btn_drop.visible:
		_btn_drop.text = tr("INV_BTN_DROP")
	_btn_salvage.visible = can_salvage and _focus_area == FocusArea.GRID
	_bind_target_index = bind_index


func _on_action_equip_pressed() -> void:
	if _selected_index < 0:
		return
	if _inventory().equip_from_index(_selected_index):
		_apply_equipment()
		_refresh_all()


func _on_action_unequip_pressed() -> void:
	var slot_name := (
		_hover_equip_slot if _hover_equip_slot != "" else _equip_nav_slots[_equip_cursor]
	)
	_unequip_slot(slot_name)


func _on_action_use_pressed() -> void:
	if _selected_index < 0:
		return
	_use_selected_consumable()


func _on_action_drop_pressed() -> void:
	if _selected_index < 0:
		return
	if InventoryService.drop_slot_at_index(_selected_index):
		_selected_index = -1
		_refresh_all()


## IV-05: salvage is reachable mid-run, not only at the hub blacksmith -- away from the hub it
## yields at ForgeService.AWAY_FROM_HUB_YIELD_MULT so a full bag on a deep floor is a real
## trade-off (destroy for a partial refund) rather than a wall.
func _on_action_salvage_pressed() -> void:
	if _selected_index < 0:
		return
	var inv_index := _selected_index
	var slot: Dictionary = _inventory().slots[inv_index]
	var away_from_hub := RunFlow != null and RunFlow.is_run_active()
	var preview := ForgeServiceScript.salvage_preview(slot, away_from_hub)
	var item_name := str(_item_def(slot.get("itemId", "")).get("name", slot.get("itemId", "")))
	var parts: PackedStringArray = []
	for material_id in preview:
		parts.append("%s x%d" % [str(material_id), int(preview[material_id])])
	var yield_text := ", ".join(parts) if parts.size() > 0 else tr("SMITH_SALVAGED")
	MenuShellScript.show_confirmation(
		self,
		tr("SMITH_SALVAGE_CONFIRM_TITLE"),
		tr("SMITH_SALVAGE_CONFIRM_MESSAGE") % [item_name, yield_text],
		_do_salvage.bind(inv_index, away_from_hub),
		Callable(),
		tr("SMITH_SALVAGE"),
		tr("UI_CANCEL")
	)


func _do_salvage(inv_index: int, away_from_hub: bool) -> void:
	var result := ForgeServiceScript.salvage(inv_index, away_from_hub)
	if result.get("ok", false):
		_selected_index = -1
		_refresh_all()


func _try_quick_slot_bind_input(event: InputEvent) -> bool:
	if _waves_mode or _selected_index < 0:
		return false
	for i in 4:
		if event.is_action_pressed("quick_slot_%d" % (i + 1)):
			var slot: Dictionary = _inventory().slots[_selected_index]
			InventoryService.set_quick_slot(i, str(slot.get("instanceId", "")))
			_refresh_quick_slot_row()
			return true
	return false
