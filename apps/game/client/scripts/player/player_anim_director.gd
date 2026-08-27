class_name PlayerAnimDirector

extends DioramaAnimController


const DEFAULT_STAGGER := 0.85
const CAMERA_PATH := "CameraPivot/SpringArm3D/Camera3D"
const SPRING_PATH := "CameraPivot/SpringArm3D"
const TURN_FACING_ERROR := 1.4
const Viewmodel := preload("res://scripts/art/characters/diorama_viewmodel.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const DamageInfoScript := preload("res://scripts/combat/damage_info.gd")


const SWAY_RESPONSE := 9.0
const SWAY_YAW_LIMIT := 0.09
const SWAY_PITCH_LIMIT := 0.07
const BOB_HEIGHT := 0.014
const HEAD_LOOK_SPEED := 9.0

var _cached_lock_on: LockOn
var _cached_head: Node3D
var _last_head_look := Vector3(INF, INF, INF)
var _head_look := Vector3.ZERO

var _viewmodel_root: Node3D
var _viewmodel_anim: DioramaAnimController
var _viewmodel_theme: int = PixelStyle.PaletteTheme.HUB
var _spring: Node
var _sway := Vector2.ZERO
var _last_camera_basis := Basis.IDENTITY
var _bob_phase := 0.0
var _body: CharacterBody3D
var _dodge: Node
var _guard: Node
var _weapon: Node
var _reactions: Node
var _health: Health
var _poise: Poise
var _hurtbox: Hurtbox
var _last_health := -1.0
var _was_airborne := false
var _last_weapon_archetype := ""


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		return
	_dodge = _body.get_node_or_null("Dodge")
	_guard = _body.get_node_or_null("Guard")
	_weapon = _body.get_node_or_null("WeaponController")
	_reactions = _body.get_node_or_null("CombatReactions")
	_health = _body.get_node_or_null("Health") as Health
	_poise = _body.get_node_or_null("Poise") as Poise
	_hurtbox = _body.get_node_or_null("Hurtbox") as Hurtbox
	_spring = _body.get_node_or_null(SPRING_PATH)
	if CharacterService:
		_viewmodel_theme = CharacterService.appearance_theme
	set_profile("player")
	_connect_signals()
	footstep_frame.connect(_on_footstep_frame)
	swing_frame.connect(_on_swing_frame)
	_build_viewmodel()
	sync_camera_mode()


func _build_viewmodel() -> void:
	var camera := _body.get_node_or_null(CAMERA_PATH) as Camera3D
	if camera == null:
		return
	if _viewmodel_anim != null and is_instance_valid(_viewmodel_anim):
		remove_mirror(_viewmodel_anim)
		_viewmodel_anim.queue_free()
		_viewmodel_anim = null
	var holder := Viewmodel.build(camera, _viewmodel_theme)
	if holder == null:
		return
	_viewmodel_root = Viewmodel.get_root(camera)
	if _viewmodel_root == null:
		return
	_viewmodel_anim = DioramaAnimController.new()
	_viewmodel_anim.name = "ViewmodelAnim"
	add_child(_viewmodel_anim)
	_viewmodel_anim.expects_hitbox_listeners = false
	_viewmodel_anim.set_profile("player")
	_viewmodel_anim.set_theme(_viewmodel_theme)
	if _weapon != null and _weapon.has_method("get_archetype"):
		_viewmodel_anim.set_weapon(String(_weapon.call("get_archetype")))
	_viewmodel_anim.bind(_viewmodel_root)
	add_mirror(_viewmodel_anim)
	_last_camera_basis = camera.global_transform.basis


func set_viewmodel_theme(theme: int) -> void:
	_viewmodel_theme = theme
	set_theme(theme)
	if _viewmodel_anim:
		_viewmodel_anim.set_theme(theme)
	var camera := _body.get_node_or_null(CAMERA_PATH) as Camera3D if _body else null
	if camera:
		Viewmodel.retint(camera, theme)


func flash_viewmodel(params: Dictionary) -> void:
	if _viewmodel_root and is_instance_valid(_viewmodel_root):
		MaterialFlashScript.flash(_viewmodel_root, params)


func sync_camera_mode() -> void:
	if _spring == null or not _spring.has_method("is_first_person"):
		return
	var first_person := bool(_spring.call("is_first_person"))
	var camera := _body.get_node_or_null(CAMERA_PATH) as Camera3D if _body else null
	if camera:
		var holder := camera.get_node_or_null(Viewmodel.NODE_NAME)
		if holder and holder.has_method("set_pass_visible"):
			holder.call("set_pass_visible", first_person)
	if _visual and is_instance_valid(_visual):
		_visual.visible = true


func _connect_signals() -> void:
	if _dodge:
		if _dodge.has_signal("dash_started"):
			_dodge.dash_started.connect(_on_dash_started)
	if _guard:
		if _guard.has_signal("block_state_changed"):
			_guard.block_state_changed.connect(_on_block_state_changed)
		if _guard.has_signal("parry_success"):
			_guard.parry_success.connect(_on_parry_success)
		if _guard.has_signal("guard_broken"):
			_guard.guard_broken.connect(_on_guard_broken)
	if _weapon:
		if _weapon.has_signal("attack_started"):
			_weapon.attack_started.connect(_on_attack_started)
		if _weapon.has_signal("weapon_changed"):
			_weapon.weapon_changed.connect(_on_weapon_changed)
		if _weapon.has_method("get_archetype"):
			_on_weapon_changed(String(_weapon.call("get_archetype")))
	if _reactions:
		if _reactions.has_signal("stagger_started"):
			_reactions.stagger_started.connect(_on_stagger_started)
		if _reactions.has_signal("player_died"):
			_reactions.player_died.connect(play_death)
	if _health:
		_last_health = _health.current
		_health.health_changed.connect(_on_health_changed)
	if _hurtbox and not _hurtbox.damaged.is_connected(_on_hurtbox_damaged):
		_hurtbox.damaged.connect(_on_hurtbox_damaged)


func _on_health_changed(current: float, _max_value: float) -> void:
	_last_health = current


func _on_hurtbox_damaged(info: DamageInfo) -> void:
	if info.amount <= 0.0 and info.poise_damage <= 0.0:
		return
	_arbitrate_hit_reaction(info)


func _arbitrate_hit_reaction(info: DamageInfo) -> void:
	if _guard and bool(_guard.get("is_blocking")) and _is_frontal_hit(info.direction):
		play_block_impact()
		return
	if _poise != null and _poise.is_broken():
		return
	if info.poise_damage > 0.0 or info.amount > 0.0:
		play_flinch(info.direction)


func _is_frontal_hit(direction: Vector3) -> bool:
	if direction.length_squared() < 0.01:
		return true
	if _guard and _guard.has_method("_is_frontal_hit"):
		return bool(_guard.call("_is_frontal_hit", direction))
	var facing := _body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return true
	var facing_forward := CombatFacing.forward_of(facing)
	var flat_facing := Vector3(facing_forward.x, 0.0, facing_forward.z)
	if flat_facing.length_squared() < 0.01:
		return true
	var flat_hit := Vector3(direction.x, 0.0, direction.z)
	if flat_hit.length_squared() < 0.01:
		return true
	return flat_facing.normalized().angle_to(-flat_hit.normalized()) <= deg_to_rad(55.0)


func update_locomotion(

	on_floor: bool,
	velocity: Vector3,
	sprinting: bool,
	fall_height: float = 0.0,
	local_dir: Vector2 = Vector2.ZERO
) -> void:
	if not is_bound():
		return
	if _dodge and bool(_dodge.get("is_dodging")):
		return
	if fall_height > 0.0:
		_was_airborne = false
		if fall_height >= 3.5:
			_start_action(&"land_hard" if has_clip(&"land_hard") else &"land", Priority.DASH)
		elif fall_height >= 1.2:
			_start_action(&"land", Priority.DASH)
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not on_floor:
		_was_airborne = true
		var air_clip := &"air_rise" if velocity.y > 1.0 and has_clip(&"air_rise") else &"air_fall"
		if not has_clip(air_clip):
			air_clip = &"air"
		request_locomotion(air_clip, {"vertical_speed": velocity.y})
		return
	if _was_airborne:
		_was_airborne = false
		return
	if horizontal_speed <= 0.2:
		var turn_clip := _turn_clip_if_needed()
		if turn_clip != &"":
			_start_action(turn_clip, Priority.LOCOMOTION)
			return
		request_locomotion(&"idle")
		return
	var clip := _locomotion_clip_for(sprinting, local_dir)
	request_locomotion(clip, {"speed": horizontal_speed})


func _turn_clip_if_needed() -> StringName:
	var facing := _body.get_node_or_null("Facing") as Node3D
	var spring := _body.get_node_or_null(SPRING_PATH)
	if facing == null or spring == null or not spring.has_method("is_first_person"):
		return &""
	if not bool(spring.call("is_first_person")):
		return &""
	var camera := _body.get_node_or_null(CAMERA_PATH) as Camera3D
	if camera == null:
		return &""
	var cam_forward := -camera.global_transform.basis.z
	var body_forward := CombatFacing.forward_of(facing)
	cam_forward.y = 0.0
	body_forward.y = 0.0
	if cam_forward.length_squared() < 0.01 or body_forward.length_squared() < 0.01:
		return &""
	var error := body_forward.normalized().signed_angle_to(cam_forward.normalized(), Vector3.UP)
	if absf(error) < TURN_FACING_ERROR:
		return &""
	return &"turn_l" if error > 0.0 else &"turn_r"


func _locomotion_clip_for(sprinting: bool, local_dir: Vector2) -> StringName:
	var prefix := &"run" if sprinting else &"walk"
	if local_dir.length_squared() < 0.04:
		return prefix
	var x := local_dir.x
	var y := local_dir.y
	if absf(x) >= absf(y):
		var side := &"_r" if x >= 0.0 else &"_l"
		var strafe_clip: StringName = prefix + side
		if has_clip(strafe_clip):
			return strafe_clip
	if y < -0.2:
		var back_clip: StringName = prefix + &"_b"
		if has_clip(back_clip):
			return back_clip
	return prefix


func _process(delta: float) -> void:
	_update_viewmodel_sway(delta)
	_update_head_look(delta)


func bind(visual: Node3D) -> void:
	_cached_head = null
	_last_head_look = Vector3(INF, INF, INF)
	_head_look = Vector3.ZERO
	super.bind(visual)


func _release_head_look(delta: float) -> void:
	if _last_head_look.x == INF or _head_look.is_zero_approx():
		return
	_head_look = _head_look.lerp(Vector3.ZERO, clampf(delta * HEAD_LOOK_SPEED, 0.0, 1.0))
	if _head_look.length_squared() < 0.000001:
		_head_look = Vector3.ZERO
	_write_head_look(_head_look)


func _write_head_look(look_rot: Vector3) -> void:
	if _additive_library == null or not _additive_library.has_animation(&"head_look"):
		return
	var anim := _additive_library.get_animation(&"head_look")
	if anim.get_track_count() > 0 and not look_rot.is_equal_approx(_last_head_look):
		_last_head_look = look_rot
		var rest: Dictionary = _rest_pose.get("Head", {})
		var base_rot: Vector3 = rest.get("rotation", Vector3.ZERO)
		anim.track_set_key_value(0, 0, base_rot + look_rot)
	if _additive_player and _additive_player.current_animation != "head_look":
		_additive_player.play(&"head_look")


func _update_head_look(delta: float) -> void:
	if _visual == null or _additive_player == null:
		return
	var lock_on := _cached_lock_on
	if lock_on == null or not is_instance_valid(lock_on):
		lock_on = _body.get_node_or_null("LockOn") as LockOn
		_cached_lock_on = lock_on
	if lock_on == null or lock_on.current_target == null:
		_release_head_look(delta)
		return
	var head := _cached_head
	if head == null or not is_instance_valid(head):
		head = CharacterSkin.find_part(_visual, "Head")
		_cached_head = head
	if head == null:
		return
	var aim := LockOn.get_target_aim_point(lock_on.current_target)
	var parent := head.get_parent() as Node3D
	if parent == null:
		return
	var rest: Dictionary = _rest_pose.get("Head", {})
	var base_rot: Vector3 = rest.get("rotation", Vector3.ZERO)
	if absf(parent.global_transform.basis.determinant()) < 0.00001:
		return
	var local := (parent.global_transform.affine_inverse() * aim) - head.position
	if local.length_squared() < 0.0001:
		return
	var yaw := atan2(local.x, local.z) - base_rot.y
	var pitch := -atan2(local.y, Vector2(local.x, local.z).length()) - base_rot.x
	var wanted := Vector3(
		clampf(wrapf(pitch, -PI, PI), -0.35, 0.35),
		clampf(wrapf(yaw, -PI, PI), -0.55, 0.55),
		0.0,
	)
	if _last_head_look.x == INF:
		_head_look = wanted
	else:
		_head_look = _head_look.lerp(wanted, clampf(delta * HEAD_LOOK_SPEED, 0.0, 1.0))
	_write_head_look(_head_look)


func _update_viewmodel_sway(delta: float) -> void:
	if _viewmodel_root == null or not _viewmodel_root.is_visible_in_tree():
		return
	var camera := _body.get_node_or_null(CAMERA_PATH) as Camera3D
	if camera == null:
		return
	var basis := camera.global_transform.basis
	var forward := -basis.z
	var previous := -_last_camera_basis.z
	_last_camera_basis = basis
	var yaw_delta := wrapf(atan2(forward.x, forward.z) - atan2(previous.x, previous.z), -PI, PI)
	var pitch_delta := asin(clampf(forward.y, -1.0, 1.0)) - asin(clampf(previous.y, -1.0, 1.0))
	var target := Vector2(
		clampf(-yaw_delta * 1.6, -SWAY_YAW_LIMIT, SWAY_YAW_LIMIT),
		clampf(-pitch_delta * 1.4, -SWAY_PITCH_LIMIT, SWAY_PITCH_LIMIT)
	)
	var blend := clampf(delta * SWAY_RESPONSE, 0.0, 1.0)
	_sway = _sway.lerp(target, blend)
	_viewmodel_root.rotation = Vector3(_sway.y, _sway.x, _sway.x * 0.4)
	var speed := 0.0
	if _body.is_on_floor():
		speed = Vector2(_body.velocity.x, _body.velocity.z).length()
	if speed > 0.25:
		_bob_phase = fmod(_bob_phase + delta * speed * 2.2, TAU)
	else:
		_bob_phase = lerp_angle(_bob_phase, 0.0, blend)
	_viewmodel_root.position = Vector3(
		sin(_bob_phase * 0.5) * BOB_HEIGHT, sin(_bob_phase) * BOB_HEIGHT, 0.0
	)


func _on_dash_started() -> void:
	var direction := &"dash_f"
	if _dodge and _dodge.has_method("get_dash_direction") and _body:
		var world_dir: Vector3 = _dodge.call("get_dash_direction")
		direction = _dash_clip_for(world_dir)
	play_dash(direction)


func _dash_clip_for(world_dir: Vector3) -> StringName:
	if world_dir.length_squared() < 0.01:
		return &"dash_b"
	var facing := _body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return &"dash_f"
	var forward := CombatFacing.forward_of(facing)
	var right := facing.global_transform.basis.x
	var flat := Vector3(world_dir.x, 0.0, world_dir.z).normalized()
	var fwd_dot := forward.dot(flat)
	var right_dot := right.dot(flat)
	if absf(fwd_dot) >= absf(right_dot):
		return &"dash_f" if fwd_dot >= 0.0 else &"dash_b"
	return &"dash_r" if right_dot >= 0.0 else &"dash_l"


func _on_block_state_changed(blocking: bool) -> void:
	set_blocking(blocking)


func _on_parry_success(_target: Node) -> void:
	play_parry()


func _on_guard_broken() -> void:
	play_guard_break()


func _on_stagger_started() -> void:
	var direction := Vector3.ZERO
	var duration := DEFAULT_STAGGER
	if _reactions:
		direction = _reactions.stagger_direction
		duration = float(_reactions.stagger_duration) if _reactions.stagger_duration > 0.0 else DEFAULT_STAGGER
	play_stagger(duration, direction)


func _on_attack_started(attack_name: String) -> void:
	if _weapon == null or not _weapon.has_method("get_current_attack_phases"):
		return
	var phases: Dictionary = _weapon.call("get_current_attack_phases")
	var startup := float(phases.get("startup", 0.2))
	var active := float(phases.get("active", 0.15))
	var recovery := float(phases.get("recovery", 0.3))
	if attack_name == "riposte":
		play_riposte(startup, active, recovery)
	elif attack_name == "backstab":
		play_backstab(startup, active, recovery)
	elif attack_name.begins_with("heavy"):
		play_heavy_attack(startup, active, recovery)
	elif attack_name.begins_with("bow"):
		play_attack(startup, active, recovery, &"attack_shoot")
	else:
		play_attack(startup, active, recovery)


func play_riposte(startup: float, active: float, recovery: float) -> void:
	play_attack(startup, active, recovery, _execution_clip(&"attack_thrust_2"))


func play_backstab(startup: float, active: float, recovery: float) -> void:
	play_attack(startup, active, recovery, _execution_clip(&"attack_thrust"))


func _execution_clip(preferred: StringName) -> StringName:
	if AnimLibrary.ATTACKS.has(preferred):
		return preferred
	if AnimLibrary.ATTACKS.has(&"attack_thrust"):
		return &"attack_thrust"
	return AnimLibrary.heavy_clip_for(_weapon_archetype)


func _on_weapon_changed(archetype: String) -> void:
	var needs_rebind := archetype == "bow" or _last_weapon_archetype == "bow"
	var weapon_id := archetype
	if _weapon and _weapon.has_method("get_weapon_id"):
		var equipped := String(_weapon.call("get_weapon_id"))
		if equipped != "":
			weapon_id = equipped
	set_weapon(weapon_id, archetype)
	if needs_rebind and _visual:
		bind(_visual)
	_last_weapon_archetype = archetype


func _on_footstep_frame() -> void:
	if _body == null or not _body.is_on_floor():
		return
	if _body.has_method("play_footstep_effects"):
		_body.call("play_footstep_effects")


func _on_swing_frame() -> void:
	if _body == null:
		return
	var anchor: Array = VfxService.resolve_combat_anchor(_body)
	VfxService.play_weapon_trail(anchor[0], anchor[1])


func set_weapon(weapon_id: String, archetype: String = "") -> void:
	super.set_weapon(weapon_id, archetype)
	_sync_first_person_weapon_shadows()


func _sync_first_person_weapon_shadows() -> void:
	if _body == null or _visual == null:
		return
	var spring := _body.get_node_or_null(SPRING_PATH)
	var first_person: bool = (
		spring != null
		and spring.has_method("is_first_person")
		and bool(spring.call("is_first_person"))
	)
	CharacterSkin.sync_first_person_weapon_shadows(_visual, first_person)


func revive() -> void:
	super.revive()
	sync_camera_mode()
	var facing := _body.get_node_or_null("Facing") as Node3D
	var spring := _body.get_node_or_null(SPRING_PATH)
	if facing and spring and spring.has_method("is_first_person"):
		CharacterSkin.apply_first_person(facing, bool(spring.call("is_first_person")))
