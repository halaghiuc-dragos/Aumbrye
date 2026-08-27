extends PanelContainer
class_name AppearanceRow

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")


signal value_changed(index: int)

var _options: PackedStringArray = PackedStringArray()
var _index := 0
var _label: Label
var _value_label: Label
var _left_arrow: Button
var _right_arrow: Button


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_build_ui()
	_apply_focus_style(has_focus())
	focus_entered.connect(_apply_focus_style.bind(true))
	focus_exited.connect(_apply_focus_style.bind(false))


func _build_ui() -> void:
	if _label != null:
		return
	add_theme_stylebox_override("panel", GameUISkinScript.make_row_style(false, 4))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	add_child(row)
	_label = Label.new()
	_label.name = "RowLabel"
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	GameUISkinScript.style_body_label(_label)
	_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(_label)
	_left_arrow = _make_chevron("<", -1)
	row.add_child(_left_arrow)
	_value_label = Label.new()
	_value_label.name = "ValueLabel"
	_value_label.custom_minimum_size = Vector2(132, 0)
	_value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_stat_value(_value_label)
	row.add_child(_value_label)
	_right_arrow = _make_chevron(">", 1)
	row.add_child(_right_arrow)


func _make_chevron(glyph: String, direction: int) -> Button:
	var arrow := Button.new()
	arrow.text = glyph
	arrow.flat = true
	arrow.focus_mode = Control.FOCUS_NONE
	arrow.custom_minimum_size = Vector2(26, 0)
	arrow.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	for state in ["normal", "hover", "pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = (
			GameUISkinScript.FRAME_BG.lightened(0.18) if state == "hover" else Color(0, 0, 0, 0)
		)
		box.set_corner_radius_all(3)
		box.set_content_margin_all(2)
		arrow.add_theme_stylebox_override(state, box)
	arrow.pressed.connect(_on_chevron_pressed.bind(direction))
	GameUISkinScript.wire_button_sfx(arrow)
	return arrow


func _on_chevron_pressed(direction: int) -> void:
	grab_focus()
	step(direction)


func step(direction: int) -> void:
	if _options.is_empty():
		return
	select((_index + direction + _options.size()) % _options.size())
	value_changed.emit(_index)


func _apply_focus_style(focused: bool) -> void:
	add_theme_stylebox_override("panel", GameUISkinScript.make_row_style(focused))
	var arrow_color := (
		GameUISkinScript.TITLE_COLOR if focused else GameUISkinScript.HINT_COLOR.darkened(0.3)
	)
	for arrow in [_left_arrow, _right_arrow]:
		if arrow:
			arrow.add_theme_color_override("font_color", arrow_color)
			arrow.add_theme_color_override("font_hover_color", GameUISkinScript.TITLE_COLOR)


func setup(row_label: String, options: PackedStringArray, initial_index: int = 0) -> void:
	_build_ui()
	_options = options
	_label.text = row_label
	select(initial_index)


func select(index: int) -> void:
	if _options.is_empty():
		return
	_index = clampi(index, 0, _options.size() - 1)
	if _value_label:
		_value_label.text = _options[_index]


func get_selected_index() -> int:
	return _index


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var click := event as InputEventMouseButton
		if click.pressed and click.button_index == MOUSE_BUTTON_LEFT:
			grab_focus()
			accept_event()
		return
	if not has_focus() or _options.is_empty():
		return
	if event.is_action_pressed("ui_right"):
		step(1)
		accept_event()
	elif event.is_action_pressed("ui_left"):
		step(-1)
		accept_event()
