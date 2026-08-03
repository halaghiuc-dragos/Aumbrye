extends RoomTemplate
class_name CastleRoomScene

## Shared setup for castle blockout rooms — applies materials and socket rotations.


func _ready() -> void:
	var biome_id := _resolve_biome_id()
	var blockout := get_node_or_null("CastleBlockout") as CastleBlockout
	if blockout:
		var needs_rebuild := false
		if blockout.floor_material == null:
			blockout.floor_material = BiomeRegistry.get_floor_material(biome_id)
			needs_rebuild = true
		if blockout.wall_material == null:
			blockout.wall_material = BiomeRegistry.get_wall_material(biome_id)
			needs_rebuild = true
		if blockout.accent_material == null:
			blockout.accent_material = BiomeRegistry.get_accent_material(biome_id)
		if needs_rebuild:
			blockout._request_rebuild()
	_align_socket_rotations()
	DioramaRoomDressing.apply_to_room(self, biome_id)


func _resolve_biome_id() -> String:
	if RunFlow.current_biome_id != "":
		return RunFlow.current_biome_id
	return BiomeRegistry.biome_from_template_id(template_id)


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
