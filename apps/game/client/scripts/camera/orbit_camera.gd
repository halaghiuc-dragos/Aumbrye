extends SpringArm3D
class_name OrbitCamera

const MOUSE_SENSITIVITY_BASE := 0.003
const STICK_SENSITIVITY_BASE := 2.5
const THIRD_PERSON_MIN_PITCH := deg_to_rad(-45.0)
const THIRD_PERSON_MAX_PITCH := deg_to_rad(60.0)
const FIRST_PERSON_MIN_PITCH := deg_to_rad(-80.0)
const FIRST_PERSON_MAX_PITCH := deg_to_rad(80.0)
const MIN_ZOOM := 3.2
const MAX_ZOOM := 5.2
const ZOOM_STEP := 0.25
const FIRST_PERSON_LENGTH := 0.0
const FIRST_PERSON_FOV := 82.0
const FIRST_PERSON_NEAR := 0.02
const THIRD_PERSON_NEAR := 0.05
const CAMERA_MODE_BLEND_TIME := 0.22
const SPRINT_FOV_GAIN := 6.0
const SPRINT_FOV_ATTACK := 2.6
const SPRINT_FOV_RELEASE := 7.0
const SHOULDER_OFFSET_X := 0.45
const SHOULDER_OFFSET_BLEND := 8.0
const ARM_PULL_IN_RATE := 24.0
const ARM_PUSH_OUT_RATE := 6.0
const LOCK_YAW_RATE := 9.0
const LOCK_PITCH_RATE := 7.0
const LOCK_FRAME_BIAS := 0.62
const LOCK_CLOSE_RANGE := 4.5
const LOCK_CLOSE_DOLLY := 0.9
const LOCK_SWITCH_MOUSE := 0.5
const LOCK_SWITCH_DECAY := 6.0

## `RG-01`: composes with (does not replace) the lock-on dolly/FOV above -- both add onto the same
## `spring_length`/`fov` so aiming while locked on pulls in further rather than fighting lock-on.
const AIM_DOLLY := 0.8
const AIM_FOV_REDUCTION_DEG := 8.0
const AIM_SHOULDER_EXTRA := 0.15
const AIM_BLEND_RATE := 6.0

@export var yaw_pivot_path: NodePath
@export var facing_path: NodePath = NodePath("../../Facing")

const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const PixelCameraSnapScript := preload("res://scripts/art/pipeline/pixel_camera_snap.gd")

var _pitch := 0.0
var _target_zoom := 4.0
var _saved_third_person_zoom := 4.0
var _smoothed_arm_length := 4.0
var _yaw_pivot: Node3D
var _facing: Node3D
var _camera: Camera3D
var _first_person := false
var _fp_blend := 0.0
var _lock_on_active := false
var _lock_focus := Vector3.ZERO
var _lock_pivot_base := Vector3(0.0, 1.6, 0.0)
var _lock_pivot_offset := Vector3.ZERO
const LOCK_PITCH_MOUSE_MAX := deg_to_rad(28.0)

var _lock_pitch_bias := 0.0
var _lock_dolly := 0.0
var _lock_switch_travel := 0.0
var _shoulder_x := 0.0

var _aim_active := false
var _aim_blend := 0.0

var _shake_offset := Vector3.ZERO
var _shake_timer := 0.0
var _shake_duration := 0.11
var _shake_strength := 0.0
var _punch_offset := Vector3.ZERO
var _punch_timer := 0.0
var _landing_dip := 0.0
var _death_framing := false
const DEATH_FRAMING_DOLLY := 0.12
var _fov_kick := 0.0
var _sprint_fov := 0.0

