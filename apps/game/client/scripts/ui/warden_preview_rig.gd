class_name WardenPreviewRig
extends Node3D

## Live 3D warden preview for character creation.
##
## The camera and lights are children of the rig, not of the rotating stage. They used to live on
## the stage, which broke them two ways: DioramaCharacterSkin.build_preview_body() frees every
## child of the node it builds into, so the first apply_profile() deleted the camera and both
## lights outright; and while they survived, turning the stage turned the camera with the model, so
## the preview could never actually be rotated.

const CharacterSkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

## One press of a rotate button or of Q / E.
const ROTATE_STEP := deg_to_rad(30.0)

## Fallback frame used until a built body reports its own bounds. Matches an assembled standard
## warden: 1.44 tall from feet to crown, 0.80 across the pauldrons.
const DEFAULT_SUBJECT_HEIGHT := 1.44
const DEFAULT_SUBJECT_WIDTH := 0.80
const DEFAULT_SUBJECT_DEPTH := 0.42
const CAMERA_PITCH := deg_to_rad(-6.0)
## A portrait lens. The engine default of 75 degrees is a wide angle: at the distance needed to
## frame a one-metre diorama figure it bows the silhouette outward and exaggerates whichever limb
## is nearest the lens.
const CAMERA_FOV := 34.0
## Fraction of the visible frame the warden should occupy — the rest is headroom and floor.
const SUBJECT_SCREEN_FRACTION := 0.82

var _stage: Node3D
var _camera: Camera3D
var _yaw := 0.0
var _profile: Dictionary = {}


func _ready() -> void:
	_stage = Node3D.new()
	_stage.name = "PreviewStage"
	add_child(_stage)
	_camera = Camera3D.new()
	_camera.name = "PreviewCamera"
	_camera.current = true
	add_child(_camera)
	var key_light := DirectionalLight3D.new()
	key_light.name = "KeyLight"
	key_light.rotation = Vector3(deg_to_rad(-45.0), deg_to_rad(35.0), 0.0)
	key_light.light_energy = 1.1
	add_child(key_light)
	var fill_light := DirectionalLight3D.new()
	fill_light.name = "FillLight"
	fill_light.rotation = Vector3(deg_to_rad(-20.0), deg_to_rad(-120.0), 0.0)
	fill_light.light_energy = 0.35
	add_child(fill_light)
	_frame_subject(
		Vector3(DEFAULT_SUBJECT_WIDTH, DEFAULT_SUBJECT_HEIGHT, DEFAULT_SUBJECT_DEPTH),
		DEFAULT_SUBJECT_HEIGHT
	)


func apply_profile(profile: Dictionary) -> void:
	_profile = CharacterAppearance.sanitize(profile)
	CharacterSkinScript.build_preview_body(_stage, _profile)
	_stage.rotation.y = _yaw
	_reframe_when_built()


## The body is assembled from a manifest and then mesh-merged, so the parts are not all in the tree
## with final transforms during the build call itself — measuring there reports roughly the torso
## alone and frames the camera far too close. Measuring after the tree has settled sees the whole
## warden.
func _reframe_when_built() -> void:
	var tree := get_tree()
	if tree == null:
		return
	await tree.process_frame
	await tree.process_frame
	if not is_inside_tree():
		return
	var bounds := _stage_bounds()
	_frame_subject(_turn_extent(bounds), bounds.get_center().y)


## Converts the body's bounds into the box it sweeps as the stage turns.
##
## The raw AABB is not centred on the turn axis — a shouldered weapon or an outstretched arm pushes
## it to one side — so framing the AABB directly leaves the warden sitting off-centre and clipped
## against one edge, and the crop changes every time the player rotates the preview. Taking the
## furthest point from the axis on both horizontal axes gives a frame that holds at any yaw.
func _turn_extent(bounds: AABB) -> Vector3:
	var far_end := bounds.position + bounds.size
	var radius := maxf(
		maxf(absf(bounds.position.x), absf(far_end.x)),
		maxf(absf(bounds.position.z), absf(far_end.z))
	)
	return Vector3(radius * 2.0, bounds.size.y, radius * 2.0)


## Union of every mesh AABB under the stage, in stage space. Framing from the real bounds is what
## keeps head and feet inside the portrait regardless of the stature and bulk the player picked.
func _stage_bounds() -> AABB:
	var bounds := AABB()
	var found := false
	for node in _stage.find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		if visual == null:
			continue
		var world_aabb := visual.global_transform * visual.get_aabb()
		if found:
			bounds = bounds.merge(world_aabb)
		else:
			bounds = world_aabb
			found = true
	if not found or bounds.size.y <= 0.0:
		return AABB(
			Vector3(-DEFAULT_SUBJECT_WIDTH * 0.5, DEFAULT_SUBJECT_HEIGHT * 0.5, 0.0),
			Vector3(DEFAULT_SUBJECT_WIDTH, DEFAULT_SUBJECT_HEIGHT, DEFAULT_SUBJECT_DEPTH)
		)
	return bounds


## Pulls the camera back far enough that the warden fits the frame on both axes.
##
## Height alone is not enough: the preview sits in a tall, narrow portrait, so a figure framed to
## fill 82% of the height has its shoulders cut off at the sides. The subject's own depth is added
## on top, because the distance that frames a flat plane at the model's centre still puts whatever
## faces the camera much closer than that.
func _frame_subject(size: Vector3, center_y: float) -> void:
	if _camera == null:
		return
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


## Godot keeps the vertical FOV and widens the horizontal one with the aspect ratio, so the
## horizontal fit depends on how wide the preview panel actually ended up.
func _viewport_aspect() -> float:
	var viewport := get_viewport()
	if viewport == null:
		return 0.75
	var rect := viewport.get_visible_rect().size
	if rect.x <= 0.0 or rect.y <= 0.0:
		return 0.75
	return rect.x / rect.y


func get_applied_profile() -> Dictionary:
	return _profile.duplicate(true)


func get_stage() -> Node3D:
	return _stage


func rotate_by(delta_yaw: float) -> void:
	_yaw = wrapf(_yaw + delta_yaw, -PI, PI)
	if _stage:
		_stage.rotation.y = _yaw


func rotate_left() -> void:
	rotate_by(-ROTATE_STEP)


func rotate_right() -> void:
	rotate_by(ROTATE_STEP)


func reset_yaw() -> void:
	_yaw = 0.0
	if _stage:
		_stage.rotation.y = 0.0
