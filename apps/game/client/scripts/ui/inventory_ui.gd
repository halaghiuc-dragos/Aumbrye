extends Control

## Grid inventory UI — keyboard + gamepad cursor navigation (INV-2.1).

const CELL_SIZE := 48
const GRID_PADDING := 16

@onready var _grid: GridContainer = $Panel/Margin/VBox/GridContainer
@onready var _detail_label: Label = $Panel/Margin/VBox/DetailLabel
@onready var _hint_label: Label = $Panel/Margin/VBox/HintLabel

var _inventory_open := false
var _cursor := Vector2i(0, 0)
var _selected_index := -1
var _cells: Array[PanelContainer] = []


func _ready() -> void:
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	InventoryService.inventory_changed.connect(_refresh_grid)
	_build_grid()
	_refresh_grid()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("inventory"):
		toggle()
		get_viewport().set_input_as_handled()
	if not _inventory_open:
		return
	if event.is_action_pressed("ui_cancel"):
		hide_inventory()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_accept"):
		_confirm_cell()
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_left"):
		_move_cursor(Vector2i(-1, 0))
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_right"):
		_move_cursor(Vector2i(1, 0))
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_up"):
		_move_cursor(Vector2i(0, -1))
		get_viewport().set_input_as_handled()
	if event.is_action_pressed("ui_down"):
		_move_cursor(Vector2i(0, 1))
		get_viewport().set_input_as_handled()


func toggle() -> void:
	if _inventory_open:
		hide_inventory()
	else:
		show_inventory()


func show_inventory() -> void:
	_inventory_open = true
	visible = true
	_cursor = Vector2i(0, 0)
	_refresh_grid()
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE


func hide_inventory() -> void:
	_inventory_open = false
	visible = false
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED


func _build_grid() -> void:
	var inv := InventoryService.inventory
	_grid.columns = inv.grid_width
	for y in inv.grid_height:
		for x in inv.grid_width:
			var cell := PanelContainer.new()
			cell.custom_minimum_size = Vector2(CELL_SIZE, CELL_SIZE)
			var label := Label.new()
			label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
			label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
			cell.add_child(label)
			_grid.add_child(cell)
			_cells.append(cell)


func _refresh_grid() -> void:
	var inv := InventoryService.inventory
	for cell in _cells:
		var label: Label = cell.get_child(0) as Label
		label.text = ""
		cell.modulate = Color(0.3, 0.3, 0.35, 0.9)
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		var def := InventoryService.get_item_def(slot.get("itemId", ""))
		var x: int = slot.get("x", 0)
		var y: int = slot.get("y", 0)
		var idx := y * inv.grid_width + x
		if idx >= 0 and idx < _cells.size():
			var label: Label = _cells[idx].get_child(0) as Label
			label.text = def.get("name", "?").substr(0, 3)
			if inv.get_equipped_weapon_id() == slot.get("itemId", ""):
				_cells[idx].modulate = Color(0.5, 0.7, 1.0, 1.0)
			else:
				_cells[idx].modulate = Color(0.45, 0.55, 0.4, 1.0)
	_highlight_cursor()


func _highlight_cursor() -> void:
	var inv := InventoryService.inventory
	var idx := _cursor.y * inv.grid_width + _cursor.x
	for i in _cells.size():
		if i == idx:
			_cells[i].self_modulate = Color(1.2, 1.2, 1.0)
		else:
			_cells[i].self_modulate = Color.WHITE
	_selected_index = _find_slot_at(_cursor.x, _cursor.y)
	if _selected_index >= 0:
		var slot: Dictionary = inv.slots[_selected_index]
		var def := InventoryService.get_item_def(slot.get("itemId", ""))
		_detail_label.text = "%s x%d" % [def.get("name", "?"), slot.get("quantity", 1)]
		match def.get("itemType", ""):
			"weapon":
				_hint_label.text = "Enter: equip weapon"
			"consumable":
				_hint_label.text = "Enter: use item"
			_:
				_hint_label.text = ""
	else:
		_detail_label.text = "Empty"
		_hint_label.text = ""


func _move_cursor(delta: Vector2i) -> void:
	var inv := InventoryService.inventory
	_cursor.x = clampi(_cursor.x + delta.x, 0, inv.grid_width - 1)
	_cursor.y = clampi(_cursor.y + delta.y, 0, inv.grid_height - 1)
	_highlight_cursor()


func _find_slot_at(x: int, y: int) -> int:
	var inv := InventoryService.inventory
	for i in inv.slots.size():
		var slot: Dictionary = inv.slots[i]
		if slot.get("x", -1) == x and slot.get("y", -1) == y:
			return i
	return -1


func _confirm_cell() -> void:
	if _selected_index < 0:
		return
	var inv := InventoryService.inventory
	var slot: Dictionary = inv.slots[_selected_index]
	var def := InventoryService.get_item_def(slot.get("itemId", ""))
	match def.get("itemType", ""):
		"weapon":
			_equip_selected_weapon()
		"consumable":
			_use_selected_consumable()


func _equip_selected_weapon() -> void:
	if InventoryService.inventory.equip_weapon(_selected_index):
		var weapon := get_tree().get_first_node_in_group("player")
		if weapon:
			var wc := weapon.get_node_or_null("WeaponController")
			if wc and wc.has_method("load_weapon_from_path"):
				wc.call("load_weapon_from_path", InventoryService.inventory.get_equipped_weapon_data_path())
		_refresh_grid()


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
	_selected_index = -1
	_refresh_grid()
