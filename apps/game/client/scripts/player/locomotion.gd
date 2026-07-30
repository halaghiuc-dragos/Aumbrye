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
var _lock_on: LockOn
var _speed_multiplier := 1.0


func _ready() -> void:
	add_to_group("player")
	_stamina = get_node_or_null("Stamina") as Stamina
	_dodge = get_node_or_null("Dodge")
	_combat_reactions = get_node_or_null("CombatReactions")
	_lock_on = get_node_or_null("LockOn") as LockOn
	if camera_yaw_path:
		_camera_yaw = get_node(camera_yaw_path) as Node3D
	if facing_path:
		_facing = get_node_or_null(facing_path) as Node3D


func set_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.1, multiplier)


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
	var target_speed := (SPRINT_SPEED if sprinting else WALK_SPEED) * _speed_multiplier
	var status_ctrl := get_node_or_null("StatusController") as StatusController
	if status_ctrl:
		target_speed *= status_ctrl.get_slow_multiplier()

	if sprinting and _stamina:
		if not _stamina.consume(SPRINT_STAMINA_DRAIN * delta):
			target_speed = WALK_SPEED

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_velocity := direction * target_speed
	var rate := ACCELERATION if direction else DECELERATION
	horizontal = horizontal.move_toward(target_velocity, rate * delta)

	if LockOnMovement.is_active(_lock_on):
		horizontal = LockOnMovement.apply_orbit_radius_correction(
			self, _lock_on, input_dir, horizontal, delta
		)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	if LockOnMovement.is_active(_lock_on):
		var target := LockOnMovement.get_target(_lock_on)
		LockOnMovement.update_facing_toward_target(_facing, target, delta, ROTATION_SPEED)
	elif direction.length_squared() > 0.01 and _facing:
		var target_angle := atan2(direction.x, direction.z)
		_facing.rotation.y = lerp_angle(_facing.rotation.y, target_angle, ROTATION_SPEED * delta)

	move_and_slide()


func _get_move_direction(input_dir: Vector2) -> Vector3:
	if LockOnMovement.is_active(_lock_on):
		return LockOnMovement.get_move_direction(
			self,
			_lock_on,
			input_dir,
			_get_camera_relative_direction
		)
	return _get_camera_relative_direction(input_dir)


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
