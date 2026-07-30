extends Control

## Grid inventory UX — drag-drop, sort, filter, compare; controller-first (INV-4.1).

const CELL_SIZE := 44
const EQUIP_CELL_SIZE := 40

enum FocusArea { GRID, EQUIPMENT, FILTER }

var _grid: GridContainer
var _detail_label: Label
var _compare_label: Label
var _hint_label: Label
var _filter_label: Label
var _equip_grid: GridContainer
var _title_label: Label

var _inventory_open := false
var _cursor := Vector2i(0, 0)
var _equip_cursor := 0
var _focus_area := FocusArea.GRID
var _selected_index := -1
var _cells: Array[PanelContainer] = []
var _equip_cells: Array[PanelContainer] = []
var _equip_slots: Array[String] = []
var _visible_indices: Array[int] = []
var _drag_index := -1
var _sort_mode_idx := 0
var _type_filter_idx := 0
var _rarity_filter_idx := 0


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_ui_shell()
	_build_equipment_panel()
	_build_grid()
	InventoryService.inventory_changed.connect(_refresh_all)
	_refresh_all()


func _build_ui_shell() -> void:
	for child in get_children():
		child.queue_free()
	var panel := PanelContainer.new()
	panel.name = "Panel"
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -360
	panel.offset_top = -220
	panel.offset_right = 360
	panel.offset_bottom = 220
	add_child(panel)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)
	var root_hbox := HBoxContainer.new()
	root_hbox.add_theme_constant_override("separation", 16)
	margin.add_child(root_hbox)
	var equip_vbox := VBoxContainer.new()
	equip_vbox.name = "EquipVBox"
	root_hbox.add_child(equip_vbox)
	var equip_title := Label.new()
	equip_title.text = "Equipment"
	equip_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	equip_vbox.add_child(equip_title)
	_equip_grid = GridContainer.new()
	_equip_grid.name = "EquipGrid"
	_equip_grid.columns = 3
	equip_vbox.add_child(_equip_grid)
	var grid_vbox := VBoxContainer.new()
	grid_vbox.name = "GridVBox"
	root_hbox.add_child(grid_vbox)
	_title_label = Label.new()
	_title_label.name = "Title"
	_title_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	grid_vbox.add_child(_title_label)
	_filter_label = Label.new()
	_filter_label.name = "FilterLabel"
	grid_vbox.add_child(_filter_label)
	_grid = GridContainer.new()
	_grid.name = "GridContainer"
	grid_vbox.add_child(_grid)
	_detail_label = Label.new()
	_detail_label.name = "DetailLabel"
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_detail_label.custom_minimum_size = Vector2(360, 48)
	grid_vbox.add_child(_detail_label)
	_compare_label = Label.new()
	_compare_label.name = "CompareLabel"
	_compare_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid_vbox.add_child(_compare_label)
	_hint_label = Label.new()
	_hint_label.name = "HintLabel"
	grid_vbox.add_child(_hint_label)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _inventory_open:
		return
	if event.is_action_pressed("ui_cancel"):
		if _drag_index >= 0:
			_drag_index = -1
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


func toggle() -> void:
	if _inventory_open:
		hide_inventory()
	else:
		show_inventory()


func show_inventory() -> void:
	_inventory_open = true
	visible = true
	_focus_area = FocusArea.GRID
	_cursor = Vector2i(0, 0)
	_drag_index = -1
	_rebuild_visible_indices()
	_refresh_all()


func hide_inventory() -> void:
	_inventory_open = false
	visible = false
	_drag_index = -1
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_equipment_panel() -> void:
	_equip_slots = Equipment.SLOT_ORDER.duplicate()
	for slot_name in _equip_slots:
		var cell := _make_cell(EQUIP_CELL_SIZE)
		var label: Label = cell.get_child(0) as Label
		label.text = slot_name.substr(0, 3).to_upper()
		_equip_grid.add_child(cell)
		_equip_cells.append(cell)


func _build_grid() -> void:
	var inv := InventoryService.inventory
	_grid.columns = inv.grid_width
	for y in inv.grid_height:
		for x in inv.grid_width:
			var cell := _make_cell(CELL_SIZE)
			cell.gui_input.connect(_on_cell_gui_input.bind(x, y))
			_grid.add_child(cell)
			_cells.append(cell)


