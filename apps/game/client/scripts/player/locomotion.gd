extends CharacterBody3D

const WALK_SPEED := 4.5
const SPRINT_SPEED := 7.0
const ACCELERATION := 12.0
const DECELERATION := 14.0
const SPRINT_STAMINA_DRAIN := 18.0
const ROTATION_SPEED := 10.0
const SPEED_SCALE_FORWARD := 1.0
const SPEED_SCALE_STRAFE := 0.82
const SPEED_SCALE_BACK := 0.65
const SPRINT_MIN_FORWARD_DOT := 0.5
const AIR_ACCELERATION := 4.0
const AIR_CONTROL_MAX_TURN_DEG := 55.0
const TERMINAL_FALL_SPEED := 22.0
const LAND_SOFT_HEIGHT := 1.2
const LAND_HARD_HEIGHT := 3.5
const LAND_DAMAGE_HEIGHT := 7.0
const LAND_HARD_LOCK := 0.18
const LAND_SPEED_PENALTY := 0.45
const LAND_CAMERA_DIP := 0.12
const SPRINT_RAMP_UP := 0.35
const SPRINT_RAMP_DOWN := 0.5
const SURFACE_PROBE_INTERVAL := 0.25
const SURFACE_PROBE_LENGTH := 0.4
const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const AnimDirectorScript := preload("res://scripts/player/player_anim_director.gd")
const FloorSnap := preload("res://scripts/art/characters/character_floor_snap.gd")

@export var camera_yaw_path: NodePath
@export var facing_path: NodePath = NodePath("Facing")

var _camera_yaw: Node3D
var _facing: Node3D
var _stamina: Stamina
var _dodge: Dodge
var _combat_reactions: PlayerCombatReactions
var _lock_on: LockOn
var _speed_multiplier := 1.0
var _weapon: WeaponController
var _status: StatusController
var _anim_director: PlayerAnimDirector
var _footstep_timer := 0.0
var _was_on_floor := true
var _fall_start_y := 0.0
var _airborne_velocity_dir := Vector3.ZERO
var _landing_lock_timer := 0.0
var _landing_penalty_timer := 0.0
var _sprint_blend := 0.0
var _cached_surface: StringName = &"stone"
var _surface_probe_timer := 0.0
var _last_speed_breakdown := {
	"base": WALK_SPEED,
	"equipment": 1.0,
	"status": 1.0,
	"weapon": 1.0,
	"direction": 1.0,
	"dodge": 1.0,
	"final": 0.0,
}


func _ready() -> void:
	add_to_group("player")
	if CharacterService and not CharacterService.appearance_changed.is_connected(_on_appearance_changed):
		CharacterService.appearance_changed.connect(_on_appearance_changed)
	_stamina = get_node_or_null("Stamina") as Stamina
	_dodge = get_node_or_null("Dodge") as Dodge
	_combat_reactions = get_node_or_null("CombatReactions") as PlayerCombatReactions
	_lock_on = get_node_or_null("LockOn") as LockOn
	_weapon = get_node_or_null("WeaponController") as WeaponController
	_status = get_node_or_null("StatusController") as StatusController
	if camera_yaw_path:
		_camera_yaw = get_node(camera_yaw_path) as Node3D
	if facing_path:
		_facing = get_node_or_null(facing_path) as Node3D
		if _facing:
			var visual := CharacterSkin.build_player_body(_facing)
			FloorSnap.snap_character(self, visual)
			_anim_director = AnimDirectorScript.new()
			_anim_director.name = "AnimDirector"
			add_child(_anim_director)
			_anim_director.bind(visual)
			if InventoryService:
				InventoryService.apply_equipment_to_player_node(self)
			_sync_first_person_body_visibility()


func set_speed_multiplier(multiplier: float) -> void:
	_speed_multiplier = clampf(multiplier, 0.1, 3.0)


func get_current_speed_breakdown() -> Dictionary:
	return _last_speed_breakdown.duplicate()


func get_sprint_blend() -> float:
	return _sprint_blend


func _on_appearance_changed(_profile: Dictionary) -> void:
	refresh_appearance_visual()


func refresh_appearance_visual() -> void:
	if _facing == null:
		return
	var visual := CharacterSkin.build_player_body(_facing)
	FloorSnap.snap_character(self, visual)
	if _anim_director:
		_anim_director.bind(visual)
	InventoryService.apply_equipment_to_player_node(self)
	_sync_first_person_body_visibility()


