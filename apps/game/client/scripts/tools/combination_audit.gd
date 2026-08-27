extends Node


const CLASS_IDS: PackedStringArray = [
	"knight", "sentinel", "berserker", "rogue", "hunter", "scholar", "herald",
]
const REQUIRED_PARTS: PackedStringArray = ["Root", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]

const MIN_HEIGHT := 1.15
const MAX_HEIGHT := 1.65

var _checked := 0
var _failures: Array[String] = []


func _ready() -> void:
	await get_tree().process_frame
	_sweep_geometry()
	_sweep_cosmetics()
	print("\ncombination_audit: %d combinations, %d failures" % [_checked, _failures.size()])
	var shown := 0
	for failure in _failures:
		print("  " + failure)
		shown += 1
		if shown >= 40:
			print("  ... and %d more" % (_failures.size() - shown))
			break
	get_tree().quit(0 if _failures.is_empty() else 1)


func _sweep_geometry() -> void:
	for height in CharacterAppearance.FRAME_VARIANTS:
		for bulk in CharacterAppearance.FRAME_VARIANTS:
			for head_style in [
				CharacterAppearance.HEAD_OPEN,
				CharacterAppearance.HEAD_VISOR,
				CharacterAppearance.HEAD_HOOD,
			]:
				for hair in CharacterAppearance.HAIR_STYLES:
					for trim in 3:
						for class_id in CLASS_IDS:
							_check({
								"theme": 0,
								"frame": height,
								"head": head_style,
								"hair": hair,
								"trim": trim,
								"classId": class_id,
								"face": CharacterAppearance.FACE_STERN,
								"skinTone": CharacterAppearance.SKIN_TONE_TAN,
								"hairColor": CharacterAppearance.HAIR_COLOR_BROWN,
							})


func _sweep_cosmetics() -> void:
	for face in CharacterAppearance.FACE_STYLES:
		for skin in CharacterAppearance.SKIN_TONES:
			for hair_color in CharacterAppearance.HAIR_COLORS:
				_check({
					"theme": 0,
					"head": CharacterAppearance.HEAD_OPEN,
					"hair": CharacterAppearance.HAIR_SHORT,
					"trim": 2,
					"classId": "knight",
					"face": face,
					"skinTone": skin,
					"hairColor": hair_color,
				})


func _check(profile: Dictionary) -> void:
	_checked += 1
	var host := Node3D.new()
	add_child(host)
	var visual := DioramaCharacterSkin.build_preview_body(host, profile)
	var label := "%s/%s head=%s hair=%s trim=%s class=%s face=%s" % [
		str(profile.get("frame", "standard")), str(profile.get("frame", "standard")),
		str(profile.get("head", "")), str(profile.get("hair", "")), str(profile.get("trim", 0)),
		str(profile.get("classId", "")), str(profile.get("face", "")),
	]
	if visual == null:
		_failures.append("%s: no rig built" % label)
		host.queue_free()
		return

	for part_name in REQUIRED_PARTS:
		if DioramaCharacterSkin.find_part(visual, part_name) == null:
			_failures.append("%s: missing part %s" % [label, part_name])

	var head := DioramaCharacterSkin.find_part(visual, "Head")
	if head != null:
		var open_face: bool = str(profile.get("head", "")) == CharacterAppearance.HEAD_OPEN
		var hair_node := head.get_node_or_null("Hair")
		var hair_shown := hair_node != null and (hair_node as Node3D).visible
		if not open_face and hair_shown:
			_failures.append("%s: hair visible under a covered head" % label)
		var plate := head.get_node_or_null("FacePlate")
		if not open_face and plate != null:
			_failures.append("%s: face plate under a covered head" % label)
		if open_face and plate == null:
			_failures.append("%s: open head with no face plate" % label)

	var torso := DioramaCharacterSkin.find_part(visual, "Torso")
	if torso != null and str(profile.get("classId", "")) != "":
		if torso.get_node_or_null("ClassGarment") == null:
			_failures.append("%s: class has no garment" % label)

	var bounds := _visible_bounds(visual)
	if bounds.size.y < MIN_HEIGHT or bounds.size.y > MAX_HEIGHT:
		_failures.append("%s: height %.2f outside %.2f..%.2f" % [
			label, bounds.size.y, MIN_HEIGHT, MAX_HEIGHT
		])
	elif absf(bounds.position.y) > 0.02:
		_failures.append("%s: feet at y %.2f, not on the floor" % [label, bounds.position.y])

	host.queue_free()


func _visible_bounds(visual: Node3D) -> AABB:
	var bounds := AABB()
	var found := false
	for node in visual.find_children("*", "MeshInstance3D", true, false):
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.mesh == null or not mesh_inst.is_visible_in_tree():
			continue
		var world: AABB = mesh_inst.global_transform * mesh_inst.get_aabb()
		bounds = world if not found else bounds.merge(world)
		found = true
	return bounds
