extends RefCounted
class_name FloorShellBuilder


const CEILING_THICKNESS := 0.4
const SHELL_PADDING := 2.0
const PERIMETER_INSET := 0.5
const BEDROCK_DROP := 2.0
const BEDROCK_THICKNESS := 1.0


static func build(parent: Node3D, rooms: Dictionary, biome_id: String) -> void:
	if rooms.is_empty():
		return
	var bounds := _compute_bounds(parent, rooms)
	if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
		return
	var shell := Node3D.new()
	shell.name = "FloorShell"
	parent.add_child(shell)

	var wall_mat := BiomeRegistry.get_wall_material(biome_id)
	var floor_mat := BiomeRegistry.get_floor_material(biome_id)
	var min_room_y := _min_room_y(parent, rooms)
	_build_bedrock(shell, bounds, floor_mat, min_room_y)
	_build_perimeter_walls(shell, bounds, wall_mat)
	_build_height_skirts(shell, parent, rooms, wall_mat, min_room_y)

	for room in rooms.values():
		var template := room as RoomTemplate
		if template:
			DioramaRoomDressing.apply_ceiling_lighting(template, biome_id, template.room_type)


static func _min_room_y(parent: Node3D, rooms: Dictionary) -> float:
	var min_y := INF
	for room in rooms.values():
		var template := room as RoomTemplate
		if template == null:
			continue
		var local_y := parent.to_local(template.global_position).y
		min_y = minf(min_y, local_y)
	return 0.0 if is_inf(min_y) else min_y


## A safety net, not a floor: it sits below every room so a hole in the tiling drops the player
## onto dark stone instead of into the void. Kept out of the nav mesh on purpose -- see
## `_setup_floor_nav_map()`, which bakes only from the room blockouts.
static func _build_bedrock(shell: Node3D, bounds: AABB, floor_mat: Material, min_room_y: float) -> void:
	var top_y := min_room_y - BEDROCK_DROP
	var body := StaticBody3D.new()
	body.name = "Bedrock"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	body.add_to_group("floor_bedrock")
	shell.add_child(body)

	var size := Vector3(bounds.size.x, BEDROCK_THICKNESS, bounds.size.z)
	var center := Vector3(
		bounds.position.x + bounds.size.x * 0.5, top_y - BEDROCK_THICKNESS * 0.5, bounds.position.z + bounds.size.z * 0.5
	)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = center
	if floor_mat:
		var darkened := floor_mat.duplicate() as Material
		if darkened is StandardMaterial3D:
			var std := darkened as StandardMaterial3D
			std.albedo_color = std.albedo_color.darkened(0.4)
		mesh_instance.material_override = darkened
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


## Under any elevated room, the space between the bedrock and that room's own floor is solid --
## otherwise it is a pit a player can walk into sideways from the room below.
static func _build_height_skirts(
	shell: Node3D, parent: Node3D, rooms: Dictionary, wall_mat: Material, min_room_y: float
) -> void:
	var bedrock_top := min_room_y - BEDROCK_DROP + BEDROCK_THICKNESS
	for room in rooms.values():
		var template := room as RoomTemplate
		if template == null:
			continue
		var blockout := template.get_blockout()
		if blockout == null:
			continue
		var local_y := parent.to_local(template.global_position).y
		if local_y - min_room_y < 0.01:
			continue
		var local_xz := parent.to_local(template.global_position)
		var height := local_y - bedrock_top
		if height <= 0.0:
			continue
		var size := Vector3(blockout.room_width, height, blockout.room_depth)
		var center := Vector3(local_xz.x, bedrock_top + height * 0.5, local_xz.z)
		_add_skirt_segment(shell, center, size, wall_mat)


static func _add_skirt_segment(parent: Node3D, center: Vector3, size: Vector3, material: Material) -> void:
	var body := StaticBody3D.new()
	body.name = "HeightSkirt"
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("surface", "stone")
	parent.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = center
	if material:
		mesh_instance.material_override = material
	body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = center
	body.add_child(collision)