## `BS-02`: boss-entrance framing. A separate mode from lock-on -- it drives yaw/pitch/zoom directly
## rather than through player look input, and runs while `PlayerInput` camera input is blocked by the
## caller, so there is no fight over who owns the spring arm during the sequence.
const INTRO_ORBIT_RATE := deg_to_rad(8.0)
const INTRO_FRAME_YAW_RATE := 2.0
const INTRO_FRAME_PITCH_RATE := 2.0
const INTRO_PULLBACK_ZOOM := 2.4
const INTRO_PITCH := deg_to_rad(18.0)
var _intro_active := false
var _intro_timer := 0.0
var _intro_target: Node3D
var _saved_intro_zoom := 0.0

## `VS-09`: the two other set-piece framings the plan asked for alongside the boss intro --
## an execution pulls the camera in tight for the kill, a reveal turns to look at what just
## opened. Both are short, skippable-by-timeout, and never touch player control outside the window
## the caller already owns (i-frames for an execution, a beat after a gate opens for a reveal).
const EXECUTION_PULL_ZOOM := -1.0
const EXECUTION_ORBIT_RATE := deg_to_rad(14.0)
const EXECUTION_FRAME_RATE := 5.0
const EXECUTION_PITCH := deg_to_rad(10.0)
var _execution_active := false
var _execution_timer := 0.0
var _execution_target: Node3D
var _saved_execution_zoom := 0.0

const REVEAL_FRAME_RATE := 3.0
var _reveal_active := false
var _reveal_timer := 0.0
var _reveal_point := Vector3.ZERO


## The SpringArm3D's own transform must only ever be written from `_physics_process`. With 3D
## physics interpolation on, Godot interpolates a physics-driven node between ticks, and a write
## from any other callback fights that and reintroduces judder. Mouse deltas arrive at render
## cadence, so they are buffered here and consumed in `_physics_process`.
var _pending_mouse_yaw := 0.0
var _pending_mouse_pitch := 0.0


func _ready() -> void:
	_target_zoom = spring_length
	_saved_third_person_zoom = spring_length
	_smoothed_arm_length = spring_length
	collision_mask = 1
	if yaw_pivot_path:
		_yaw_pivot = get_node(yaw_pivot_path) as Node3D
	if facing_path:
		_facing = get_node_or_null(facing_path) as Node3D
	_camera = get_node_or_null("Camera3D") as Camera3D
	if _camera:
		# The arm stays interpolated; the camera hanging off it must not be. Shoulder offset, optics,
		# shake and the pixel snap are all applied in `_process` by design, and the snap cannot work
		# if the engine interpolates the camera back off the pixel grid afterwards.
		_camera.physics_interpolation_mode = Node.PHYSICS_INTERPOLATION_MODE_OFF
	if LocalSave.is_first_person_camera():
		_apply_first_person(true)
	else:
		_update_spring_collision()
	AccessibilitySettings.connect_settings_changed(_on_accessibility_settings_changed)
	_capture_mouse_if_allowed()


func _exit_tree() -> void:
	AccessibilitySettings.disconnect_settings_changed(_on_accessibility_settings_changed)


