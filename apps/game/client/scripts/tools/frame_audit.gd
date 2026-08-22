extends Node3D

## Does the preview show what the player picked, and is each frame a believable figure?
##
## Builds all five frames and measures them. Three things have to hold, and each has been false at
## some point: no two frames may be the same size, the arms must clear the torso by enough to see,
## and the leg and head fractions of total height must hold across all five — a figure whose legs
## are 33% of its height at one setting and 41% at another is not the same character resized.

const SkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

const MIN_STEP := 0.03
## Metres of arm that must be visible outside the torso silhouette.
const MIN_ARM_CLEAR := 0.06
## How far the leg fraction may drift across the five frames.
const RATIO_SPREAD := 0.05
## The head is a band, not a constant. Once the face plate needs a minimum skull to keep a chin on
## it, the short frames necessarily carry a proportionally larger head — that is the stylised
## convention, not a defect. What still has to hold is that no frame leaves the plausible range and
## that a taller frame never gets a smaller skull, which is what the original bug looked like: one
## literal head size for every stature, drifting from 27% of height down to 19%.
const HEAD_FRACTION_MIN := 0.18
const HEAD_FRACTION_MAX := 0.28
## The smallest skull the face plate still fits on with a jaw left under it. The plate is seated two
## voxels above the head's base and sized from the head, so at seven voxels it reaches the collar
## and the chin is gone — which is what "the head is inside the torso" looked like on Slight and
## Stout. Eight voxels at 0.04 m each. This is the check that fails on that build; the fraction band
## above does not, and neither does head clearance, because the head was seated correctly the whole
## time and simply too small to carry a face.
const MIN_HEAD_SIZE := 0.32


