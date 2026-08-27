extends Node


const WardenPreviewRigScript := preload("res://scripts/ui/warden_preview_rig.gd")
const AppearanceCatalogScript := preload("res://scripts/ui/appearance_catalog.gd")
const OUTPUT_DIR := "user://warden_captures"

const CELL := Vector2i(390, 520)
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
	await _capture_frames()
	await _capture_aspects()
	await _capture_class_fit()
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
	env.ambient_light_color = Color(0.34, 0.36, 0.48)
	env.ambient_light_energy = 0.32
	world_env.environment = env
	stage.add_child(world_env)
	_rig = WardenPreviewRigScript.new()
	stage.add_child(_rig)


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
		"frame": CharacterAppearance.FRAME_STANDARD,
		"head": CharacterAppearance.HEAD_VISOR,
		"trim": 2,
		"skinTone": CharacterAppearance.SKIN_TONE_NEUTRAL,
		"hair": CharacterAppearance.HAIR_SHORT,
		"face": CharacterAppearance.FACE_STERN,
	}


func _capture_body_shapes() -> void:
	var cells: Array[Image] = []
	var labels: PackedStringArray = []
	for frame: String in CharacterAppearance.FRAME_VARIANTS:
		var profile := _base_profile()
		profile["frame"] = frame
		cells.append(await _render(profile))
		labels.append(frame)
	_write_sheet("body_shapes", cells, 5)
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


func _capture_classes() -> void:
	var cells: Array[Image] = []
	for class_id in CLASS_IDS:
		var profile := _base_profile()
		profile["head"] = CharacterAppearance.HEAD_OPEN
		profile["classId"] = class_id
		cells.append(await _render(profile))
	_write_sheet("classes", cells, 4)
	print("classes: %s" % ", ".join(CLASS_IDS))


func _capture_identity() -> void:
	var cells: Array[Image] = []
	var hair := CharacterAppearance.HAIR_STYLES
	var colors := CharacterAppearance.HAIR_COLORS
	var skins := CharacterAppearance.SKIN_TONES
	var faces := CharacterAppearance.FACE_STYLES
	var frames: Array = CharacterAppearance.FRAME_VARIANTS
	for i in hair.size():
		var profile := _base_profile()
		profile["head"] = CharacterAppearance.HEAD_OPEN
		profile["hair"] = hair[i]
		profile["hairColor"] = colors[i % colors.size()]
		profile["skinTone"] = skins[i % skins.size()]
		profile["face"] = faces[i % faces.size()]
		profile["frame"] = frames[i % frames.size()]
		cells.append(await _render(profile))
	_write_sheet("identity", cells, 5)


func _capture_frames() -> void:
	var cells: Array[Image] = []
	for frame: String in CharacterAppearance.FRAME_VARIANTS:
		var profile := _base_profile()
		profile["head"] = CharacterAppearance.HEAD_OPEN
		profile["frame"] = frame
		cells.append(await _render(profile))
	_write_sheet("frames", cells, 5)


func _capture_class_fit() -> void:
	var cells: Array[Image] = []
	for frame: String in CharacterAppearance.FRAME_VARIANTS:
		for class_id in CLASS_IDS:
			var profile := _base_profile()
			profile["head"] = CharacterAppearance.HEAD_OPEN
			profile["frame"] = frame
			profile["classId"] = class_id
			cells.append(await _render(profile))
	_write_sheet("class_fit", cells, CLASS_IDS.size())
	print("class fit: %d frames x %d classes" % [
		CharacterAppearance.FRAME_VARIANTS.size(), CLASS_IDS.size()
	])


func _capture_aspects() -> void:
	var cells: Array[Image] = []
	var names: PackedStringArray = []
	for i in AppearanceCatalogScript.aspect_count():
		var profile := _base_profile()
		profile["head"] = CharacterAppearance.HEAD_OPEN
		profile["theme"] = AppearanceCatalogScript.theme_for_index(i)
		cells.append(await _render(profile))
		names.append(str(AppearanceCatalogScript.aspect_at(i).get("name", "?")))
	_write_sheet("aspects", cells, 5)
	print("aspects: %d - %s" % [cells.size(), ", ".join(names)])


func _capture_yaw() -> void:
	var cells: Array[Image] = []
	_rig.reset_yaw()
	for step in 4:
		var yaw_profile := _base_profile()
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
	image.resize(CELL.x, CELL.y, Image.INTERPOLATE_NEAREST)
	return image


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
