class_name LockOnMovement


const DEFAULT_ORBIT_RADIUS := 1.75
const ORBIT_RADIUS_SMALL := 1.4
const ORBIT_RADIUS_STANDARD := 1.75
const ORBIT_RADIUS_LARGE := 2.6
const ORBIT_RADIUS_BOSS_PAD := 1.8
const ORBIT_RADIUS_BOSS_MIN := 3.5

const ORBIT_INPUT_DEADZONE := 0.15

const LOCKED_SPEED_APPROACH := 1.0
const LOCKED_SPEED_ORBIT := 0.78
const LOCKED_SPEED_RETREAT := 0.62
const LOCKED_SPRINT_ALLOWED := false

const FACING_TURN_RATE_DEG := 540.0
const FACING_SNAP_DEG := 1.5

const FACING_SPEED := FACING_TURN_RATE_DEG / 54.0


static func is_active(lock_on: Node) -> bool:
	return lock_on is LockOn and (lock_on as LockOn).is_locked


static func get_target(lock_on: Node) -> Node3D:
	if not is_active(lock_on):
		return null
	return (lock_on as LockOn).current_target


## Resolution is one-directional: `LockOn` asks this, this never asks `LockOn`. `LockOn`'s own
## `get_orbit_radius()` delegates straight back here, so a branch that calls it stack-overflows.
static func get_orbit_radius(lock_on: Node, target: Node3D = null) -> float:
	if target == null:
		target = get_target(lock_on)
	if target and target.has_method("get_lock_orbit_radius"):
		return float(target.call("get_lock_orbit_radius"))
	return DEFAULT_ORBIT_RADIUS


static func break_lock_on_sprint(lock_on: Node, sprint_requested: bool) -> bool:
	if (
		sprint_requested
		and not LOCKED_SPRINT_ALLOWED
		and lock_on is LockOn
		and (lock_on as LockOn).is_locked
	):
		(lock_on as LockOn).break_lock()
		return false
	return sprint_requested


static func get_locked_speed_scale(input_dir: Vector2) -> float:
	var x := absf(_apply_axis_deadzone(input_dir.x))
	var forward := -_apply_axis_deadzone(input_dir.y)
	var approach := maxf(forward, 0.0)
	var retreat := maxf(-forward, 0.0)
	var total := x + approach + retreat
	if total < 0.001:
		return LOCKED_SPEED_ORBIT
	return (
		(x * LOCKED_SPEED_ORBIT + approach * LOCKED_SPEED_APPROACH + retreat * LOCKED_SPEED_RETREAT)
		/ total
	)


## `Input.get_vector("move_forward", "move_back")` puts *forward* at y = -1, which is what the
## camera-relative path relies on. Reading the raw y as though forward were positive inverts the
## controls the moment a lock is taken; `get_locked_dodge_direction` mirrors this sign deliberately.
static func get_move_direction(
	player: Node3D, lock_on: Node, input_dir: Vector2, camera_relative_fn: Callable
) -> Vector3:
	if input_dir.length_squared() < 0.01:
		return Vector3.ZERO
	var target := get_target(lock_on)
	if target == null or not is_instance_valid(target):
		return camera_relative_fn.call(input_dir)

	var stick_x := _apply_axis_deadzone(input_dir.x)
	var forward := -_apply_axis_deadzone(input_dir.y)
	if absf(stick_x) < 0.001 and absf(forward) < 0.001:
		return Vector3.ZERO

	var offset := player.global_position - target.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, 1.0)
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial).normalized()
	var radial_forward := -radial

	var direction := tangent * stick_x + radial_forward * forward
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()


static func get_locked_dodge_direction(
	player: Node3D, lock_on: Node, input_dir: Vector2
) -> Vector3:
	var target := get_target(lock_on)
	if target == null or not is_instance_valid(target):
		return Vector3.ZERO
	var offset := player.global_position - target.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, 1.0)
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial).normalized()
	var stick_x := _apply_axis_deadzone(input_dir.x)
	var forward := -_apply_axis_deadzone(input_dir.y)
	if absf(stick_x) < 0.001 and absf(forward) < 0.001:
		return radial
	var direction := tangent * stick_x + (-radial) * forward
	if direction.length_squared() < 0.0001:
		return radial
	return direction.normalized()


static func world_direction_to_local_facing_y(body: Node3D, world_direction: Vector3) -> float:
	var dir := world_direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return 0.0
	dir = dir.normalized()
	var world_yaw := atan2(dir.x, dir.z)
	var body_yaw := body.rotation.y if body else 0.0
	return world_yaw - body_yaw


static func world_velocity_to_local_facing(facing: Node3D, velocity: Vector3) -> Vector2:
	var flat := Vector3(velocity.x, 0.0, velocity.z)
	if flat.length_squared() < 0.0001 or facing == null:
		return Vector2.ZERO
	flat = flat.normalized()
	var forward := CombatFacing.forward_of(facing)
	forward.y = 0.0
	if forward.length_squared() < 0.0001:
		return Vector2.ZERO
	forward = forward.normalized()
	var right := Vector3.UP.cross(forward).normalized()
	return Vector2(flat.dot(right), flat.dot(forward))


static func update_facing_toward_target(
	facing: Node3D, target: Node3D, delta: float, _speed: float = FACING_SPEED
) -> void:
	if facing == null or target == null or not is_instance_valid(target):
		return
	var body := facing.get_parent() as Node3D
	if body == null:
		return
	var aim_point := LockOn.get_target_aim_point(target)
	var to_target := aim_point - facing.global_position
	to_target.y = 0.0
	if to_target.length_squared() < 0.001:
		return
	var target_angle := world_direction_to_local_facing_y(body, to_target)
	var current := facing.rotation.y
	var error := angle_difference(current, target_angle)
	if absf(rad_to_deg(error)) <= FACING_SNAP_DEG:
		facing.rotation.y = target_angle
		return
	var max_step := deg_to_rad(FACING_TURN_RATE_DEG) * delta
	facing.rotation.y = current + clampf(error, -max_step, max_step)


static func _apply_axis_deadzone(value: float) -> float:
	if absf(value) < ORBIT_INPUT_DEADZONE:
		return 0.0
	return value