func _on_accessibility_settings_changed() -> void:
	_apply_camera_optics()


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("toggle_camera"):
		if _lock_on_active:
			_break_player_lock()
		_toggle_camera_mode()
		return
	if not _first_person:
		if event.is_action_pressed("zoom_in"):
			_target_zoom = clampf(_target_zoom - ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
		if event.is_action_pressed("zoom_out"):
			_target_zoom = clampf(_target_zoom + ZOOM_STEP, MIN_ZOOM, MAX_ZOOM)
	if event is InputEventMouseMotion and Input.get_mouse_mode() == Input.MOUSE_MODE_CAPTURED:
		if _lock_on_active:
			_apply_lock_pitch_look(-event.relative.y * _mouse_sensitivity())
			_accumulate_lock_switch(-event.relative.x * _mouse_sensitivity())
			get_viewport().set_input_as_handled()
			return
		_pending_mouse_yaw += -event.relative.x * _mouse_sensitivity()
		_pending_mouse_pitch += -event.relative.y * _mouse_sensitivity()


func _physics_process(delta: float) -> void:
	if _intro_active:
		_update_intro_framing(delta)
		_update_arm_length(delta)
		return
	if _execution_active:
		_update_execution_framing(delta)
		_update_arm_length(delta)
		return
	if _reveal_active:
		_update_reveal_framing(delta)
		_update_arm_length(delta)
		return
	if _pending_mouse_yaw != 0.0 or _pending_mouse_pitch != 0.0:
		_apply_look(_pending_mouse_yaw, _pending_mouse_pitch)
		_pending_mouse_yaw = 0.0
		_pending_mouse_pitch = 0.0
	if not _lock_on_active:
		var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
		if stick.length_squared() > 0.01:
			var magnitude := stick.length()
			var curved := _stick_curve_magnitude(
				magnitude,
				AccessibilitySettings.camera_stick_deadzone,
				AccessibilitySettings.camera_stick_curve
			)
			if curved > 0.0:
				var direction := stick / magnitude
				var sens := _stick_sensitivity() * curved
				_apply_look(-direction.x * sens * delta, direction.y * sens * delta)
	_update_mode_blend(delta)
	_update_aim_blend(delta)
	_update_arm_length(delta)


func _process(delta: float) -> void:
	_update_camera_effects(delta)
	_apply_shoulder_offset(delta)
	_apply_camera_optics()
	_apply_camera_effects_transform()


func _update_mode_blend(delta: float) -> void:
	var target_blend := 1.0 if _first_person else 0.0
	var blend_rate := 1.0 / maxf(CAMERA_MODE_BLEND_TIME, 0.001)
	_fp_blend = move_toward(_fp_blend, target_blend, blend_rate * delta)
	_reclamp_pitch()


func _update_aim_blend(delta: float) -> void:
	var target := 1.0 if _aim_active else 0.0
	_aim_blend = move_toward(_aim_blend, target, AIM_BLEND_RATE * delta)


## `RG-01`: parallel to `set_lock_on_active` -- a separate flag rather than a second camera mode,
## so aiming while locked on stacks its dolly/FOV pull on top of lock-on's own.
func set_aim_active(active: bool) -> void:
	_aim_active = active


func _update_arm_length(delta: float) -> void:
	var ideal := lerpf(_target_zoom, FIRST_PERSON_LENGTH, _fp_blend)
	if _death_framing:
		ideal += DEATH_FRAMING_DOLLY
	ideal += _lock_dolly
	ideal += _aim_blend * AIM_DOLLY
	# Smoothed toward the *desired* length, never toward `get_hit_length()`. That reports the last
	# completed query, which ran with the previous `spring_length`, so feeding it back makes the
	# shortened value the new ceiling — a one-way ratchet the arm can never climb out of.
	# Collision is the SpringArm's own job; `spring_length` is only the maximum it may extend to.
	var rate := ARM_PULL_IN_RATE if ideal < _smoothed_arm_length else ARM_PUSH_OUT_RATE
	_smoothed_arm_length = lerpf(_smoothed_arm_length, ideal, clampf(rate * delta, 0.0, 1.0))
	spring_length = _smoothed_arm_length


func _min_pitch() -> float:
	return lerpf(THIRD_PERSON_MIN_PITCH, FIRST_PERSON_MIN_PITCH, _fp_blend)


func _max_pitch() -> float:
	return lerpf(THIRD_PERSON_MAX_PITCH, FIRST_PERSON_MAX_PITCH, _fp_blend)


func _third_person_fov() -> float:
	return AccessibilitySettings.camera_fov


func _first_person_fov() -> float:
	return AccessibilitySettings.camera_fov * (FIRST_PERSON_FOV / AccessibilitySettings.CAMERA_FOV_DEFAULT)


func _mouse_sensitivity() -> float:
	return MOUSE_SENSITIVITY_BASE * AccessibilitySettings.camera_mouse_sensitivity


func _stick_sensitivity() -> float:
	return STICK_SENSITIVITY_BASE * AccessibilitySettings.camera_stick_sensitivity


func _invert_y() -> bool:
	return AccessibilitySettings.camera_invert_y


static func stick_curve_magnitude(
	magnitude: float, deadzone: float, curve: float
) -> float:
	if magnitude <= deadzone:
		return 0.0
	var span := maxf(1.0 - deadzone, 0.0001)
	var t := clampf((magnitude - deadzone) / span, 0.0, 1.0)
	return pow(t, curve)


func _stick_curve_magnitude(magnitude: float, deadzone: float, curve: float) -> float:
	return stick_curve_magnitude(magnitude, deadzone, curve)


func _reclamp_pitch() -> void:
	_pitch = clampf(_pitch, _min_pitch(), _max_pitch())
	rotation.x = _pitch


func _apply_look(yaw_delta: float, pitch_delta: float) -> void:
	if _yaw_pivot:
		_yaw_pivot.rotate_y(yaw_delta)
	var pitch_sign := -1.0 if _invert_y() else 1.0
	_pitch = clampf(_pitch + pitch_delta * pitch_sign, _min_pitch(), _max_pitch())
	rotation.x = _pitch


func _apply_lock_pitch_look(pitch_delta: float) -> void:
	var pitch_sign := -1.0 if _invert_y() else 1.0
	_lock_pitch_bias = clampf(
		_lock_pitch_bias + pitch_delta * pitch_sign, -LOCK_PITCH_MOUSE_MAX, LOCK_PITCH_MOUSE_MAX
	)


func snap_look_direction(world_direction: Vector3) -> void:
	var dir := world_direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001 or _yaw_pivot == null:
		return
	dir = dir.normalized()
	var yaw := _yaw_for_look_direction(dir)
	_yaw_pivot.rotation.y = yaw
	_yaw_pivot.reset_physics_interpolation()
	reset_physics_interpolation()

func set_lock_on_active(active: bool) -> void:
	_lock_on_active = active
	_lock_switch_travel = 0.0
	if active:
		_lock_pivot_offset = Vector3.ZERO
		_lock_pitch_bias = 0.0
		if _yaw_pivot:
			_yaw_pivot.position = _lock_pivot_base
			_yaw_pivot.reset_physics_interpolation()
	else:
		_lock_focus = Vector3.ZERO
		_lock_pivot_offset = Vector3.ZERO
		_lock_pitch_bias = 0.0
		_lock_dolly = 0.0
		if _yaw_pivot:
			_yaw_pivot.position = _lock_pivot_base
			_yaw_pivot.reset_physics_interpolation()


func update_lock_on_frame(focus_world: Vector3, player_eye: Vector3, delta: float) -> void:
	_lock_focus = focus_world
	if not _lock_on_active or _yaw_pivot == null:
		return
	var to_target := focus_world - player_eye
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() < 0.0001:
		return
	var planar := flat.length()
	flat /= planar

	var yaw_blend := clampf(delta * LOCK_YAW_RATE, 0.0, 1.0)
	var target_yaw := _yaw_for_look_direction(flat, not _lock_on_active)
	_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, target_yaw, yaw_blend)

	var frame_point := player_eye.lerp(focus_world, LOCK_FRAME_BIAS)
	var pivot_world := _yaw_pivot.global_position
	var to_frame := frame_point - pivot_world
	var frame_planar := Vector2(to_frame.x, to_frame.z).length()
	var wanted_pitch := 0.0
	if frame_planar > 0.05:
		wanted_pitch = atan2(to_frame.y, frame_planar)
	wanted_pitch = clampf(
		wanted_pitch + _lock_pitch_bias, _min_pitch(), _max_pitch()
	)
	var pitch_blend := clampf(delta * LOCK_PITCH_RATE, 0.0, 1.0)
	_pitch = lerpf(_pitch, wanted_pitch, pitch_blend)
	rotation.x = _pitch

	var close := clampf(1.0 - planar / LOCK_CLOSE_RANGE, 0.0, 1.0)
	_lock_dolly = lerpf(_lock_dolly, close * LOCK_CLOSE_DOLLY, pitch_blend)
	_lock_switch_travel *= maxf(0.0, 1.0 - LOCK_SWITCH_DECAY * delta)


