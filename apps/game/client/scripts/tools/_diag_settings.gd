extends SceneTree


func _initialize() -> void:
	await process_frame
	var controls := root.get_node_or_null("PlayerControls")
	if controls == null:
		print("no PlayerControls autoload")
		quit()
		return
	controls.open_settings()
	await process_frame
	await process_frame
	var ui: Control = controls.get("_settings_ui")
	if ui == null:
		print("no settings ui")
		quit()
		return
	var panel := ui.get_node_or_null("Panel") as Control
	print("viewport: ", root.get_visible_rect().size)
	print("panel rect: ", panel.get_rect(), "  min: ", panel.get_combined_minimum_size())
	_walk(panel, 0)
	quit()


func _walk(node: Node, depth: int) -> void:
	if depth > 4:
		return
	var c := node as Control
	if c != null:
		var m := c.get_combined_minimum_size()
		if true:
			print("  ".repeat(depth), c.name, " [", c.get_class(), "] minW=", m.x, " size=", c.size)
	for ch in node.get_children():
		_walk(ch, depth + 1)
