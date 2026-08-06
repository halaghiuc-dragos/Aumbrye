@tool
extends Node3D
class_name CastleBlockout

## Procedural castle blockout geometry with doorway cutouts.

const CEILING_THICKNESS := 0.4
const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

@export var kind: StringName = &"":
	set(value):
		kind = value
		_request_rebuild()

@export var room_width: float = 16.0:
	set(value):
		room_width = maxf(value, CastleRoomConstants.GRID_UNIT)
		_request_rebuild()

@export var room_depth: float = 12.0:
	set(value):
		room_depth = maxf(value, CastleRoomConstants.GRID_UNIT)
		_request_rebuild()

@export var wall_height: float = CastleRoomConstants.WALL_HEIGHT:
	set(value):
		wall_height = maxf(value, CastleRoomConstants.DOOR_HEIGHT)
		_request_rebuild()

@export var door_north: bool = false:
	set(value):
		door_north = value
		_request_rebuild()

@export var door_south: bool = false:
	set(value):
		door_south = value
		_request_rebuild()

@export var door_east: bool = false:
	set(value):
		door_east = value
		_request_rebuild()

@export var door_west: bool = false:
	set(value):
		door_west = value
		_request_rebuild()

@export var floor_material: Material
@export var wall_material: Material
@export var accent_material: Material
@export var skip_floor: bool = false
@export var hide_walls: bool = false:
	set(value):
		hide_walls = value
		_request_rebuild()

@export var build_ceiling: bool = true:
	set(value):
		build_ceiling = value
		_request_rebuild()

var _geometry_root: Node3D
var _cover_root: Node3D
var _walls_body: StaticBody3D
var _nav_region: NavigationRegion3D
var _nav_links: Array[NavigationLink3D] = []
var _cover_nodes: Array[Node3D] = []
var _pending_stairs: Array[Dictionary] = []
var _navigation_map: RID = RID()
var _geometry_dirty: bool = true
var _nav_bake_count: int = 0
var _applying_kind_spec := false


func _ready() -> void:
	_apply_kind_spec()
	_rebuild()
	if Engine.is_editor_hint():
		_verify_socket_positions()


func _request_rebuild() -> void:
	if _applying_kind_spec:
		return
	_geometry_dirty = true
	if not is_inside_tree():
		return
	if Engine.is_editor_hint():
		_rebuild()
		_build_navigation_mesh()


func finalize_geometry() -> void:
	if _geometry_dirty:
		_rebuild()
	_build_navigation_mesh()
	_geometry_dirty = false


func get_nav_bake_count() -> int:
	return _nav_bake_count


func _rebuild() -> void:
	_apply_kind_spec()
	_clear_geometry_children()
	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)
	if Engine.is_editor_hint():
		_geometry_root.owner = get_tree().edited_scene_root
	_walls_body = null

	if not skip_floor:
		_build_floor()
	_build_wall(
		Vector3(0.0, 0.0, -room_depth * 0.5),
		Vector3(room_width, wall_height, CastleRoomConstants.WALL_THICKNESS),
		door_north,
		true
	)
	_build_wall(
		Vector3(0.0, 0.0, room_depth * 0.5),
		Vector3(room_width, wall_height, CastleRoomConstants.WALL_THICKNESS),
		door_south,
		true
	)
	_build_wall(
		Vector3(room_width * 0.5, 0.0, 0.0),
		Vector3(CastleRoomConstants.WALL_THICKNESS, wall_height, room_depth),
		door_east,
		false
	)
	_build_wall(
		Vector3(-room_width * 0.5, 0.0, 0.0),
		Vector3(CastleRoomConstants.WALL_THICKNESS, wall_height, room_depth),
		door_west,
		false
	)
	_build_pending_stairs()
	if build_ceiling:
		_build_ceiling()
	_add_room_occluder()
	_geometry_dirty = false


func _clear_geometry_children() -> void:
	for child in get_children():
		if child.name == "CoverObstacles":
			continue
		if child.name == "Geometry" or child is NavigationRegion3D or child is NavigationLink3D:
			remove_child(child)
			child.free()
	_geometry_root = null
	_walls_body = null
	_nav_region = null
	_nav_links.clear()


func _ensure_cover_root() -> Node3D:
	if _cover_root != null and is_instance_valid(_cover_root):
		return _cover_root
	_cover_root = get_node_or_null("CoverObstacles") as Node3D
	if _cover_root == null:
		_cover_root = Node3D.new()
		_cover_root.name = "CoverObstacles"
		add_child(_cover_root)
		if Engine.is_editor_hint():
			_cover_root.owner = get_tree().edited_scene_root
	return _cover_root