## Head height in metres per frame, for the monotonicity check below.
var _part_head_height: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	var frames: Array = CharacterAppearance.FRAME_VARIANTS
	var size_by: Dictionary = {}
	var ratios: Dictionary = {}
	for f: String in frames:
		var profile := CharacterAppearance.default_profile()
		profile["frame"] = f
		var host := Node3D.new()
		add_child(host)
		SkinScript.build_preview_body(host, profile)
		await get_tree().process_frame
		size_by[f] = _measure(host)
		var head := _part_size(host, "Head")
		_part_head_height[f] = head.y
		var torso := _part_size(host, "Torso")
		var leg := _part_size(host, "LegL")
		var arm := _part_size(host, "ArmL")
		var total := head.y + torso.y + leg.y
		ratios[f] = {
			"head": head.y / maxf(total, 0.001),
			"leg": leg.y / maxf(total, 0.001),
			"arm_out": (arm.x * 0.0) + _arm_protrusion(host),
			"head_clear": _head_clear(host),
		}
		host.queue_free()

	var fails := 0
	print("AUDIT frames")
	for f: String in frames:
		var s3: Vector3 = size_by[f]
		var r: Dictionary = ratios[f]
		print(
			(
				"AUDIT %-9s %5.2f m tall  %5.2f m wide   legs %2.0f%%  head %2.0f%%  "
				+ "arm clear %.2f m  head clear %2.0f%%"
			)
			% [
				f,
				s3.y,
				s3.x,
				float(r["leg"]) * 100.0,
				float(r["head"]) * 100.0,
				r["arm_out"],
				float(r["head_clear"]) * 100.0,
			]
		)

	# Every frame must be tellable from every other by size alone.
	for i in frames.size():
		for j in range(i + 1, frames.size()):
			var a3: Vector3 = size_by[frames[i]]
			var b3: Vector3 = size_by[frames[j]]
			if absf(a3.x - b3.x) < MIN_STEP and absf(a3.y - b3.y) < MIN_STEP:
				print("AUDIT FAIL %s and %s are the same size" % [frames[i], frames[j]])
				fails += 1

	# Proportions must hold across all five, and the arms must clear the body.
	var legs: Array[float] = []
	var heads: Array[float] = []
	for f: String in frames:
		legs.append(float((ratios[f] as Dictionary)["leg"]))
		heads.append(float((ratios[f] as Dictionary)["head"]))
		var clear: float = float((ratios[f] as Dictionary)["arm_out"])
		if clear < MIN_ARM_CLEAR:
			print("AUDIT FAIL %s: arms clear the torso by only %.3f m" % [f, clear])
			fails += 1
	var leg_spread: float = legs.max() - legs.min()
	var head_spread: float = heads.max() - heads.min()
	if leg_spread > RATIO_SPREAD:
		print("AUDIT FAIL leg/height spread %.3f exceeds %.3f" % [leg_spread, RATIO_SPREAD])
		fails += 1
	for f: String in frames:
		var head_h: float = _part_head_height[f]
		if head_h < MIN_HEAD_SIZE - 0.001:
			print("AUDIT FAIL %s: head is %.2f m, under the %.2f m the face plate needs"
				% [f, head_h, MIN_HEAD_SIZE])
			fails += 1
		var frac: float = float((ratios[f] as Dictionary)["head"])
		if frac < HEAD_FRACTION_MIN or frac > HEAD_FRACTION_MAX:
			print("AUDIT FAIL %s: head is %.0f%% of height, outside %.0f-%.0f%%"
				% [f, frac * 100.0, HEAD_FRACTION_MIN * 100.0, HEAD_FRACTION_MAX * 100.0])
			fails += 1
	# A taller frame may not have a smaller skull. Sorted by height rather than by the order the
	# variants are declared in, because that order is a menu, not a scale.
	var by_height: Array = frames.duplicate()
	by_height.sort_custom(
		func(a: String, b: String) -> bool:
			return (size_by[a] as Vector3).y < (size_by[b] as Vector3).y
	)
	for i in range(1, by_height.size()):
		var prev: float = _part_head_height[by_height[i - 1]]
		var here: float = _part_head_height[by_height[i]]
		if here < prev - 0.001:
			print("AUDIT FAIL %s is taller than %s but has a smaller head"
				% [by_height[i], by_height[i - 1]])
			fails += 1
	print("AUDIT spread: legs %.3f (max %.2f)  head %.3f in %.2f-%.2f"
		% [leg_spread, RATIO_SPREAD, head_spread, HEAD_FRACTION_MIN, HEAD_FRACTION_MAX])
	fails += await _audit_garments(frames)
	print("AUDIT RESULT %d failures across %d frames" % [fails, frames.size()])
	get_tree().quit(0)


## What fraction of the head stands above everything at the shoulders — the torso's collar and both
## pauldrons. This is what "the head is inside the torso" actually means: the head mesh can be the
## right size and seated correctly and still be swallowed, because the collar and the pauldron rise
## past its jaw. Measuring the mesh alone never showed it.
func _head_clear(root: Node3D) -> float:
	var head := _part_bounds(root, "Head")
	if head == AABB():
		return 0.0
	var shoulder_top: float = _top_of(root, "Torso")
	shoulder_top = maxf(shoulder_top, _top_of(root, "Pauldron"))
	shoulder_top = maxf(shoulder_top, _top_of(root, "PauldronR"))
	var head_top := head.position.y + head.size.y
	return clampf((head_top - shoulder_top) / maxf(head.size.y, 0.001), 0.0, 1.0)


func _top_of(root: Node3D, part: String) -> float:
	var b := _part_bounds(root, part)
	if b == AABB():
		return -INF
	return b.position.y + b.size.y


## How far the arm sticks out past the side of the torso. An arm buried inside its own body is why
## the narrow frames looked like they had no hands.
func _arm_protrusion(root: Node3D) -> float:
	var torso := _part_bounds(root, "Torso")
	var arm := _part_bounds(root, "ArmL")
	if torso == AABB() or arm == AABB():
		return 0.0
	return (torso.position.x) - (arm.position.x)


func _part_size(root: Node3D, part: String) -> Vector3:
	var b := _part_bounds(root, part)
	return b.size if b != AABB() else Vector3.ONE


