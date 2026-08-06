extends Control

## Grid inventory UX — D2-inspired paper doll + stash grid (INV-4.1).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const InventoryUILayoutScript := preload("res://scripts/ui/inventory_ui_layout.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const BlacksmithServiceScript := preload("res://scripts/hub/blacksmith_service.gd")
const InputGlyphServiceScript := preload("res://scripts/ui/input_glyph_service.gd")
const RunModeConfigScript := preload("res://scripts/app/run_mode_config.gd")
const ItemIconAtlasScript := preload("res://scripts/ui/item_icon_atlas.gd")

const CELL_SIZE := InventoryUILayoutScript.CELL_SIZE
const EQUIP_CELL_SIZE := InventoryUILayoutScript.EQUIP_CELL_SIZE
const GRID_GAP := InventoryUILayoutScript.GRID_GAP
const EQUIP_LAYOUT: Array = InventoryUILayoutScript.EQUIP_LAYOUT
const SLOT_LABELS: Dictionary = InventoryUILayoutScript.SLOT_LABELS

enum FocusArea { GRID, EQUIPMENT }

var _backdrop: ColorRect
var _grid: GridContainer
var _detail_label: Label
var _compare_label: Label
var _hint_label: Label
var _filter_label: Label
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
var _cells: Array[PanelContainer] = []
var _equip_cells: Dictionary = {}
var _equip_nav_slots: Array[String] = []
var _visible_indices: Array[int] = []
var _drag_index := -1
var _drag_equip_slot := ""
var _mouse_dragging := false
var _sort_mode_idx := 0
var _type_filter_idx := 0
var _rarity_filter_idx := 0
var _equip_wrap: Control
var _waves_mode := false
var _bound_grid_w := -1
var _bound_grid_h := -1
var _action_row: HBoxContainer
var _quick_slot_row: HBoxContainer
var _btn_equip: Button
var _btn_unequip: Button
var _btn_use: Button
var _btn_bind: Array[Button] = []


func _ready() -> void:
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui_shell()
	_build_equipment_panel()
	_bind_inventory_context()
	InventoryService.inventory_changed.connect(_on_main_inventory_changed)
	get_tree().scene_changed.connect(func() -> void: call_deferred("_bind_inventory_context"))
	if WavesRunService:
		WavesRunService.inventory_changed.connect(_on_waves_inventory_changed)
	_refresh_all()


