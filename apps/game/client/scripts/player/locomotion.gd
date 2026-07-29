extends CharacterBody3D

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const ACCELERATION := 12.0
const DECELERATION := 14.0
const SPRINT_STAMINA_DRAIN := 18.0
const ROTATION_SPEED := 10.0

@export var camera_yaw_path: NodePath

var _camera_yaw: Node3D
var _stamina: Stamina
var _dodge: Node


func _ready() -> void:
	_stamina = get_node_or_null("Stamina") as Stamina
	_dodge = get_node_or_null("Dodge")
	if camera_yaw_path:
		_camera_yaw = get_node(camera_yaw_path) as Node3D


func _physics_process(delta: float) -> void:
	if _dodge and _dodge.has_method("process_dodge_physics"):
		_dodge.call("process_dodge_physics", delta)
		if _dodge.get("is_dodging"):
			return

	if not is_on_floor():
		velocity += get_gravity() * delta

	if _is_movement_locked():
		velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
		velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)
		move_and_slide()
		return

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _get_camera_relative_direction(input_dir)

	var sprinting := Input.is_action_pressed("sprint") and direction.length_squared() > 0.01
	var target_speed := SPRINT_SPEED if sprinting else WALK_SPEED

	if sprinting and _stamina:
		if not _stamina.consume(SPRINT_STAMINA_DRAIN * delta):
			target_speed = WALK_SPEED

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_velocity := direction * target_speed
	var rate := ACCELERATION if direction else DECELERATION
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if direction.length_squared() > 0.01:
		var target_angle := atan2(direction.x, direction.z)
		rotation.y = lerp_angle(rotation.y, target_angle, ROTATION_SPEED * delta)

	move_and_slide()


func _get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() < 0.01:
		return Vector3.ZERO
	var yaw_basis := Basis.IDENTITY
	if _camera_yaw:
		yaw_basis = Basis(Vector3.UP, _camera_yaw.global_rotation.y)
	var direction := (yaw_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	return direction


func get_facing_direction() -> Vector3:
	return -global_transform.basis.z


func _is_movement_locked() -> bool:
	var weapon := get_node_or_null("WeaponController")
	if weapon and weapon.get("is_attacking"):
		return true
	var guard := get_node_or_null("Guard")
	if guard and (guard.get("is_blocking") or guard.get("_stagger_timer", 0.0) > 0.0):
		return true
	var parry := get_node_or_null("Parry")
	if parry and parry.get("_recovery_timer", 0.0) > 0.0:
		return true
	var dodge := get_node_or_null("Dodge")
	if dodge and dodge.get("_recovery_timer", 0.0) > 0.0:
		return true
	return false
