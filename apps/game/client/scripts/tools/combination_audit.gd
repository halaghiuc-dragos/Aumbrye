extends Node

## Builds every combination of the character options and checks each one against the invariants a
## warden has to satisfy, without rendering any of them.
##
## Rendering every combination is not possible — stature x build x head x trim x hair x hair colour
## x skin x face x class is over a million wardens — but the things that actually go wrong are
## structural and can be asserted on the built rig: a part that failed to load, hair coming through a
## hood, a face plate under a visor, a class with no clothing, a body that is not one connected
## height. The contact sheets stay the visual check; this is the exhaustive one.
##
## Usage:
##   godot --headless --path apps/game/client res://scenes/debug/combination_audit.tscn

const CLASS_IDS: PackedStringArray = [
	"knight", "sentinel", "berserker", "rogue", "hunter", "scholar", "herald",
]
const REQUIRED_PARTS: PackedStringArray = ["Root", "Torso", "Head", "ArmL", "ArmR", "LegL", "LegR"]

## A standard warden is 1.36 m; compact and tall move it by a few voxels either way. Anything
## outside this is a part that did not land where it belongs.
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


## Everything that changes the rig's shape.
func _sweep_geometry() -> void:
	for height in CharacterAppearance.HEIGHT_VARIANTS:
		for bulk in CharacterAppearance.BULK_VARIANTS:
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
								"heightVariant": height,
								"bulkVariant": bulk,
								"head": head_style,
								"hair": hair,
								"trim": trim,
								"classId": class_id,
								"face": CharacterAppearance.FACE_STERN,
								"skinTone": CharacterAppearance.SKIN_TONE_TAN,
								"hairColor": CharacterAppearance.HAIR_COLOR_BROWN,
							})


## Everything that only changes colour or the face plate, at one geometry.
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
		str(profile.get("heightVariant", "standard")), str(profile.get("bulkVariant", "standard")),
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
		# Hair belongs to an open head only: a hood wraps the skull and a visor helm covers it, and
		# hair under either came through the covering.
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
