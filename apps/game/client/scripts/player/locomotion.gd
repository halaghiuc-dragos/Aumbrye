extends CharacterBody3D

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const ACCELERATION := 12.0
const DECELERATION := 14.0
const SPRINT_STAMINA_DRAIN := 18.0
const ROTATION_SPEED := 10.0

@export var camera_yaw_path: NodePath
@export var facing_path: NodePath = NodePath("Facing")

var _camera_yaw: Node3D
var _facing: Node3D
var _stamina: Stamina
var _dodge: Node
var _combat_reactions: Node
var _lock_on: Node


func _ready() -> void:
	_stamina = get_node_or_null("Stamina") as Stamina
	_dodge = get_node_or_null("Dodge")
	_combat_reactions = get_node_or_null("CombatReactions")
	_lock_on = get_node_or_null("LockOn")
	if camera_yaw_path:
		_camera_yaw = get_node(camera_yaw_path) as Node3D
	if facing_path:
		_facing = get_node_or_null(facing_path) as Node3D


func _physics_process(delta: float) -> void:
	if _combat_reactions and _combat_reactions.has_method("is_movement_locked"):
		if _combat_reactions.call("is_movement_locked"):
			if not is_on_floor():
				velocity += get_gravity() * delta
			velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)
			move_and_slide()
			return

	if _dodge and _dodge.has_method("process_dodge_physics"):
		_dodge.call("process_dodge_physics", delta)
		if _dodge.get("is_dodging"):
			return

	if not is_on_floor():
		velocity += get_gravity() * delta

	var input_dir := Input.get_vector("move_left", "move_right", "move_forward", "move_back")
	var direction := _get_move_direction(input_dir)

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

	if direction.length_squared() > 0.01 and _facing:
		var target_angle := atan2(direction.x, direction.z)
		_facing.rotation.y = lerp_angle(_facing.rotation.y, target_angle, ROTATION_SPEED * delta)

	move_and_slide()


func _get_move_direction(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() < 0.01:
		return Vector3.ZERO
	if _is_lock_on_active():
		return _get_locked_move_direction(input_dir)
	return _get_camera_relative_direction(input_dir)


func _get_locked_move_direction(input_dir: Vector2) -> Vector3:
	var target := _lock_on.get("current_target") as Node3D
	if target == null or not is_instance_valid(target):
		return _get_camera_relative_direction(input_dir)

	var forward_back := Vector3.ZERO
	if absf(input_dir.y) > 0.01:
		forward_back = _get_camera_relative_direction(Vector2(0.0, input_dir.y))

	var strafe := Vector3.ZERO
	if absf(input_dir.x) > 0.01:
		strafe = _get_orbit_strafe_direction(input_dir.x, target)

	if forward_back.length_squared() < 0.01 and strafe.length_squared() < 0.01:
		return Vector3.ZERO

	if forward_back.length_squared() < 0.01:
		return strafe
	if strafe.length_squared() < 0.01:
		return forward_back

	var combined := forward_back + strafe
	return combined.normalized()


func _get_orbit_strafe_direction(stick_x: float, enemy: Node3D) -> Vector3:
	var offset := global_position - enemy.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, 1.0)
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial).normalized()
	return tangent * signf(stick_x)


func _is_lock_on_active() -> bool:
	return _lock_on != null and _lock_on.get("is_locked")


func _get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	if input_dir.length_squared() < 0.01:
		return Vector3.ZERO
	var yaw_basis := Basis.IDENTITY
	if _camera_yaw:
		yaw_basis = Basis(Vector3.UP, _camera_yaw.global_rotation.y)
	var direction := (yaw_basis * Vector3(input_dir.x, 0.0, input_dir.y)).normalized()
	return direction


func get_camera_relative_direction(input_dir: Vector2) -> Vector3:
	return _get_camera_relative_direction(input_dir)


func get_facing_direction() -> Vector3:
	if _facing:
		return -_facing.global_transform.basis.z
	return -global_transform.basis.z


func get_facing_yaw() -> float:
	if _facing:
		return _facing.rotation.y
	return rotation.y
