extends Node3D

## Syncs a dedicated viewmodel SubViewport camera to the gameplay camera.

var _gameplay_camera: Camera3D
var _view_root: Node3D
var _canvas: CanvasLayer
var _container: SubViewportContainer
var _subvp: SubViewport
var _vm_camera: Camera3D


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
	_vm_camera.fov = 60.0
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
	if _subvp:
		_subvp.size = _viewport_size()


func _viewport_size() -> Vector2i:
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
