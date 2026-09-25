extends Node3D

var _failures := 0


func _check(condition: bool, message: String) -> void:
	if not condition:
		_failures += 1
		push_error(message)


func _room_with_props(anchor_positions: Array[Vector3]) -> Node3D:
	var room := Node3D.new()
	var props := Node3D.new()
	props.name = "Props"
	room.add_child(props)
	for index in anchor_positions.size():
		var anchor := Node3D.new()
		anchor.name = "PropAnchor_%d" % index
		anchor.position = anchor_positions[index]
		props.add_child(anchor)
	add_child(room)
	return room


func _content(room: Node3D, required: bool) -> RoomContentBase:
	var content := RoomContentBase.new()
	content.set_meta("required_content", required)
	room.add_child(content)
	return content


func _ready() -> void:
	var authored_room := _room_with_props([Vector3(2.0, 0.0, -3.0)])
	var authored := _content(authored_room, true)
	var authored_result := authored.prepare_placement(true)
	_check(bool(authored_result.get("ok", false)), "Required content accepts an authored free anchor")
	_check(not bool(authored_result.get("fallback", true)), "Authored anchor must not report fallback")
	var authored_transform: Variant = authored_result.get("transform")
	_check(authored_transform is Transform3D and (authored_transform as Transform3D).origin.is_equal_approx(Vector3(2.0, 0.0, -3.0)), "Placement result preserves root-local anchor transform")

	var missing_room := _room_with_props([])
	var optional := _content(missing_room, false)
	var optional_result := optional.prepare_placement(false)
	_check(bool(optional_result.get("ok", false)) and bool(optional_result.get("fallback", false)), "Optional content gets explicit root-local fallback")
	var optional_transform: Variant = optional_result.get("transform")
	_check(optional_transform is Transform3D and (optional_transform as Transform3D).is_equal_approx(Transform3D.IDENTITY), "Optional fallback is identity, not inherited world translation")
	var required_missing := _content(missing_room, true)
	var missing_result := required_missing.prepare_placement(true)
	_check(not bool(missing_result.get("ok", true)), "Required content rejects a missing anchor")

	var crowded_room := _room_with_props([Vector3.ZERO, Vector3(0.8, 0.0, 0.0)])
	var first := _content(crowded_room, true)
	_check(bool(first.prepare_placement(true, 0, 0.75).get("ok", false)), "First required placement reserves its footprint")
	var overlapping := _content(crowded_room, true)
	_check(not bool(overlapping.prepare_placement(true, 1, 0.75).get("ok", true)), "Overlapping required footprints are rejected")

	print("ROOM CONTENT PLACEMENT RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)
