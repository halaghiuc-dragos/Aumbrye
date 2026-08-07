extends Control

## Floor transition menu — ascend, descend, retreat without modifier keys.

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")

signal closed

var _lever: Node3D
var _open := false
var _action_buttons: Array[Button] = []


func _ready() -> void:
	add_to_group("stair_menu")
	visible = false
	process_mode = Node.PROCESS_MODE_ALWAYS
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_build_ui()


func is_open() -> bool:
	return _open


func open_for_lever(lever: Node3D, options: Array = []) -> void:
	if _open:
		return
	_lever = lever
	_open = true
	visible = true
	mouse_filter = Control.MOUSE_FILTER_STOP
	if MenuStack:
		MenuStack.push(self, true)
	else:
		get_tree().paused = true
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _lever and _lever.has_method("set_menu_open"):
		_lever.call("set_menu_open", true)
	_rebuild_buttons(options)


func close_menu() -> void:
	if not _open:
		return
	_open = false
	visible = false
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	if MenuStack:
		MenuStack.pop(self)
	if _lever and _lever.has_method("set_menu_open"):
		_lever.call("set_menu_open", false)
	_lever = null
	_action_buttons.clear()
	closed.emit()


func _build_ui() -> void:
	var shell: Dictionary = MenuShellScript.build_modal(
		self, "Stair Lever", GameUISkinScript.MENU_HALF_W + 20.0, GameUISkinScript.MENU_HALF_H + 40.0
	)
	MenuShellScript.add_hint(shell["content_vbox"], "Esc to close")


func _rebuild_buttons(options: Array) -> void:
	var vbox := get_node_or_null("Panel/Margin/ContentVBox") as VBoxContainer
	if vbox == null:
		return
	for child in vbox.get_children():
		if child.name != "TitleLabel" and child.name != "HintLabel":
			child.queue_free()
	_action_buttons.clear()
	for option in options:
		if not option is Dictionary:
			continue
		var row: Dictionary = option
		var enabled := bool(row.get("enabled", false))
		var label := str(row.get("label", "Action"))
		if not enabled:
			var reason := str(row.get("reason", ""))
			if reason != "":
				label = "%s (%s)" % [label, reason]
		var option_id := str(row.get("id", ""))
		var btn := MenuShellScript.make_menu_button(
			label,
			func() -> void:
				if enabled:
					_on_option_pressed(option_id)
		)
		btn.disabled = not enabled
		vbox.add_child(btn)
		_action_buttons.append(btn)
	vbox.add_child(MenuShellScript.make_menu_button("Close", close_menu))
	_wire_focus_ring()
	_focus_first_enabled()


func _wire_focus_ring() -> void:
	if _action_buttons.is_empty():
		return
	for i in _action_buttons.size():
		var btn := _action_buttons[i]
		var prev := _action_buttons[(i - 1 + _action_buttons.size()) % _action_buttons.size()]
		var next := _action_buttons[(i + 1) % _action_buttons.size()]
		btn.focus_neighbor_top = prev.get_path()
		btn.focus_neighbor_bottom = next.get_path()


func _focus_first_enabled() -> void:
	for btn in _action_buttons:
		if not btn.disabled:
			btn.grab_focus()
			return
	if not _action_buttons.is_empty():
		_action_buttons[0].grab_focus()


func _on_option_pressed(option_id: String) -> void:
	if _lever == null:
		close_menu()
		return
	if option_id == "retreat":
		close_menu()
		RunFlow.retreat_to_hub()
		return
	if _lever.has_method("use"):
		_lever.call("use", option_id)
	close_menu()


func _unhandled_input(event: InputEvent) -> void:
	if not _open:
		return
	if event.is_action_pressed("ui_cancel"):
		get_viewport().set_input_as_handled()
		close_menu()