func _create_walls_body() -> StaticBody3D:
	if _walls_body != null and is_instance_valid(_walls_body):
		return _walls_body
	_walls_body = StaticBody3D.new()
	_walls_body.name = "Walls"
	_walls_body.collision_layer = 1
	_walls_body.collision_mask = 0
	_geometry_root.add_child(_walls_body)
	if Engine.is_editor_hint():
		_walls_body.owner = get_tree().edited_scene_root
	return _walls_body


func _build_floor() -> void:
	var floor_body := StaticBody3D.new()
	floor_body.name = "Floor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	_geometry_root.add_child(floor_body)
	if Engine.is_editor_hint():
		floor_body.owner = get_tree().edited_scene_root

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(room_width, CastleRoomConstants.FLOOR_THICKNESS, room_depth)
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0)
	if floor_material:
		mesh_instance.material_override = floor_material
	floor_body.add_child(mesh_instance)
	if Engine.is_editor_hint():
		mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = box.size
	collision.shape = shape
	collision.position = mesh_instance.position
	floor_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


func _build_ceiling() -> void:
	var ceiling_body := StaticBody3D.new()
	ceiling_body.name = "Ceiling"
	ceiling_body.collision_layer = 1
	ceiling_body.collision_mask = 0
	_geometry_root.add_child(ceiling_body)
	if Engine.is_editor_hint():
		ceiling_body.owner = get_tree().edited_scene_root

	var size := Vector3(room_width, CEILING_THICKNESS, room_depth)
	var center_y := wall_height + CEILING_THICKNESS * 0.5
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = Vector3(0.0, center_y, 0.0)
	if wall_material:
		mesh_instance.material_override = wall_material
	ceiling_body.add_child(mesh_instance)
	if Engine.is_editor_hint():
		mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = mesh_instance.position
	ceiling_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root

	var occluder := OccluderInstance3D.new()
	occluder.name = "CeilingOccluder"
	var occluder_mesh := _make_box_occluder(size)
	occluder.occluder = occluder_mesh
	occluder.position = mesh_instance.position
	_geometry_root.add_child(occluder)
	if Engine.is_editor_hint():
		occluder.owner = get_tree().edited_scene_root


func _build_wall(center: Vector3, size: Vector3, has_door: bool, spans_x: bool) -> void:
	if not has_door:
		_add_wall_segment(center, size)
		return

	var span := size.x if spans_x else size.z
	var door := CastleRoomConstants.DOOR_WIDTH
	var leftover := span - door
	if leftover <= 0.0:
		_add_wall_segment(center, size)
		return

	var side := leftover * 0.5
	if spans_x:
		var left_center := Vector3(center.x - (side + door) * 0.5, center.y, center.z)
		var right_center := Vector3(center.x + (side + door) * 0.5, center.y, center.z)
		_add_wall_segment(left_center, Vector3(side, size.y, size.z))
		_add_wall_segment(right_center, Vector3(side, size.y, size.z))
	else:
		var back_center := Vector3(center.x, center.y, center.z - (side + door) * 0.5)
		var front_center := Vector3(center.x, center.y, center.z + (side + door) * 0.5)
		_add_wall_segment(back_center, Vector3(size.x, size.y, side))
		_add_wall_segment(front_center, Vector3(size.x, size.y, side))

	var lintel_h := wall_height - CastleRoomConstants.DOOR_HEIGHT
	if lintel_h > 0.0:
		var lintel_y := CastleRoomConstants.DOOR_HEIGHT + lintel_h * 0.5
		if spans_x:
			_add_wall_segment(
				Vector3(center.x, lintel_y, center.z),
				Vector3(door, lintel_h, size.z)
			)
		else:
			_add_wall_segment(
				Vector3(center.x, lintel_y, center.z),
				Vector3(size.x, lintel_h, door)
			)


func _add_wall_segment(center: Vector3, size: Vector3) -> void:
	var wall_body := _create_walls_body()
	if not hide_walls:
		var mesh_instance := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = size
		mesh_instance.mesh = box
		mesh_instance.position = center + Vector3(0.0, size.y * 0.5, 0.0)
		mesh_instance.lod_bias = 0.8
		if wall_material:
			mesh_instance.material_override = wall_material
		wall_body.add_child(mesh_instance)
		if Engine.is_editor_hint():
			mesh_instance.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center + Vector3(0.0, size.y * 0.5, 0.0)
	wall_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


func _add_room_occluder() -> void:
	var size := Vector3(room_width, wall_height, room_depth)
	var occluder := OccluderInstance3D.new()
	occluder.name = "RoomOccluder"
	occluder.occluder = _make_box_occluder(size)
	occluder.position = Vector3(0.0, wall_height * 0.5, 0.0)
	_geometry_root.add_child(occluder)
	if Engine.is_editor_hint():
		occluder.owner = get_tree().edited_scene_root