func _part_bounds(root: Node3D, part: String) -> AABB:
	var node := root.find_child(part, true, false) as Node3D
	if node == null:
		return AABB()
	# The part's own mesh only: ArmL and Head are children of Torso in the rig, so walking the
	# subtree measures the whole upper body and calls it the torso.
	var mesh := node.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return AABB()
	return mesh.global_transform * mesh.mesh.get_aabb()


func _measure(root: Node3D) -> Vector3:
	var aabb := AABB()
	var first := true
	for node in _all_meshes(root):
		var mesh := node as MeshInstance3D
		if mesh.mesh == null:
			continue
		# Only what is actually on screen. The rig builds every head style and hides the ones not
		# chosen, so counting hidden meshes measured the hood on a warden wearing a visor — which
		# made the standard stature read 4cm taller than its neighbours and the steps look uneven
		# when the geometry was fine.
		if not mesh.is_visible_in_tree():
			continue
		var world := mesh.global_transform * mesh.mesh.get_aabb()
		if first:
			aabb = world
			first = false
		else:
			aabb = aabb.merge(world)
	return aabb.size


func _all_meshes(node: Node) -> Array:
	var out: Array = []
	if node is MeshInstance3D:
		out.append(node)
	for child in node.get_children():
		out.append_array(_all_meshes(child))
	return out


## Class clothing has to fit the frame wearing it.
##
## The garment is grown from a torso volume by the generator and is never scaled at runtime, so a
## surcoat authored for one chest width is simply the wrong garment on another — too narrow to close
## on the broad frames, hanging off the sides on the narrow ones. Every class was cut for the
## standard 12-wide torso and worn by all five.
##
## The volume wraps the torso, so it is expected to be *slightly* wider than the body it covers:
## `sculpt_garment` builds it at `torso + 2` in x and z. Anything outside that band is a garment
## belonging to a different frame.
## `sculpt_garment` builds the volume at `torso + 2` in x and z, so the margin is 0.08 m on every
## frame that wears its own cut. The band is one voxel either side of that. Zero is *not* an
## acceptable floor: when all five frames shared the standard 14-wide cut, Stout's 14-wide torso
## measured exactly 0.00 m of margin — the surcoat sat inside the chest rather than over it — and a
## floor of zero would have called that passing.
const GARMENT_MARGIN_MIN := 0.04
const GARMENT_MARGIN_MAX := 0.12
const CLASS_IDS: PackedStringArray = [
	"knight", "sentinel", "berserker", "rogue", "hunter", "scholar", "herald",
]


func _audit_garments(frames: Array) -> int:
	var fails := 0
	print("AUDIT garments (width over the torso, metres)")
	for f: String in frames:
		var line := "AUDIT %-9s" % f
		for class_id: String in CLASS_IDS:
			var profile := CharacterAppearance.default_profile()
			profile["frame"] = f
			profile["classId"] = class_id
			var host := Node3D.new()
			add_child(host)
			SkinScript.build_preview_body(host, profile)
			await get_tree().process_frame
			var torso := _part_bounds(host, "Torso")
			var garment := _garment_bounds(host)
			host.queue_free()
			if torso == AABB() or garment == AABB():
				print("AUDIT FAIL %s / %s: no garment built" % [f, class_id])
				fails += 1
				continue
			var over := garment.size.x - torso.size.x
			line += "  %s %+.2f" % [class_id.substr(0, 3), over]
			if over < GARMENT_MARGIN_MIN or over > GARMENT_MARGIN_MAX:
				print("AUDIT FAIL %s / %s: garment is %.2f m over the torso, outside %.2f-%.2f"
					% [f, class_id, over, GARMENT_MARGIN_MIN, GARMENT_MARGIN_MAX])
				fails += 1
		print(line)
	return fails


## The garment is merged into the rig by `MeshMerger`, so it is found by name rather than by walking
## for a "Mesh" child the way the rigid parts are.
func _garment_bounds(root: Node3D) -> AABB:
	var holder := root.find_child("ClassGarment", true, false) as Node3D
	if holder == null:
		return AABB()
	var mesh := holder.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return AABB()
	return mesh.global_transform * mesh.mesh.get_aabb()
