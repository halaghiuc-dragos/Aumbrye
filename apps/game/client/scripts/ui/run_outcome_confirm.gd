extends RefCounted
class_name RunOutcomeConfirm

## Pause-style confirmation before ending a run via the exit portal.

const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")


static func ask(message: String, on_confirm: Callable) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		if on_confirm.is_valid():
			on_confirm.call()
		return
	var parent := _find_ui_parent(tree.root)
	if parent == null:
		if on_confirm.is_valid():
			on_confirm.call()
		return
	MenuShellScript.show_confirmation(
		parent,
		"Leave the dungeon?",
		message,
		on_confirm,
		Callable(),
		"Leave",
		"Stay"
	)


static func _find_ui_parent(root: Node) -> Control:
	for node in root.get_children():
		if node is Control and node.visible:
			return node as Control
		if node.get_child_count() > 0:
			var nested := _find_ui_parent(node)
			if nested:
				return nested
	return null
