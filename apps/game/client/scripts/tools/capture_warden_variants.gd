extends Node

## Renders the character-creation warden preview across every appearance option and writes a PNG
## contact sheet per axis, so a change to the rig can be checked against all nine body shapes
## instead of whichever one happened to be selected.
##
## This exists because the six lean/heavy/tall variants were broken for as long as the baked-mesh
## path was live and nothing looked at them: the default Standard/Standard warden was the only
## combination anyone ever saw.
##
## Must run windowed — a headless run has no rendering device and produces blank images.
##
## Usage:
##   godot --path apps/game/client --resolution 1280x720 \
##     res://scenes/debug/capture_warden_variants.tscn

const WardenPreviewRigScript := preload("res://scripts/ui/warden_preview_rig.gd")
const OUTPUT_DIR := "user://warden_captures"

## Matches the SubViewport the real preview column uses, scaled up so the contact sheet is
## readable. The aspect must stay 3:4 or the rig frames the subject differently than it does
## in game and the capture stops being evidence about the real screen.
const CELL := Vector2i(390, 520)
## The preview renders at 1/N and is scaled back up with nearest filtering, exactly as
## `character_create_ui` does it, so the sheet shows the pixel density a player actually sees
## rather than a full-resolution render nothing in the game produces.
const PIXEL_SHRINK := 4

const CLASS_IDS: PackedStringArray = [
	"knight", "sentinel", "berserker", "rogue", "hunter", "scholar", "herald",
]
const SETTLE_FRAMES := 8

var _viewport: SubViewport
var _rig: WardenPreviewRig


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(OUTPUT_DIR))
	_build_stage()
	await _capture_body_shapes()
	await _capture_head_and_trim()
	await _capture_head_hair()
	await _capture_classes()
	await _capture_identity()
	await _capture_yaw()
	await _report_facing()
	get_tree().quit(0)


func _build_stage() -> void:
	_viewport = SubViewport.new()
	@warning_ignore("integer_division")
	var internal := Vector2i(CELL.x / PIXEL_SHRINK, CELL.y / PIXEL_SHRINK)
	_viewport.size = internal
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.own_world_3d = true
	_viewport.transparent_bg = false
	add_child(_viewport)
	var stage := Node3D.new()
	stage.name = "PreviewStage"
	_viewport.add_child(stage)
	var world_env := WorldEnvironment.new()
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.08, 0.08, 0.11)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	# Low enough that the key light still decides which faces are lit. See WardenPreviewRig.
	env.ambient_light_color = Color(0.34, 0.36, 0.48)
	env.ambient_light_energy = 0.32
	world_env.environment = env
	stage.add_child(world_env)
	_rig = WardenPreviewRigScript.new()
	stage.add_child(_rig)


## Which way the built warden actually faces, measured rather than assumed: the chest placard is
## painted on the frontmost column of the torso, so the sign of its z tells us where the front is.
func _report_facing() -> void:
	_rig.reset_yaw()
	_rig.apply_profile(_base_profile())
	await get_tree().process_frame
	await get_tree().process_frame
	var torso := DioramaCharacterSkin.find_part(_rig.get_stage(), "Torso")
	if torso == null:
		print("facing: no torso")
		return
	for node in torso.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh == null or not mesh_inst.is_visible_in_tree():
			continue
		var world: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		print(
			"facing: %s spans z %.2f .. %.2f (camera sits at +z)"
			% [mesh_inst.name, world.position.z, world.position.z + world.size.z]
		)


func _base_profile() -> Dictionary:
	return {
		"theme": 0,
		"heightVariant": CharacterAppearance.HEIGHT_VARIANT_STANDARD,
		"bulkVariant": CharacterAppearance.BULK_VARIANT_STANDARD,
		"head": CharacterAppearance.HEAD_VISOR,
		"trim": 2,
		"skinTone": CharacterAppearance.SKIN_TONE_NEUTRAL,
		"hair": CharacterAppearance.HAIR_SHORT,
		"face": CharacterAppearance.FACE_STERN,
	}


## Every stature x build combination — the axis that was broken. Rows are stature, columns build,
## so a variant that assembles differently from its neighbours is obvious at a glance.
func _capture_body_shapes() -> void:
	var cells: Array[Image] = []
	var labels: PackedStringArray = []
	for height in CharacterAppearance.HEIGHT_VARIANTS:
		for bulk in CharacterAppearance.BULK_VARIANTS:
			var profile := _base_profile()
			profile["heightVariant"] = height
			profile["bulkVariant"] = bulk
			cells.append(await _render(profile))
			labels.append("%s/%s" % [height, bulk])
	_write_sheet("body_shapes", cells, 3)
	print("body shapes: %s" % ", ".join(labels))


func _capture_head_and_trim() -> void:
	var cells: Array[Image] = []
	for head_style in [
		CharacterAppearance.HEAD_OPEN,
		CharacterAppearance.HEAD_VISOR,
		CharacterAppearance.HEAD_HOOD,
	]:
		for trim in 3:
			var profile := _base_profile()
			profile["head"] = head_style
			profile["trim"] = trim
			cells.append(await _render(profile))
	_write_sheet("head_and_trim", cells, 3)


