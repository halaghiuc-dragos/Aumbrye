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
	var marker := root.get_node_or_null("PropAnchor_%d" % index) as Node3D
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
		marker = root.get_node_or_null("PropAnchor_0") as Node3D
	if marker == null:
		push_warning(
			"RoomContent missing PropAnchor_%d on %s" % [index, get_parent().name if get_parent() else name]
		)
		return root
	return marker
