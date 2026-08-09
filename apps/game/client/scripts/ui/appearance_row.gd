extends HBoxContainer
class_name AppearanceRow

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

## Focusable appearance row — cycles values with ui_left / ui_right (no popup).

signal value_changed(index: int)

var _options: PackedStringArray = PackedStringArray()
var _index := 0
var _value_label: Label


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	add_theme_constant_override("separation", 10)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL


func setup(row_label: String, options: PackedStringArray, initial_index: int = 0) -> void:
	_options = options
	var label := Label.new()
	label.text = row_label
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(label)
	add_child(label)
	_value_label = Label.new()
	_value_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	GameUISkinScript.style_stat_value(_value_label)
	add_child(_value_label)
	select(initial_index)


func select(index: int) -> void:
	if _options.is_empty():
		return
	_index = clampi(index, 0, _options.size() - 1)
	if _value_label:
		_value_label.text = _options[_index]


func get_selected_index() -> int:
	return _index


func get_option_count() -> int:
	return _options.size()


func _gui_input(event: InputEvent) -> void:
	if not has_focus():
		return
	if event.is_action_pressed("ui_right"):
		select((_index + 1) % _options.size())
		value_changed.emit(_index)
		accept_event()
	elif event.is_action_pressed("ui_left"):
		select((_index - 1 + _options.size()) % _options.size())
		value_changed.emit(_index)
		accept_event()
