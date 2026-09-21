extends RefCounted
class_name RunOutcomeConfirm


const MenuShellScript := preload("res://scripts/ui/menu_shell.gd")


static func ask(message: String, on_confirm: Callable, on_cancel: Callable = Callable()) -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null or tree.root == null:
		_cancel_unavailable(on_cancel, "scene tree unavailable")
		return
	var parent := _modal_host(tree.current_scene)
	if parent == null:
		_cancel_unavailable(on_cancel, "modal host unavailable")
		return
	MenuShellScript.show_confirmation(
		parent,
		"Leave the dungeon?",
		message,
		on_confirm,
		on_cancel,
		"Leave",
		"Stay"
	)




static func _modal_host(scene: Node) -> Control:
	if scene == null:
		return null
	var host := scene.get_node_or_null("CombatHUD") as Control
	if host != null and host.is_visible_in_tree():
		return host
	return null


static func _cancel_unavailable(on_cancel: Callable, reason: String) -> void:
	push_warning("RunOutcomeConfirm: %s" % reason)
	if on_cancel.is_valid():
		on_cancel.call()
