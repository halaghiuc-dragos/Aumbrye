extends Node

## Exercises the equipment *visuals* -- the models that go on the warden when gear is
## worn -- rather than the inventory data behind them.
##
## What it checks, for every equippable item and over repeated equip/unequip cycles:
##
##   - mounted models do not accumulate: taking gear off removes its nodes
##   - body parts hidden by armour come back when the armour comes off
##   - every mounted model is a sane size next to the body part it is worn on
##
## Diagnostic, not a test suite.

const SkinScript := preload("res://scripts/art/characters/diorama_character_skin.gd")
const EquipmentHelper := preload("res://scripts/items/equipment.gd")

## A model more than this many times the size of the body part it is fitted to is
## reported. Fitted gear should be within a small multiple of its part.
const MAX_SIZE_RATIO := 6.0

var _failures: Array[String] = []
var _visual: Node3D


func _ready() -> void:
	var facing := Node3D.new()
	add_child(facing)
	_visual = SkinScript.build_player_body(facing, 0)
	if _visual == null:
		print("EQUIPVIS could not build a player body")
		get_tree().quit(1)
		return
	await get_tree().process_frame

	var baseline_nodes := _count_equip_nodes()
	var baseline_hidden := _hidden_parts()

	var checked := 0
	for item_id in _equipment_ids():
		var def := ItemCatalog.get_definition(item_id)
		var slot_name := EquipmentHelper.slot_for_item_def(def)
		if slot_name == "":
			continue
		checked += 1
		# Wear it.
		var equipped := EquipmentHelper.empty_equipped()
		equipped[slot_name] = {"itemId": item_id, "quantity": 1}
		SkinScript.apply_equipment(_visual, equipped, 0)
		_check_sizes(item_id, slot_name)

		# Take it off again.
		SkinScript.apply_equipment(_visual, EquipmentHelper.empty_equipped(), 0)
		var nodes := _count_equip_nodes()
		if nodes != baseline_nodes:
			_fail(
				"%s in %s: %d equipment nodes left behind after unequip (baseline %d)"
				% [item_id, slot_name, nodes, baseline_nodes]
			)
			break
		var hidden := _hidden_parts()
		var still_hidden := _difference(hidden, baseline_hidden)
		if not still_hidden.is_empty():
			_fail(
				"%s in %s: body parts still hidden after unequip: %s"
				% [item_id, slot_name, ", ".join(still_hidden)]
			)
			break

	_check_repeat_cycles()

	print("EQUIPVIS exercised %d items" % checked)
	if _failures.is_empty():
		print("EQUIPVIS RESULT 0 failures")
	else:
		print("EQUIPVIS RESULT %d failures" % _failures.size())
		for line in _failures:
			print("  " + line)
	get_tree().quit(0 if _failures.is_empty() else 1)


func _fail(message: String) -> void:
	_failures.append(message)


func _equipment_ids() -> Array[String]:
	var out: Array[String] = []
	for item_id in ItemCatalog.get_items_by_type("armor"):
		out.append(item_id)
	for item_id in ItemCatalog.get_items_by_type("weapon"):
		out.append(item_id)
	for item_id in ItemCatalog.get_items_by_type("accessory"):
		out.append(item_id)
	out.sort()
	return out


func _count_equip_nodes() -> int:
	return _collect_prefixed(_visual).size()


func _collect_prefixed(node: Node) -> Array[Node]:
	var found: Array[Node] = []
	if str(node.name).begins_with(SkinScript.EQUIP_VISUAL_PREFIX):
		found.append(node)
	for child in node.get_children():
		found.append_array(_collect_prefixed(child))
	return found


## Names of every mesh currently invisible, so a part that armour hid and never
## restored can be named rather than just counted.
func _hidden_parts() -> Array[String]:
	var out: Array[String] = []
	_walk_hidden(_visual, out)
	out.sort()
	return out


func _walk_hidden(node: Node, out: Array[String]) -> void:
	var mesh := node as GeometryInstance3D
	if mesh != null and not mesh.visible:
		# Every mesh is called "Mesh"; the path is what identifies the body part.
		var path := str(node.name)
		var walk := node.get_parent()
		while walk != null and walk != _visual:
			path = "%s/%s" % [walk.name, path]
			walk = walk.get_parent()
		out.append(path)
	for child in node.get_children():
		_walk_hidden(child, out)