func _accumulate_lock_switch(yaw_delta: float) -> void:
	if not _lock_on_active:
		return
	if signf(yaw_delta) != signf(_lock_switch_travel):
		_lock_switch_travel = 0.0
	_lock_switch_travel += yaw_delta
	if absf(_lock_switch_travel) < LOCK_SWITCH_MOUSE:
		return
	var direction := -1 if _lock_switch_travel > 0.0 else 1
	_lock_switch_travel = 0.0
	var body := _get_player_body()
	if body == null:
		return
	var lock_on := body.get_node_or_null("LockOn")
	if lock_on and lock_on.has_method("switch_target"):
		lock_on.call("switch_target", direction)


func _yaw_for_look_direction(flat_dir: Vector3, apply_fp_offset: bool = true) -> float:
	var yaw := atan2(-flat_dir.x, -flat_dir.z)
	if _first_person and apply_fp_offset:
		yaw += PI
	return yaw


func snap_camera_forward(world_forward: Vector3) -> void:
	var fwd := world_forward
	if fwd.length_squared() < 0.0001:
		return
	fwd = fwd.normalized()
	if _yaw_pivot:
		var flat := Vector3(fwd.x, 0.0, fwd.z)
		if flat.length_squared() > 0.0001:
			flat = flat.normalized()
			var yaw := atan2(-flat.x, -flat.z)
			if _first_person:
				yaw += PI
			_yaw_pivot.rotation.y = yaw
			_yaw_pivot.reset_physics_interpolation()
	_pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)), _min_pitch(), _max_pitch())
	rotation.x = _pitch
	reset_physics_interpolation()


