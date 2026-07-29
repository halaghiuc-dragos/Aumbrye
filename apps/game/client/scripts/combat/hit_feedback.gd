extends Node

const DEFAULT_HITSTOP := 0.06
const DEFAULT_CAMERA_PUNCH := 0.15
const DEFAULT_INTENSITY := 1.0

signal hit_landed(target: Node, damage: float)

@export var camera_path: NodePath
@export var feedback_intensity := DEFAULT_INTENSITY

var show_damage_numbers := false

var _camera: Camera3D
var _hitstop_active := false


func _ready() -> void:
	if camera_path:
		_camera = get_node(camera_path) as Camera3D


func on_hit(target: Node, damage: float) -> void:
	hit_landed.emit(target, damage)
	_apply_hitstop()
	_apply_camera_punch()
	_play_sfx_hook()


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