func _sync_first_person_body_visibility() -> void:
	if _facing == null:
		return
	var spring := get_node_or_null("CameraPivot/SpringArm3D")
	if spring and spring.has_method("is_first_person"):
		CharacterSkin.apply_first_person(_facing, spring.call("is_first_person"))


func _physics_process(delta: float) -> void:
	if _landing_lock_timer > 0.0:
		_landing_lock_timer = maxf(0.0, _landing_lock_timer - delta)
	if _landing_penalty_timer > 0.0:
		_landing_penalty_timer = maxf(0.0, _landing_penalty_timer - delta)

	if _combat_reactions and _combat_reactions.is_movement_locked():
		var lunge := Vector3.ZERO
		if _weapon:
			lunge = _weapon.get_attack_lunge_velocity()
		if not is_on_floor():
			velocity += get_gravity() * delta
		velocity.x = lunge.x
		velocity.z = lunge.z
		move_and_slide()
		_update_floor_state()
		_update_character_animation(delta, 0.0)
		return

	if _landing_lock_timer > 0.0:
		if not is_on_floor():
			velocity += get_gravity() * delta
		velocity.y = maxf(velocity.y, -TERMINAL_FALL_SPEED)
		var horizontal := Vector3(velocity.x, 0.0, velocity.z)
		horizontal = horizontal.move_toward(Vector3.ZERO, DECELERATION * delta)
		velocity.x = horizontal.x
		velocity.z = horizontal.z
		move_and_slide()
		_update_floor_state()
		_update_character_animation(delta, 0.0)
		return

	if _dodge:
		_dodge.process_dash_physics(delta)
		if _dodge.is_dodging:
			_update_floor_state()
			_update_character_animation(delta, 0.0)
			return

	var fall_height := 0.0
	if not is_on_floor():
		velocity += get_gravity() * delta
		velocity.y = maxf(velocity.y, -TERMINAL_FALL_SPEED)

	var input_dir := PlayerInput.move_vector()
	var direction := _get_move_direction(input_dir)
	var locked_on := LockOnMovement.is_active(_lock_on)

	var sprint_requested := PlayerInput.pressed(&"sprint") and direction.length_squared() > 0.01
	if locked_on:
		sprint_requested = LockOnMovement.break_lock_on_sprint(_lock_on, sprint_requested)
		locked_on = LockOnMovement.is_active(_lock_on)
	var forward_dot := _movement_forward_dot(direction)
	if sprint_requested and forward_dot < SPRINT_MIN_FORWARD_DOT:
		sprint_requested = false

	var attack_speed_mult := 1.0
	var rotation_cap_mult := 1.0
	if _weapon:
		attack_speed_mult = _weapon.get_move_speed_multiplier()
		rotation_cap_mult = _weapon.get_rotation_cap_multiplier()
	var stamina_mult := 1.0
	if _stamina:
		stamina_mult = _stamina.get_speed_multiplier()
	var dodge_mult := 1.0
	if _dodge:
		dodge_mult = _dodge.get_move_speed_multiplier()

	var sprint_ramp_target := 1.0 if sprint_requested else 0.0
	var ramp_rate := (
		(1.0 / SPRINT_RAMP_UP) if sprint_ramp_target > _sprint_blend else (1.0 / SPRINT_RAMP_DOWN)
	)
	_sprint_blend = move_toward(_sprint_blend, sprint_ramp_target, ramp_rate * delta)

	var base_speed := lerpf(WALK_SPEED, SPRINT_SPEED, _sprint_blend)
	var direction_scale := (
		LockOnMovement.get_locked_speed_scale(input_dir)
		if locked_on
		else _direction_speed_scale(direction)
	)
	var target_speed := (
		base_speed * _speed_multiplier * attack_speed_mult * stamina_mult * direction_scale * dodge_mult
	)
	var status_mult := 1.0
	if _status:
		status_mult = _status.get_slow_multiplier()
		target_speed *= status_mult

	if sprint_requested and _stamina:
		if not _stamina.drain(SPRINT_STAMINA_DRAIN * delta):
			_sprint_blend = move_toward(_sprint_blend, 0.0, ramp_rate * delta)
			base_speed = lerpf(WALK_SPEED, SPRINT_SPEED, _sprint_blend)
			target_speed = (
				base_speed
				* _speed_multiplier
				* attack_speed_mult
				* stamina_mult
				* direction_scale
				* dodge_mult
				* status_mult
			)

	if _landing_penalty_timer > 0.0:
		target_speed *= LAND_SPEED_PENALTY

	_last_speed_breakdown = {
		"base": base_speed,
		"equipment": _speed_multiplier,
		"status": status_mult,
		"weapon": attack_speed_mult,
		"direction": direction_scale,
		"dodge": dodge_mult,
		"final": target_speed,
	}

	var horizontal := Vector3(velocity.x, 0.0, velocity.z)
	var target_velocity := direction * target_speed
	var rate := ACCELERATION if direction.length_squared() > 0.01 else DECELERATION
	if not is_on_floor():
		rate = AIR_ACCELERATION
	horizontal = horizontal.move_toward(target_velocity, rate * delta)
	if not is_on_floor() and horizontal.length_squared() > 0.01:
		horizontal = _clamp_airborne_turn(horizontal)

	if _weapon:
		var lunge := _weapon.get_attack_lunge_velocity()
		if lunge.length_squared() > 0.01:
			horizontal += lunge

	if locked_on:
		var dodging := _dodge != null and _dodge.is_dodging
		horizontal = LockOnMovement.apply_orbit_radius_correction(
			self, _lock_on, input_dir, horizontal, delta, dodging
		)

	velocity.x = horizontal.x
	velocity.z = horizontal.z

	var attacking: bool = _weapon != null and _weapon.is_attacking
	if locked_on:
		var target := LockOnMovement.get_target(_lock_on)
		LockOnMovement.update_facing_toward_target(_facing, target, delta)
	elif not attacking and direction.length_squared() > 0.01 and _facing:
		var target_angle := LockOnMovement.world_direction_to_local_facing_y(self, direction)
		_facing.rotation.y = lerp_angle(
			_facing.rotation.y, target_angle, ROTATION_SPEED * rotation_cap_mult * delta
		)

	move_and_slide()
	fall_height = _update_floor_state()
	if fall_height > 0.0:
		_on_landed(fall_height)
	_update_footstep_vfx(delta)
	_update_character_animation(delta, fall_height)