func is_first_person() -> bool:
	return _first_person


func capture_state() -> Dictionary:
	var lock_path := NodePath()
	var body := _get_player_body()
	if body and _lock_on_active:
		var lock_on := body.get_node_or_null("LockOn")
		if lock_on and lock_on.is_locked and lock_on.current_target:
			lock_path = body.get_path_to(lock_on.current_target)
	return {
		"yaw": _yaw_pivot.rotation.y if _yaw_pivot else 0.0,
		"pitch": _pitch,
		"zoom": _target_zoom,
		"firstPerson": _first_person,
		"lockTargetPath": lock_path,
	}


func apply_state(state: Dictionary) -> void:
	if state.is_empty():
		return
	if _yaw_pivot and state.has("yaw"):
		_yaw_pivot.rotation.y = float(state.get("yaw", _yaw_pivot.rotation.y))
		_yaw_pivot.reset_physics_interpolation()
	if state.has("pitch"):
		_pitch = float(state.get("pitch", _pitch))
		_reclamp_pitch()
	if state.has("zoom"):
		_target_zoom = float(state.get("zoom", _target_zoom))
		spring_length = _target_zoom
		_smoothed_arm_length = _target_zoom
	reset_physics_interpolation()
	if state.has("firstPerson"):
		_apply_first_person(bool(state.get("firstPerson", _first_person)))
	if state.has("lockTargetPath"):
		var path := state.get("lockTargetPath", NodePath()) as NodePath
		if path != NodePath():
			var body := _get_player_body()
			if body:
				var target := body.get_node_or_null(path) as Node3D
				var lock_on := body.get_node_or_null("LockOn")
				if target and lock_on and lock_on.has_method("request_lock"):
					lock_on.call("request_lock", target)


