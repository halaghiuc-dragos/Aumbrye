class_name WardenPreviewRig
extends Node3D


const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

const ROTATE_STEP := deg_to_rad(30.0)

const FRONT_YAW := 0.0

const DEFAULT_SUBJECT_HEIGHT := 1.44
const DEFAULT_SUBJECT_WIDTH := 0.80
const DEFAULT_SUBJECT_DEPTH := 0.42
const CAMERA_PITCH := deg_to_rad(-6.0)
const CAMERA_FOV := 34.0
const SUBJECT_SCREEN_FRACTION := 0.82

var _stage: Node3D
var _camera: Camera3D
var _yaw := FRONT_YAW
var _profile: Dictionary = {}


func _ready() -> void:
	_stage = Node3D.new()
	_stage.name = "PreviewStage"
	add_child(_stage)
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.current = true
	add_child(_camera)
	_build_outline_pass()
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation = Vector3(deg_to_rad(-38.0), deg_to_rad(32.0), 0.0)
	key_light.light_energy = 1.6
	add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation = Vector3(deg_to_rad(-14.0), deg_to_rad(-128.0), 0.0)
	fill_light.light_energy = 0.28
	add_child(fill_light)
	_frame_subject(
		Vector3(DEFAULT_SUBJECT_WIDTH, DEFAULT_SUBJECT_HEIGHT, DEFAULT_SUBJECT_DEPTH),
		DEFAULT_SUBJECT_HEIGHT
	)


func apply_profile(profile: Dictionary) -> void:
	_profile = CharacterAppearance.sanitize(profile)
	CharacterSkinScript.build_preview_body(_stage, _profile)
	_stage.rotation.y = _yaw
	_reframe_when_built()


func _reframe_when_built() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if not is_inside_tree():
		return
	var bounds := _stage_bounds()
	_frame_subject(_turn_extent(bounds), bounds.get_center().y)


func _turn_extent(bounds: AABB) -> Vector3:
	var far_end := bounds.position + bounds.size
	var radius := maxf(
		maxf(absf(bounds.position.x), absf(far_end.x)),
		maxf(absf(bounds.position.z), absf(far_end.z))
	)
	return Vector3(radius * 2.0, bounds.size.y, radius * 2.0)


func _stage_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	for node in _stage.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		if visual == null or not visual.is_visible_in_tree() or visual.mesh == null:
			continue
		var world_aabb := visual.global_transform * visual.get_aabb()
		if found:
			bounds = bounds.merge(world_aabb)
		else:
			bounds = world_aabb
			found = true
	if not found or bounds.size.y <= 0.0:
		return AABB(
			Vector3(-DEFAULT_SUBJECT_WIDTH * 0.5, DEFAULT_SUBJECT_HEIGHT * 0.5, 0.0),
			Vector3(DEFAULT_SUBJECT_WIDTH, DEFAULT_SUBJECT_HEIGHT, DEFAULT_SUBJECT_DEPTH)
		)
	return bounds


func _build_outline_pass() -> void:
	var material := PixelDioramaSettings.make_outline_material()
	if material.shader == null:
		return
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	var pass_quad := MeshInstance3D.new()
	pass_quad.name = "PreviewOutlinePass"
	pass_quad.mesh = quad
	pass_quad.material_override = material
	pass_quad.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	pass_quad.extra_cull_margin = 16384.0
	material.render_priority = 100
	_camera.add_child(pass_quad)


func _frame_subject(size: Vector3, center_y: float) -> void:
	if _camera == null:
		return
	_camera.fov = CAMERA_FOV
	var half_fov := deg_to_rad(CAMERA_FOV) * 0.5
	var tan_v := maxf(tan(half_fov), 0.001)
	var tan_h := tan_v * maxf(_viewport_aspect(), 0.05)
	var distance := maxf(
		(maxf(size.y, 0.1) / SUBJECT_SCREEN_FRACTION * 0.5) / tan_v,
		(maxf(size.x, 0.1) / SUBJECT_SCREEN_FRACTION * 0.5) / tan_h
	)
	distance += maxf(size.z, 0.0) * 0.5
	_camera.position = Vector3(0.0, center_y - distance * tan(CAMERA_PITCH), distance)
	_camera.rotation = Vector3(CAMERA_PITCH, 0.0, 0.0)
	_camera.near = 0.05
	_camera.far = distance * 8.0


func _viewport_aspect() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 0.75
	var rect := viewport.get_visible_rect().size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return 0.75
	return rect.x / rect.y


func get_stage() -> Node3D:
	return _stage


func rotate_by(delta_yaw: float) -> void:
	_yaw = wrapf(_yaw + delta_yaw, -PI, PI)
	if _stage:
		_stage.rotation.y = _yaw


func rotate_left() -> void:
	rotate_by(-ROTATE_STEP)


func rotate_right() -> void:
	rotate_by(ROTATE_STEP)


func reset_yaw() -> void:
	_yaw = FRONT_YAW
	if _stage:
		_stage.rotation.y = FRONT_YAW