func _update_floor_state() -> float:
	var on_floor_now := is_on_floor()
	var fall_height := 0.0
	if not _was_on_floor and on_floor_now:
		fall_height = maxf(0.0, _fall_start_y - global_position.y)
	if _was_on_floor and not on_floor_now:
		_fall_start_y = global_position.y
		var flat := Vector3(velocity.x, 0.0, velocity.z)
		_airborne_velocity_dir = flat.normalized() if flat.length_squared() > 0.01 else get_facing_direction()
	_was_on_floor = on_floor_now
	return fall_height


func _on_landed(fall_height: float) -> void:
	if fall_height < LAND_SOFT_HEIGHT:
		play_footstep_effects()
		return
	if fall_height >= LAND_HARD_HEIGHT:
		_landing_lock_timer = LAND_HARD_LOCK
		_landing_penalty_timer = LAND_HARD_LOCK
		var spring := get_node_or_null("CameraPivot/SpringArm3D")
		if spring and spring.has_method("apply_landing_dip"):
			spring.call("apply_landing_dip", LAND_CAMERA_DIP)
	if fall_height >= LAND_DAMAGE_HEIGHT:
		var health := get_node_or_null("Health") as Health
		if health:
			var excess := fall_height - LAND_DAMAGE_HEIGHT
			health.take_damage(4.0 * excess)


func _direction_speed_scale(direction: Vector3) -> float:
	if direction.length_squared() < 0.01:
		return 1.0
	var dot := clampf(_movement_forward_dot(direction), -1.0, 1.0)
	if dot >= 0.0:
		if dot >= 0.70710678:
			return lerpf(
				SPEED_SCALE_STRAFE, SPEED_SCALE_FORWARD, smoothstep(0.70710678, 1.0, dot)
			)
		return lerpf(SPEED_SCALE_STRAFE, SPEED_SCALE_FORWARD, smoothstep(0.0, 0.70710678, dot))
	var abs_dot := absf(dot)
	if abs_dot >= 0.70710678:
		return lerpf(
			SPEED_SCALE_STRAFE, SPEED_SCALE_BACK, smoothstep(0.70710678, 1.0, abs_dot)
		)
	return lerpf(SPEED_SCALE_STRAFE, SPEED_SCALE_BACK, smoothstep(0.0, 0.70710678, abs_dot))


