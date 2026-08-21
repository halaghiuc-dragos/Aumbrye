extends Node

enum ImpactClass { GLANCING, SOLID, CRITICAL }

const DEFAULT_HITSTOP := 0.09
const DEFAULT_CAMERA_PUNCH := 0.15
const DEFAULT_INTENSITY := 1.0
const HITSTOP_TIME_SCALE := 0.08
const GLANCING_DAMAGE := 15.0
const CRITICAL_DAMAGE := 40.0

const IMPACT_PROFILES := {
	ImpactClass.GLANCING:
	{
		"freeze": 0.04,
		"punch": 0.07,
		"shake": 0.0,
		"shake_time": 0.0,
		"rumble_weak": 0.18,
		"rumble_strong": 0.22,
		"rumble_time": 0.08,
		"audio_layer": "",
	},
	ImpactClass.SOLID:
	{
		"freeze": 0.085,
		"punch": 0.15,
		"shake": 0.05,
		"shake_time": 0.11,
		"rumble_weak": 0.3,
		"rumble_strong": 0.45,
		"rumble_time": 0.12,
		"audio_layer": "",
	},
	ImpactClass.CRITICAL:
	{
		"freeze": 0.17,
		"punch": 0.28,
		"shake": 0.16,
		"shake_time": 0.2,
		"rumble_weak": 0.55,
		"rumble_strong": 0.9,
		"rumble_time": 0.22,
		"audio_layer": "hit_armor",
	},
}
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
var _anim_hitstop_until_ms := 0
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


func _process(_delta: float) -> void:
	# Measured against unscaled wall time, not the delta this callback receives — delta is
	# itself scaled by the hit-stop this timer is tracking, which was BUG-40 (a 0.09s freeze
	# measuring itself on an 0.08x clock runs ~12x long).
	if _anim_hitstop_until_ms > 0 and Time.get_ticks_msec() >= _anim_hitstop_until_ms:
		_anim_hitstop_until_ms = 0
		var director := _director()
		if director and director.has_method("set_speed_scale"):
			director.call("set_speed_scale", _anim_hitstop_restore)


func on_hit(
	target: Node,
	damage: float,
	direction: Vector3 = Vector3.ZERO,
	damage_type: String = "physical",
	impact: int = ImpactClass.SOLID,
	_crit: bool = false
) -> void:
	hit_landed.emit(target, damage)
	_apply_hitstop(impact)
	_apply_camera_punch(direction, impact)
	_apply_vibration(impact)
	_play_hit_sfx(target, direction, impact)
	if show_damage_numbers and target is Node3D:
		_spawn_damage_number(target as Node3D, damage, Vector3.ZERO, damage_type)
	# C-51: this used to also run `_flash_diorama_body(target, 1.0, Color.WHITE, crit)` on the same
	# visual the victim's `Hurtbox._emit_victim_feedback` had just flashed — a flat white,
	# full-strength flash overwriting a careful one that is damage-proportional (strength 0.35→1.0,
	# duration 0.14→0.30) and tinted by damage type. A fire hit and a physical hit looked
	# identical on the target. Same resolution as C-06: the victim side owns victim feedback. This
	# function keeps hitstop, camera punch, rumble, audio and the damage number.


func preview_hitstop_duration(damage: float) -> float:
	if feedback_intensity <= 0.0 or AccessibilitySettings.hitstop_scale() <= 0.0:
		return 0.0
	return _freeze_duration(impact_class_for_damage(damage)) * AccessibilitySettings.hitstop_scale()


func impact_class_for_damage(damage: float) -> int:
	if damage < GLANCING_DAMAGE:
		return ImpactClass.GLANCING
	if damage >= CRITICAL_DAMAGE:
		return ImpactClass.CRITICAL
	return ImpactClass.SOLID


func _profile(impact: int) -> Dictionary:
	return IMPACT_PROFILES.get(impact, IMPACT_PROFILES[ImpactClass.SOLID])


func _freeze_duration(impact: int) -> float:
	return float(_profile(impact).get("freeze", DEFAULT_HITSTOP)) * feedback_intensity


func on_dodge_iframe() -> void:
	if AudioDirector:
		AudioDirector.play_combat_sfx("dodge_perfect")
	if AchievementService:
		AchievementService.notify("dodge")


func on_hit_received(
	damage: float,
	direction: Vector3 = Vector3.ZERO,
	damage_type: String = "physical",
	impact: int = ImpactClass.SOLID
) -> void:
	_apply_hitstop(impact)
	_apply_camera_punch(direction, impact)
	_apply_vibration(impact)
	_play_combat_sfx_at_body("hit")
	var layer := String(_profile(impact).get("audio_layer", ""))
	if layer != "":
		_play_combat_sfx_at_body(layer)
	_pulse_damage_vignette()
	var body := get_parent() as Node3D
	if show_damage_numbers and body:
		_spawn_damage_number(body, damage, Vector3(-0.2, 0.15, 0.0), damage_type)


