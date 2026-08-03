extends Node

## Crisp low-res 3D: shared-world SubViewport + mirrored camera (no node reparenting).

signal world_attached(scene_root: Node)

var _layer: CanvasLayer
var _container: SubViewportContainer
var _viewport: SubViewport
var _render_camera: Camera3D
var _source_camera: Camera3D
var _attached_scene: Node
var _root_3d_was_disabled := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_nodes()
	get_tree().root.size_changed.connect(_on_root_size_changed)
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)


func _build_nodes() -> void:
	_layer = CanvasLayer.new()
	_layer.name = "PixelDioramaViewportLayer"
	_layer.layer = -1
	_layer.visible = false
	add_child(_layer)
	_container = SubViewportContainer.new()
	_container.name = "PixelViewportContainer"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_layer.add_child(_container)
	_viewport = SubViewport.new()
	_viewport.name = "PixelSubViewport"
	_viewport.disable_3d = false
	_viewport.own_world_3d = false
	_viewport.transparent_bg = false
	_viewport.handle_input_locally = false
	_viewport.gui_disable_input = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_container.add_child(_viewport)
	_render_camera = Camera3D.new()
	_render_camera.name = "PixelRenderCamera"
	_render_camera.current = false
	_viewport.add_child(_render_camera)


func _process(_delta: float) -> void:
	if not PixelDioramaSettings.low_res_viewport_enabled:
		return
	if _source_camera == null or not is_instance_valid(_source_camera):
		if _attached_scene:
			_bind_source_camera(_attached_scene)
		return
	_render_camera.global_transform = _source_camera.global_transform
	_render_camera.projection = _source_camera.projection
	_render_camera.fov = _source_camera.fov
	_render_camera.near = _source_camera.near
	_render_camera.far = _source_camera.far
	_render_camera.keep_aspect = _source_camera.keep_aspect
	_render_camera.cull_mask = _source_camera.cull_mask


func apply_settings() -> void:
	_apply_internal_size()
	if PixelDioramaSettings.low_res_viewport_enabled and _attached_scene:
		_enable_pipeline()
	else:
		_disable_pipeline()


func attach_to_scene(scene_root: Node) -> void:
	if not PixelDioramaSettings.low_res_viewport_enabled:
		detach()
		return
	if scene_root == null:
		return
	if scene_root != _attached_scene:
		detach()
		_attached_scene = scene_root
		if not scene_root.tree_exiting.is_connected(_on_attached_scene_exiting):
			scene_root.tree_exiting.connect(_on_attached_scene_exiting)
	call_deferred("_bind_source_camera", scene_root)
	apply_settings()
	world_attached.emit(scene_root)


func detach() -> void:
	_disable_pipeline()
	if _attached_scene and _attached_scene.tree_exiting.is_connected(_on_attached_scene_exiting):
		_attached_scene.tree_exiting.disconnect(_on_attached_scene_exiting)
	_attached_scene = null
	_source_camera = null


func get_gameplay_camera() -> Camera3D:
	## Active 3D camera for billboards, lock-on, and HUD (mirrors SubViewport when low-res is on).
	if PixelDioramaSettings.low_res_viewport_enabled:
		if is_instance_valid(_render_camera) and _render_camera.current:
			return _render_camera
		if is_instance_valid(_source_camera):
			return _source_camera
	var tree := get_tree()
	if tree == null:
		return null
	return tree.root.get_camera_3d()


func get_subviewport() -> SubViewport:
	return _viewport


func get_world_root() -> Node3D:
	return null


func _apply_internal_size() -> void:
	if _viewport == null or _container == null:
		return
	var size := PixelDioramaSettings.viewport_internal_size()
	var was_stretched := _container.stretch
	_container.stretch = false
	_viewport.size = size
	_container.stretch = was_stretched
	_viewport.snap_2d_transforms_to_pixel = true
	_viewport.snap_2d_vertices_to_pixel = true
	_container.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if PixelDioramaSettings.nearest_texture_filter
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)


func _enable_pipeline() -> void:
	var root := get_tree().root
	if root == null:
		return
	root.scaling_3d_scale = 1.0
	if not _layer.visible:
		_root_3d_was_disabled = root.disable_3d
	root.disable_3d = true
	_layer.visible = true
	if _source_camera and is_instance_valid(_source_camera):
		_source_camera.current = false
	_render_camera.current = true


func _disable_pipeline() -> void:
	var root := get_tree().root
	if root:
		root.scaling_3d_scale = 1.0
		root.disable_3d = _root_3d_was_disabled
	if _render_camera:
		_render_camera.current = false
	if _source_camera and is_instance_valid(_source_camera):
		_source_camera.current = true
	_layer.visible = false


func _bind_source_camera(scene_root: Node) -> void:
	_source_camera = null
	var player := scene_root.get_tree().get_first_node_in_group("player")
	if player == null and scene_root.has_node("Player"):
		player = scene_root.get_node("Player")
	if player == null:
		return
	_source_camera = player.get_node_or_null("CameraPivot/SpringArm3D/Camera3D") as Camera3D
	if PixelDioramaSettings.low_res_viewport_enabled:
		_enable_pipeline()


func _on_root_size_changed() -> void:
	if PixelDioramaSettings.low_res_viewport_enabled:
		_apply_internal_size()


func _on_attached_scene_exiting() -> void:
	detach()


func _on_root_child_entered(node: Node) -> void:
	if node == self:
		return
	if not PixelDioramaSettings.low_res_viewport_enabled:
		return
	if node is Window:
		return
	call_deferred("_try_auto_attach", node)


func _try_auto_attach(scene_root: Node) -> void:
	if not PixelDioramaSettings.low_res_viewport_enabled:
		return
	if scene_root != get_tree().current_scene:
		return
	if scene_root.is_in_group("pixel_viewport_exclude"):
		return
	attach_to_scene(scene_root)
