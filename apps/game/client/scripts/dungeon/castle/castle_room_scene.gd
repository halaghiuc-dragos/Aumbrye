extends RoomTemplate
class_name CastleRoomScene

## Shared setup for castle blockout rooms — applies materials and socket rotations.


func _ready() -> void:
	var blockout := get_node_or_null("CastleBlockout") as CastleBlockout
	if blockout:
		if blockout.floor_material == null:
			blockout.floor_material = load("res://assets/castle/mat_floor.tres")
		if blockout.wall_material == null:
			blockout.wall_material = load("res://assets/castle/mat_wall.tres")
		if blockout.accent_material == null:
			blockout.accent_material = load("res://assets/castle/mat_accent.tres")
	_align_socket_rotations()


func _align_socket_rotations() -> void:
	for socket in get_sockets():
		match socket.direction:
			CastleRoomConstants.Direction.NORTH:
				socket.rotation_degrees = Vector3(0.0, 0.0, 0.0)
			CastleRoomConstants.Direction.SOUTH:
				socket.rotation_degrees = Vector3(0.0, 180.0, 0.0)
			CastleRoomConstants.Direction.EAST:
				socket.rotation_degrees = Vector3(0.0, -90.0, 0.0)
			CastleRoomConstants.Direction.WEST:
				socket.rotation_degrees = Vector3(0.0, 90.0, 0.0)