func _make_box_occluder(size: Vector3) -> ArrayOccluder3D:
	var occluder_mesh := ArrayOccluder3D.new()
	occluder_mesh.vertices = PackedVector3Array(
		[
			Vector3(-size.x * 0.5, 0.0, -size.z * 0.5),
			Vector3(size.x * 0.5, 0.0, -size.z * 0.5),
			Vector3(size.x * 0.5, size.y, -size.z * 0.5),
			Vector3(-size.x * 0.5, size.y, -size.z * 0.5),
			Vector3(-size.x * 0.5, 0.0, size.z * 0.5),
			Vector3(size.x * 0.5, 0.0, size.z * 0.5),
			Vector3(size.x * 0.5, size.y, size.z * 0.5),
			Vector3(-size.x * 0.5, size.y, size.z * 0.5),
		]
	)
	occluder_mesh.indices = PackedInt32Array(
		[
			0, 1, 2, 0, 2, 3, 5, 4, 7, 5, 7, 6, 4, 0, 3, 4, 3, 7, 1, 5, 6, 1, 6, 2, 3, 2, 6, 3,
			6, 7, 4, 5, 1, 4, 1, 0,
		]
	)
	return occluder_mesh


func _build_navigation_mesh() -> void:
	if _nav_region != null and is_instance_valid(_nav_region):
		remove_child(_nav_region)
		_nav_region.free()
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavigationRegion3D"
	add_child(_nav_region)
	if Engine.is_editor_hint():
		_nav_region.owner = get_tree().edited_scene_root

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_height = 1.8
	nav_mesh.agent_radius = 0.45
	nav_mesh.agent_max_climb = 0.5
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	nav_mesh.geometry_parsed_geometry_type = NavigationMesh.PARSED_GEOMETRY_STATIC_COLLIDERS
	nav_mesh.geometry_source_geometry_mode = NavigationMesh.SOURCE_GEOMETRY_ROOT_NODE_CHILDREN
	nav_mesh.filter_low_hanging_obstacles = true
	_nav_region.navigation_mesh = nav_mesh

	var source_data := NavigationMeshSourceGeometryData3D.new()
	if _geometry_root != null:
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, _geometry_root)
	var cover_root := get_node_or_null("CoverObstacles")
	if cover_root != null:
		NavigationServer3D.parse_source_geometry_data(nav_mesh, source_data, cover_root)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)
	_nav_bake_count += 1
	if _navigation_map != RID():
		_nav_region.set_navigation_map(_navigation_map)


func get_navigation_map() -> RID:
	if _navigation_map != RID():
		return _navigation_map
	if _nav_region == null:
		return RID()
	return _nav_region.get_navigation_map()


func set_navigation_map(map: RID) -> void:
	_navigation_map = map
	if _nav_region != null:
		_nav_region.set_navigation_map(map)
	for link in _nav_links:
		if is_instance_valid(link):
			link.navigation_map = map


func sample_random_nav_point(rng: RandomNumberGenerator) -> Vector3:
	var map := get_navigation_map()
	if map == RID() or rng == null:
		return Vector3.ZERO
	var inset := 1.0
	var half_w := maxf(room_width * 0.5 - inset, 0.5)
	var half_d := maxf(room_depth * 0.5 - inset, 0.5)
	for _attempt in 8:
		var local := Vector3(
			rng.randf_range(-half_w, half_w), 0.05, rng.randf_range(-half_d, half_d)
		)
		var world := to_global(local)
		var closest := NavigationServer3D.map_get_closest_point(map, world)
		var closest_local := to_local(closest)
		if absf(closest_local.x) <= half_w and absf(closest_local.z) <= half_d:
			return closest_local
	return Vector3.ZERO


func add_cover_obstacle(local_pos: Vector3, size: Vector3, material: Material = null) -> void:
	var cover_root := _ensure_cover_root()
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	cover_root.add_child(body)
	if Engine.is_editor_hint():
		body.owner = get_tree().edited_scene_root
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = local_pos + Vector3(0.0, size.y * 0.5, 0.0)
	if material:
		mesh_instance.material_override = material
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = mesh_instance.position
	body.add_child(collision)
	_cover_nodes.append(body)


func add_height_stairs(step_count: int, direction: Vector2i, step_height: float = 0.5) -> void:
	if step_count <= 0:
		return
	_pending_stairs.append(
		{"step_count": step_count, "direction": direction, "step_height": step_height}
	)
	_geometry_dirty = true
	if Engine.is_editor_hint() or not is_inside_tree():
		_request_rebuild()


func _build_pending_stairs() -> void:
	for stair in _pending_stairs:
		_build_height_stairs(
			int(stair.get("step_count", 0)),
			stair.get("direction", Vector2i.ZERO),
			float(stair.get("step_height", 0.5))
		)


