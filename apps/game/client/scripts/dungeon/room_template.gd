extends Node3D
class_name RoomTemplate

## Hand-authored dungeon room prefab consumed by DungeonBuilder (M2+).

@export var template_id: String = ""
@export var room_id: String = ""
@export var room_type: String = "combat"
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


func get_player_spawn_global() -> Vector3:
	var spawn := get_node_or_null(player_spawn_path) as Node3D
	if spawn:
		return spawn.global_position
	return global_position


func get_nav_region() -> NavigationRegion3D:
	return get_node_or_null(nav_region_path) as NavigationRegion3D


func get_blockout() -> CastleBlockout:
	return get_node_or_null("CastleBlockout") as CastleBlockout


func contains_world_point(world_pos: Vector3) -> bool:
	var blockout := get_blockout()
	if blockout == null:
		return false
	var local := to_local(world_pos)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	return absf(local.x) <= half_w and absf(local.z) <= half_d