func apply_shake(strength: float, duration: float) -> void:
	if AccessibilitySettings.camera_shake_scale() <= 0.0:
		return
	_shake_strength = maxf(_shake_strength, strength * AccessibilitySettings.camera_shake_scale())
	if duration > _shake_timer:
		_shake_duration = duration
	_shake_timer = maxf(_shake_timer, duration)


func apply_punch(direction: Vector3, strength: float) -> void:
	if AccessibilitySettings.camera_shake_scale() <= 0.0:
		return
	var punch := strength * AccessibilitySettings.camera_shake_scale()
	var dir := direction
	if dir.length_squared() < 0.01 and _camera:
		dir = -_camera.global_transform.basis.z
	if dir.length_squared() > 0.01:
		_punch_offset = dir.normalized() * punch
	_punch_timer = maxf(_punch_timer, 0.11)
	if punch >= 0.14:
		_fov_kick = maxf(_fov_kick, 1.5 * punch)


func apply_landing_dip(strength: float) -> void:
	if AccessibilitySettings.camera_shake_scale() <= 0.0:
		return
	_landing_dip = maxf(_landing_dip, strength * AccessibilitySettings.camera_shake_scale())


func enter_death_framing() -> void:
	_death_framing = true


func exit_death_framing() -> void:
	_death_framing = false


func _toggle_camera_mode() -> void:
	_apply_first_person(not _first_person)
	LocalSave.set_first_person_camera(_first_person)


func _apply_first_person(enabled: bool) -> void:
	if enabled == _first_person:
		return
	if enabled:
		_saved_third_person_zoom = (
			_target_zoom if _target_zoom > FIRST_PERSON_LENGTH else _saved_third_person_zoom
		)
		_first_person = true
		_target_zoom = FIRST_PERSON_LENGTH
	else:
		_first_person = false
		_target_zoom = _saved_third_person_zoom
	_update_body_visibility()
	_update_spring_collision()


func _update_spring_collision() -> void:
	collision_mask = 0 if _first_person else 1


func _update_body_visibility() -> void:
	if _facing:
		CharacterSkin.apply_first_person(_facing, _first_person)
	var director := _find_anim_director()
	if director and director.has_method("sync_camera_mode"):
		director.call("sync_camera_mode")


func _apply_shoulder_offset(delta: float) -> void:
	if _camera == null:
		return
	var target := 0.0 if _fp_blend > 0.99 or _lock_on_active else (
		SHOULDER_OFFSET_X + _aim_blend * AIM_SHOULDER_EXTRA
	)
	# Held as a value only, folded into the camera's `h_offset` by
	# `_apply_camera_effects_transform`. Writing `_camera.position.x` instead does not survive: the
	# spring arm owns its child's position and rewrites it every physics tick.
	_shoulder_x = lerpf(_shoulder_x, target, clampf(SHOULDER_OFFSET_BLEND * delta, 0.0, 1.0))


func _apply_camera_optics() -> void:
	if _camera == null:
		return
	var fov := lerpf(_third_person_fov(), _first_person_fov(), _fp_blend) - _fov_kick
	fov -= _aim_blend * AIM_FOV_REDUCTION_DEG
	fov += _sprint_fov * SPRINT_FOV_GAIN
	_camera.fov = fov
	var near := lerpf(THIRD_PERSON_NEAR, FIRST_PERSON_NEAR, _fp_blend)
	_camera.near = near


func _update_camera_effects(delta: float) -> void:
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var t := 1.0 - clampf(_shake_timer / maxf(0.001, _shake_duration), 0.0, 1.0)
		var noise := sin(Time.get_ticks_msec() * 0.04) * cos(Time.get_ticks_msec() * 0.031)
		_shake_offset = Vector3(noise, absf(noise) * 0.55, 0.0) * _shake_strength * (1.0 - t)
	else:
		_shake_offset = Vector3.ZERO
		_shake_strength = lerpf(_shake_strength, 0.0, delta * 9.0)
	if _punch_timer > 0.0:
		_punch_timer -= delta
	else:
		_punch_offset = _punch_offset.lerp(Vector3.ZERO, clampf(delta * 12.0, 0.0, 1.0))
	_landing_dip = lerpf(_landing_dip, 0.0, clampf(delta * 8.0, 0.0, 1.0))
	_fov_kick = lerpf(_fov_kick, 0.0, clampf(delta * 10.0, 0.0, 1.0))
	_update_sprint_fov(delta)


