extends Node3D
class_name RoomTemplate


@export var template_id: String = ""
@export var room_id: String = ""
@export var room_type: String = "combat"
@export var room_kind: String = ""

@export var room_tags: PackedStringArray = PackedStringArray()


@export var player_spawn_path: NodePath = NodePath("SpawnPoints/PlayerSpawn")
@export var nav_region_path: NodePath = NodePath("CastleBlockout/NavigationRegion3D")


func get_sockets() -> Array[DoorwaySocket]:
	var sockets: Array[DoorwaySocket] = []
	var socket_root := get_node_or_null("DoorwaySockets")
	if socket_root == null:
		return sockets
	for child in socket_root.get_children():
		if child is DoorwaySocket:
			sockets.append(child)
	return sockets


func find_socket(direction: CastleRoomConstants.Direction) -> DoorwaySocket:
	for socket in get_sockets():
		if socket.direction == direction:
			return socket
	return null


func door_mask_toward(other: RoomTemplate) -> int:
	var delta := other.global_position - global_position
	if absf(delta.x) > absf(delta.z):
		return RoomGraphSlot.DOOR_EAST if delta.x > 0.0 else RoomGraphSlot.DOOR_WEST
	return RoomGraphSlot.DOOR_SOUTH if delta.z > 0.0 else RoomGraphSlot.DOOR_NORTH


func socket_toward(other: RoomTemplate) -> DoorwaySocket:
	var want := other.global_position - global_position
	want.y = 0.0
	if want.length_squared() < 0.0001:
		return null
	want = want.normalized()
	var best: DoorwaySocket = null
	var best_dot := 0.5
	for socket in get_sockets():
		var dot := socket.get_world_facing().dot(want)
		if dot > best_dot:
			best_dot = dot
			best = socket
	return best


func socket_for_direction(
	direction: CastleRoomConstants.Direction, prefer_secret: bool = false
) -> DoorwaySocket:
	if prefer_secret:
		for socket in get_sockets():
			if socket.direction == direction and socket.is_secret:
				return socket
	return find_socket(direction)


func get_player_spawn_global() -> Vector3:
	var spawn := get_node_or_null(player_spawn_path) as Node3D
	if spawn:
		return spawn.global_position
	return global_position


func get_nav_region() -> NavigationRegion3D:
	return get_node_or_null(nav_region_path) as NavigationRegion3D


func get_blockout() -> CastleBlockout:
	return get_node_or_null("CastleBlockout") as CastleBlockout


## X/Z stays a rectangle even for round rooms (RM-01 gives those a circular footprint, but the
## containment test here only needs to know "roughly this room's plot"). The Y band is what makes
## this test mean anything at all: without it, a player falling through the floor still reads as
## "inside" whichever room is overhead, and the out-of-world recovery in `castle_run.gd` can never
## see that anything went wrong.
func contains_world_point(world_pos: Vector3) -> bool:
	var blockout := get_blockout()
	if blockout == null:
		return false
	var local := to_local(world_pos)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	if absf(local.x) > half_w or absf(local.z) > half_d:
		return false
	var min_y := position.y - 4.0
	var max_y := position.y + CastleRoomConstants.WALL_HEIGHT + 4.0
	return world_pos.y >= min_y and world_pos.y <= max_y