static func _build_perimeter_walls(shell: Node3D, bounds: AABB, wall_mat: Material) -> void:
	var walls := Node3D.new()
	walls.name = "PerimeterWalls"
	shell.add_child(walls)

	var min_x := bounds.position.x + PERIMETER_INSET
	var min_z := bounds.position.z + PERIMETER_INSET
	var max_x := bounds.position.x + bounds.size.x - PERIMETER_INSET
	var max_z := bounds.position.z + bounds.size.z - PERIMETER_INSET
	var span_x := max_x - min_x
	var span_z := max_z - min_z
	var center_x := min_x + span_x * 0.5
	var center_z := min_z + span_z * 0.5
	var wall_h := CastleRoomConstants.WALL_HEIGHT
	var thick := CastleRoomConstants.WALL_THICKNESS

	_add_wall_segment(
		walls,
		Vector3(center_x, 0.0, min_z + thick * 0.5),
		Vector3(span_x, wall_h, thick),
		wall_mat,
		"PerimeterNorth"
	)
	_add_wall_segment(
		walls,
		Vector3(center_x, 0.0, max_z - thick * 0.5),
		Vector3(span_x, wall_h, thick),
		wall_mat,
		"PerimeterSouth"
	)
	_add_wall_segment(
		walls,
		Vector3(min_x + thick * 0.5, 0.0, center_z),
		Vector3(thick, wall_h, span_z),
		wall_mat,
		"PerimeterWest"
	)
	_add_wall_segment(
		walls,
		Vector3(max_x - thick * 0.5, 0.0, center_z),
		Vector3(thick, wall_h, span_z),
		wall_mat,
		"PerimeterEast"
	)


static func _compute_bounds(parent: Node3D, rooms: Dictionary) -> AABB:
	var min_v := Vector3(INF, 0.0, INF)
	var max_v := Vector3(-INF, 0.0, -INF)
	for room in rooms.values():
		var room_bounds := _room_corner_bounds(parent, room as RoomTemplate)
		min_v.x = minf(min_v.x, room_bounds[0].x)
		min_v.z = minf(min_v.z, room_bounds[0].z)
		max_v.x = maxf(max_v.x, room_bounds[1].x)
		max_v.z = maxf(max_v.z, room_bounds[1].z)
	min_v.x -= SHELL_PADDING
	min_v.z -= SHELL_PADDING
	max_v.x += SHELL_PADDING
	max_v.z += SHELL_PADDING
	return AABB(min_v, max_v - min_v)


static func _room_corner_bounds(parent: Node3D, room: RoomTemplate) -> Array:
	if room == null:
		return [Vector3.ZERO, Vector3.ZERO]
	var blockout := room.get_blockout()
	if blockout == null:
		var origin := parent.to_local(room.global_position)
		return [origin, origin]
	var min_v := Vector3(INF, 0.0, INF)
	var max_v := Vector3(-INF, 0.0, -INF)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	for corner in [
		Vector3(-half_w, 0.0, -half_d),
		Vector3(half_w, 0.0, -half_d),
		Vector3(-half_w, 0.0, half_d),
		Vector3(half_w, 0.0, half_d),
	]:
		var local := parent.to_local(room.to_global(corner))
		min_v.x = minf(min_v.x, local.x)
		min_v.z = minf(min_v.z, local.z)
		max_v.x = maxf(max_v.x, local.x)
		max_v.z = maxf(max_v.z, local.z)
	return [min_v, max_v]

static func _add_wall_segment(
	parent: Node3D, center: Vector3, size: Vector3, material: Material, node_name: String
) -> void:
	var wall_body := StaticBody3D.new()
	wall_body.name = node_name
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
	wall_body.set_meta("surface", "stone")
	parent.add_child(wall_body)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = center + Vector3(0.0, size.y * 0.5, 0.0)
	if material:
		mesh_instance.material_override = material
	wall_body.add_child(mesh_instance)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	collision.position = mesh_instance.position
	wall_body.add_child(collision)
