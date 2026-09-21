extends Node3D
class_name RoomContentBase


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	pass


func _content_root() -> Node3D:
	var props := get_parent().get_node_or_null("Props")
	return props as Node3D if props else get_parent() as Node3D


static var _warned_anchors: Dictionary = {}


func _anchor(index: int = 0) -> Node3D:
	var root := _content_root()
	var reservations: Dictionary = root.get_meta("content_anchor_reservations", {}) as Dictionary
	var owner := str(get_instance_id())
	var marker := root.get_node_or_null("PropAnchor_%d" % index) as Node3D
	if marker and str(reservations.get(marker.name, owner)) != owner:
		marker = null
		for candidate in root.get_children():
			if not candidate is Node3D or not candidate.name.begins_with("PropAnchor_"):
				continue
			if not reservations.has(candidate.name):
				marker = candidate as Node3D
				break
	if marker == null and index != 0:
		var room_name := get_parent().name if get_parent() else name
		var warn_key := "%s/%d" % [room_name, index]
		if not _warned_anchors.has(warn_key):
			_warned_anchors[warn_key] = true
			push_warning(
				(
					"RoomContent: %s has no PropAnchor_%d; falling back to PropAnchor_0, which"
					+ " stacks this content on whatever already uses it."
				)
				% [room_name, index]
			)
		var fallback := root.get_node_or_null("PropAnchor_0") as Node3D
		if fallback and str(reservations.get(fallback.name, owner)) == owner:
			marker = fallback
		elif fallback and not reservations.has(fallback.name):
			marker = fallback
	if marker == null:
		push_warning(
			"RoomContent missing PropAnchor_%d on %s" % [index, get_parent().name if get_parent() else name]
		)
		marker = root.get_node_or_null("FallbackPropAnchor_%d" % index) as Node3D
		if marker == null:
			marker = Node3D.new()
			var fallback_index := index
			while reservations.has("FallbackPropAnchor_%d" % fallback_index):
				fallback_index += 1
			marker.name = "FallbackPropAnchor_%d" % fallback_index
			marker.position = Vector3(
				float(fallback_index % 3) * 1.5, 0.0, float(fallback_index / 3) * 1.5
			)
			root.add_child(marker)
	reservations[marker.name] = owner
	root.set_meta("content_anchor_reservations", reservations)
	return marker
