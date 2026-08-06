extends Node

const DEFAULT_HITSTOP := 0.09
const DEFAULT_CAMERA_PUNCH := 0.15
const DEFAULT_INTENSITY := 1.0
const HITSTOP_TIME_SCALE := 0.08
const DAMAGE_NUMBER := preload("res://scripts/combat/damage_number.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const COLOR_PARRY := Color(1.0, 0.88, 0.2)
const COLOR_BLOCK := Color(0.45, 0.78, 1.0)

signal hit_landed(target: Node, damage: float)

@export var camera_path: NodePath
@export var feedback_intensity := DEFAULT_INTENSITY

var show_damage_numbers := true

var _orbit_camera: Node
var _anim_director: Node
var _hitstop_timer := 0.0
var _hitstop_restore_scale := 1.0
var _anim_hitstop_timer := 0.0
var _anim_hitstop_restore := 1.0
var _shake_noise: FastNoiseLite


func _ready() -> void:
	_shake_noise = FastNoiseLite.new()
	_shake_noise.noise_type = FastNoiseLite.TYPE_SIMPLEX
	_shake_noise.frequency = 4.0
	_resolve_orbit_camera()
	var guard := get_parent().get_node_or_null("Guard")
	if guard and guard.has_signal("parry_success"):
		guard.parry_success.connect(_on_parry_success)


func _resolve_orbit_camera() -> void:
	if camera_path == NodePath():
		return
	_orbit_camera = get_node_or_null(camera_path)
	if _orbit_camera == null:
		_orbit_camera = get_node_or_null("../" + String(camera_path))


func _director() -> Node:
	if _anim_director == null or not is_instance_valid(_anim_director):
		var body := get_parent()
		_anim_director = body.get_node_or_null("AnimDirector") if body else null
	return _anim_director


func _process(delta: float) -> void:
	if _hitstop_timer > 0.0:
		_hitstop_timer -= delta
		if _hitstop_timer <= 0.0:
			Engine.time_scale = _hitstop_restore_scale
	if _anim_hitstop_timer > 0.0:
		_anim_hitstop_timer -= delta
		if _anim_hitstop_timer <= 0.0:
			var director := _director()
			if director and director.has_method("set_speed_scale"):
				director.call("set_speed_scale", _anim_hitstop_restore)


func on_hit(
	target: Node,
	damage: float,
	direction: Vector3 = Vector3.ZERO,
	damage_type: String = "physical"
) -> void:
	hit_landed.emit(target, damage)
	var weight := clampf(damage / 20.0, 0.85, 1.35)
	_apply_hitstop(weight)
	_apply_camera_punch(direction, weight)
	_apply_vibration()
	_play_hit_sfx(target, direction)
	if show_damage_numbers and target is Node3D:
		_spawn_damage_number(target as Node3D, damage, Vector3.ZERO, damage_type)
	_flash_diorama_body(target as Node3D)


func preview_hitstop_duration(damage: float) -> float:
	if feedback_intensity <= 0.0 or AccessibilitySettings.reduce_hitstop:
		return 0.0
	var weight := clampf(damage / 20.0, 0.85, 1.35)
	return DEFAULT_HITSTOP * feedback_intensity * weight


func on_dodge_iframe() -> void:
	if AudioDirector:
		AudioDirector.play_combat_sfx("dodge_perfect")
	if AchievementService:
		AchievementService.notify("dodge")


func on_hit_received(
	damage: float, direction: Vector3 = Vector3.ZERO, damage_type: String = "physical"
) -> void:
	_apply_hitstop()
	_apply_camera_punch(direction)
	_apply_vibration()
	_play_combat_sfx_at_body("hit")
	_pulse_damage_vignette()
	var body := get_parent() as Node3D
	if show_damage_numbers and body:
		_spawn_damage_number(body, damage, Vector3(-0.2, 0.15, 0.0), damage_type)


func on_hit_blocked(blocker: Node3D, chip_damage: float) -> void:
	_apply_hitstop(0.75)
	_play_combat_sfx_at_body("block", blocker)
	if blocker:
		_flash_diorama_body(blocker, 0.65, Color(0.45, 0.78, 1.0))
		var anchor: Array = VfxService.resolve_combat_anchor(blocker)
		VfxService.play_block(anchor[0], anchor[1])
	if not show_damage_numbers or blocker == null:
		return
	_spawn_combat_text(blocker, "BLOCKED", COLOR_BLOCK)
	if chip_damage > 0.0:
		_spawn_damage_number(blocker, chip_damage, Vector3(0.35, -0.15, 0.0))


func _on_parry_success(_attacker: Node) -> void:
	_apply_hitstop(1.2)
	_play_combat_sfx_at_body("parry")
	if AchievementService:
		AchievementService.notify("parry")
	var body := get_parent() as Node3D
	if body:
		_flash_diorama_body(body, 1.0, COLOR_PARRY)
	if not show_damage_numbers or body == null:
		return
	_spawn_combat_text(body, "PARRIED", COLOR_PARRY)


func _spawn_combat_text(at_node: Node3D, text: String, color: Color) -> void:
	var root := get_tree().current_scene
	if root:
		DAMAGE_NUMBER.spawn_text(at_node.global_position, text, root, color)


func _spawn_damage_number(
	at_node: Node3D,
	damage: float,
	offset: Vector3 = Vector3.ZERO,
	damage_type: String = "physical"
) -> void:
	var root := get_tree().current_scene
	if root:
		DAMAGE_NUMBER.spawn(at_node.global_position + offset, damage, root, damage_type)


func _apply_hitstop(weight: float = 1.0) -> void:
	if feedback_intensity <= 0.0 or AccessibilitySettings.reduce_hitstop:
		return
	var duration := DEFAULT_HITSTOP * feedback_intensity * weight
	_hitstop_timer = maxf(_hitstop_timer, duration)
	if Engine.time_scale >= HITSTOP_TIME_SCALE:
		_hitstop_restore_scale = Engine.time_scale
	Engine.time_scale = HITSTOP_TIME_SCALE
	var director := _director()
	if director and director.has_method("set_speed_scale"):
		_anim_hitstop_timer = maxf(_anim_hitstop_timer, duration)
		if _anim_hitstop_timer == duration:
			_anim_hitstop_restore = 1.0
		director.call("set_speed_scale", 0.05)


func _apply_camera_punch(direction: Vector3 = Vector3.ZERO, weight: float = 1.0) -> void:
	if AccessibilitySettings.reduce_camera_shake or feedback_intensity <= 0.0:
		return
	if _orbit_camera == null:
		_resolve_orbit_camera()
	if _orbit_camera and _orbit_camera.has_method("apply_punch"):
		var strength := DEFAULT_CAMERA_PUNCH * feedback_intensity * weight
		_orbit_camera.call("apply_punch", direction, strength)
		if weight >= 1.1 and _orbit_camera.has_method("apply_shake"):
			_orbit_camera.call("apply_shake", strength * 0.35, 0.11)


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


func _play_hit_sfx(target: Node, direction: Vector3) -> void:
	var cue := "hit"
	if target is Node3D:
		var body := target as Node3D
		if body.has_method("get_enemy_id"):
			var enemy_id: String = body.call("get_enemy_id")
			if enemy_id.contains("shield") or enemy_id.contains("knight"):
				cue = "hit_armor"
	_play_combat_sfx_at_body(cue, target if target is Node3D else null)


func _play_combat_sfx_at_body(cue: String, body: Node3D = null) -> void:
	if not AudioDirector:
		return
	var pos: Variant = null
	if body:
		var anchor: Array = VfxService.resolve_combat_anchor(body)
		pos = anchor[0]
	AudioDirector.play_combat_sfx(cue, pos)


func _flash_diorama_body(body: Node3D, strength: float = 1.0, tint: Color = Color.WHITE) -> void:
	if body == null:
		return
	var visual: Node3D = null
	if body.has_method("get_diorama_visual"):
		visual = body.call("get_diorama_visual") as Node3D
	if visual == null:
		visual = body.get_node_or_null("Facing/DioramaVisual") as Node3D
	if visual == null:
		visual = body.get_node_or_null("DioramaVisual") as Node3D
	if visual == null:
		return
	MaterialFlashScript.flash(visual, {"strength": strength, "tint": tint})
	var anchor: Array = VfxService.resolve_combat_anchor(body)
	VfxService.play_hit_spark(anchor[0], anchor[1])