func _inventory() -> GridInventory:
	if _waves_mode:
		return WavesRunService.waves_inventory
	return InventoryService.inventory


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
			_grid.add_child(cell)
			_cells.append(cell)


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
	var grid_frame := GameUISkinScript.make_section_frame("Stash")
	root_hbox.add_child(grid_frame)
	var grid_vbox := GameUISkinScript.section_content(grid_frame)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_section_title(_title_label, "Stash")
	grid_vbox.add_child(_title_label)
	_filter_label = Label.new()
	_filter_label.name = "FilterLabel"
	GameUISkinScript.style_hint_label(_filter_label)
	grid_vbox.add_child(_filter_label)
	_grid = GridContainer.new()
	_grid.name = "GridContainer"
	_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_grid.add_theme_constant_override("v_separation", GRID_GAP)
	grid_vbox.add_child(_grid)
	var footer := VBoxContainer.new()
	footer.add_theme_constant_override("separation", 6)
	grid_vbox.add_child(footer)
	_detail_label = Label.new()
	_detail_label.name = "DetailLabel"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size = Vector2(560, 88)
	GameUISkinScript.style_body_label(_detail_label)
	footer.add_child(_detail_label)
	_action_row = HBoxContainer.new()
	_action_row.add_theme_constant_override("separation", 8)
	_btn_equip = MenuShellScript.make_menu_button("Equip", _on_action_equip_pressed)
	_btn_unequip = MenuShellScript.make_menu_button("Unequip", _on_action_unequip_pressed)
	_btn_use = MenuShellScript.make_menu_button("Use", _on_action_use_pressed)
	_action_row.add_child(_btn_equip)
	_action_row.add_child(_btn_unequip)
	_action_row.add_child(_btn_use)
	for i in 4:
		var bind_btn := MenuShellScript.make_menu_button(
			"Bind %d" % (i + 1), _on_bind_quick_slot_pressed.bind(i)
		)
		_btn_bind.append(bind_btn)
		_action_row.add_child(bind_btn)
	footer.add_child(_action_row)
	_quick_slot_row = HBoxContainer.new()
	_quick_slot_row.add_theme_constant_override("separation", 10)
	footer.add_child(_quick_slot_row)
	_compare_label = Label.new()
	_compare_label.name = "CompareLabel"
	_compare_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_compare_label.add_theme_color_override("font_color", Color(0.65, 0.9, 0.65))
	footer.add_child(_compare_label)
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	GameUISkinScript.style_hint_label(_hint_label)
	footer.add_child(_hint_label)
	var separator := VSeparator.new()
	separator.custom_minimum_size.x = 4
	root_hbox.add_child(separator)
	var equip_frame := GameUISkinScript.make_section_frame("Character")
	root_hbox.add_child(equip_frame)
	var equip_vbox := GameUISkinScript.section_content(equip_frame)
	_equip_wrap = Control.new()
	_equip_wrap.name = "EquipWrap"
	_equip_wrap.custom_minimum_size = Vector2(
		EQUIP_CELL_SIZE * 3 + GRID_GAP * 2 + 24, EQUIP_CELL_SIZE * 4 + GRID_GAP * 3 + 24
	)
	equip_vbox.add_child(_equip_wrap)
	GameUISkinScript.build_human_silhouette(_equip_wrap, EQUIP_CELL_SIZE, GRID_GAP, 1.12)
	_equip_host = GridContainer.new()
	_equip_host.name = "EquipGrid"
	_equip_host.columns = 3
	_equip_host.add_theme_constant_override("h_separation", GRID_GAP)
	_equip_host.add_theme_constant_override("v_separation", GRID_GAP)
	_equip_wrap.add_child(_equip_host)
	_drag_ghost = _make_item_cell(CELL_SIZE, "common", 0)
	_drag_ghost.visible = false
	_drag_ghost.z_index = 100
	_drag_ghost.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_drag_ghost)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _inventory_open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _drag_index >= 0 or _drag_equip_slot != "":
			_clear_drag()
			_refresh_all()
			get_viewport().set_input_as_handled()
			return
		hide_inventory()
		get_viewport().set_input_as_handled()
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
	if _try_quick_slot_bind_input(event):
		get_viewport().set_input_as_handled()


func _process(_delta: float) -> void:
	if not _inventory_open or not _drag_ghost.visible:
		return
	var half := Vector2(CELL_SIZE, CELL_SIZE) * 0.5
	_drag_ghost.global_position = get_global_mouse_position() - half


func toggle() -> void:
	if _inventory_open:
		hide_inventory()
	else:
		show_inventory()


func show_inventory() -> void:
	_bind_inventory_context()
	_inventory_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_focus_area = FocusArea.GRID
	_cursor = Vector2i(0, 0)
	_clear_drag()
	_rebuild_visible_indices()
	_refresh_all()


func hide_inventory() -> void:
	_inventory_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_clear_drag()
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


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
	return cell


func _make_item_cell(cell_size: int, rarity: String, upgrade_level: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(cell_size, cell_size)
	var style := GameUISkinScript.make_item_cell_style(rarity, false)
	cell.add_theme_stylebox_override("panel", style)
	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	icon.offset_left = 2
	icon.offset_top = 2
	icon.offset_right = -2
	icon.offset_bottom = -2
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	cell.add_child(icon)
	var upgrade_label := Label.new()
	upgrade_label.name = "UpgradeLabel"
	upgrade_label.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	upgrade_label.offset_left = -cell_size + 2
	upgrade_label.offset_top = 0
	upgrade_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	upgrade_label.add_theme_font_size_override("font_size", 10)
	upgrade_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.45))
	upgrade_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	upgrade_label.text = ("+%d" % upgrade_level) if upgrade_level > 0 else ""
	cell.add_child(upgrade_label)
	return cell


