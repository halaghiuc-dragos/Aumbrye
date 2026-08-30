extends RoomTemplate
class_name CastleRoomScene


const DoorwaySocketScript := preload("res://scripts/dungeon/doorway_socket.gd")
const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

const SOCKET_DIRECTIONS := [
	CastleRoomConstants.Direction.NORTH,
	CastleRoomConstants.Direction.EAST,
	CastleRoomConstants.Direction.SOUTH,
	CastleRoomConstants.Direction.WEST,
]


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
		sync_kit_contract()
		if needs_rebuild:
			blockout._request_rebuild()
	DioramaRoomDressing.apply_to_room(self, biome_id, room_id.hash())
	_skin_untextured_props(biome_id)


## Authored props with no material on them.
##
## A room scene may author a prop the code also knows how to build -- the stair ramp is the case
## that started this. `_ensure_stair_ramp` returns early when the node already exists, which is the
## right call for its geometry and the wrong one for its material: the authored node kept its
## position and never got skinned, so every stairs room in all ten biomes had the player walking up
## a slab of Godot's default grey. The secret-cue panel in the courtyards was worse -- nothing in
## the code touched it at all, so it was never going to get a material from anywhere.
##
## Rather than chase each prop, anything visible in Props with nothing to draw it with gets the
## biome accent. It cannot overwrite authored art, because it only touches meshes that have no
## material of any kind, and it means the next authored prop someone forgets to skin comes out in
## the palette instead of in grey.
func _skin_untextured_props(biome_id: String) -> void:
	var props := get_node_or_null("Props") as Node3D
	if props == null:
		return
	var accent := BiomeRegistry.get_accent_material(biome_id)
	if accent == null:
		return
	for node in props.find_children("*", "MeshInstance3D", true, false):
		var mesh_instance := node as MeshInstance3D
		if mesh_instance == null or not mesh_instance.visible:
			continue
		if _has_any_material(mesh_instance):
			continue
		mesh_instance.material_override = accent


static func _has_any_material(mesh_instance: MeshInstance3D) -> bool:
	if mesh_instance.material_override != null:
		return true
	if mesh_instance.mesh == null:
		return true
	for surface in mesh_instance.mesh.get_surface_count():
		if mesh_instance.get_surface_override_material(surface) != null:
			return true
		if mesh_instance.mesh.surface_get_material(surface) != null:
			return true
	return false


func sync_kit_contract() -> void:
	var blockout := get_blockout()
	if blockout == null:
		return
	if blockout.kind.is_empty() and not template_id.is_empty():
		blockout.kind = RoomTemplateCatalogScript.kind_from_template_id(template_id)
	blockout.sync_dimensions_from_kind()
	_ensure_socket_completeness(blockout)
	_ensure_marker_contract(blockout, _resolve_biome_id())
	_align_socket_rotations()


func _resolve_biome_id() -> String:
	var from_template := BiomeRegistry.biome_from_template_id(template_id)
	if from_template != "":
		return from_template
	return RunFlow.current_biome_id


func _ensure_socket_completeness(blockout: CastleBlockout) -> void:
	var socket_root := get_node_or_null("DoorwaySockets")
	if socket_root == null:
		socket_root = Node3D.new()
		socket_root.name = "DoorwaySockets"
		add_child(socket_root)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	for direction in SOCKET_DIRECTIONS:
		var socket := find_socket(direction)
		if socket == null:
			socket = DoorwaySocketScript.new()
			socket.name = CastleRoomConstants.SOCKET_NAMES.get(direction, "Socket_Unknown")
			socket.direction = direction
			socket_root.add_child(socket)
		socket.position = RoomTemplateCatalogScript.socket_wall_position(
			direction, half_w, half_d
		)


func _ensure_marker_contract(blockout: CastleBlockout, biome_id: String) -> void:
	var kind := RoomTemplateCatalogScript.kind_from_template_id(template_id)
	var props := get_node_or_null("Props")
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		add_child(props)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	var anchors := [
		Vector3(-half_w * 0.6, 0.0, -half_d * 0.6),
		Vector3(half_w * 0.6, 0.0, -half_d * 0.6),
		Vector3(-half_w * 0.6, 0.0, half_d * 0.6),
		Vector3(half_w * 0.6, 0.0, half_d * 0.6),
	]
	for index in anchors.size():
		_ensure_marker(props, "PropAnchor_%d" % index, anchors[index])
	if kind == "stairs":
		var spawn_root := get_node_or_null("SpawnPoints")
		if spawn_root == null:
			spawn_root = Node3D.new()
			spawn_root.name = "SpawnPoints"
			add_child(spawn_root)
		_ensure_marker(spawn_root, "LeverSpawn", Vector3(-3.45, 0.0, -2.0))
		_ensure_stair_ramp(props, biome_id)
	if kind == "boss":
		_ensure_marker(props, "BossSpawn", Vector3(0.0, 0.0, -6.0))
		_ensure_marker(props, "ExitPortalMarker", Vector3(0.0, 0.0, 12.0))
		_ensure_boss_authored(props, biome_id)


func _ensure_marker(parent: Node3D, marker_name: String, local_pos: Vector3) -> void:
	var marker := parent.get_node_or_null(marker_name) as Node3D
	if marker == null:
		marker = Marker3D.new()
		marker.name = marker_name
		parent.add_child(marker)
	marker.position = local_pos


func _ensure_stair_ramp(props: Node3D, biome_id: String) -> void:
	if props.get_node_or_null("StairRamp") != null:
		return
	var ramp := MeshInstance3D.new()
	ramp.name = "StairRamp"
	var box := BoxMesh.new()
	box.size = Vector3(4.0, 0.4, 12.0)
	ramp.mesh = box
	ramp.transform = Transform3D(Basis(Vector3.RIGHT, deg_to_rad(25.0)), Vector3(0.0, 1.2, 0.0))
	var accent := BiomeRegistry.get_accent_material(biome_id)
	if accent:
		ramp.material_override = accent
	props.add_child(ramp)


func _ensure_boss_authored(_props: Node3D, biome_id: String) -> void:
	var authored := get_node_or_null("Authored")
	if authored == null:
		authored = Node3D.new()
		authored.name = "Authored"
		add_child(authored)
	if authored.get_child_count() > 0:
		return
	var dais := MeshInstance3D.new()
	dais.name = "Dais"
	var box := BoxMesh.new()
	box.size = Vector3(10.0, 0.6, 10.0)
	dais.mesh = box
	dais.position = Vector3(0.0, 0.3, -4.0)
	var accent := BiomeRegistry.get_accent_material(biome_id)
	if accent:
		dais.material_override = accent
	authored.add_child(dais)


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
