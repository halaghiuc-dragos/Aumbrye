extends Node3D


var _gameplay_camera: Camera3D
var _view_root: Node3D
var _canvas: CanvasLayer
var _container: SubViewportContainer
var _subvp: SubViewport
var _vm_camera: Camera3D
var _env: WorldEnvironment

var _last_viewport_size := Vector2i.ZERO

const AMBIENT_COLOR := Color(0.62, 0.64, 0.72)
const AMBIENT_ENERGY := 0.55
const KEY_ROTATION := Vector3(-0.62, 0.55, 0.0)
const KEY_ENERGY := 1.35
const FILL_ROTATION := Vector3(-0.15, -1.05, 0.0)
const FILL_ENERGY := 0.45
const FILL_COLOR := Color(0.72, 0.78, 0.95)


func setup_pass(gameplay_camera: Camera3D, view_root: Node3D) -> void:
	_gameplay_camera = gameplay_camera
	_view_root = view_root
	if _gameplay_camera == null or _view_root == null:
		return
	_canvas = CanvasLayer.new()
	_canvas.name = "ViewmodelCanvas"
	_canvas.layer = 5
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
	_vm_camera.fov = _gameplay_camera.fov
	_vm_camera.current = true
	_subvp.add_child(_vm_camera)
	# The arms hang off the camera, not off the sub-viewport's origin. Parented to the viewport they
	# kept a fixed world orientation while the camera spun around them, so looking left or right
	# swung the hands out of frame instead of carrying them along.
	_vm_camera.add_child(_view_root)
	_build_lighting()


## The pass renders into its own `World3D`, so it inherits none of the level's lights or ambient.
##
## Nothing lit these arms before: the diorama surface shader is a lit `spatial` shader, and with no
## light and no ambient in the world it resolves to black, which is why the first-person hands read
## as silhouettes. A fixed key/fill rig parented to the camera also keeps the weapon lit the same way
## no matter which room the player is standing in, which is what a viewmodel wants.
func _build_lighting() -> void:
	_env = WorldEnvironment.new()
	_env.name = "ViewmodelEnvironment"
	var environment := Environment.new()
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT_COLOR
	environment.ambient_light_energy = AMBIENT_ENERGY
	_env.environment = environment
	_subvp.add_child(_env)

	var key := DirectionalLight3D.new()
	key.name = "ViewmodelKey"
	key.rotation = KEY_ROTATION
	key.light_energy = KEY_ENERGY
	key.shadow_enabled = false
	_vm_camera.add_child(key)

	var fill := DirectionalLight3D.new()
	fill.name = "ViewmodelFill"
	fill.rotation = FILL_ROTATION
	fill.light_energy = FILL_ENERGY
	fill.light_color = FILL_COLOR
	fill.shadow_enabled = false
	_vm_camera.add_child(fill)


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
		var target_size := _viewport_size()
		if target_size != _last_viewport_size:
			_last_viewport_size = target_size
			_subvp.size = target_size
	# Matched to the gameplay camera rather than to the raw setting: first person runs a widened
	# field of view of its own and blends into it, and a viewmodel drawn at a different angle than
	# the world it sits in slides against the scene as the blend runs.
	if _vm_camera and _gameplay_camera and not is_equal_approx(_vm_camera.fov, _gameplay_camera.fov):
		_vm_camera.fov = _gameplay_camera.fov


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