func _set_cell_content(
	cell: PanelContainer,
	rarity: String,
	upgrade_level: int,
	slot: Dictionary = {},
	empty_slot_name: String = ""
) -> void:
	var filled := not slot.is_empty()
	var display_rarity := rarity if filled else "common"
	var style := GameUISkinScript.make_item_cell_style(display_rarity, filled)
	cell.add_theme_stylebox_override("panel", style)
	var icon: TextureRect = cell.get_node("Icon")
	var upgrade_label: Label = cell.get_node("UpgradeLabel")
	if filled:
		var item_id: String = str(slot.get("itemId", ""))
		var def := _item_def(item_id)
		icon.texture = ItemIconAtlasScript.get_icon(item_id, str(def.get("iconPath", "")))
	elif empty_slot_name != "":
		icon.texture = ItemIconAtlasScript.get_slot_icon(empty_slot_name)
	else:
		icon.texture = null
	upgrade_label.text = ("+%d" % upgrade_level) if upgrade_level > 0 else ""


func _refresh_all() -> void:
	_rebuild_visible_indices()
	_refresh_grid()
	_refresh_equipment()
	_update_filter_label()
	_update_detail()
	_refresh_quick_slot_row()
	_update_action_buttons()


func _rebuild_visible_indices() -> void:
	_visible_indices.clear()
	var type_filter := GridInventory.FILTER_TYPES[_type_filter_idx]
	var rarity_filter := GridInventory.FILTER_RARITIES[_rarity_filter_idx]
	var inv := _inventory()
	for filtered in inv.filter_slots(type_filter, rarity_filter):
		_visible_indices.append(int(filtered.get("_index", -1)))


func _refresh_grid() -> void:
	var inv := _inventory()
	for cell in _cells:
		_set_cell_content(cell, "common", 0)
		cell.self_modulate = Color.WHITE
	var occupied: Dictionary = {}
	var visible_set: Dictionary = {}
	for idx in _visible_indices:
		visible_set[idx] = true
	for i in inv.slots.size():
		if _visible_indices.size() > 0 and not visible_set.has(i):
			continue
		var slot: Dictionary = inv.slots[i]
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
				var is_origin := dx == 0 and dy == 0
				_set_cell_content(
					_cells[idx], rarity, upgrade if is_origin else 0, slot if is_origin else {}
				)
				if i == _drag_index:
					_cells[idx].self_modulate = Color(1.1, 1.0, 0.55)
				elif _is_equipped_instance(slot):
					_cells[idx].self_modulate = Color(0.75, 0.85, 1.0)
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
		var highlight := _focus_area == FocusArea.GRID and i == idx
		var hovered := _focus_area == FocusArea.GRID and _hover_grid_index == i
		if highlight or hovered:
			_cells[i].self_modulate = _cells[i].self_modulate * Color(1.2, 1.2, 1.05)
	_selected_index = inv.find_slot_at(_cursor.x, _cursor.y)


func _update_filter_label() -> void:
	var sort_mode := GridInventory.SORT_MODES[_sort_mode_idx]
	var type_f := GridInventory.FILTER_TYPES[_type_filter_idx]
	var rarity_f := GridInventory.FILTER_RARITIES[_rarity_filter_idx]
	_filter_label.text = "Sort: %s  |  Type: %s  |  Rarity: %s" % [sort_mode, type_f, rarity_f]
	_title_label.text = "Stash" if not _waves_mode else "Waves Stash"
	GameUISkinScript.style_section_title(_title_label)


