extends Node

## Modal stack — mouse mode, ui_cancel routing, and shared confirmations.

signal stack_changed(depth: int)

const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")
const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")
const ConfirmSpecScript := preload("res://scripts/ui/confirm_spec.gd")

var _stack: Array[Control] = []
var _focus_records: Array[Dictionary] = []
var _saved_mouse_mode: Input.MouseMode = Input.MOUSE_MODE_CAPTURED
var _saved_paused := false
var _confirm_layer: CanvasLayer
var _active_confirm: Control
var _active_spec: ConfirmSpec
var _focus_before_confirm: Control


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_confirm_layer = CanvasLayer.new()
	_confirm_layer.name = "ConfirmLayer"
	_confirm_layer.layer = 40
	add_child(_confirm_layer)


func push(modal: Control, owns_pause: bool = false) -> void:
	if modal == null or modal in _stack:
		return
	if _stack.is_empty():
		_saved_mouse_mode = Input.mouse_mode
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
		_saved_paused = get_tree().paused
	if owns_pause:
		get_tree().paused = true
	_focus_records.append(
		{"modal": modal, "focus": get_viewport().gui_get_focus_owner() as Control}
	)
	_stack.append(modal)
	stack_changed.emit(depth())


func pop(modal: Control) -> void:
	var idx := _stack.find(modal)
	if idx < 0:
		return
	_stack.remove_at(idx)
	for i in range(_focus_records.size() - 1, -1, -1):
		if _focus_records[i].get("modal") == modal:
			var prev := _focus_records[i].get("focus") as Control
			_focus_records.remove_at(i)
			if is_instance_valid(prev) and prev.is_inside_tree():
				prev.grab_focus()
			break
	if _stack.is_empty() and _active_confirm == null:
		Input.mouse_mode = _saved_mouse_mode
		get_tree().paused = _saved_paused
	stack_changed.emit(depth())


func top() -> Control:
	if _active_confirm != null:
		return _active_confirm
	if _stack.is_empty():
		return null
	return _stack[_stack.size() - 1]


func depth() -> int:
	var d := _stack.size()
	if _active_confirm != null:
		d += 1
	return d


func handles_cancel(menu: Control) -> bool:
	return _active_confirm == null and top() == menu


func confirm(spec: ConfirmSpec) -> void:
	if spec == null:
		return
	_dismiss_confirm(false, false)
	_focus_before_confirm = get_viewport().gui_get_focus_owner() as Control
	_active_spec = spec
	_active_confirm = _build_confirm_overlay(spec)
	_confirm_layer.add_child(_active_confirm)
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stack_changed.emit(depth())


func _build_confirm_overlay(spec: ConfirmSpec) -> Control:
	var overlay := Control.new()
	overlay.name = "ConfirmOverlay"
	GameUISkinScript.ensure_full_rect(overlay)
	var title := tr(String(spec.title_key)) if spec.title_key != &"" else ""
	var shell: Dictionary = MenuShellScript.build_modal(overlay, title, 300.0, 130.0)
	var vbox: VBoxContainer = shell["content_vbox"]
	var msg := Label.new()
	msg.text = _format_message(spec)
	msg.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	msg.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	GameUISkinScript.style_body_label(msg)
	vbox.add_child(msg)
	var cancel := MenuShellScript.make_menu_button(
		tr(String(spec.cancel_key)),
		func() -> void:
			_dismiss_confirm(false, true)
	)
	var confirm_btn := MenuShellScript.make_menu_button(
		tr(String(spec.confirm_key)),
		func() -> void:
			_dismiss_confirm(true, true)
	)
	if spec.destructive:
		confirm_btn.add_theme_color_override("font_color", GameUISkinScript.DANGER_COLOR)
	MenuShellScript.add_button_row(vbox, [cancel, confirm_btn])
	cancel.focus_neighbor_right = confirm_btn.get_path()
	confirm_btn.focus_neighbor_left = cancel.get_path()
	if spec.destructive:
		cancel.grab_focus()
	else:
		confirm_btn.grab_focus()
	return overlay


func _format_message(spec: ConfirmSpec) -> String:
	if spec.message_text != "":
		return spec.message_text
	if spec.message_key == &"":
		return ""
	if spec.message_args.is_empty():
		return tr(String(spec.message_key))
	return tr(String(spec.message_key)) % spec.message_args


func _dismiss_confirm(confirmed: bool, run_callbacks: bool) -> void:
	if _active_confirm == null:
		return
	var overlay := _active_confirm
	var spec := _active_spec
	_active_confirm = null
	_active_spec = null
	overlay.queue_free()
	if run_callbacks and spec != null:
		if confirmed and spec.on_confirm.is_valid():
			spec.on_confirm.call()
		elif not confirmed and spec.on_cancel.is_valid():
			spec.on_cancel.call()
	if is_instance_valid(_focus_before_confirm):
		_focus_before_confirm.grab_focus()
	_focus_before_confirm = null
	if _stack.is_empty():
		Input.mouse_mode = _saved_mouse_mode
		get_tree().paused = _saved_paused
	else:
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	stack_changed.emit(depth())


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_action_pressed("ui_cancel"):
		return
	if _active_confirm != null:
		_dismiss_confirm(false, true)
		get_viewport().set_input_as_handled()
		return
	var modal := top()
	if modal == null:
		return
	if modal.has_signal("cancel_requested"):
		modal.emit_signal("cancel_requested")
	elif modal.has_method("_on_cancel_requested"):
		modal.call("_on_cancel_requested")
	get_viewport().set_input_as_handled()
