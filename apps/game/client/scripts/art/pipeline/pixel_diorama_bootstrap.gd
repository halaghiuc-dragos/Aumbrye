extends RefCounted
class_name PixelDioramaBootstrap

## Thin static helper: load pixel settings at boot and attach the viewport pipeline.


static func prime() -> void:
	PixelDioramaSettings.load_from_save()
	PixelDioramaSettings.apply_rendering_project_settings()


static func attach(scene: Node) -> void:
	if scene == null:
		return
	PixelDioramaSettings.apply_to_scene(scene)
	var viewport := _get_viewport()
	if viewport and viewport.has_method("attach_to_scene"):
		viewport.call("attach_to_scene", scene)


static func attach_deferred(scene: Node) -> void:
	if scene == null:
		return
	var viewport := _get_viewport()
	if viewport and viewport.has_method("bootstrap_scene"):
		viewport.call_deferred("bootstrap_scene", scene)


static func _get_viewport() -> Node:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return null
	return tree.root.get_node_or_null("PixelDioramaViewport")
