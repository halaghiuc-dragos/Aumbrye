extends SpringArm3D

const MOUSE_SENSITIVITY := 0.003
const STICK_SENSITIVITY := 2.5
const MIN_PITCH := deg_to_rad(-45.0)
const MAX_PITCH := deg_to_rad(60.0)
const MIN_ZOOM := 2.5
const MAX_ZOOM := 7.0
const ZOOM_STEP := 0.5
const ZOOM_SPEED := 8.0
const FIRST_PERSON_LENGTH := 0.0
const INVERT_Y := false

@export var yaw_pivot_path: NodePath
@export var body_mesh_path: NodePath = NodePath("../../Facing/MeshInstance3D")

var _pitch := 0.0
var _target_zoom := 4.0
var _saved_third_person_zoom := 4.0
var _yaw_pivot: Node3D
var _body_mesh: GeometryInstance3D
var _first_person := false


func _ready() -> void:
	_target_zoom = spring_length
	_saved_third_person_zoom = spring_length
	collision_mask = 1
	if yaw_pivot_path:
		_yaw_pivot = get_node(yaw_pivot_path) as Node3D
	if body_mesh_path:
		_body_mesh = get_node_or_null(body_mesh_path) as GeometryInstance3D
	if LocalSave.is_first_person_camera():
		_apply_first_person(true)
	else:
		_update_spring_collision()
	Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		_apply_look(-event.relative.x * MOUSE_SENSITIVITY, -event.relative.y * MOUSE_SENSITIVITY)
	if event.is_action_pressed("pause"):
		if Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
			Input.set_mouse_mode(Input.MOUSE_MODE_VISIBLE)
		else:
			Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)
	if event.is_action_pressed("toggle_camera"):
		_toggle_camera_mode()
	if not _first_person:
		if event.is_action_pressed("zoom_in"):
			_target_zoom = clampf(_target_zoom - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
		if event.is_action_pressed("zoom_out"):
			_target_zoom = clampf(_target_zoom + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)


func _physics_process(delta: float) -> void:
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	if stick.length_squared() > 0.01:
		_apply_look(-stick.x * STICK_SENSITIVITY * delta, stick.y * STICK_SENSITIVITY * delta)
	spring_length = lerpf(spring_length, _target_zoom, ZOOM_SPEED * delta)


func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	if _yaw_pivot:
		_yaw_pivot.rotate_y(yaw_delta)
	var pitch_sign := -1.0 if INVERT_Y else 1.0
	_pitch = clampf(_pitch + pitch_delta * pitch_sign, MIN_PITCH, MAX_PITCH)
	rotation.x = _pitch


func get_yaw_basis() -> Basis:
	if _yaw_pivot:
		return Basis(Vector3.UP, _yaw_pivot.global_rotation.y)
	return Basis(Vector3.UP, global_rotation.y)


func is_first_person() -> bool:
	return _first_person


func _toggle_camera_mode() -> void:
	_apply_first_person(not _first_person)
	LocalSave.set_first_person_camera(_first_person)


func _apply_first_person(enabled: bool) -> void:
	if enabled == _first_person:
		return
	if enabled:
		_saved_third_person_zoom = _target_zoom if _target_zoom > FIRST_PERSON_LENGTH else _saved_third_person_zoom
		_first_person = true
		_target_zoom = FIRST_PERSON_LENGTH
		spring_length = FIRST_PERSON_LENGTH
	else:
		_first_person = false
		_target_zoom = _saved_third_person_zoom
	_update_body_visibility()
	_update_spring_collision()


func _update_spring_collision() -> void:
	# Spring-arm wall pull fights first-person eye position; disable collision in 1P.
	collision_mask = 0 if _first_person else 1


func _update_body_visibility() -> void:
	if _body_mesh:
		_body_mesh.visible = not _first_person
