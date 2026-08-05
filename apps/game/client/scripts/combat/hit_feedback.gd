extends Node

const DEFAULT_HITSTOP := 0.06
const DEFAULT_CAMERA_PUNCH := 0.15
const DEFAULT_INTENSITY := 1.0
const DAMAGE_NUMBER := preload("res://scripts/combat/damage_number.gd")
const COLOR_PARRY := Color(1.0, 0.88, 0.2)
const COLOR_BLOCK := Color(0.45, 0.78, 1.0)

signal hit_landed(target: Node, damage: float)

@export var camera_path: NodePath
@export var feedback_intensity := DEFAULT_INTENSITY

var show_damage_numbers := true

var _camera: Camera3D
var _hitstop_timer := 0.0
var _anim_director: Node
var _shake_timer := 0.0
var _shake_strength := 0.0
var _shake_direction := Vector3.ZERO
var _shake_noise: FastNoiseLite


func _ready() -> void:
	_shake_noise = FastNoiseLite.new()
	_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_shake_noise.frequency = 4.0
	if camera_path:
		_camera = get_node_or_null(camera_path) as Camera3D
	var body := get_parent() as CharacterBody3D
	if body:
		_anim_director = body.get_node_or_null("AnimDirector")
	var guard := get_parent().get_node_or_null("Guard")
	if guard and guard.has_signal("parry_success"):
		guard.parry_success.connect(_on_parry_success)


func _process(delta: float) -> void:
	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		_apply_animation_speed()
	else:
		_restore_animation_speed()
	_apply_camera_shake(delta)


func on_hit(target: Node, damage: float, direction: Vector3 = Vector3.ZERO) -> void:
	hit_landed.emit(target, damage)
	_apply_local_hitstop()
	_apply_camera_punch(direction)
	_apply_vibration()
	_play_sfx_hook()
	if show_damage_numbers and target is Node3D:
		_spawn_damage_number(target as Node3D, damage)


func on_hit_received(damage: float, direction: Vector3 = Vector3.ZERO) -> void:
	_apply_local_hitstop()
	_apply_camera_punch(direction)
	_apply_vibration()
	_play_sfx_hook()
	_pulse_damage_vignette()
	if show_damage_numbers:
		var body := get_parent() as Node3D
		if body:
			_spawn_damage_number(body, damage, Vector3(-0.2, 0.15, 0.0))


func on_hit_blocked(blocker: Node3D, chip_damage: float) -> void:
	if not show_damage_numbers or blocker == null:
		return
	_spawn_combat_text(blocker, "BLOCKED", COLOR_BLOCK)
	if chip_damage > 0.0:
		_spawn_damage_number(blocker, chip_damage, Vector3(0.35, -0.15, 0.0))


func _on_parry_success(_attacker: Node) -> void:
	if not show_damage_numbers:
		return
	var body := get_parent() as Node3D
	if body:
		_spawn_combat_text(body, "PARRIED", COLOR_PARRY)


func _spawn_combat_text(at_node: Node3D, text: String, color: Color) -> void:
	var root := get_tree().current_scene
	if root:
		DAMAGE_NUMBER.spawn_text(at_node.global_position, text, root, color)


func _spawn_damage_number(at_node: Node3D, damage: float, offset: Vector3 = Vector3.ZERO) -> void:
	var root := get_tree().current_scene
	if root:
		DAMAGE_NUMBER.spawn(at_node.global_position + offset, damage, root)


func _apply_local_hitstop() -> void:
	_hitstop_timer = maxf(_hitstop_timer, DEFAULT_HITSTOP * feedback_intensity)
	_apply_animation_speed()


func _apply_animation_speed() -> void:
	if _anim_director and _anim_director.has_method("set_speed_scale"):
		_anim_director.call("set_speed_scale", 0.05)


func _restore_animation_speed() -> void:
	if _anim_director and _anim_director.has_method("set_speed_scale"):
		_anim_director.call("set_speed_scale", 1.0)


func _apply_camera_punch(direction: Vector3 = Vector3.ZERO) -> void:
	if AccessibilitySettings.reduce_camera_shake:
		return
	var dir := direction
	if dir.length_squared() < 0.01 and _camera:
		dir = -_camera.global_transform.basis.z
	if dir.length_squared() > 0.01:
		_shake_direction = dir.normalized()
	_shake_strength = DEFAULT_CAMERA_PUNCH * feedback_intensity
	_shake_timer = 0.11


func _apply_camera_shake(delta: float) -> void:
	if _camera == null or _shake_timer <= 0.0:
		if _camera:
			_camera.h_offset = 0.0
			_camera.v_offset = 0.0
		return
	if AccessibilitySettings.reduce_camera_shake:
		_shake_timer = 0.0
		_camera.h_offset = 0.0
		_camera.v_offset = 0.0
		return
	_shake_timer -= delta
	var t := 1.0 - clampf(_shake_timer / 0.11, 0.0, 1.0)
	var side := _shake_direction.cross(Vector3.UP)
	if side.length_squared() < 0.01:
		side = Vector3.RIGHT
	else:
		side = side.normalized()
	var noise := _shake_noise.get_noise_1d(Time.get_ticks_msec() * 0.02)
	var amp := _shake_strength * (1.0 - t)
	_camera.h_offset = side.x * noise * amp + _shake_direction.x * amp * 0.35
	_camera.v_offset = absf(noise) * amp * 0.55


func _apply_vibration() -> void:
	var intensity := AccessibilitySettings.vibration_intensity
	if intensity <= 0.0:
		return
	var joypads := Input.get_connected_joypads()
	if joypads.is_empty():
		return
	Input.start_joy_vibration(int(joypads[0]), 0.0, intensity * 0.45, 0.12)


func _pulse_damage_vignette() -> void:
	if PixelDioramaViewport and PixelDioramaViewport.has_method("pulse_damage_vignette"):
		PixelDioramaViewport.call("pulse_damage_vignette", 0.72 * feedback_intensity)


func _play_sfx_hook() -> void:
	if AudioDirector:
		AudioDirector.play_combat_sfx("hit")
