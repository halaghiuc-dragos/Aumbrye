@tool
extends Node3D
class_name CastleBlockout

## Procedural castle blockout geometry with doorway cutouts.

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

var _geometry_root: Node3D
var _nav_region: NavigationRegion3D
var _nav_links: Array[NavigationLink3D] = []
var _cover_nodes: Array[Node3D] = []


func _ready() -> void:
	_rebuild()


func _request_rebuild() -> void:
	if is_inside_tree():
		_rebuild()


func _rebuild() -> void:
	_clear_children()
	_geometry_root = Node3D.new()
	_geometry_root.name = "Geometry"
	add_child(_geometry_root)
	if Engine.is_editor_hint():
		_geometry_root.owner = get_tree().edited_scene_root

	if not skip_floor:
		_build_floor()
	_build_wall(Vector3(0.0, 0.0, -room_depth * 0.5), Vector3(room_width, wall_height, CastleRoomConstants.WALL_THICKNESS), door_north, true)
	_build_wall(Vector3(0.0, 0.0, room_depth * 0.5), Vector3(room_width, wall_height, CastleRoomConstants.WALL_THICKNESS), door_south, true)
	_build_wall(Vector3(room_width * 0.5, 0.0, 0.0), Vector3(CastleRoomConstants.WALL_THICKNESS, wall_height, room_depth), door_east, false)
	_build_wall(Vector3(-room_width * 0.5, 0.0, 0.0), Vector3(CastleRoomConstants.WALL_THICKNESS, wall_height, room_depth), door_west, false)
	_build_navigation_mesh()


func _clear_children() -> void:
	for child in get_children():
		if child.name == "Geometry" or child is NavigationRegion3D or child is NavigationLink3D:
			child.queue_free()
	_geometry_root = null
	_nav_region = null
	_nav_links.clear()
	_cover_nodes.clear()


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


func _add_wall_segment(center: Vector3, size: Vector3) -> void:
	var wall_body := StaticBody3D.new()
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	_geometry_root.add_child(wall_body)
	if Engine.is_editor_hint():
		wall_body.owner = get_tree().edited_scene_root

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

	var occluder := OccluderInstance3D.new()
	var occluder_mesh := ArrayOccluder3D.new()
	occluder_mesh.vertices = PackedVector3Array([
		Vector3(-size.x * 0.5, 0.0, -size.z * 0.5),
		Vector3(size.x * 0.5, 0.0, -size.z * 0.5),
		Vector3(size.x * 0.5, size.y, -size.z * 0.5),
		Vector3(-size.x * 0.5, size.y, -size.z * 0.5),
		Vector3(-size.x * 0.5, 0.0, size.z * 0.5),
		Vector3(size.x * 0.5, 0.0, size.z * 0.5),
		Vector3(size.x * 0.5, size.y, size.z * 0.5),
		Vector3(-size.x * 0.5, size.y, size.z * 0.5),
	])
	occluder_mesh.indices = PackedInt32Array([
		0, 1, 2, 0, 2, 3,
		5, 4, 7, 5, 7, 6,
		4, 0, 3, 4, 3, 7,
		1, 5, 6, 1, 6, 2,
		3, 2, 6, 3, 6, 7,
		4, 5, 1, 4, 1, 0,
	])
	occluder.occluder = occluder_mesh
	occluder.position = mesh_instance.position
	_geometry_root.add_child(occluder)
	if Engine.is_editor_hint():
		occluder.owner = get_tree().edited_scene_root

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = mesh_instance.position
	wall_body.add_child(collision)
	if Engine.is_editor_hint():
		collision.owner = get_tree().edited_scene_root


func _build_navigation_mesh() -> void:
	_nav_region = NavigationRegion3D.new()
	_nav_region.name = "NavigationRegion3D"
	add_child(_nav_region)
	if Engine.is_editor_hint():
		_nav_region.owner = get_tree().edited_scene_root

	var nav_mesh := NavigationMesh.new()
	nav_mesh.agent_height = 1.5
	nav_mesh.agent_radius = 0.25
	nav_mesh.cell_size = 0.25
	nav_mesh.cell_height = 0.25
	var playable := Vector3(
		maxf(room_width - 1.0, 1.0),
		0.1,
		maxf(room_depth - 1.0, 1.0)
	)
	nav_mesh.filter_low_hanging_obstacles = true
	_nav_region.navigation_mesh = nav_mesh

	var half_w := playable.x * 0.5
	var half_d := playable.z * 0.5
	var floor_y := 0.05
	var faces := PackedVector3Array([
		Vector3(-half_w, floor_y, -half_d),
		Vector3(half_w, floor_y, -half_d),
		Vector3(half_w, floor_y, half_d),
		Vector3(-half_w, floor_y, -half_d),
		Vector3(half_w, floor_y, half_d),
		Vector3(-half_w, floor_y, half_d),
	])
	var source_data := NavigationMeshSourceGeometryData3D.new()
	source_data.add_faces(faces, Transform3D.IDENTITY)
	NavigationServer3D.bake_from_source_geometry_data(nav_mesh, source_data)


func get_navigation_map() -> RID:
	if _nav_region == null:
		return RID()
	return _nav_region.get_navigation_map()


func sample_random_nav_point() -> Vector3:
	var map := get_navigation_map()
	if map == RID():
		return Vector3.ZERO
	var point: Vector3 = NavigationServer3D.map_get_random_point(map, true, 1)
	if point == Vector3.ZERO:
		return Vector3.ZERO
	return to_local(point)


func add_cover_obstacle(local_pos: Vector3, size: Vector3, material: Material = null) -> void:
	var body := StaticBody3D.new()
	body.collision_layer = 1
	body.collision_mask = 0
	_geometry_root.add_child(body)
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
	add_child(link)
	if Engine.is_editor_hint():
		link.owner = get_tree().edited_scene_root
	_nav_links.append(link)
	return link
