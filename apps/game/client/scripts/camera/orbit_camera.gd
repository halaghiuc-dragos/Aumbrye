extends SpringArm3D

const MOUSE_SENSITIVITY_BASE := 0.003
const STICK_SENSITIVITY_BASE := 2.5
const THIRD_PERSON_MIN_PITCH := deg_to_rad(-45.0)
const THIRD_PERSON_MAX_PITCH := deg_to_rad(60.0)
const FIRST_PERSON_MIN_PITCH := deg_to_rad(-80.0)
const FIRST_PERSON_MAX_PITCH := deg_to_rad(80.0)
const MIN_ZOOM := 2.5
const MAX_ZOOM := 7.0
const ZOOM_STEP := 0.5
const ZOOM_SPEED := 8.0
const FIRST_PERSON_LENGTH := 0.0
const FIRST_PERSON_FOV := 82.0
const FIRST_PERSON_NEAR := 0.02
const THIRD_PERSON_NEAR := 0.05
const CAMERA_MODE_BLEND_TIME := 0.22
const SHOULDER_OFFSET_X := 0.45
const SHOULDER_OFFSET_BLEND := 8.0
const ARM_PULL_IN_RATE := 24.0
const ARM_PUSH_OUT_RATE := 6.0
const SNAP_DISABLE_WHILE_LOCKED := false

@export var yaw_pivot_path: NodePath
@export var facing_path: NodePath = NodePath("../../Facing")

const CharacterSkin := preload("res://scripts/art/characters/diorama_character_skin.gd")
const PixelCameraSnap := preload("res://scripts/art/pipeline/pixel_camera_snap.gd")

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
const LOCK_PITCH_BIAS_MAX := deg_to_rad(12.0)
const LOCK_PITCH_MOUSE_MAX := deg_to_rad(28.0)

var _lock_pitch_bias := 0.0
var _shoulder_x := 0.0

var _shake_offset := Vector3.ZERO
var _shake_timer := 0.0
var _shake_strength := 0.0
var _punch_offset := Vector3.ZERO
var _punch_timer := 0.0
var _landing_dip := 0.0
var _death_framing := false
var _fov_kick := 0.0
var _snap_base_transform := Transform3D.IDENTITY


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
			get_viewport().set_input_as_handled()
			return
		_apply_look(-event.relative.x * _mouse_sensitivity(), -event.relative.y * _mouse_sensitivity())


func _physics_process(delta: float) -> void:
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
	_update_arm_length(delta)


func _process(delta: float) -> void:
	_update_camera_effects(delta)
	_apply_shoulder_offset(delta)
	_apply_camera_optics()
	_apply_camera_effects_transform()
	_apply_gameplay_pixel_snap()


func _update_mode_blend(delta: float) -> void:
	var target_blend := 1.0 if _first_person else 0.0
	var blend_rate := 1.0 / maxf(CAMERA_MODE_BLEND_TIME, 0.001)
	_fp_blend = move_toward(_fp_blend, target_blend, blend_rate * delta)


func _update_arm_length(delta: float) -> void:
	var ideal := lerpf(_target_zoom, FIRST_PERSON_LENGTH, _fp_blend)
	spring_length = ideal
	var hit_length := ideal
	if collision_mask != 0:
		hit_length = minf(ideal, get_hit_length())
	var target := hit_length
	var rate := ARM_PULL_IN_RATE if target < _smoothed_arm_length else ARM_PUSH_OUT_RATE
	_smoothed_arm_length = lerpf(_smoothed_arm_length, target, clampf(rate * delta, 0.0, 1.0))
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


func get_yaw_basis() -> Basis:
	if _yaw_pivot:
		return Basis(Vector3.UP, _yaw_pivot.global_rotation.y)
	return Basis(Vector3.UP, global_rotation.y)


func snap_look_direction(world_direction: Vector3) -> void:
	var dir := world_direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001 or _yaw_pivot == null:
		return
	dir = dir.normalized()
	var yaw := _yaw_for_look_direction(dir)
	_yaw_pivot.rotation.y = yaw


func blend_look_direction(world_direction: Vector3, blend_rate: float) -> void:
	var dir := world_direction
	dir.y = 0.0
	if dir.length_squared() < 0.0001 or _yaw_pivot == null:
		return
	dir = dir.normalized()
	var target_yaw := _yaw_for_look_direction(dir, not _lock_on_active)
	_yaw_pivot.rotation.y = lerp_angle(
		_yaw_pivot.rotation.y, target_yaw, clampf(blend_rate, 0.0, 1.0)
	)


func set_lock_on_active(active: bool) -> void:
	_lock_on_active = active
	if active:
		_lock_pivot_offset = Vector3.ZERO
		_lock_pitch_bias = 0.0
		if _yaw_pivot:
			_yaw_pivot.position = _lock_pivot_base
	else:
		_lock_focus = Vector3.ZERO
		_lock_pivot_offset = Vector3.ZERO
		_lock_pitch_bias = 0.0
		if _yaw_pivot:
			_yaw_pivot.position = _lock_pivot_base


