extends PanelContainer
class_name SettingsRow

## One labeled settings row with name, description, widget, and formatted value (SET-01, SET-13).

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const SettingsSchemaScript := preload("res://scripts/ui/settings_schema.gd")

@onready var _name_label: Label = %NameLabel
@onready var _desc_label: Label = %DescLabel
@onready var _value_label: Label = %ValueLabel
@onready var _widget_host: Control = %Widget

var _entry: Dictionary = {}
var _slider: HSlider
var _toggle: CheckBox
var _option: OptionButton


func _ready() -> void:
	focus_mode = Control.FOCUS_ALL


func configure(entry: Dictionary) -> void:
	_entry = entry
	_name_label.text = tr(str(entry.get("name_key", "")))
	_desc_label.text = tr(str(entry.get("desc_key", "")))
	for child in _widget_host.get_children():
		child.queue_free()
	match str(entry.get("kind", "")):
		"slider":
			_build_slider()
		"toggle":
			_build_toggle()
		"option":
			_build_option()
		_:
			pass
	_refresh_value()


func _build_slider() -> void:
	var range_def: Dictionary = _entry.get("range", {})
	_slider = HSlider.new()
	_slider.min_value = float(range_def.get("min", 0.0))
	_slider.max_value = float(range_def.get("max", 1.0))
	_slider.step = float(range_def.get("step", 0.05))
	_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var getter: Callable = _entry.get("getter", Callable())
	if getter.is_valid():
		_slider.value = float(getter.call())
	_slider.value_changed.connect(_on_slider_changed)
	_slider.drag_ended.connect(_on_slider_drag_ended)
	_widget_host.add_child(_slider)


func _build_toggle() -> void:
	_toggle = CheckBox.new()
	var getter: Callable = _entry.get("getter", Callable())
	if getter.is_valid():
		_toggle.button_pressed = bool(getter.call())
	_toggle.toggled.connect(_on_toggle_changed)
	_widget_host.add_child(_toggle)


func _build_option() -> void:
	_option = OptionButton.new()
	_option.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var labels: Array = _entry.get("option_labels", [])
	var options: Array = _entry.get("options", [])
	if labels.is_empty():
		for i in options.size():
			_option.add_item(str(options[i]), i)
	else:
		for i in labels.size():
			_option.add_item(tr(str(labels[i])), i)
	var getter: Callable = _entry.get("getter", Callable())
	if getter.is_valid():
		_option.selected = int(getter.call())
	_option.item_selected.connect(_on_option_selected)
	_widget_host.add_child(_option)


func _on_slider_changed(value: float) -> void:
	var setter: Callable = _entry.get("setter", Callable())
	if setter.is_valid():
		setter.call(value)
	_refresh_value()


func _on_slider_drag_ended(_value_changed: bool) -> void:
	var commit: Callable = _entry.get("commit", Callable())
	if commit.is_valid():
		commit.call()


func _on_toggle_changed(on: bool) -> void:
	var setter: Callable = _entry.get("setter", Callable())
	if setter.is_valid():
		setter.call(on)
	_refresh_value()


func _on_option_selected(idx: int) -> void:
	var setter: Callable = _entry.get("setter", Callable())
	if setter.is_valid():
		setter.call(idx)
	_refresh_value()


func _refresh_value() -> void:
	var format_id := str(_entry.get("format", ""))
	var value: Variant = null
	match str(_entry.get("kind", "")):
		"slider":
			if _slider:
				value = _slider.value
		"toggle":
			if _toggle:
				value = tr("SETTINGS_VALUE_ON") if _toggle.button_pressed else tr("SETTINGS_VALUE_OFF")
				_value_label.text = str(value)
				return
		"option":
			if _option:
				value = _option.get_item_text(_option.selected)
				_value_label.text = str(value)
				return
	_value_label.text = SettingsSchemaScript.format_value(format_id, value)


func reset_to_default() -> void:
	var default_value: Variant = _entry.get("default")
	match str(_entry.get("kind", "")):
		"slider":
			if _slider:
				_slider.value = float(default_value)
				_on_slider_changed(_slider.value)
				_on_slider_drag_ended(true)
		"toggle":
			if _toggle:
				_toggle.button_pressed = bool(default_value)
				_on_toggle_changed(_toggle.button_pressed)
		"option":
			if _option:
				var getter_default := 0
				if default_value is String:
					var options: Array = _entry.get("options", [])
					getter_default = options.find(default_value)
				_option.selected = maxi(0, getter_default)
				_on_option_selected(_option.selected)


func get_widget() -> Control:
	if _slider:
		return _slider
	if _toggle:
		return _toggle
	if _option:
		return _option
	return null
