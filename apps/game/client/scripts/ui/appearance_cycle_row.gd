class_name AppearanceCycleRow
extends Button

## Focusable appearance row that cycles values with ui_left / ui_right (no popup).

signal value_changed(index: int)

var _options: PackedStringArray = PackedStringArray()
var _index := 0
var _row_label: Label
var _value_label: Label


func setup(row_label: String, options: PackedStringArray, start_index: int = 0) -> void:
	focus_mode = Control.FOCUS_ALL
	toggle_mode = false
	flat = true
	_options = options
	_index = clampi(start_index, 0, maxi(options.size() - 1, 0))
	custom_minimum_size.y = 32
	var row := HBoxContainer.new()
	row.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 10)
	add_child(row)
	_row_label = Label.new()
	_row_label.text = row_label
	_row_label.custom_minimum_size.x = 88
	_row_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkin.style_body_label(_row_label)
	row.add_child(_row_label)
	_value_label = Label.new()
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	_value_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	GameUISkin.style_body_label(_value_label)
	row.add_child(_value_label)
	_refresh_value_label()
	pressed.connect(_cycle_forward)


func get_selected_index() -> int:
	return _index


func current_label() -> String:
	if _options.is_empty():
		return "?"
	return _options[_index]


func select_index(index: int) -> void:
	_index = clampi(index, 0, maxi(_options.size() - 1, 0))
	_refresh_value_label()


func _refresh_value_label() -> void:
	if _value_label == null:
		return
	if _options.is_empty():
		_value_label.text = "?"
		return
	_value_label.text = _options[_index]


func _cycle_forward() -> void:
	if _options.is_empty():
		return
	_index = (_index + 1) % _options.size()
	_refresh_value_label()
	value_changed.emit(_index)


func _cycle_backward() -> void:
	if _options.is_empty():
		return
	_index = (_index - 1 + _options.size()) % _options.size()
	_refresh_value_label()
	value_changed.emit(_index)


func _gui_input(event: InputEvent) -> void:
	if not has_focus():
		return
	if event.is_action_pressed("ui_right"):
		_cycle_forward()
		accept_event()
	elif event.is_action_pressed("ui_left"):
		_cycle_backward()
		accept_event()
