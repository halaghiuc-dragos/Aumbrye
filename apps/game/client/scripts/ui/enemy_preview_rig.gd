class_name EnemyPreviewRig
extends Node3D

## UX-01 (bestiary): renders one enemy's diorama body into a SubViewport, the same framing
## approach `warden_preview_rig.gd` uses for the player's character-creation preview -- a stage
## node holding the built body, a camera auto-distanced to fit it in frame, and two static
## lights. Built specifically for small grid-cell portraits, so it skips the rotate controls and
## outline pass `warden_preview_rig.gd` needs for its bigger, interactive preview.

const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

const DEFAULT_SUBJECT_HEIGHT := 1.6
const DEFAULT_SUBJECT_WIDTH := 0.9
const CAMERA_PITCH := deg_to_rad(-10.0)
const CAMERA_FOV := 32.0
const SUBJECT_SCREEN_FRACTION := 0.86

var _stage: Node3D
var _camera: Camera3D


func _ready() -> void:
	_stage = Node3D.new()
	_stage.name = "EnemyPreviewStage"
	add_child(_stage)
	_camera = Camera3D.new()
	_camera.name = "EnemyPreviewCamera"
	_camera.current = true
	add_child(_camera)
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation = Vector3(deg_to_rad(-42.0), deg_to_rad(28.0), 0.0)
	key_light.light_energy = 1.5
	add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation = Vector3(deg_to_rad(-16.0), deg_to_rad(-132.0), 0.0)
	fill_light.light_energy = 0.3
	add_child(fill_light)
	_frame_subject(Vector3(DEFAULT_SUBJECT_WIDTH, DEFAULT_SUBJECT_HEIGHT, DEFAULT_SUBJECT_WIDTH))


## `enemy_type` / `theme` / `enemy_data` mirror the args `CharacterSkin.build_enemy_body` takes
## everywhere else it's called (see `castle_enemy_base.gd`).
func show_enemy(enemy_id: String, enemy_type: String, theme: int, enemy_data: Dictionary) -> void:
	if _stage == null:
		return
	CharacterSkinScript.build_enemy_body(_stage, enemy_type, theme, enemy_id, enemy_data)
	_reframe_when_built()


func _reframe_when_built() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if not is_inside_tree():
		return
	var bounds := _stage_bounds()
	_frame_subject(bounds.size, bounds.get_center().y)


func _stage_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	for node in _stage.find_children("*", "MeshInstance3D", true, false):
		var visual := node as MeshInstance3D
		if visual == null or not visual.is_visible_in_tree() or visual.mesh == null:
			continue
		var world_aabb := visual.global_transform * visual.get_aabb()
		if found:
			bounds = bounds.merge(world_aabb)
		else:
			bounds = world_aabb
			found = true
	if not found or bounds.size.y <= 0.0:
		return AABB(
			Vector3(-DEFAULT_SUBJECT_WIDTH * 0.5, 0.0, -DEFAULT_SUBJECT_WIDTH * 0.5),
			Vector3(DEFAULT_SUBJECT_WIDTH, DEFAULT_SUBJECT_HEIGHT, DEFAULT_SUBJECT_WIDTH)
		)
	return bounds


func _frame_subject(size: Vector3, center_y: float = -1.0) -> void:
	if _camera == null:
		return
	if center_y < 0.0:
		center_y = size.y * 0.5
	_camera.fov = CAMERA_FOV
	var half_fov := deg_to_rad(CAMERA_FOV) * 0.5
	var tan_v := maxf(tan(half_fov), 0.001)
	var tan_h := tan_v * maxf(_viewport_aspect(), 0.05)
	var distance := maxf(
		(maxf(size.y, 0.1) / SUBJECT_SCREEN_FRACTION * 0.5) / tan_v,
		(maxf(size.x, 0.1) / SUBJECT_SCREEN_FRACTION * 0.5) / tan_h
	)
	distance += maxf(size.z, 0.0) * 0.5
	_camera.position = Vector3(0.0, center_y - distance * tan(CAMERA_PITCH), distance)
	_camera.rotation = Vector3(CAMERA_PITCH, 0.0, 0.0)
	_camera.near = 0.05
	_camera.far = distance * 8.0


func _viewport_aspect() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 1.0
	var rect := viewport.get_visible_rect().size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return 1.0
	return rect.x / rect.y
