extends Node3D
class_name RoomTemplate

## Hand-authored dungeon room prefab consumed by DungeonBuilder (M2+).

@export var template_id: String = ""
@export var room_id: String = ""
@export var room_type: String = "combat"
## The role the floor generator assigned this room — `combat`, `stairs`, `boss`, `treasure`,
## `shop`, `rest`, `lore`. Distinct from `template_id`, which only says which *scene* was picked
## to fit the room's door mask: templates are interchangeable shapes, so an ordinary combat room
## can legitimately be built from `castle_stairs` geometry. Anything that cares about a room's
## role must read this and not the template id.
@export var room_kind: String = ""

## C-151: the generator tags rooms `["merchant"]`, `["traversal"]`, `["spawn"]`, `["final_arena"]`,
## `["final_boss"]` and so on, `room_graph_geometry` copies them into every room record, and nothing
## anywhere read them — a room-level behaviour hook carried all the way into the definition and
## dropped on the floor. They reach the room node now, and the node joins a group per tag so a
## system can find "every arena" or "the merchant room" without walking the definition.
@export var room_tags: PackedStringArray = PackedStringArray()


func has_room_tag(tag: String) -> bool:
	return room_tags.has(tag)
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


func contains_world_point(world_pos: Vector3) -> bool:
	var blockout := get_blockout()
	if blockout == null:
		return false
	var local := to_local(world_pos)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	return absf(local.x) <= half_w and absf(local.z) <= half_d