func _make_cell(size: int) -> PanelContainer:
	var cell := PanelContainer.new()
	cell.custom_minimum_size = Vector2(size, size)
	var label := Label.new()
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	cell.add_child(label)
	return cell


func _refresh_all() -> void:
	_rebuild_visible_indices()
	_refresh_grid()
	_refresh_equipment()
	_update_filter_label()
	_update_detail()


func _rebuild_visible_indices() -> void:
	_visible_indices.clear()
	var type_filter := GridInventory.FILTER_TYPES[_type_filter_idx]
	var rarity_filter := GridInventory.FILTER_RARITIES[_rarity_filter_idx]
	var inv := InventoryService.inventory
	for filtered in inv.filter_slots(type_filter, rarity_filter):
		_visible_indices.append(int(filtered.get("_index", -1)))


func _refresh_grid() -> void:
	var inv := InventoryService.inventory
	for cell in _cells:
		var label: Label = cell.get_child(0) as Label
		label.text = ""
		cell.modulate = Color(0.3, 0.3, 0.35, 0.9)
		cell.self_modulate = Color.WHITE
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var x: int = slot.get("x", 0)
		var y: int = slot.get("y", 0)
		var idx := y * inv.grid_width + x
		if idx < 0 or idx >= _cells.size():
			continue
		var label: Label = _cells[idx].get_child(0) as Label
		label.text = inv.get_slot_display_name(slot).substr(0, 4)
		if _is_equipped_instance(slot):
			_cells[idx].modulate = Color(0.5, 0.7, 1.0, 1.0)
		elif i == _drag_index:
			_cells[idx].modulate = Color(0.9, 0.8, 0.3, 1.0)
		else:
			_cells[idx].modulate = Color(0.45, 0.55, 0.4, 1.0)
	_highlight_cursor()


func _refresh_equipment() -> void:
	var inv := InventoryService.inventory
	for i in _equip_slots.size():
		var slot_name := _equip_slots[i]
		var cell := _equip_cells[i]
		var label: Label = cell.get_child(0) as Label
		var inst: Dictionary = inv.equipped.get(slot_name, {})
		if inst.is_empty():
			label.text = slot_name.substr(0, 3).to_upper()
			cell.modulate = Color(0.25, 0.25, 0.3, 0.9)
		else:
			label.text = inv.get_slot_display_name(inst).substr(0, 4)
			cell.modulate = Color(0.5, 0.65, 0.85, 1.0)
		cell.self_modulate = Color(1.15, 1.15, 1.0) if _focus_area == FocusArea.EQUIPMENT and i == _equip_cursor else Color.WHITE


func _highlight_cursor() -> void:
	var inv := InventoryService.inventory
	var idx := _cursor.y * inv.grid_width + _cursor.x
	for i in _cells.size():
		var highlight := _focus_area == FocusArea.GRID and i == idx
		_cells[i].self_modulate = Color(1.2, 1.2, 1.0) if highlight else Color.WHITE
	_selected_index = inv.find_slot_at(_cursor.x, _cursor.y)


func _update_filter_label() -> void:
	var sort_mode := GridInventory.SORT_MODES[_sort_mode_idx]
	var type_f := GridInventory.FILTER_TYPES[_type_filter_idx]
	var rarity_f := GridInventory.FILTER_RARITIES[_rarity_filter_idx]
	_filter_label.text = "Sort:%s | Type:%s | Rarity:%s" % [sort_mode, type_f, rarity_f]
	_title_label.text = "Inventory (Tab)"


