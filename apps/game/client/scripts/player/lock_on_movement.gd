class_name LockOnMovement

## Shared lock-on locomotion helpers (DEC-G08 — used by player locomotion).

const DEFAULT_ORBIT_RADIUS := 1.75
const FACING_SPEED := 10.0


static func is_active(lock_on: Node) -> bool:
	return lock_on is LockOn and (lock_on as LockOn).is_locked


static func get_target(lock_on: Node) -> Node3D:
	if not is_active(lock_on):
		return null
	return (lock_on as LockOn).current_target


static func get_orbit_radius(lock_on: Node) -> float:
	if lock_on and lock_on.has_method("get_orbit_radius"):
		return float(lock_on.call("get_orbit_radius"))
	return DEFAULT_ORBIT_RADIUS


static func get_move_direction(
	player: Node3D,
	lock_on: Node,
	input_dir: Vector2,
	camera_relative_fn: Callable
) -> Vector3:
	if input_dir.length_squared() < 0.01:
		return Vector3.ZERO
	var target := get_target(lock_on)
	if target == null or not is_instance_valid(target):
		return camera_relative_fn.call(input_dir)

	var forward_back := Vector3.ZERO
	if absf(input_dir.y) > 0.01:
		forward_back = camera_relative_fn.call(Vector2(0.0, input_dir.y))

	var strafe := Vector3.ZERO
	if absf(input_dir.x) > 0.01:
		strafe = get_orbit_strafe_direction(player, input_dir.x, target)

	if forward_back.length_squared() < 0.01 and strafe.length_squared() < 0.01:
		return Vector3.ZERO
	if forward_back.length_squared() < 0.01:
		return strafe
	if strafe.length_squared() < 0.01:
		return forward_back
	return (forward_back + strafe).normalized()


static func get_orbit_strafe_direction(player: Node3D, stick_x: float, enemy: Node3D) -> Vector3:
	var offset := player.global_position - enemy.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, 1.0)
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial).normalized()
	return tangent * signf(stick_x)


static func apply_orbit_radius_correction(
	player: Node3D,
	lock_on: Node,
	input_dir: Vector2,
	horizontal_velocity: Vector3,
	delta: float
) -> Vector3:
	if absf(input_dir.x) < 0.01:
		return horizontal_velocity
	var target := get_target(lock_on)
	if target == null:
		return horizontal_velocity
	var offset := player.global_position - target.global_position
	offset.y = 0.0
	var dist := offset.length()
	if dist < 0.01:
		return horizontal_velocity
	var radius := get_orbit_radius(lock_on)
	var radial := offset / dist
	var error := dist - radius
	var correction := -radial * clampf(error * 6.0, -3.0, 3.0)
	return horizontal_velocity + correction * delta


static func update_facing_toward_target(
	facing: Node3D,
	target: Node3D,
	delta: float,
	speed: float = FACING_SPEED
) -> void:
	if facing == null or target == null or not is_instance_valid(target):
		return
	var aim_point := LockOn.get_target_aim_point(target)
	var to_target := aim_point - facing.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		return
	var target_angle := atan2(to_target.x, to_target.z)
	facing.rotation.y = lerp_angle(facing.rotation.y, target_angle, speed * delta)