func _difference(a: Array[String], b: Array[String]) -> Array[String]:
	var out: Array[String] = []
	for part_name in a:
		if not (part_name in b):
			out.append(part_name)
	return out


## A mounted model should be in the same league as the body part it is worn on. A
## helmet ten times the size of a head is the "weird model" case this is looking for.
func _check_sizes(item_id: String, slot_name: String) -> void:
	for node in _collect_prefixed(_visual):
		var holder := node as Node3D
		if holder == null:
			continue
		var parent := holder.get_parent() as Node3D
		if parent == null:
			continue
		var model := _world_size(holder)
		var part := _part_size(parent)
		if model == Vector3.ZERO or part == Vector3.ZERO:
			continue
		for axis in 3:
			if part[axis] <= 0.0001:
				continue
			var ratio: float = model[axis] / part[axis]
			if ratio > MAX_SIZE_RATIO or not is_finite(ratio):
				_fail(
					"%s in %s: model is %.1fx the %s part on axis %d (%.3f vs %.3f)"
					% [item_id, slot_name, ratio, parent.name, axis, model[axis], part[axis]]
				)
				return


func _world_size(root: Node3D) -> Vector3:
	var box := _merged_aabb(root, root, true)
	return box.size * root.scale.abs() if box.size != Vector3.ZERO else Vector3.ZERO


func _part_size(part: Node3D) -> Vector3:
	return _merged_aabb(part, part, false).size


## Merged mesh bounds in `root` space. `equipment_only` picks between the mounted
## models under `root` and the part's own geometry.
func _merged_aabb(node: Node, root: Node3D, equipment_only: bool) -> AABB:
	var result := AABB()
	var started := false
	var stack: Array[Node] = [node]
	while not stack.is_empty():
		var current: Node = stack.pop_back()
		var is_equip := str(current.name).begins_with(SkinScript.EQUIP_VISUAL_PREFIX)
		if is_equip and not equipment_only and current != node:
			continue
		var mesh := current as MeshInstance3D
		if mesh != null and mesh.mesh != null:
			var local := root.global_transform.affine_inverse() * mesh.global_transform
			var box := local * mesh.mesh.get_aabb()
			result = box if not started else result.merge(box)
			started = true
		for child in current.get_children():
			stack.append(child)
	return result


## Equipping and unequipping the same thing over and over must not drift: this is what
## catches nodes or hidden parts piling up one cycle at a time.
func _check_repeat_cycles() -> void:
	var ids := _equipment_ids()
	if ids.is_empty():
		return
	SkinScript.apply_equipment(_visual, EquipmentHelper.empty_equipped(), 0)
	var baseline_nodes := _count_equip_nodes()
	var baseline_hidden := _hidden_parts().size()

	var rng := RandomNumberGenerator.new()
	rng.seed = 31337
	for cycle in 60:
		var equipped := EquipmentHelper.empty_equipped()
		for i in 4:
			var item_id: String = ids[rng.randi() % ids.size()]
			var slot_name := EquipmentHelper.slot_for_item_def(
				ItemCatalog.get_definition(item_id)
			)
			if slot_name != "":
				equipped[slot_name] = {"itemId": item_id, "quantity": 1}
		SkinScript.apply_equipment(_visual, equipped, 0)
		SkinScript.apply_equipment(_visual, EquipmentHelper.empty_equipped(), 0)
		var now := _hidden_parts()
		if now.size() != baseline_hidden:
			var worn: Array[String] = []
			for slot_name in equipped:
				var inst: Dictionary = equipped[slot_name]
				if not inst.is_empty():
					worn.append("%s=%s" % [slot_name, inst.get("itemId", "")])
			print(
				"EQUIPVIS first divergence at cycle %d wearing [%s]; hidden now: %s"
				% [cycle, ", ".join(worn), ", ".join(now)]
			)
			break

	var nodes := _count_equip_nodes()
	if nodes != baseline_nodes:
		_fail(
			"after 60 equip/unequip cycles: %d equipment nodes (baseline %d)"
			% [nodes, baseline_nodes]
		)
	var hidden := _hidden_parts().size()
	if hidden != baseline_hidden:
		_fail(
			"after 60 equip/unequip cycles: %d hidden meshes (baseline %d)"
			% [hidden, baseline_hidden]
		)
