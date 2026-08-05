extends Control

## Floor transition menu — ascend, descend, retreat without modifier keys.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

signal closed

var _lever: Node3D
var _open := false


func _ready() -> void:
	add_to_group("stair_menu")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func is_open() -> bool:
	return _open


func open_for_lever(lever: Node3D) -> void:
	_lever = lever
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	_rebuild_buttons()


func close_menu() -> void:
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
	_lever = null
	closed.emit()


func _build_ui() -> void:
	GameUISkinScript.make_backdrop(self)
	var panel := GameUISkinScript.make_center_panel(self, GameUISkinScript.MENU_HALF_W + 20.0, GameUISkinScript.MENU_HALF_H + 40.0)
	panel.name = "Panel"
	var margin := MarginContainer.new()
	margin.name = "Margin"
	margin.add_theme_constant_override("margin_left", 16)
	margin.add_theme_constant_override("margin_top", 16)
	margin.add_theme_constant_override("margin_right", 16)
	margin.add_theme_constant_override("margin_bottom", 16)
	panel.add_child(margin)
	var vbox := VBoxContainer.new()
	vbox.name = "VBox"
	margin.add_child(vbox)
	var title := Label.new()
	title.name = "Title"
	title.text = "Stair Lever"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_menu_title(title)
	vbox.add_child(title)


func _rebuild_buttons() -> void:
	var vbox := get_node_or_null("Panel/Margin/VBox") as VBoxContainer
	if vbox == null or _lever == null:
		return
	for child in vbox.get_children():
		if child.name != "Title":
			child.queue_free()
	if _lever.get("_can_ascend"):
		vbox.add_child(_action_button("Ascend floor", func() -> void: _use_lever("ascend")))
	if _lever.get("_can_descend"):
		vbox.add_child(_action_button("Descend floor", func() -> void: _use_lever("descend")))
	if _lever.get("_can_retreat") and RunFlow.can_retreat_to_hub():
		vbox.add_child(_action_button("Retreat to hub", _retreat))
	vbox.add_child(_action_button("Close", close_menu))


func _action_button(text: String, on_pressed: Callable) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.pressed.connect(on_pressed)
	return btn


func _use_lever(direction: String) -> void:
	if _lever and _lever.has_method("_use_lever"):
		_lever.call("_use_lever", direction)
	close_menu()


func _retreat() -> void:
	close_menu()
	RunFlow.retreat_to_hub()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()