func _update_detail() -> void:
	var inv := InventoryService.inventory
	if _focus_area == FocusArea.EQUIPMENT:
		var slot_name := _equip_slots[_equip_cursor]
		var inst: Dictionary = inv.equipped.get(slot_name, {})
		if inst.is_empty():
			_detail_label.text = "%s slot empty" % slot_name.capitalize()
			_compare_label.text = ""
			_hint_label.text = "Enter: unequip"
		else:
			_detail_label.text = InventoryService.format_slot_tooltip(inst)
			_compare_label.text = ""
			_hint_label.text = "Enter: unequip"
		return
	if _selected_index < 0:
		_detail_label.text = "Empty"
		_compare_label.text = ""
		_hint_label.text = "D-pad move | Enter pick/place | Sprint sort | LockOn type | E rarity"
		return
	var slot: Dictionary = inv.slots[_selected_index]
	var def := InventoryService.get_item_def(slot.get("itemId", ""))
	var delta := InventoryService.compare_slot_to_equipped(_selected_index)
	_detail_label.text = InventoryService.format_slot_tooltip(slot, delta)
	var compare_lines: PackedStringArray = []
	for stat in Equipment.STAT_KEYS:
		if delta.has(stat) and not is_zero_approx(delta[stat]):
			compare_lines.append("vs equipped: %s" % Equipment.format_delta_line(stat, delta[stat]))
	_compare_label.text = "\n".join(compare_lines)
	match def.get("itemType", ""):
		"weapon", "armor", "accessory":
			_hint_label.text = "Enter: equip or pick up to move"
		"consumable":
			_hint_label.text = "Enter: use"
		_:
			_hint_label.text = "Enter: pick up / place"


func _navigate(delta: Vector2i) -> void:
	if _focus_area == FocusArea.EQUIPMENT:
		var col := _equip_cursor % 3
		var row := _equip_cursor / 3
		col = clampi(col + delta.x, 0, 2)
		row = clampi(row + delta.y, 0, 2)
		_equip_cursor = row * 3 + col
		if delta.x > 0 and col == 2:
			_focus_area = FocusArea.GRID
	else:
		var inv := InventoryService.inventory
		_cursor.x = clampi(_cursor.x + delta.x, 0, inv.grid_width - 1)
		_cursor.y = clampi(_cursor.y + delta.y, 0, inv.grid_height - 1)
		if delta.x < 0 and _cursor.x == 0:
			_focus_area = FocusArea.EQUIPMENT
			_equip_cursor = 2
	_highlight_cursor()
	_refresh_equipment()
	_update_detail()


func _confirm_action() -> void:
	if _focus_area == FocusArea.EQUIPMENT:
		var slot_name := _equip_slots[_equip_cursor]
		InventoryService.inventory.unequip(slot_name)
		InventoryService.apply_equipment_to_player_node(get_tree().get_first_node_in_group("player"))
		_refresh_all()
		return
	if _drag_index >= 0:
		var inv := InventoryService.inventory
		if inv.move_slot(_drag_index, _cursor.x, _cursor.y):
			_drag_index = -1
			_refresh_all()
		return
	if _selected_index < 0:
		return
	var inv := InventoryService.inventory
	var slot: Dictionary = inv.slots[_selected_index]
	var def := InventoryService.get_item_def(slot.get("itemId", ""))
	var item_type: String = def.get("itemType", "")
	if item_type in ["weapon", "armor", "accessory"]:
		if inv.equip_from_index(_selected_index):
			InventoryService.apply_equipment_to_player_node(get_tree().get_first_node_in_group("player"))
			_refresh_all()
		return
	if item_type == "consumable":
		_use_selected_consumable()
		return
	_drag_index = _selected_index
	_refresh_all()


func _use_selected_consumable() -> void:
	var player := get_tree().get_first_node_in_group("player")
	if player == null:
		return
	var health := player.get_node_or_null("Health") as Health
	if health == null or health.is_dead():
		return
	var def := InventoryService.inventory.consume_at(_selected_index)
	if def.is_empty():
		return
	health.heal(def.get("healAmount", 30.0))
	_refresh_all()


func _cycle_sort() -> void:
	_sort_mode_idx = (_sort_mode_idx + 1) % GridInventory.SORT_MODES.size()
	InventoryService.inventory.sort_slots(GridInventory.SORT_MODES[_sort_mode_idx])
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
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_cursor = Vector2i(x, y)
		_focus_area = FocusArea.GRID
		_confirm_action()


func _is_equipped_instance(slot: Dictionary) -> bool:
	var inv := InventoryService.inventory
	var instance_id: String = slot.get("instanceId", "")
	if instance_id == "":
		return false
	for slot_name in Equipment.SLOT_ORDER:
		var eq: Dictionary = inv.equipped.get(slot_name, {})
		if eq.get("instanceId", "") == instance_id:
			return true
	return false
