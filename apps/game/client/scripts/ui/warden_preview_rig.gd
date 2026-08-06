class_name WardenPreviewRig
extends Node3D

## Live 3D warden preview for character creation.

const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

var _stage: Node3D
var _yaw := 0.0
var _profile: Dictionary = {}


func _ready() -> void:
	_stage = Node3D.new()
	_stage.name = "PreviewStage"
	add_child(_stage)
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.position = Vector3(0.0, 1.1, 2.4)
	camera.rotation.x = deg_to_rad(-12.0)
	camera.current = true
	_stage.add_child(camera)
	var key_light := DirectionalLight3D.new()
	key_light.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	key_light.light_energy = 1.1
	_stage.add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-120.0), 0.0)
	fill_light.light_energy = 0.35
	_stage.add_child(fill_light)


func apply_profile(profile: Dictionary) -> void:
	_profile = CharacterAppearance.sanitize(profile)
	CharacterSkinScript.build_preview_body(_stage, _profile)
	_stage.rotation.y = _yaw


func get_applied_profile() -> Dictionary:
	return _profile.duplicate(true)


func get_stage() -> Node3D:
	return _stage


func rotate_by(delta_yaw: float) -> void:
	_yaw += delta_yaw
	if _stage:
		_stage.rotation.y = _yaw


func reset_yaw() -> void:
	_yaw = 0.0
	if _stage:
		_stage.rotation.y = 0.0