func _update_sprint_fov(delta: float) -> void:
	var target := 0.0
	var body := _get_player_body()
	if body != null:
		var loco := body as Node
		if loco.has_method("get_sprint_blend"):
			target = clampf(float(loco.call("get_sprint_blend")), 0.0, 1.0)
	target *= 1.0 - _fp_blend
	var rate := SPRINT_FOV_ATTACK if target > _sprint_fov else SPRINT_FOV_RELEASE
	_sprint_fov = lerpf(_sprint_fov, target, clampf(delta * rate, 0.0, 1.0))


func _apply_camera_effects_transform() -> void:
	if _camera == null:
		return
	var offset := _shake_offset + _punch_offset + VfxService.consume_shake()
	offset.x += _shoulder_x
	offset.y += _landing_dip
	if _death_framing:
		offset.y += 0.18
	_camera.h_offset = offset.x
	_camera.v_offset = offset.y


func _capture_mouse_if_allowed() -> void:
	if PlayerInput.blocked():
		return
	if PlayerControls and PlayerControls.has_method("capture_mouse_if_allowed"):
		PlayerControls.capture_mouse_if_allowed()
	else:
		Input.set_mouse_mode(Input.MOUSE_MODE_CAPTURED)


func _find_anim_director() -> Node:
	var body := get_parent()
	while body != null and not (body is CharacterBody3D):
		body = body.get_parent()
	if body == null:
		return null
	return body.get_node_or_null("AnimDirector")


func _get_player_body() -> CharacterBody3D:
	var body := get_parent()
	while body != null and not (body is CharacterBody3D):
		body = body.get_parent()
	return body as CharacterBody3D


func _break_player_lock() -> void:
	var body := _get_player_body()
	if body == null:
		return
	var lock_on := body.get_node_or_null("LockOn")
	if lock_on and lock_on.has_method("break_lock"):
		lock_on.call("break_lock")


## `BS-02`: pulls back and slow-orbits to frame `target` for `duration` seconds, then restores
## normal control on its own. The caller is responsible for blocking player camera/movement input
## for the same window (via `PlayerInput.block_groups`) and for cutting the sequence short with
## `skip_intro_framing()` on a skip -- this coroutine does not know about skip input itself.
func play_intro_framing(target: Node3D, duration: float) -> void:
	if target == null or _yaw_pivot == null:
		return
	_intro_target = target
	_intro_timer = 0.0
	_saved_intro_zoom = _target_zoom
	_target_zoom = _target_zoom + INTRO_PULLBACK_ZOOM
	_intro_active = true
	await get_tree().create_timer(maxf(0.1, duration)).timeout
	if is_instance_valid(self):
		_end_intro_framing()


func skip_intro_framing() -> void:
	if not _intro_active:
		return
	_end_intro_framing()


func is_intro_framing_active() -> bool:
	return _intro_active


func _end_intro_framing() -> void:
	_intro_active = false
	_intro_target = null
	_target_zoom = _saved_intro_zoom


func _update_intro_framing(delta: float) -> void:
	_intro_timer += delta
	if _intro_target == null or not is_instance_valid(_intro_target) or _yaw_pivot == null:
		return
	var to_target := _intro_target.global_position - _yaw_pivot.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		# Slow continuous drift layered on top of the facing so the shot reads as an orbit rather
		# than a static lock -- the plan's whole complaint is that the camera does not move.
		var target_yaw := _yaw_for_look_direction(flat, false) + _intro_timer * INTRO_ORBIT_RATE
		var yaw_blend := clampf(delta * INTRO_FRAME_YAW_RATE, 0.0, 1.0)
		_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, target_yaw, yaw_blend)
	var pitch_blend := clampf(delta * INTRO_FRAME_PITCH_RATE, 0.0, 1.0)
	_pitch = lerpf(_pitch, INTRO_PITCH, pitch_blend)
	rotation.x = _pitch


