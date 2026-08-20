extends Node

## Debug-only command console for content iteration and dev utilities.

var _commands: Dictionary = {}

## C-252: the entry overlay, built on demand so a debug build pays nothing until the key is pressed.
var _overlay: CanvasLayer
var _entry: LineEdit
var _output: Label
var _history: Array[String] = []
var _history_cursor := -1


func _ready() -> void:
	if not OS.is_debug_build():
		set_process_input(false)
		return
	register_command(
		"content_reload",
		_cmd_content_reload,
		"Clear all content catalog caches; next lookup reloads from disk"
	)
	register_command("help", _cmd_help, "List available commands")


func register_command(command_name: String, handler: Callable, help: String = "") -> void:
	_commands[command_name] = {"handler": handler, "help": help}


func execute(line: String) -> String:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return ""
	var parts := trimmed.split(" ", false)
	var command_name: String = parts[0]
	if not _commands.has(command_name):
		return "Unknown command: %s (try help)" % command_name
	var args: Array = parts.slice(1) if parts.size() > 1 else []
	return str(_commands[command_name].handler.call(args))


## C-252: `register_command`, `execute` with argument splitting and `_cmd_help` listing every
## registered command all existed — and the only caller of `execute` was one hardcoded
## `execute("content_reload")` on the `debug_console` key. So `help` could never be run, arguments
## could never be passed, and the key was in practice a "reload content" hotkey. A command framework
## with no way to enter a command.
##
## The key now opens a one-line entry overlay: type, Enter to run, Escape to close, Up/Down through
## history. Debug builds only — `_ready` disables input entirely outside them.
func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event.is_action_pressed("debug_console"):
		_toggle_overlay()
		get_viewport().set_input_as_handled()


func _toggle_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_close_overlay()
		return
	_build_overlay()


func _build_overlay() -> void:
	_overlay = CanvasLayer.new()
	_overlay.name = "DebugConsoleOverlay"
	_overlay.layer = 128
	# So the console is usable while the game is paused, which is when it is most wanted.
	_overlay.process_mode = Node.PROCESS_MODE_ALWAYS
	add_child(_overlay)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_TOP_WIDE)
	panel.custom_minimum_size = Vector2(0, 96)
	_overlay.add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	_output = Label.new()
	_output.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_output.text = execute("help")
	box.add_child(_output)

	_entry = LineEdit.new()
	_entry.placeholder_text = "command (Enter to run, Esc to close)"
	_entry.caret_blink = true
	box.add_child(_entry)
	_entry.text_submitted.connect(_on_command_submitted)
	_entry.gui_input.connect(_on_entry_gui_input)
	_entry.grab_focus()


func _close_overlay() -> void:
	if _overlay and is_instance_valid(_overlay):
		_overlay.queue_free()
	_overlay = null
	_entry = null
	_output = null
	_history_cursor = -1


func _on_command_submitted(line: String) -> void:
	var trimmed := line.strip_edges()
	if trimmed.is_empty():
		return
	_history.append(trimmed)
	_history_cursor = -1
	var result := execute(trimmed)
	if _output:
		_output.text = result if not result.is_empty() else "(no output)"
	print("DebugConsole: %s" % result)
	if _entry:
		_entry.clear()


func _on_entry_gui_input(event: InputEvent) -> void:
	if not event is InputEventKey or not (event as InputEventKey).pressed:
		return
	var key := event as InputEventKey
	match key.keycode:
		KEY_ESCAPE:
			_close_overlay()
		KEY_UP:
			_step_history(1)
		KEY_DOWN:
			_step_history(-1)
		_:
			return
	if _entry:
		_entry.accept_event()


func _step_history(direction: int) -> void:
	if _history.is_empty() or _entry == null:
		return
	_history_cursor = clampi(_history_cursor + direction, -1, _history.size() - 1)
	if _history_cursor < 0:
		_entry.clear()
		return
	_entry.text = _history[_history.size() - 1 - _history_cursor]
	_entry.caret_column = _entry.text.length()


func _cmd_content_reload(_args: Array) -> String:
	ContentLoader.clear_all_caches()
	return "Content caches cleared; catalogs reload on next access."


func _cmd_help(_args: Array) -> String:
	var lines: PackedStringArray = []
	for command_name in _commands.keys():
		var entry: Dictionary = _commands[command_name]
		var help_text: String = str(entry.get("help", ""))
		if help_text.is_empty():
			lines.append(command_name)
		else:
			lines.append("%s — %s" % [command_name, help_text])
	lines.sort()
	return "\n".join(lines)