## Every head style against every hair style — 3 x 7. The interaction the hood has to survive: a
## cowl that wraps the skull must leave nothing for hair to come through, and an open head must not
## lose its face plate to whichever crop is selected.
func _capture_head_hair() -> void:
	var cells: Array[Image] = []
	for head_style in [
		CharacterAppearance.HEAD_OPEN,
		CharacterAppearance.HEAD_VISOR,
		CharacterAppearance.HEAD_HOOD,
	]:
		for hair in CharacterAppearance.HAIR_STYLES:
			var profile := _base_profile()
			profile["head"] = head_style
			profile["hair"] = hair
			profile["hairColor"] = CharacterAppearance.HAIR_COLOR_COPPER
			cells.append(await _render(profile))
	_write_sheet("head_hair", cells, 7)


## The default clothing of every class, with nothing equipped. This is what a player sees before
## they pick up a single item, and for a long time it was the same warden seven times.
func _capture_classes() -> void:
	var cells: Array[Image] = []
	for class_id in CLASS_IDS:
		var profile := _base_profile()
		profile["head"] = CharacterAppearance.HEAD_OPEN
		profile["classId"] = class_id
		cells.append(await _render(profile))
	_write_sheet("classes", cells, 4)
	print("classes: %s" % ", ".join(CLASS_IDS))


## Eight wardens that differ only in the axes meant to give them an identity — hair style, hair
## colour, complexion and face. If this sheet reads as eight of the same character, those axes are
## not doing anything, which is exactly what it looked like before the face plate and hair colour
## existed.
func _capture_identity() -> void:
	var cells: Array[Image] = []
	var hair := CharacterAppearance.HAIR_STYLES
	var colors := CharacterAppearance.HAIR_COLORS
	var skins := CharacterAppearance.SKIN_TONES
	var faces := CharacterAppearance.FACE_STYLES
	for i in 8:
		var profile := _base_profile()
		profile["head"] = CharacterAppearance.HEAD_OPEN
		profile["hair"] = hair[(i + 1) % hair.size()]
		profile["hairColor"] = colors[i % colors.size()]
		profile["skinTone"] = skins[i % skins.size()]
		profile["face"] = faces[i % faces.size()]
		cells.append(await _render(profile))
	_write_sheet("identity", cells, 4)


## The preview can be turned, and the framing is meant to hold at any yaw.
func _capture_yaw() -> void:
	var cells: Array[Image] = []
	_rig.reset_yaw()
	for step in 4:
		var yaw_profile := _base_profile()
		# Open-faced, so the face plate is present and can act as an unambiguous front marker.
		yaw_profile["head"] = CharacterAppearance.HEAD_OPEN
		yaw_profile["skinTone"] = CharacterAppearance.SKIN_TONE_UMBER
		cells.append(await _render(yaw_profile, false))
		for i in 3:
			_rig.rotate_right()
	_write_sheet("yaw", cells, 4)


func _render(profile: Dictionary, reset_yaw: bool = true) -> Image:
	if reset_yaw:
		_rig.reset_yaw()
	_rig.apply_profile(profile)
	for i in SETTLE_FRAMES:
		await get_tree().process_frame
	_report_framing()
	var image := _viewport.get_texture().get_image()
	# Nearest, so the sheet shows hard pixel edges instead of the bilinear smear that would make
	# every judgement about the art a judgement about the resampler.
	image.resize(CELL.x, CELL.y, Image.INTERPOLATE_NEAREST)
	return image


## Prints what fraction of the frame the warden actually occupies, so the framing constants can be
## checked against the render instead of re-derived on paper.
func _report_framing() -> void:
	var camera := _rig.get_node_or_null("PreviewCamera") as Camera3D
	if camera == null:
		return
	var bounds := AABB()
	var found := false
	for node in _rig.get_stage().find_children("*", "VisualInstance3D", true, false):
		var visual := node as VisualInstance3D
		var world: AABB = visual.global_transform * visual.get_aabb()
		bounds = world if not found else bounds.merge(world)
		found = true
	if not found:
		return
	var top := camera.unproject_position(Vector3(0.0, bounds.position.y + bounds.size.y, 0.0))
	var bottom := camera.unproject_position(Vector3(0.0, bounds.position.y, 0.0))
	var far_end := bounds.position + bounds.size
	print(
		(
			"framing: y %.2f..%.2f  x %.2f..%.2f  z %.2f..%.2f | screen %.0f%% | camera z %.2f | "
			+ "meshes %d"
		)
		% [
			bounds.position.y,
			far_end.y,
			bounds.position.x,
			far_end.x,
			bounds.position.z,
			far_end.z,
			absf(bottom.y - top.y) / float(CELL.y) * 100.0,
			camera.position.z,
			_rig.get_stage().find_children("*", "VisualInstance3D", true, false).size(),
		]
	)


func _write_sheet(sheet_name: String, cells: Array[Image], columns: int) -> void:
	if cells.is_empty():
		return
	var rows := int(ceil(float(cells.size()) / float(columns)))
	var sheet := Image.create_empty(
		CELL.x * columns, CELL.y * rows, false, cells[0].get_format()
	)
	sheet.fill(Color(0.02, 0.02, 0.03))
	for i in cells.size():
		var cell := cells[i]
		@warning_ignore("integer_division")
		var row := i / columns
		sheet.blit_rect(
			cell,
			Rect2i(Vector2i.ZERO, cell.get_size()),
			Vector2i((i % columns) * CELL.x, row * CELL.y)
		)
	var path := ProjectSettings.globalize_path(OUTPUT_DIR).path_join(sheet_name + ".png")
	sheet.save_png(path)
	print("captured %s -> %s" % [sheet_name, path])
