extends Marker3D
class_name DoorwaySocket

## Doorway attachment point on a castle room template edge.
## See docs/design/CASTLE_ROOM_SOCKETS.md for placement rules.

@export var direction: CastleRoomConstants.Direction = CastleRoomConstants.Direction.NORTH
@export var socket_id: String = ""
@export var is_secret: bool = false


func get_socket_name() -> String:
	if not socket_id.is_empty():
		return socket_id
	return CastleRoomConstants.SOCKET_NAMES.get(direction, "Socket_Unknown")


func get_world_facing() -> Vector3:
	match direction:
		CastleRoomConstants.Direction.NORTH:
			return -global_transform.basis.z
		CastleRoomConstants.Direction.SOUTH:
			return global_transform.basis.z
		CastleRoomConstants.Direction.EAST:
			return global_transform.basis.x
		CastleRoomConstants.Direction.WEST:
			return -global_transform.basis.x
	return Vector3.FORWARD
