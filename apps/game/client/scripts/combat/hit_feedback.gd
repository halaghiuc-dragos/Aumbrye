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

var show_damage_numbers := false

var _camera: Camera3D
var _hitstop_active := false


func _ready() -> void:
	if camera_path:
		_camera = get_node_or_null(camera_path) as Camera3D
	var guard := get_parent().get_node_or_null("Guard")
	if guard and guard.has_signal("parry_success"):
		guard.parry_success.connect(_on_parry_success)


func on_hit(target: Node, damage: float) -> void:
	hit_landed.emit(target, damage)
	_apply_hitstop()
	_apply_camera_punch()
	_play_sfx_hook()
	if show_damage_numbers and target is Node3D:
		_spawn_damage_number(target as Node3D, damage)


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


func _apply_hitstop() -> void:
	if _hitstop_active:
		return
	_hitstop_active = true
	var duration := DEFAULT_HITSTOP * feedback_intensity
	Engine.time_scale = 0.05
	await get_tree().create_timer(duration, true, false, true).timeout
	Engine.time_scale = 1.0
	_hitstop_active = false


func _apply_camera_punch() -> void:
	if not _camera:
		return
	var punch := DEFAULT_CAMERA_PUNCH * feedback_intensity
	var tween := create_tween()
	tween.tween_property(_camera, "h_offset", punch, 0.03)
	tween.tween_property(_camera, "h_offset", 0.0, 0.08)


func _play_sfx_hook() -> void:
	pass