## `VS-09`: 0.6s, pulls in and orbits slightly around the kill -- called during the execution's own
## i-frames, so it never costs the player control they'd otherwise be spending.
func play_execution_framing(target: Node3D) -> void:
	if target == null or _yaw_pivot == null:
		return
	_execution_target = target
	_execution_timer = 0.0
	_saved_execution_zoom = _target_zoom
	_target_zoom = clampf(_target_zoom + EXECUTION_PULL_ZOOM, MIN_ZOOM, MAX_ZOOM)
	_execution_active = true
	await get_tree().create_timer(0.6).timeout
	if is_instance_valid(self):
		_end_execution_framing()


func is_execution_framing_active() -> bool:
	return _execution_active


func _end_execution_framing() -> void:
	_execution_active = false
	_execution_target = null
	_target_zoom = _saved_execution_zoom


func _update_execution_framing(delta: float) -> void:
	_execution_timer += delta
	if _execution_target == null or not is_instance_valid(_execution_target) or _yaw_pivot == null:
		return
	var to_target := _execution_target.global_position - _yaw_pivot.global_position
	var flat := Vector3(to_target.x, 0.0, to_target.z)
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		var target_yaw := (
			_yaw_for_look_direction(flat, false) + _execution_timer * EXECUTION_ORBIT_RATE
		)
		var yaw_blend := clampf(delta * EXECUTION_FRAME_RATE, 0.0, 1.0)
		_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, target_yaw, yaw_blend)
	var pitch_blend := clampf(delta * EXECUTION_FRAME_RATE, 0.0, 1.0)
	_pitch = lerpf(_pitch, EXECUTION_PITCH, pitch_blend)
	rotation.x = _pitch


## `VS-09`: 0.8s, turns to look at a world point -- a secret found or a gate that just opened.
## Takes a `Vector3` rather than a `Node3D` on purpose: the thing being revealed is often not a
## node at all (a wall panel's world position, a socket transform).
func play_reveal_framing(point: Vector3) -> void:
	if _yaw_pivot == null:
		return
	_reveal_point = point
	_reveal_timer = 0.0
	_reveal_active = true
	await get_tree().create_timer(0.8).timeout
	if is_instance_valid(self):
		_end_reveal_framing()


func is_reveal_framing_active() -> bool:
	return _reveal_active


func _end_reveal_framing() -> void:
	_reveal_active = false


func _update_reveal_framing(delta: float) -> void:
	_reveal_timer += delta
	if _yaw_pivot == null:
		return
	var to_point := _reveal_point - _yaw_pivot.global_position
	var flat := Vector3(to_point.x, 0.0, to_point.z)
	if flat.length_squared() > 0.0001:
		flat = flat.normalized()
		var target_yaw := _yaw_for_look_direction(flat, false)
		var yaw_blend := clampf(delta * REVEAL_FRAME_RATE, 0.0, 1.0)
		_yaw_pivot.rotation.y = lerp_angle(_yaw_pivot.rotation.y, target_yaw, yaw_blend)
	var to_point_pitch := to_point.y
	var horiz_dist := Vector3(to_point.x, 0.0, to_point.z).length()
	var wanted_pitch := clampf(atan2(to_point_pitch, maxf(0.5, horiz_dist)), _min_pitch(), _max_pitch())
	var pitch_blend := clampf(delta * REVEAL_FRAME_RATE, 0.0, 1.0)
	_pitch = lerpf(_pitch, wanted_pitch, pitch_blend)
	rotation.x = _pitch