func _update_detail() -> void:
	var inv := _inventory()
	var detail_slot: Dictionary = {}
	var compare_index := -1
	if _focus_area == FocusArea.EQUIPMENT or _hover_equip_slot != "":
		var slot_name := (
			_hover_equip_slot if _hover_equip_slot != "" else _equip_nav_slots[_equip_cursor]
		)
		detail_slot = inv.equipped.get(slot_name, {})
		if detail_slot.is_empty():
			_detail_label.text = "%s — empty" % SLOT_LABELS.get(slot_name, slot_name.capitalize())
			_compare_label.text = ""
			_hint_label.text = "Click or Enter to unequip  |  Drag items onto character"
			return
		_detail_label.text = _format_slot_tooltip(detail_slot)
		_compare_label.text = ""
		_hint_label.text = "Click or Enter to unequip"
		return
	if _hover_grid_index >= 0:
		compare_index = _index_at_grid_cell(_hover_grid_index)
	elif _selected_index >= 0:
		compare_index = _selected_index
	if compare_index < 0:
		_detail_label.text = "Select an item to inspect"
		_compare_label.text = ""
		_hint_label.text = _footer_hint_default()
		return
	detail_slot = inv.slots[compare_index]
	var delta := _compare_slot_to_equipped(compare_index)
	var rarity := inv.get_slot_rarity(detail_slot)
	var rarity_name := RarityRegistryScript.display_name(rarity)
	_detail_label.text = (
		"[%s] %s\n%s"
		% [
			rarity_name,
			_item_def(detail_slot.get("itemId", "")).get("name", detail_slot.get("itemId", "?")),
			_format_slot_tooltip(detail_slot, delta),
		]
	)
	var compare_lines: PackedStringArray = []
	for stat in Equipment.STAT_KEYS:
		if delta.has(stat) and not is_zero_approx(delta[stat]):
			compare_lines.append("vs equipped: %s" % Equipment.format_delta_line(stat, delta[stat]))
	_compare_label.text = "\n".join(compare_lines)
	var def := _item_def(detail_slot.get("itemId", ""))
	match def.get("itemType", ""):
		"weapon", "armor", "accessory":
			_hint_label.text = "Click/Enter: equip  |  Drag to character panel"
		"consumable":
			_hint_label.text = "Click/Enter: use consumable"
		_:
			_hint_label.text = "Click/Enter: pick up and move"


func _navigate(delta: Vector2i) -> void:
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
	if inv.move_slot(_drag_index, x, y):
		_clear_drag()
		_refresh_all()


func _drop_equip_on_grid(slot_name: String, x: int, y: int) -> void:
	var inv := _inventory()
	var instance: Dictionary = inv.equipped.get(slot_name, {})
	if instance.is_empty():
		return
	var instance_id: String = instance.get("instanceId", "")
	if not inv.unequip(slot_name):
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
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var health := player.get_node_or_null("Health") as Health
	if health == null or health.is_dead():
		return
	var def := _inventory().consume_at(_selected_index)
	if def.is_empty():
		return
	health.heal(def.get("healAmount", 30.0))
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
			_handle_grid_release(x, y)
			_mouse_dragging = false
		_highlight_cursor()
		_refresh_equipment()
		_update_detail()
	_update_action_buttons()


func _on_equip_gui_input(event: InputEvent, slot_name: String) -> void:
	if not _inventory_open:
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_focus_area = FocusArea.EQUIPMENT
		_equip_cursor = _equip_nav_slots.find(slot_name)
		_handle_equip_press(slot_name)


func _on_cell_mouse_entered(x: int, y: int) -> void:
	if not _inventory_open:
		return
	_hover_grid_index = y * _inventory().grid_width + x
	_hover_equip_slot = ""
	_highlight_cursor()
	_update_detail()
	_update_action_buttons()


func _on_cell_mouse_exited() -> void:
	_hover_grid_index = -1
	_highlight_cursor()
	_update_detail()
	_update_action_buttons()


func _on_equip_mouse_entered(slot_name: String) -> void:
	if not _inventory_open:
		return
	_hover_equip_slot = slot_name
	_refresh_equipment()
	_update_detail()
	_update_action_buttons()


func _on_equip_mouse_exited() -> void:
	_hover_equip_slot = ""
	_refresh_equipment()
	_update_detail()
	_update_action_buttons()


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
	var slot: Dictionary = inv.slots[idx]
	var def := _item_def(slot.get("itemId", ""))
	var item_type: String = def.get("itemType", "")
	if item_type in ["weapon", "armor", "accessory"]:
		if inv.equip_from_index(idx):
			_apply_equipment()
			_refresh_all()
		return
	if item_type == "consumable":
		_selected_index = idx
		_use_selected_consumable()
		return
	_drag_index = idx
	_mouse_dragging = true
	_show_drag_ghost_from_slot(slot)
	_refresh_all()


func _handle_grid_release(x: int, y: int) -> void:
	if _drag_index < 0:
		return
	_drop_on_grid(x, y)


func _handle_equip_press(slot_name: String) -> void:
	if _drag_index >= 0:
		_try_equip_dragged_to_slot(slot_name)
		return
	_unequip_slot(slot_name)


