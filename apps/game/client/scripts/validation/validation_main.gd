extends SceneTree

## Headless entry for: Godot --path . --headless --script res://scripts/validation/validation_main.gd
## Prefer the scene for MCP/CI: res://scenes/debug/mcp_validation.tscn


func _initialize() -> void:
	var runner_script: Script = load("res://scripts/validation/validation_runner.gd") as Script
	if runner_script == null:
		push_error("validation_main: failed to load validation_runner.gd")
		quit(1)
		return
	var runner: Node = runner_script.new() as Node
	if runner == null:
		push_error("validation_main: failed to instantiate validation runner")
		quit(1)
		return
	root.add_child(runner)
