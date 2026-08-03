extends Control

## Umbral Waves loadout — equip from isolated waves inventory (M7 WAVES-7.x).

const CELL_SIZE := 44
const EQUIP_CELL_SIZE := 40

var _grid: GridContainer
var _detail_label: Label
var _equip_grid: GridContainer
var _equip_slots: Array[String] = []
var _open := false
var _cursor := Vector2i(0, 0)
var _equip_cursor := 0
var _focus_equipment := false


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_shell()
	WavesRunService.inventory_changed.connect(_refresh)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
		return
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		close()
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
	elif event.is_action_pressed("ui_accept"):
		_confirm()
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _open:
		close()
	else:
		open()


func open() -> void:
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_refresh()


func close() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func is_open() -> bool:
	return _open


func _build_shell() -> void:
	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_CENTER)
	panel.offset_left = -320
	panel.offset_top = -200
	panel.offset_right = 320
	panel.offset_bottom = 200
	add_child(panel)
	var margin := MarginContainer.new()
	panel.add_child(margin)
	var hbox := HBoxContainer.new()
	margin.add_child(hbox)
	var equip_vbox := VBoxContainer.new()
	hbox.add_child(equip_vbox)
	var equip_title := Label.new()
	equip_title.text = "Waves equipment"
	equip_vbox.add_child(equip_title)
	_equip_grid = GridContainer.new()
	_equip_grid.columns = 3
	equip_vbox.add_child(_equip_grid)
	var grid_vbox := VBoxContainer.new()
	hbox.add_child(grid_vbox)
	var title := Label.new()
	title.text = "Waves stash (Tab)"
	grid_vbox.add_child(title)
	_grid = GridContainer.new()
	grid_vbox.add_child(_grid)
	_detail_label = Label.new()
	_detail_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	grid_vbox.add_child(_detail_label)
	_equip_slots = Equipment.SLOT_ORDER.duplicate()


func _refresh() -> void:
	if not _open:
		return
	var inv := WavesRunService.waves_inventory
	_grid.columns = inv.grid_width
	for child in _grid.get_children():
		child.queue_free()
	for y in inv.grid_height:
		for x in inv.grid_width:
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			var label := Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			var idx := inv.find_slot_at(x, y)
			if idx >= 0:
				label.text = inv.get_slot_display_name(inv.slots[idx]).substr(0, 4)
			cell.add_child(label)
			_grid.add_child(cell)
	for child in _equip_grid.get_children():
		child.queue_free()
	for i in _equip_slots.size():
		var slot_name := _equip_slots[i]
		var cell := PanelContainer.new()
		cell.custom_minimum_size = Vector2(EQUIP_CELL_SIZE, EQUIP_CELL_SIZE)
		var label := Label.new()
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		var inst: Dictionary = inv.equipped.get(slot_name, {})
		if inst.is_empty():
			label.text = slot_name.substr(0, 3).to_upper()
		else:
			label.text = inv.get_slot_display_name(inst).substr(0, 4)
		cell.add_child(label)
		_equip_grid.add_child(cell)
	_update_detail()


func _navigate(delta: Vector2i) -> void:
	var inv := WavesRunService.waves_inventory
	if _focus_equipment:
		var col := _equip_cursor % 3
		var row := int(_equip_cursor / 3.0)
		col = clampi(col + delta.x, 0, 2)
		row = clampi(row + delta.y, 0, 2)
		_equip_cursor = row * 3 + col
		if delta.x > 0 and col == 2:
			_focus_equipment = false
	else:
		_cursor.x = clampi(_cursor.x + delta.x, 0, inv.grid_width - 1)
		_cursor.y = clampi(_cursor.y + delta.y, 0, inv.grid_height - 1)
		if delta.x < 0 and _cursor.x == 0:
			_focus_equipment = true
			_equip_cursor = 2
	_refresh()


func _confirm() -> void:
	var inv := WavesRunService.waves_inventory
	var player := get_tree().get_first_node_in_group("player")
	if _focus_equipment:
		var slot_name := _equip_slots[_equip_cursor]
		inv.unequip(slot_name)
	else:
		var idx := inv.find_slot_at(_cursor.x, _cursor.y)
		if idx < 0:
			return
		var slot: Dictionary = inv.slots[idx]
		var def := ItemCatalog.get_definition(slot.get("itemId", ""))
		var item_type: String = def.get("itemType", "")
		if item_type in ["weapon", "armor", "accessory"]:
			inv.equip_from_index(idx)
	if player:
		WavesRunService.apply_equipment_to_player(player)
	_refresh()


func _update_detail() -> void:
	var inv := WavesRunService.waves_inventory
	if _focus_equipment:
		var slot_name := _equip_slots[_equip_cursor]
		var inst: Dictionary = inv.equipped.get(slot_name, {})
		if inst.is_empty():
			_detail_label.text = "%s: empty — Enter to unequip" % slot_name
		else:
			_detail_label.text = inv.get_slot_display_name(inst)
		return
	var idx := inv.find_slot_at(_cursor.x, _cursor.y)
	if idx < 0:
		_detail_label.text = "Empty slot"
		return
	var slot: Dictionary = inv.slots[idx]
	_detail_label.text = inv.get_slot_display_name(slot) + " — Enter to equip"
