extends Node

enum ImpactClass { GLANCING, SOLID, CRITICAL, PARRY }

const DEFAULT_HITSTOP := 0.09
const DEFAULT_CAMERA_PUNCH := 0.15
const DEFAULT_INTENSITY := 1.0
const HITSTOP_TIME_SCALE := 0.08
const GLANCING_DAMAGE := 15.0

## `PH-02`: the attacker recovers first -- that asymmetry is what makes a hit feel like *you* did
## something rather than like the game paused. The victim's freeze is always this much longer than
## whatever the attacker gets for the same impact class.
const VICTIM_FREEZE_MULT := 1.4

const TUNING_PATH := "content/combat/impact.json"
const IMPACT_CLASS_KEYS := {
	ImpactClass.GLANCING: "glancing",
	ImpactClass.SOLID: "solid",
	ImpactClass.CRITICAL: "critical",
	ImpactClass.PARRY: "parry",
}
const FALLBACK_IMPACT_PROFILES := {
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
	ImpactClass.PARRY:
	{
		"freeze": 0.22,
		"punch": 0.3,
		"shake": 0.14,
		"shake_time": 0.16,
		"rumble_weak": 0.6,
		"rumble_strong": 0.95,
		"rumble_time": 0.2,
		"audio_layer": "",
	},
}
static var _impact_profiles: Dictionary = {}
const DAMAGE_NUMBER := preload("res://scripts/combat/damage_number.gd")
const MaterialFlashScript := preload("res://scripts/art/characters/material_flash.gd")
const COLOR_PARRY := Color(1.0, 0.88, 0.2)
const COLOR_BLOCK := Color(0.45, 0.78, 1.0)
const COLOR_JUST_GUARD := Color(0.68, 0.95, 1.0)

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
	_ensure_impact_profiles_loaded()
	var guard := get_parent().get_node_or_null("Guard")
	if guard and guard.has_signal("parry_success"):
		guard.parry_success.connect(_on_parry_success)
	if guard and guard.has_signal("just_guard_success"):
		guard.just_guard_success.connect(_on_just_guard_success)


static func _ensure_impact_profiles_loaded() -> void:
	if not _impact_profiles.is_empty():
		return
	var data := ContentLoader.load_json(TUNING_PATH)
	var profiles: Dictionary = data.get("profiles", {})
	for impact_class in IMPACT_CLASS_KEYS:
		var key := String(IMPACT_CLASS_KEYS[impact_class])
		if profiles.has(key):
			_impact_profiles[impact_class] = profiles[key]
		else:
			_impact_profiles[impact_class] = FALLBACK_IMPACT_PROFILES[impact_class]


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
	crit: bool = false,
	poise_broke: bool = false
) -> void:
	hit_landed.emit(target, damage)
	_freeze_attacker(impact)
	_apply_impact_recoil(impact)
	_apply_camera_punch(direction, impact)
	_apply_vibration(impact)
	_play_hit_sfx(target, direction, impact, poise_broke)
	if show_damage_numbers and target is Node3D:
		_spawn_damage_number(target as Node3D, damage, Vector3.ZERO, damage_type, crit)


## `AN-03`: hitting a golem should visibly stop your arm; hitting air should not. `on_hit()` only
## fires when a hitbox actually landed, so this is never called on a whiff.
const IMPACT_RECOIL_STRENGTH := {
	ImpactClass.GLANCING: 0.3,
	ImpactClass.SOLID: 0.7,
	ImpactClass.CRITICAL: 1.0,
	ImpactClass.PARRY: 1.0,
}


func _apply_impact_recoil(impact: int) -> void:
	var director := _director()
	if director == null or not director.has_method("play_impact_recoil"):
		return
	var strength := float(IMPACT_RECOIL_STRENGTH.get(impact, 0.7))
	director.call("play_impact_recoil", strength)


func _profile(impact: int) -> Dictionary:
	_ensure_impact_profiles_loaded()
	return _impact_profiles.get(impact, _impact_profiles[ImpactClass.SOLID])


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
	_freeze_victim(impact)
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


