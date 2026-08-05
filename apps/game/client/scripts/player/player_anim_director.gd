class_name PlayerAnimDirector
extends DioramaAnimController

## Single place where player gameplay state becomes player animation.
##
## Subclasses the rig controller so AnimationPlayer method tracks resolve
## straight onto this node. Locomotion owns the per-frame call; everything else
## arrives through the existing combat signals, so no combat script needs to
## know that a rig exists.

const DEFAULT_STAGGER := 0.85
const CAMERA_PATH := "CameraPivot/SpringArm3D/Camera3D"
const SPRING_PATH := "CameraPivot/SpringArm3D"

const Viewmodel := preload("res://scripts/art/characters/diorama_viewmodel.gd")
const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")

## How far the viewmodel lags the camera. Low enough to feel attached, high
## enough that a fast mouse flick throws the weapon around a little.
const SWAY_RESPONSE := 9.0
const SWAY_YAW_LIMIT := 0.09
const SWAY_PITCH_LIMIT := 0.07
const BOB_HEIGHT := 0.014

var _viewmodel_root: Node3D
var _viewmodel_anim: DioramaAnimController
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
var _last_health := -1.0
var _was_airborne := false


func _ready() -> void:
	_body = get_parent() as CharacterBody3D
	if _body == null:
		return
	_dodge = _body.get_node_or_null("Dodge")
	_guard = _body.get_node_or_null("Guard")
	_weapon = _body.get_node_or_null("WeaponController")
	_reactions = _body.get_node_or_null("CombatReactions")
	_health = _body.get_node_or_null("Health") as Health
	_spring = _body.get_node_or_null(SPRING_PATH)
	set_profile("player")
	_connect_signals()
	footstep_frame.connect(_on_footstep_frame)
	swing_frame.connect(_on_swing_frame)
	_build_viewmodel()
	sync_camera_mode()


## Builds the first-person arms and slaves them to this director, so gameplay
## code keeps making one animation call regardless of which camera is active.
func _build_viewmodel() -> void:
	var camera := _body.get_node_or_null(CAMERA_PATH) as Camera3D
	if camera == null:
		return
	var theme: int = PixelStyle.PaletteTheme.HUB
	var holder := Viewmodel.build(camera, theme)
	if holder == null:
		return
	_viewmodel_root = Viewmodel.get_root(camera)
	if _viewmodel_root == null:
		return
	_viewmodel_anim = DioramaAnimController.new()
	_viewmodel_anim.name = "ViewmodelAnim"
	add_child(_viewmodel_anim)
	_viewmodel_anim.set_profile("player")
	_viewmodel_anim.set_theme(theme)
	if _weapon != null and _weapon.has_method("get_archetype"):
		_viewmodel_anim.set_weapon(String(_weapon.call("get_archetype")))
	_viewmodel_anim.bind(_viewmodel_root)
	add_mirror(_viewmodel_anim)
	_last_camera_basis = camera.global_transform.basis


## Called on camera toggle: only one of the two rigs may be visible at a time.
func sync_camera_mode() -> void:
	if _spring == null or not _spring.has_method("is_first_person"):
		return
	var first_person := bool(_spring.call("is_first_person"))
	var holder := _viewmodel_root.get_parent() if _viewmodel_root else null
	if holder is Node3D:
		(holder as Node3D).visible = first_person
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
	var poise := _body.get_node_or_null("Poise") as Poise
	if poise:
		poise.poise_damaged.connect(_on_poise_damaged)


func play_heal(duration: float) -> void:
	play_stagger(duration)


func _on_poise_damaged(amount: float, _remaining: float) -> void:
	if amount >= 20.0:
		play_stagger(0.45)
	elif amount >= 8.0:
		play_flinch()


## Called by locomotion after move_and_slide so the pose matches the frame that
## was actually simulated.
func update_locomotion(on_floor: bool, velocity: Vector3, sprinting: bool) -> void:
	if not is_bound():
		return
	if _dodge and bool(_dodge.get("is_dodging")):
		return
	var horizontal_speed := Vector2(velocity.x, velocity.z).length()
	if not on_floor:
		_was_airborne = true
		request_locomotion(&"air", {"vertical_speed": velocity.y})
		return
	if _was_airborne:
		_was_airborne = false
		_start_action(&"land", Priority.DASH)
		return
	if horizontal_speed <= 0.2:
		request_locomotion(&"idle")
		return
	if sprinting:
		request_locomotion(&"run", {"speed": horizontal_speed})
	else:
		request_locomotion(&"walk", {"speed": horizontal_speed})


func _process(delta: float) -> void:
	_update_viewmodel_sway(delta)


## Counter-rotates and bobs the arms so the first-person view has weight. Purely
## additive on top of whatever clip the mirrored controller is playing.
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

	var yaw_delta := wrapf(
		atan2(forward.x, forward.z) - atan2(previous.x, previous.z), -PI, PI
	)
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


## Picks the roll clip from the dash vector expressed in the rig's own frame, so
## a left roll reads as a left roll no matter where the camera is.
func _dash_clip_for(world_dir: Vector3) -> StringName:
	if world_dir.length_squared() < 0.01:
		return &"dash_b"
	var facing := _body.get_node_or_null("Facing") as Node3D
	if facing == null:
		return &"dash_f"
	var forward := -facing.global_transform.basis.z
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
	play_stagger(DEFAULT_STAGGER)


func _on_attack_started(attack_name: String) -> void:
	if _weapon == null or not _weapon.has_method("get_current_attack_phases"):
		return
	var phases: Dictionary = _weapon.call("get_current_attack_phases")
	var startup := float(phases.get("startup", 0.2))
	var active := float(phases.get("active", 0.15))
	var recovery := float(phases.get("recovery", 0.3))
	if attack_name.begins_with("heavy"):
		play_heavy_attack(startup, active, recovery)
	elif attack_name.begins_with("bow"):
		play_attack(startup, active, recovery, &"attack_shoot")
	else:
		play_attack(startup, active, recovery)


func _on_weapon_changed(archetype: String) -> void:
	set_weapon(archetype, archetype)


func _on_health_changed(current: float, _max_value: float) -> void:
	var previous := _last_health
	_last_health = current
	if previous < 0.0 or current >= previous or current <= 0.0:
		return
	if _guard and bool(_guard.get("is_blocking")):
		play_block_impact()
		return
	play_flinch()


func _on_footstep_frame() -> void:
	if _body == null or not _body.is_on_floor():
		return
	var facing := Vector3.FORWARD
	if _body.has_method("get_facing_direction"):
		facing = _body.call("get_facing_direction")
	VfxService.play_footstep(_body.global_position + Vector3(0.0, 0.05, 0.0), facing)


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
	var first_person := spring != null and spring.has_method("is_first_person") and spring.call("is_first_person")
	CharacterSkin.sync_first_person_weapon_shadows(_visual, first_person)


func revive() -> void:
	super.revive()
	sync_camera_mode()
	var facing := _body.get_node_or_null("Facing") as Node3D
	var spring := _body.get_node_or_null(SPRING_PATH)
	if facing and spring and spring.has_method("is_first_person"):
		CharacterSkin.apply_first_person(facing, bool(spring.call("is_first_person")))