func update_lock_on_frame(focus_world: Vector3, player_eye: Vector3, delta: float) -> void:
	if _yaw_pivot == null:
		return
	_lock_focus = focus_world
	if _first_person:
		_yaw_pivot.position = _lock_pivot_base
	var to_focus := focus_world - player_eye
	to_focus.y = 0.0
	if to_focus.length_squared() < 0.0001:
		return
	var flat_dir := to_focus.normalized()
	blend_look_direction(flat_dir, 8.0 * delta)

	if not _first_person:
		var player_body := _yaw_pivot.get_parent() as Node3D
		if player_body:
			var local_focus := player_body.to_local(focus_world)
			var local_eye := player_body.to_local(player_eye)
			var local_delta := local_focus - local_eye
			local_delta.y = 0.0
			var planar_dist := local_delta.length()
			if planar_dist > 0.01:
				var local_dir := local_delta / planar_dist
				var shift := clampf(planar_dist * 0.42, 0.35, 2.0)
				var target_offset := Vector3(local_dir.x * shift, 0.0, local_dir.z * shift)
				_lock_pivot_offset = _lock_pivot_offset.lerp(
					target_offset, clampf(6.0 * delta, 0.0, 1.0)
				)
				_yaw_pivot.position = _lock_pivot_base + _lock_pivot_offset

	var pivot_world := _yaw_pivot.global_position
	var aim_dir := (focus_world - pivot_world).normalized()
	var target_pitch := clampf(asin(clampf(aim_dir.y, -1.0, 1.0)), _min_pitch(), _max_pitch())
	var stick := Input.get_vector("look_left", "look_right", "look_up", "look_down")
	_lock_pitch_bias = clampf(
		_lock_pitch_bias + stick.y * LOCK_PITCH_BIAS_MAX * delta * 6.0,
		-LOCK_PITCH_BIAS_MAX,
		LOCK_PITCH_BIAS_MAX
	)
	if absf(stick.y) < 0.15:
		_lock_pitch_bias = lerpf(_lock_pitch_bias, 0.0, clampf(4.0 * delta, 0.0, 1.0))
	target_pitch = clampf(target_pitch + _lock_pitch_bias, _min_pitch(), _max_pitch())
	_pitch = lerpf(_pitch, target_pitch, clampf(8.0 * delta, 0.0, 1.0))
	rotation.x = _pitch


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
	_pitch = clampf(asin(clampf(fwd.y, -1.0, 1.0)), _min_pitch(), _max_pitch())
	rotation.x = _pitch


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
	if state.has("pitch"):
		_pitch = float(state.get("pitch", _pitch))
		rotation.x = _pitch
	if state.has("zoom"):
		_target_zoom = float(state.get("zoom", _target_zoom))
		spring_length = _target_zoom
		_smoothed_arm_length = _target_zoom
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
	if AccessibilitySettings.reduce_camera_shake:
		return
	_shake_strength = maxf(_shake_strength, strength)
	_shake_timer = maxf(_shake_timer, duration)


func apply_punch(direction: Vector3, strength: float) -> void:
	if AccessibilitySettings.reduce_camera_shake:
		return
	var dir := direction
	if dir.length_squared() < 0.01 and _camera:
		dir = -_camera.global_transform.basis.z
	if dir.length_squared() > 0.01:
		_punch_offset = dir.normalized() * strength
	_punch_timer = maxf(_punch_timer, 0.11)
	if strength >= 0.14:
		_fov_kick = maxf(_fov_kick, 1.5 * strength)


func apply_landing_dip(strength: float) -> void:
	if AccessibilitySettings.reduce_camera_shake:
		return
	_landing_dip = maxf(_landing_dip, strength)


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
	var target := 0.0 if _fp_blend > 0.99 else SHOULDER_OFFSET_X
	_shoulder_x = lerpf(_shoulder_x, target, clampf(SHOULDER_OFFSET_BLEND * delta, 0.0, 1.0))
	_camera.position.x = _shoulder_x


func _apply_camera_optics() -> void:
	if _camera == null:
		return
	var fov := lerpf(_third_person_fov(), _first_person_fov(), _fp_blend) - _fov_kick
	_camera.fov = fov
	var near := lerpf(THIRD_PERSON_NEAR, FIRST_PERSON_NEAR, _fp_blend)
	_camera.near = near


func _update_camera_effects(delta: float) -> void:
	if _shake_timer > 0.0:
		_shake_timer -= delta
		var t := 1.0 - clampf(_shake_timer / 0.11, 0.0, 1.0)
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


func _apply_camera_effects_transform() -> void:
	if _camera == null:
		return
	var offset := _shake_offset + _punch_offset + VfxService.consume_shake()
	offset.y += _landing_dip
	if _death_framing:
		offset.y += 0.18
		offset.z += 0.12
	_camera.h_offset = offset.x
	_camera.v_offset = offset.y


func _apply_gameplay_pixel_snap() -> void:
	if _camera == null:
		return
	if not PixelDioramaSettings.gameplay_camera_snap_enabled:
		return
	if SNAP_DISABLE_WHILE_LOCKED and _lock_on_active:
		return
	_snap_base_transform = _camera.global_transform
	PixelDioramaSettings.snap_fov_hint = _camera.fov
	var snapped := PixelCameraSnap.snap_transform(
		_snap_base_transform, _camera.fov, maxf(0.5, _smoothed_arm_length), true
	)
	_camera.global_transform = snapped


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
