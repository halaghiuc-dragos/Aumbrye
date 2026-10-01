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


## X/Z stays a rectangle even for round rooms (round rooms have a circular footprint, but the
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
	# The shell's bedrock is two metres below room floors. It must never count as
	# being inside a room, or the fall recovery will leave the player stranded there.
	var min_y := -0.75
	var max_y := blockout.wall_height + 4.0
	return local.y >= min_y and local.y <= max_y
