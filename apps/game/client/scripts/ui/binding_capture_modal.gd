extends Control
class_name BindingCaptureModal

## Listens for the next binding event and resolves conflicts with swap/cancel (SET-04).

signal captured(action: StringName, event: InputEvent)
signal cancelled

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const InputMapServiceScript := preload("res://scripts/input/input_map_service.gd")

const MOTION_DEADZONE := 0.5

var _action: StringName = &""
var _device_family: String = "keyboard"
var _awaiting_swap := false
var _pending_event: InputEvent
var _conflict_action: StringName = &""


func open(parent: Control, action: StringName, device_family: String = "keyboard") -> void:
	_action = action
	_device_family = device_family
	_awaiting_swap = false
	GameUISkinScript.ensure_full_rect(self)
	parent.add_child(self)
	move_to_front()
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_process_unhandled_input(true)
	_build_prompt()


func close() -> void:
	queue_free()


func _build_prompt() -> void:
	for child in get_children():
		child.queue_free()
	var shell: Dictionary = MenuShellScript.build_modal(
		self,
		tr("SETTINGS_BINDING_PROMPT"),
		280.0,
		120.0
	)
	var vbox: VBoxContainer = shell["content_vbox"]
	var msg := Label.new()
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(msg)
	if _awaiting_swap:
		msg.text = tr("SETTINGS_BINDING_CONFLICT") % [
			InputRebindService.get_action_label(_action),
			InputRebindService.get_action_label(_conflict_action),
		]
	else:
		msg.text = tr("SETTINGS_BINDING_WAIT") % InputRebindService.get_action_label(_action)
	vbox.add_child(msg)
	if _awaiting_swap:
		var cancel := MenuShellScript.make_menu_button(tr("SETTINGS_BINDING_CANCEL"), _on_cancel)
		var swap := MenuShellScript.make_menu_button(tr("SETTINGS_BINDING_SWAP"), _on_swap)
		MenuShellScript.add_button_row(vbox, [cancel, swap])
		cancel.grab_focus()
	else:
		var cancel_only := MenuShellScript.make_menu_button(tr("SETTINGS_BINDING_CANCEL"), _on_cancel)
		vbox.add_child(cancel_only)
		cancel_only.grab_focus()


func _on_cancel() -> void:
	cancelled.emit()
	close()


func _on_swap() -> void:
	var result := InputMapServiceScript.swap_binding(_action, _conflict_action, _pending_event)
	if bool(result.get("ok", false)):
		captured.emit(_action, _pending_event)
	close()


func _unhandled_input(event: InputEvent) -> void:
	if _awaiting_swap:
		if event.is_action_pressed("ui_cancel"):
			_on_cancel()
			get_viewport().set_input_as_handled()
		return
	if event.is_action_pressed("ui_cancel"):
		_on_cancel()
		get_viewport().set_input_as_handled()
		return
	if not _is_binding_event(event):
		return
	if event is InputEventKey and event.echo:
		return
	if not event.is_pressed():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		return
	if event is InputEventJoypadMotion:
		if absf(event.axis_value) < MOTION_DEADZONE:
			return
	var conflict := InputMapServiceScript.find_conflict(_action, event)
	if conflict != &"":
		_pending_event = event
		_conflict_action = conflict
		_awaiting_swap = true
		_build_prompt()
		get_viewport().set_input_as_handled()
		return
	var result := InputMapServiceScript.set_binding(_action, _device_family, event)
	if bool(result.get("ok", false)):
		captured.emit(_action, event)
		close()
	get_viewport().set_input_as_handled()


func _is_binding_event(event: InputEvent) -> bool:
	return (
		event is InputEventKey
		or event is InputEventMouseButton
		or event is InputEventJoypadButton
		or event is InputEventJoypadMotion
	)