func _build_height_stairs(step_count: int, direction: Vector2i, step_height: float) -> void:
	var step_depth := 0.8
	var width := maxf(room_width * 0.4, 2.0)
	for i in step_count:
		var offset := float(i) * step_depth
		var center := Vector3.ZERO
		if direction == Vector2i(0, -1):
			center = Vector3(0.0, step_height * (i + 0.5), -room_depth * 0.5 + offset)
		elif direction == Vector2i(0, 1):
			center = Vector3(0.0, step_height * (i + 0.5), room_depth * 0.5 - offset)
		elif direction == Vector2i(1, 0):
			center = Vector3(room_width * 0.5 - offset, step_height * (i + 0.5), 0.0)
		else:
			center = Vector3(-room_width * 0.5 + offset, step_height * (i + 0.5), 0.0)
		_add_wall_segment(center, Vector3(width, step_height, step_depth))


func add_door_nav_link(local_start: Vector3, local_end: Vector3) -> NavigationLink3D:
	var link := NavigationLink3D.new()
	link.name = "DoorNavLink"
	link.start_position = local_start
	link.end_position = local_end
	link.bidirectional = true
	link.travel_cost = 1.0
	link.enabled = true
	if _navigation_map != RID():
		link.navigation_map = _navigation_map
	add_child(link)
	if Engine.is_editor_hint():
		link.owner = get_tree().edited_scene_root
	_nav_links.append(link)
	return link


func count_wall_collision_shapes() -> int:
	var count := 0
	if _walls_body == null or not is_instance_valid(_walls_body):
		return count
	for child in _walls_body.get_children():
		if child is CollisionShape3D:
			count += 1
	return count


func count_wall_meshes() -> int:
	var count := 0
	if _walls_body == null or not is_instance_valid(_walls_body):
		return count
	for child in _walls_body.get_children():
		if child is MeshInstance3D:
			count += 1
	return count


func get_nav_mesh_vertices_local() -> PackedVector3Array:
	if _nav_region == null or _nav_region.navigation_mesh == null:
		return PackedVector3Array()
	return _nav_region.navigation_mesh.get_vertices()


func get_cover_aabbs_local() -> Array[AABB]:
	var boxes: Array[AABB] = []
	for node in _cover_nodes:
		if not is_instance_valid(node):
			continue
		for child in node.get_children():
			if child is CollisionShape3D and child.shape is BoxShape3D:
				var shape := child.shape as BoxShape3D
				var half := shape.size * 0.5
				var center: Vector3 = child.position
				boxes.append(AABB(center - half, shape.size))
	return boxes


func sync_dimensions_from_kind() -> void:
	_apply_kind_spec()
	_rebuild()


func _resolve_kind() -> String:
	if not kind.is_empty():
		return str(kind)
	var room := get_parent() as RoomTemplate
	if room != null and not room.template_id.is_empty():
		return RoomTemplateCatalogScript.kind_from_template_id(room.template_id)
	return ""


func _apply_kind_spec() -> void:
	var resolved_kind := _resolve_kind()
	if resolved_kind.is_empty():
		return
	var spec: Dictionary = RoomTemplateCatalogScript.get_spec(resolved_kind)
	var spec_width: float = float(spec.get("width", room_width))
	var spec_depth: float = float(spec.get("depth", room_depth))
	var doors: int = int(spec.get("doors", 0))
	if Engine.is_editor_hint():
		if absf(room_width - spec_width) > 0.001 or absf(room_depth - spec_depth) > 0.001:
			push_warning(
				(
					"CastleBlockout '%s': kind '%s' implies %.1fx%.1f but exports %.1fx%.1f"
					% [name, resolved_kind, spec_width, spec_depth, room_width, room_depth]
				)
			)
	_applying_kind_spec = true
	room_width = spec_width
	room_depth = spec_depth
	door_north = (doors & RoomGraphSlot.DOOR_NORTH) != 0
	door_south = (doors & RoomGraphSlot.DOOR_SOUTH) != 0
	door_east = (doors & RoomGraphSlot.DOOR_EAST) != 0
	door_west = (doors & RoomGraphSlot.DOOR_WEST) != 0
	_applying_kind_spec = false


func _verify_socket_positions() -> void:
	var room := get_parent() as RoomTemplate
	if room == null:
		return
	var half_w := room_width * 0.5
	var half_d := room_depth * 0.5
	for socket in room.get_sockets():
		var expected := RoomTemplateCatalogScript.socket_wall_position(
			socket.direction, half_w, half_d
		)
		if socket.position.distance_to(expected) > 0.01:
			push_warning(
				(
					"%s socket %s is %.3f from wall face (expected %s)"
					% [
						room.template_id,
						socket.get_socket_name(),
						socket.position.distance_to(expected),
						expected,
					]
				)
			)
