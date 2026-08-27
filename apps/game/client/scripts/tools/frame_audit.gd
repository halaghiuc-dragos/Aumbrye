extends Node3D


const SkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")

const MIN_STEP := 0.03
const MIN_ARM_CLEAR := 0.06
const RATIO_SPREAD := 0.05
const HEAD_FRACTION_MIN := 0.18
const HEAD_FRACTION_MAX := 0.28
const MIN_HEAD_SIZE := 0.32


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

	for i in frames.size():
		for j in range(i + 1, frames.size()):
			var a3: Vector3 = size_by[frames[i]]
			var b3: Vector3 = size_by[frames[j]]
			if absf(a3.x - b3.x) < MIN_STEP and absf(a3.y - b3.y) < MIN_STEP:
				print("AUDIT FAIL %s and %s are the same size" % [frames[i], frames[j]])
				fails += 1

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


func _garment_bounds(root: Node3D) -> AABB:
	var holder := root.find_child("ClassGarment", true, false) as Node3D
	if holder == null:
		return AABB()
	var mesh := holder.get_node_or_null("Mesh") as MeshInstance3D
	if mesh == null or mesh.mesh == null:
		return AABB()
	return mesh.global_transform * mesh.mesh.get_aabb()