## CB-03: the defender-side counterpart to `try_just_guard()`'s attacker-side poise hit -- a
## GLANCING hitstop and its own colour/text, distinct from both a normal block ("BLOCKED", blue)
## and a parry ("PARRIED", gold, a full freeze).
func _on_just_guard_success(_attacker: Node) -> void:
	_apply_hitstop(ImpactClass.GLANCING)
	_play_combat_sfx_at_body("block")
	var body := get_parent() as Node3D
	if body:
		_flash_diorama_body(body, 0.8, COLOR_JUST_GUARD)
	if not show_damage_numbers or body == null:
		return
	_spawn_combat_text(body, "JUST GUARD", COLOR_JUST_GUARD)


func _on_parry_success(_attacker: Node) -> void:
	_freeze_attacker(ImpactClass.PARRY)
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
	damage_type: String = "physical",
	is_crit: bool = false
) -> void:
	var root := get_tree().current_scene
	if root:
		DAMAGE_NUMBER.spawn(at_node.global_position + offset, damage, root, damage_type, is_crit)


## `PH-02`: called on the attacker's own `HitFeedback` (see `on_hit()`). Left at the impact
## class's base freeze duration -- the attacker is meant to recover first.
func _freeze_attacker(impact: int) -> void:
	_apply_hitstop(impact, false)


## Called on the victim's own `HitFeedback` (see `on_hit_received()`). Longer than
## `_freeze_attacker()` by `VICTIM_FREEZE_MULT` for the same impact class.
func _freeze_victim(impact: int) -> void:
	_apply_hitstop(impact, true)


func _apply_hitstop(impact: int = ImpactClass.SOLID, is_victim: bool = false) -> void:
	if feedback_intensity <= 0.0 or AccessibilitySettings.hitstop_scale() <= 0.0:
		return
	var duration := _freeze_duration(impact) * AccessibilitySettings.hitstop_scale()
	if is_victim:
		duration *= VICTIM_FREEZE_MULT
	if duration <= 0.0:
		return
	var duration_ms := int(duration * 1000.0)
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


## `AU-02`: material replaces the old `enemy_id.contains("shield")` guess -- every enemy authors
## `hit_material` (`flesh`/`armour`/`stone`/`crystal`/`bone`/`ooze`) directly, so what you heard and
## what you hit stop being able to disagree. `"flesh"` keeps the original `"hit"` cue id rather than
## a `hit_flesh` alias, since that is the one material every already-authored variant/SFX file was
## built for.
const HIT_MATERIAL_CUES := {
	"flesh": "hit",
	"armour": "hit_armor",
	"stone": "hit_stone",
	"crystal": "hit_crystal",
	"bone": "hit_bone",
	"ooze": "hit_ooze",
}


func _hit_material_for(body: Node3D) -> String:
	if body == null or not body.has_method("get_enemy_id"):
		return "flesh"
	var enemy_id: String = body.call("get_enemy_id")
	if enemy_id.is_empty():
		return "flesh"
	return str(EnemyCatalog.get_definition(enemy_id).get("hit_material", "flesh"))


func _play_hit_sfx(
	target: Node, _direction: Vector3, impact: int = ImpactClass.SOLID, poise_broke: bool = false
) -> void:
	var body: Node3D = target as Node3D
	var material := _hit_material_for(body)
	var cue: String = str(HIT_MATERIAL_CUES.get(material, "hit"))
	_play_combat_sfx_at_body(cue, body)
	var layer := String(_profile(impact).get("audio_layer", ""))
	if layer != "" and layer != cue:
		_play_combat_sfx_at_body(layer, body)
	# The one cue that answers "did that just work" regardless of what got hit -- distinct from
	# every material cue above, and from the critical hit's `hit_armor` layer, which fires on
	# damage dealt rather than on the poise bar actually emptying.
	if poise_broke:
		_play_combat_sfx_at_body("hit_poise_break", body)


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
