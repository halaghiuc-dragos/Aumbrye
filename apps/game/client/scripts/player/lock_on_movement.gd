class_name LockOnMovement

## Shared lock-on locomotion helpers (DEC-G08 — used by player locomotion).

const DEFAULT_ORBIT_RADIUS := 1.75
const ORBIT_RADIUS_SMALL := 1.4
const ORBIT_RADIUS_STANDARD := 1.75
const ORBIT_RADIUS_LARGE := 2.6
const ORBIT_RADIUS_BOSS_PAD := 1.8
const ORBIT_RADIUS_BOSS_MIN := 3.5

const ORBIT_CORRECTION_GAIN := 6.0
const ORBIT_CORRECTION_CLAMP := 3.0
const ORBIT_CORRECTION_DEADBAND := 0.35
const ORBIT_STRAFE_DOMINANCE := 0.7
const ORBIT_CORRECTION_OUTWARD_SCALE := 0.25
const ORBIT_INPUT_DEADZONE := 0.15

const LOCKED_SPEED_APPROACH := 1.0
const LOCKED_SPEED_ORBIT := 0.78
const LOCKED_SPEED_RETREAT := 0.62
const LOCKED_SPRINT_ALLOWED := false

const FACING_TURN_RATE_DEG := 540.0
const FACING_SNAP_DEG := 1.5

## Legacy alias kept for callers that still pass a lerp rate.
const FACING_SPEED := FACING_TURN_RATE_DEG / 54.0


static func is_active(lock_on: Node) -> bool:
	return lock_on is LockOn and (lock_on as LockOn).is_locked


static func get_target(lock_on: Node) -> Node3D:
	if not is_active(lock_on):
		return null
	return (lock_on as LockOn).current_target


static func get_orbit_radius(lock_on: Node, target: Node3D = null) -> float:
	if target == null:
		target = get_target(lock_on)
	if target and target.has_method("get_lock_orbit_radius"):
		return float(target.call("get_lock_orbit_radius"))
	if lock_on and lock_on.has_method("get_orbit_radius"):
		return float(lock_on.call("get_orbit_radius"))
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
	var y_raw := _apply_axis_deadzone(input_dir.y)
	var approach := maxf(y_raw, 0.0)
	var retreat := maxf(-y_raw, 0.0)
	var total := x + approach + retreat
	if total < 0.001:
		return LOCKED_SPEED_ORBIT
	return (
		(x * LOCKED_SPEED_ORBIT + approach * LOCKED_SPEED_APPROACH + retreat * LOCKED_SPEED_RETREAT)
		/ total
	)


static func get_move_direction(
	player: Node3D, lock_on: Node, input_dir: Vector2, camera_relative_fn: Callable
) -> Vector3:
	if input_dir.length_squared() < 0.01:
		return Vector3.ZERO
	var target := get_target(lock_on)
	if target == null or not is_instance_valid(target):
		return camera_relative_fn.call(input_dir)

	var stick_x := _apply_axis_deadzone(input_dir.x)
	var stick_y := _apply_axis_deadzone(input_dir.y)
	if absf(stick_x) < 0.001 and absf(stick_y) < 0.001:
		return Vector3.ZERO

	var offset := player.global_position - target.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, 1.0)
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial).normalized()
	var radial_forward := -radial

	var direction := tangent * stick_x + radial_forward * stick_y
	if direction.length_squared() < 0.0001:
		return Vector3.ZERO
	return direction.normalized()


static func get_orbit_strafe_direction(player: Node3D, stick_x: float, enemy: Node3D) -> Vector3:
	var applied := _apply_axis_deadzone(stick_x)
	if absf(applied) < 0.001:
		return Vector3.ZERO
	var offset := player.global_position - enemy.global_position
	offset.y = 0.0
	if offset.length_squared() < 0.01:
		offset = Vector3(0.0, 0.0, 1.0)
	var radial := offset.normalized()
	var tangent := Vector3.UP.cross(radial).normalized()
	return tangent * applied


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
	if absf(stick_x) < 0.001:
		return radial
	return tangent * signf(stick_x)


static func apply_orbit_radius_correction(
	player: Node3D,
	lock_on: Node,
	input_dir: Vector2,
	horizontal_velocity: Vector3,
	delta: float,
	skip_correction: bool = false
) -> Vector3:
	if skip_correction or not _should_apply_orbit_correction(input_dir):
		return horizontal_velocity
	var target := get_target(lock_on)
	if target == null:
		return horizontal_velocity
	var offset := player.global_position - target.global_position
	offset.y = 0.0
	var dist := offset.length()
	if dist < 0.01:
		return horizontal_velocity
	var radius := get_orbit_radius(lock_on, target)
	var error := dist - radius
	if absf(error) < ORBIT_CORRECTION_DEADBAND:
		return horizontal_velocity
	var radial := offset / dist
	var gain := ORBIT_CORRECTION_GAIN
	if error < 0.0:
		gain *= ORBIT_CORRECTION_OUTWARD_SCALE
	var correction := -radial * clampf(error * gain, -ORBIT_CORRECTION_CLAMP, ORBIT_CORRECTION_CLAMP)
	return horizontal_velocity + correction * delta


static func world_direction_to_local_facing_y(body: Node3D, world_direction: Vector3) -> float:
	var dir := world_direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001:
		return 0.0
	dir = dir.normalized()
	# Player rig forward is +basis.z (see combat_suite player_hitbox_forward).
	var world_yaw := atan2(dir.x, dir.z)
	var body_yaw := body.rotation.y if body else 0.0
	return world_yaw - body_yaw


static func world_velocity_to_local_facing(body: Node3D, velocity: Vector3) -> Vector2:
	var local_yaw := world_direction_to_local_facing_y(body, velocity)
	return Vector2(sin(local_yaw), cos(local_yaw))


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


static func orbit_component_magnitude(stick_x: float) -> float:
	return absf(_apply_axis_deadzone(stick_x))


static func _apply_axis_deadzone(value: float) -> float:
	if absf(value) < ORBIT_INPUT_DEADZONE:
		return 0.0
	return value


static func _should_apply_orbit_correction(input_dir: Vector2) -> bool:
	if input_dir.length_squared() < 0.0001:
		return false
	var magnitude := input_dir.length()
	return absf(input_dir.x) > ORBIT_STRAFE_DOMINANCE * magnitude
