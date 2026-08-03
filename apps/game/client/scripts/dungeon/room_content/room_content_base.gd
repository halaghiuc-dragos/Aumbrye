extends Node3D
class_name RoomContentBase

## Base for seed-agnostic room content nodes (read/write WorldState only).


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	pass


func _content_root() -> Node3D:
	var props := get_parent().get_node_or_null("Props")
	return props as Node3D if props else get_parent() as Node3D
