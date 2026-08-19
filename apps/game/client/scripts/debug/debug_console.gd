extends Node

## Debug-only command console for content iteration and dev utilities.

var _commands: Dictionary = {}


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


func _input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if event.is_action_pressed("debug_console"):
		var result := execute("content_reload")
		if not result.is_empty():
			print("DebugConsole: %s" % result)


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
