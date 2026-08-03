extends Node

## Crisp low-res 3D: shared-world SubViewport + mirrored camera (no node reparenting).
##
## The scene graph is never reparented into the SubViewport; only the camera is
## mirrored. See docs/design/visual_enhancement_plan.md for the rejected
## alternatives (own_world_3d, scaling_3d_scale, pivot snapping) and why.

signal world_attached(scene_root: Node)

## Distance the snap grid is sized for: roughly the third-person camera boom.
const SNAP_FOCUS_DISTANCE := 5.0

var _layer: CanvasLayer
var _container: SubViewportContainer
var _viewport: SubViewport
var _render_camera: Camera3D
var _source_camera: Camera3D
var _finish_material: ShaderMaterial
var _attached_scene: Node
var _root_3d_was_disabled := false


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_build_nodes()
	get_tree().root.size_changed.connect(_on_root_size_changed)
	get_tree().root.child_entered_tree.connect(_on_root_child_entered)
	get_tree().create_timer(3.0).timeout.connect(_dbg_dump)


func _dbg_dump() -> void:
	var counts := {}
	var lights: Array[String] = []
	_dbg_walk(get_tree().root, counts, lights)
	print("[DBG] cast_shadow counts: ", counts)
	for l in lights:
		print("[DBG] ", l)
	print("[DBG] renderer: ", ProjectSettings.get_setting("rendering/renderer/rendering_method", "?"))


func _dbg_walk(n: Node, counts: Dictionary, lights: Array[String]) -> void:
	if n is GeometryInstance3D:
		var k := str((n as GeometryInstance3D).cast_shadow)
		counts[k] = int(counts.get(k, 0)) + 1
	if n is DirectionalLight3D:
		var d := n as DirectionalLight3D
		lights.append(
			"%s shadow=%s energy=%.2f rot=%s vis=%s layers=%d"
			% [d.name, d.shadow_enabled, d.light_energy, d.rotation, d.is_visible_in_tree(), d.light_cull_mask]
		)
	for c in n.get_children():
		_dbg_walk(c, counts, lights)


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
	_finish_material = PixelDioramaSettings.make_screen_finish_material()


func _process(_delta: float) -> void:
	if not PixelDioramaSettings.low_res_viewport_enabled:
		return
	if _source_camera == null or not is_instance_valid(_source_camera):
		if _attached_scene:
			_bind_source_camera(_attached_scene)
		return
	_render_camera.projection = _source_camera.projection
	_render_camera.fov = _source_camera.fov
	_render_camera.near = _source_camera.near
	_render_camera.far = _source_camera.far
	_render_camera.keep_aspect = _source_camera.keep_aspect
	_render_camera.cull_mask = _source_camera.cull_mask
	_render_camera.global_transform = _mirrored_transform()


## Snapping happens on the render camera only. Snapping the gameplay CameraPivot
## decouples yaw from player movement and breaks SpringArm follow.
func _mirrored_transform() -> Transform3D:
	var source := _source_camera.global_transform
	if not PixelDioramaSettings.camera_snap_enabled:
		return source
	var step := PixelDioramaSettings.camera_snap_step(_source_camera.fov, SNAP_FOCUS_DISTANCE)
	if step <= 0.0:
		return source
	var right := source.basis.x
	var up := source.basis.y
	var origin := source.origin
	# Quantize the two axes that slide across the screen; depth is left alone so
	# the near plane and spring-arm distance stay exact.
	var lateral := right.dot(origin)
	var vertical := up.dot(origin)
	var snapped_origin := origin
	snapped_origin += right * (snappedf(lateral, step) - lateral)
	snapped_origin += up * (snappedf(vertical, step) - vertical)
	return Transform3D(source.basis, snapped_origin)


func apply_settings() -> void:
	_apply_internal_size()
	_apply_screen_finish()
	if PixelDioramaSettings.low_res_viewport_enabled and _attached_scene:
		_enable_pipeline()
	else:
		_disable_pipeline()


## Deferred entry point used by PixelDioramaBootstrap.attach_deferred().
func bootstrap_scene(scene_root: Node) -> void:
	if scene_root == null or not is_instance_valid(scene_root):
		return
	PixelDioramaSettings.apply_to_scene(scene_root)
	attach_to_scene(scene_root)


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


func get_render_camera() -> Camera3D:
	return _render_camera


func get_world_root() -> Node3D:
	return null


## The internal resolution is expressed as an integer divisor of the window, not
## as an absolute size: SubViewportContainer.stretch drives the SubViewport size
## from the container, and any non-integer ratio would put the nearest-neighbour
## upscale on fractional pixel boundaries and shimmer.
func _apply_internal_size() -> void:
	if _viewport == null or _container == null:
		return
	var target := PixelDioramaSettings.viewport_internal_size()
	var window_height := 1080.0
	var tree := get_tree()
	if tree and tree.root:
		window_height = maxf(1.0, tree.root.get_visible_rect().size.y)
	var shrink := maxi(1, int(round(window_height / float(maxi(90, target.y)))))
	_container.stretch = true
	_container.stretch_shrink = shrink
	PixelDioramaSettings.active_render_height = int(round(window_height / float(shrink)))
	_viewport.snap_2d_transforms_to_pixel = true
	_viewport.snap_2d_vertices_to_pixel = true
	_container.texture_filter = (
		CanvasItem.TEXTURE_FILTER_NEAREST
		if PixelDioramaSettings.nearest_texture_filter
		else CanvasItem.TEXTURE_FILTER_LINEAR
	)


func _apply_screen_finish() -> void:
	if _container == null:
		return
	if not PixelDioramaSettings.screen_finish_enabled:
		_container.material = null
		return
	if _finish_material == null:
		_finish_material = PixelDioramaSettings.make_screen_finish_material()
	PixelDioramaSettings.apply_to_screen_finish(_finish_material)
	_container.material = _finish_material


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
