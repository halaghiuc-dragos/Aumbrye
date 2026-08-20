extends Node3D

## Syncs a dedicated viewmodel SubViewport camera to the gameplay camera.

var _gameplay_camera: Camera3D
var _view_root: Node3D
var _canvas: CanvasLayer
var _container: SubViewportContainer
var _subvp: SubViewport
var _vm_camera: Camera3D

## C-167: last applied SubViewport size, so the render target is only reallocated when it changes.
var _last_viewport_size := Vector2i.ZERO


func setup_pass(gameplay_camera: Camera3D, view_root: Node3D) -> void:
	_gameplay_camera = gameplay_camera
	_view_root = view_root
	if _gameplay_camera == null or _view_root == null:
		return
	_canvas = CanvasLayer.new()
	_canvas.name = "ViewmodelCanvas"
	_canvas.layer = 5
	# Deferred: the viewport is mid-setup when the player rig builds its viewmodel, so a direct
	# add_child() here fails and the first-person arms never get a canvas to render into. The
	# container and subviewport below attach to _canvas while it is still detached, which is fine —
	# they enter the tree with it.
	_gameplay_camera.get_viewport().add_child.call_deferred(_canvas)
	_container = SubViewportContainer.new()
	_container.name = "ViewmodelContainer"
	_container.set_anchors_preset(Control.PRESET_FULL_RECT)
	_container.stretch = true
	_container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_canvas.add_child(_container)
	_subvp = SubViewport.new()
	_subvp.name = "ViewmodelViewport"
	_subvp.transparent_bg = true
	_subvp.own_world_3d = true
	_subvp.handle_input_locally = false
	_subvp.size = _viewport_size()
	_container.add_child(_subvp)
	_vm_camera = Camera3D.new()
	_vm_camera.name = "ViewmodelCamera"
	_vm_camera.near = 0.01
	# C-166: this was a hardcoded 60. The gameplay camera's field of view is a player setting
	# (`CAMERA_FOV_MIN/MAX/DEFAULT` = 60/100/**70**), so at the default the arms were already 10
	# degrees narrower than the world behind them, and a player who widened their FOV to 100 pushed
	# the mismatch to 40 — the arms read as attached to a different camera, because they were.
	_vm_camera.fov = AccessibilitySettings.camera_fov
	_vm_camera.current = true
	_subvp.add_child(_vm_camera)
	_subvp.add_child(_view_root)


func set_pass_visible(on: bool) -> void:
	if _canvas:
		_canvas.visible = on


func get_view_root() -> Node3D:
	return _view_root


func _process(_delta: float) -> void:
	if _vm_camera and _gameplay_camera:
		_vm_camera.global_transform = Transform3D(
			_gameplay_camera.global_transform.basis, Vector3.ZERO
		)
	# C-167: this reassigned the SubViewport size every frame whether or not anything changed —
	# writing `size` on a SubViewport reallocates its render target, so the viewmodel pass was
	# rebuilding a texture per frame for a value that changes only on a window resize or a
	# resolution-preset change.
	#
	# C-166: the FOV setting can change at runtime from the accessibility page, so it is tracked
	# the same way.
	if _subvp:
		var target_size := _viewport_size()
		if target_size != _last_viewport_size:
			_last_viewport_size = target_size
			_subvp.size = target_size
	if _vm_camera and not is_equal_approx(_vm_camera.fov, AccessibilitySettings.camera_fov):
		_vm_camera.fov = AccessibilitySettings.camera_fov


## C-165: this returned the **window** rect, so the first-person arms rendered at native resolution
## over a world rendered at 480x270 and upscaled — the one part of the screen that was not
## pixel-art, in a pipeline whose own comments explain why the internal size must be an integer
## divisor of the window ("so the nearest-neighbour upscale stays square-pixel... avoid upscale on
## fractional pixel boundaries and shimmer"). The arms now render at the same internal resolution as
## everything else.
func _viewport_size() -> Vector2i:
	if PixelDioramaSettings and PixelDioramaSettings.low_res_viewport_enabled:
		return PixelDioramaSettings.viewport_internal_size()
	if _gameplay_camera == null:
		return Vector2i(1920, 1080)
	var vp := _gameplay_camera.get_viewport()
	if vp == null:
		return Vector2i(1920, 1080)
	var rect := vp.get_visible_rect()
	return Vector2i(maxi(1, int(rect.size.x)), maxi(1, int(rect.size.y)))


func _exit_tree() -> void:
	if _canvas and is_instance_valid(_canvas):
		_canvas.queue_free()
	_canvas = null
