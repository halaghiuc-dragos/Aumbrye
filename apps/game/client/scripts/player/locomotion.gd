extends CharacterBody3D

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const ACCELERATION := 12.0
const DECELERATION := 14.0
const SPRINT_STAMINA_DRAIN := 18.0
const ROTATION_SPEED := 10.0
const CharacterSkin := preload("res://scripts/art/diorama_character_skin.gd")
const CharacterAnimator := preload("res://scripts/art/diorama_character_animator.gd")

@export var camera_yaw_path: NodePath
@export var facing_path: NodePath = NodePath("Facing")

var _camera_yaw: Node3D
var _facing: Node3D
var _stamina: Stamina
var _dodge: Node
var _combat_reactions: Node
var _lock_on: LockOn
var _speed_multiplier := 1.0
var _animator
var _footstep_timer := 0.0


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
		if _facing:
			CharacterSkin.build_player_body(_facing)
			_animator = CharacterAnimator.new()
			_animator.bind(_facing.get_node_or_null(CharacterSkin.VISUAL_NAME) as Node3D)
			_animator.set_profile("player")
			_sync_first_person_body_visibility()


func set_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = maxf(0.1, multiplier)


func _sync_first_person_body_visibility() -> void:
	if _facing == null:
		return
	var spring := get_node_or_null("CameraPivot/SpringArm3D")
	if spring and spring.has_method("is_first_person"):
		CharacterSkin.apply_first_person(_facing, spring.call("is_first_person"))


func _physics_process(delta: float) -> void:
	if _combat_reactions and _combat_reactions.has_method("is_movement_locked"):
		if _combat_reactions.call("is_movement_locked"):
			if not is_on_floor():
				velocity += get_gravity() * delta
			velocity.x = move_toward(velocity.x, 0.0, DECELERATION * delta)
			velocity.z = move_toward(velocity.z, 0.0, DECELERATION * delta)
			move_and_slide()
			_update_character_animation(delta)
			return

	if _dodge and _dodge.has_method("process_roll_physics"):
		_dodge.call("process_roll_physics", delta)
		if _dodge.get("is_dodging"):
			_update_character_animation(delta)
			return
	elif _dodge and _dodge.has_method("process_dodge_physics"):
		_dodge.call("process_dodge_physics", delta)
		if _dodge.get("is_dodging"):
			_update_character_animation(delta)
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
	_update_footstep_vfx(delta)
	_update_character_animation(delta)


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


func _update_footstep_vfx(delta: float) -> void:
	if not is_on_floor():
		_footstep_timer = 0.0
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.35:
		_footstep_timer = 0.0
		return
	var sprinting := Input.is_action_pressed("sprint")
	var interval := VfxService.FOOTSTEP_INTERVAL_SPRINT if sprinting else VfxService.FOOTSTEP_INTERVAL_WALK
	_footstep_timer -= delta
	if _footstep_timer > 0.0:
		return
	_footstep_timer = interval
	VfxService.play_footstep(global_position + Vector3(0.0, 0.05, 0.0), get_facing_direction())


func _update_character_animation(delta: float) -> void:
	if _animator == null:
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	var anim_state := CharacterAnimator.AnimState.IDLE
	var params: Dictionary = {}
	if _dodge and _dodge.get("is_dodging"):
		anim_state = CharacterAnimator.AnimState.ROLL
		if _dodge.has_method("get_roll_progress"):
			params["roll_progress"] = _dodge.call("get_roll_progress")
		if _dodge.has_method("get_roll_direction"):
			_animator.set_roll_direction(_dodge.call("get_roll_direction"))
	elif not is_on_floor():
		anim_state = CharacterAnimator.AnimState.AIR
		params["vertical_speed"] = velocity.y
	elif horizontal_speed > 0.2:
		var sprinting := Input.is_action_pressed("sprint")
		anim_state = CharacterAnimator.AnimState.RUN if sprinting else CharacterAnimator.AnimState.WALK
		var target_speed := SPRINT_SPEED if sprinting else WALK_SPEED
		params["speed_ratio"] = clampf(horizontal_speed / maxf(target_speed, 0.01), 0.2, 1.2)
	_animator.set_state(anim_state)
	_animator.update(delta, params)