func _movement_forward_dot(direction: Vector3) -> float:
	if direction.length_squared() < 0.01:
		return 1.0
	var facing := get_facing_direction()
	var flat_facing := Vector3(facing.x, 0.0, facing.z)
	var flat_dir := Vector3(direction.x, 0.0, direction.z)
	if flat_facing.length_squared() < 0.01 or flat_dir.length_squared() < 0.01:
		return 1.0
	return flat_facing.normalized().dot(flat_dir.normalized())


func _clamp_airborne_turn(horizontal: Vector3) -> Vector3:
	if _airborne_velocity_dir.length_squared() < 0.01 or horizontal.length_squared() < 0.01:
		return horizontal
	var speed := horizontal.length()
	var desired := horizontal.normalized()
	var base := _airborne_velocity_dir.normalized()
	var max_turn := deg_to_rad(AIR_CONTROL_MAX_TURN_DEG)
	var angle := base.signed_angle_to(desired, Vector3.UP)
	angle = clampf(angle, -max_turn, max_turn)
	return base.rotated(Vector3.UP, angle) * speed


func _get_move_direction(input_dir: Vector2) -> Vector3:
	if LockOnMovement.is_active(_lock_on):
		return LockOnMovement.get_move_direction(
			self, _lock_on, input_dir, _get_camera_relative_direction
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
		return CombatFacing.forward_of(_facing)
	return CombatFacing.forward_of(self)


func get_facing_yaw() -> float:
	if _facing:
		return _facing.rotation.y
	return rotation.y


func play_footstep_effects() -> void:
	var surface := _resolve_footstep_surface()
	var pos := global_position + Vector3(0.0, 0.05, 0.0)
	VfxService.play_footstep(pos, get_facing_direction(), surface)
	AudioDirector.play_sfx("footstep_%s" % surface, pos, String(surface))


func _resolve_footstep_surface() -> StringName:
	_surface_probe_timer -= get_physics_process_delta_time()
	if _surface_probe_timer > 0.0:
		return _cached_surface
	_surface_probe_timer = SURFACE_PROBE_INTERVAL
	var space := get_world_3d().direct_space_state
	var from := global_position + Vector3(0.0, 0.1, 0.0)
	var to := from + Vector3(0.0, -SURFACE_PROBE_LENGTH, 0.0)
	var query := PhysicsRayQueryParameters3D.create(from, to)
	query.collision_mask = 1
	query.exclude = [get_rid()]
	var hit := space.intersect_ray(query)
	if hit.is_empty():
		return _cached_surface
	var collider: Object = hit.get("collider")
	if collider and collider.has_meta("surface"):
		_cached_surface = StringName(str(collider.get_meta("surface")))
	return _cached_surface


## Fallback when animation markers are absent; otherwise footsteps come from clips.
func _update_footstep_vfx(delta: float) -> void:
	if _anim_director and _anim_director.has_method("has_footstep_markers"):
		if _anim_director.call("has_footstep_markers"):
			return
	if not is_on_floor():
		_footstep_timer = 0.0
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if horizontal_speed < 0.35:
		_footstep_timer = 0.0
		return
	var sprinting := PlayerInput.pressed(&"sprint")
	var interval := (
		VfxService.FOOTSTEP_INTERVAL_SPRINT if sprinting else VfxService.FOOTSTEP_INTERVAL_WALK
	)
	_footstep_timer -= delta
	if _footstep_timer > 0.0:
		return
	_footstep_timer = interval
	play_footstep_effects()


func _update_character_animation(_delta: float, fall_height: float) -> void:
	if _anim_director == null:
		return
	var local_dir := Vector2.ZERO
	var horizontal := Vector2(velocity.x, velocity.z)
	if horizontal.length_squared() > 0.04:
		local_dir = LockOnMovement.world_velocity_to_local_facing(self, velocity)
	_anim_director.update_locomotion(
		is_on_floor(),
		velocity,
		PlayerInput.pressed(&"sprint"),
		fall_height,
		local_dir
	)