func _show_drag_ghost_from_slot(slot: Dictionary) -> void:
	var inv := _inventory()
	var rarity := inv.get_slot_rarity(slot)
	var upgrade := BlacksmithServiceScript.get_slot_upgrade_level(slot)
	_set_cell_content(_drag_ghost, rarity, upgrade, slot)
	_drag_ghost.visible = true


func _clear_drag() -> void:
	_drag_index = -1
	_drag_equip_slot = ""
	_mouse_dragging = false
	_drag_ghost.visible = false


func _apply_equipment() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	if _waves_mode:
		WavesRunService.apply_equipment_to_player(player)
	else:
		InventoryService.apply_equipment_to_player_node(player)


func _footer_hint_default() -> String:
	return (
		"%s navigate  |  %s pick/equip  |  %s close  |  %s sort  |  %s type  |  %s rarity"
		% [
			(
				InputGlyphServiceScript.get_action_glyph("ui_left")
				+ "/"
				+ InputGlyphServiceScript.get_action_glyph("ui_up")
			),
			InputGlyphServiceScript.get_action_glyph("ui_accept"),
			InputGlyphServiceScript.get_action_glyph("ui_cancel"),
			InputGlyphServiceScript.get_action_glyph("sprint"),
			InputGlyphServiceScript.get_action_glyph("lock_on"),
			InputGlyphServiceScript.get_action_glyph("interact"),
		]
	)


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


func _compare_slot_to_equipped(index: int) -> Dictionary:
	var inv := _inventory()
	if index < 0 or index >= inv.slots.size():
		return {}
	var slot: Dictionary = inv.slots[index]
	var def := _item_def(slot.get("itemId", ""))
	var slot_name := Equipment.slot_for_item_def(def)
	if slot_name == "":
		return {}
	return Equipment.compare_stats(inv.equipped, slot, Callable(AffixRoller, "get_affix_stat"))


func _format_slot_tooltip(slot: Dictionary, compare_delta: Dictionary = {}) -> String:
	var inv := _inventory()
	var lines: PackedStringArray = []
	lines.append(inv.get_slot_display_name(slot))
	var def := _item_def(slot.get("itemId", ""))
	if def.has("description"):
		lines.append(def.get("description", ""))
	var stats := Equipment.stats_for_instance(slot, Callable(AffixRoller, "get_affix_stat"))
	for stat in Equipment.STAT_KEYS:
		var line := Equipment.format_stat_line(stat, stats.get(stat, 0.0))
		if line != "":
			if compare_delta.has(stat) and not is_zero_approx(compare_delta[stat]):
				line += " (%s)" % Equipment.format_delta_line(stat, compare_delta[stat])
			lines.append(line)
	for affix in slot.get("affixes", []):
		if affix is Dictionary:
			lines.append("  %s +%s" % [affix.get("affixId", ""), affix.get("value", 0)])
	return "\n".join(lines)


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


func _update_action_buttons() -> void:
	if _btn_equip == null:
		return
	var inv := _inventory()
	var can_equip := false
	var can_use := false
	var can_unequip := false
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
		can_use = item_type == "consumable"
	_btn_equip.visible = can_equip
	_btn_use.visible = can_use
	_btn_unequip.visible = can_unequip
	for i in _btn_bind.size():
		_btn_bind[i].visible = bind_index >= 0 and not _waves_mode


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


func _on_bind_quick_slot_pressed(quick_index: int) -> void:
	if _selected_index < 0 or _waves_mode:
		return
	InventoryService.set_quick_slot(quick_index, _selected_index)
	_refresh_quick_slot_row()


func _try_quick_slot_bind_input(event: InputEvent) -> bool:
	if _waves_mode or not (event is InputEventKey and event.pressed and not event.echo):
		return false
	if _selected_index < 0:
		return false
	match event.keycode:
		KEY_1:
			InventoryService.set_quick_slot(0, _selected_index)
			_refresh_quick_slot_row()
			return true
		KEY_2:
			InventoryService.set_quick_slot(1, _selected_index)
			_refresh_quick_slot_row()
			return true
		KEY_3:
			InventoryService.set_quick_slot(2, _selected_index)
			_refresh_quick_slot_row()
			return true
		KEY_4:
			InventoryService.set_quick_slot(3, _selected_index)
			_refresh_quick_slot_row()
			return true
	return false
