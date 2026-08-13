extends SceneTree

## Headless entry for CI:
##   Godot --path . --headless --script res://scripts/validation/validation_main.gd
## In-editor equivalent: res://scenes/debug/mcp_validation.tscn (same ValidationRunner node).


func _initialize() -> void:
	# Release exports exclude scripts/validation/* entirely (see export_presets.cfg). This guard is
	# the second line of defence: if a preset is ever misconfigured, the suites — which carry
	# state-manipulation helpers and would widen the cheat surface — stay inert in a release build
	# rather than being reachable.
	if not OS.is_debug_build():
		push_error("validation_main: validation suites are not available in release builds")
		quit(1)
		return

	var runner_scene: PackedScene = load("res://scenes/debug/mcp_validation.tscn") as PackedScene
	if runner_scene == null:
		push_error("validation_main: failed to load mcp_validation.tscn")
		quit(1)
		return
	var runner: Node = runner_scene.instantiate() as Node
	if runner == null:
		push_error("validation_main: failed to instantiate validation runner")
		quit(1)
		return
	root.add_child(runner)
