extends Marker3D
class_name DoorwaySocket

## Doorway attachment point on a castle room template edge.
## Doorway socket markers for room prefab connectivity (N/E/S/W at room edges).

@export var direction: CastleRoomConstants.Direction = CastleRoomConstants.Direction.NORTH
@export var socket_id: String = ""
@export var is_secret: bool = false


func get_socket_name() -> String:
	if not socket_id.is_empty():
		return socket_id
	return CastleRoomConstants.SOCKET_NAMES.get(direction, "Socket_Unknown")


func get_world_facing() -> Vector3:
	var room := get_parent().get_parent() as Node3D
	var basis := global_transform.basis if room == null else room.global_transform.basis
	match direction:
		CastleRoomConstants.Direction.NORTH:
			return -basis.z
		CastleRoomConstants.Direction.SOUTH:
			return basis.z
		CastleRoomConstants.Direction.EAST:
			return basis.x
		CastleRoomConstants.Direction.WEST:
			return -basis.x
	return -basis.z