func on_hit_blocked(blocker: Node3D, chip_damage: float) -> void:
	_apply_hitstop(ImpactClass.GLANCING)
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
	_apply_hitstop(ImpactClass.CRITICAL)
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
	at_node: Node3D, damage: float, offset: Vector3 = Vector3.ZERO, damage_type: String = "physical"
) -> void:
	var root := get_tree().current_scene
	if root:
		DAMAGE_NUMBER.spawn(at_node.global_position + offset, damage, root, damage_type)


func _apply_hitstop(impact: int = ImpactClass.SOLID) -> void:
	if feedback_intensity <= 0.0 or AccessibilitySettings.hitstop_scale() <= 0.0:
		return
	var duration := _freeze_duration(impact) * AccessibilitySettings.hitstop_scale()
	if duration <= 0.0:
		return
	var duration_ms := int(duration * 1000.0)
	# BUG-41: Engine.time_scale has exactly one owner (VfxService). Pushing/releasing by id
	# means a second hit landing mid-freeze extends the existing request instead of caching
	# the already-slowed scale as its own "restore to" value (BUG-39).
	if impact == ImpactClass.CRITICAL:
		VfxService.push_time_scale(&"hitstop", HITSTOP_TIME_SCALE, duration_ms)
	var director := _director()
	if director and director.has_method("set_speed_scale"):
		var until_ms := Time.get_ticks_msec() + duration_ms
		if until_ms > _anim_hitstop_until_ms:
			_anim_hitstop_until_ms = until_ms
			_anim_hitstop_restore = 1.0
		director.call("set_speed_scale", 0.05)


func _apply_camera_punch(direction: Vector3 = Vector3.ZERO, impact: int = ImpactClass.SOLID) -> void:
	if AccessibilitySettings.camera_shake_scale() <= 0.0 or feedback_intensity <= 0.0:
		return
	if _orbit_camera == null:
		_resolve_orbit_camera()
	if _orbit_camera == null or not _orbit_camera.has_method("apply_punch"):
		return
	var profile := _profile(impact)
	var strength := float(profile.get("punch", DEFAULT_CAMERA_PUNCH)) * feedback_intensity
	_orbit_camera.call("apply_punch", direction, strength)
	var shake := float(profile.get("shake", 0.0)) * feedback_intensity
	if shake > 0.0 and _orbit_camera.has_method("apply_shake"):
		_orbit_camera.call("apply_shake", shake, float(profile.get("shake_time", 0.11)))


func _apply_vibration(impact: int = ImpactClass.SOLID) -> void:
	var intensity := AccessibilitySettings.vibration_intensity
	if intensity <= 0.0:
		return
	var joypads := Input.get_connected_joypads()
	if joypads.is_empty():
		return
	var profile := _profile(impact)
	Input.start_joy_vibration(
		int(joypads[0]),
		intensity * float(profile.get("rumble_weak", 0.0)),
		intensity * float(profile.get("rumble_strong", 0.45)),
		float(profile.get("rumble_time", 0.12))
	)


func _pulse_damage_vignette() -> void:
	if PixelDioramaViewport and PixelDioramaViewport.has_method("pulse_damage_vignette"):
		PixelDioramaViewport.call("pulse_damage_vignette", 0.72 * feedback_intensity)


func _play_hit_sfx(target: Node, _direction: Vector3, impact: int = ImpactClass.SOLID) -> void:
	var cue := "hit"
	var body: Node3D = target as Node3D
	if body and body.has_method("get_enemy_id"):
		var enemy_id: String = body.call("get_enemy_id")
		if enemy_id.contains("shield") or enemy_id.contains("knight"):
			cue = "hit_armor"
	_play_combat_sfx_at_body(cue, body)
	var layer := String(_profile(impact).get("audio_layer", ""))
	if layer != "" and layer != cue:
		_play_combat_sfx_at_body(layer, body)


func _play_combat_sfx_at_body(cue: String, body: Node3D = null) -> void:
	if not AudioDirector:
		return
	var pos: Variant = null
	if body:
		var anchor: Array = VfxService.resolve_combat_anchor(body)
		pos = anchor[0]
	AudioDirector.play_combat_sfx(cue, pos)


func _flash_diorama_body(
	body: Node3D, strength: float = 1.0, tint: Color = Color.WHITE, crit: bool = false
) -> void:
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
	if crit:
		VfxService.play_crit_spark(anchor[0], anchor[1])
	else:
		VfxService.play_hit_spark(anchor[0], anchor[1])
