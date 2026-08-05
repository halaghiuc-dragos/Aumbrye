extends RefCounted
class_name FloorShellBuilder

## One large floor slab + ceiling per dungeon floor, perimeter walls, and biome lighting.

const CEILING_THICKNESS := 0.4
const SHELL_PADDING := 2.0
const PERIMETER_INSET := 0.5


static func build(parent: Node3D, rooms: Dictionary, biome_id: String) -> void:
	if rooms.is_empty():
		return
	var bounds := _compute_bounds(parent, rooms)
	if bounds.size.x <= 0.0 or bounds.size.z <= 0.0:
		return
	var shell := Node3D.new()
	shell.name = "FloorShell"
	parent.add_child(shell)

	var floor_mat := BiomeRegistry.get_floor_material(biome_id)
	var wall_mat := BiomeRegistry.get_wall_material(biome_id)
	var center_xz := Vector3(
		bounds.position.x + bounds.size.x * 0.5,
		0.0,
		bounds.position.z + bounds.size.z * 0.5
	)
	var floor_pos := Vector3(
		center_xz.x,
		-CastleRoomConstants.FLOOR_THICKNESS * 0.5,
		center_xz.z
	)
	var floor_size := Vector3(bounds.size.x, CastleRoomConstants.FLOOR_THICKNESS, bounds.size.z)
	_add_slab(shell, "FloorSlab", floor_pos, floor_size, floor_mat, true)

	var ceiling_pos := Vector3(
		center_xz.x,
		CastleRoomConstants.WALL_HEIGHT + CEILING_THICKNESS * 0.5,
		center_xz.z
	)
	var ceiling_size := Vector3(bounds.size.x, CEILING_THICKNESS, bounds.size.z)
	_add_slab(shell, "CeilingSlab", ceiling_pos, ceiling_size, wall_mat, true)

	_build_perimeter_walls(shell, bounds, wall_mat)
	DioramaRoomDressing.apply_shell_lighting(shell, bounds, biome_id)

	for room in rooms.values():
		var template := room as RoomTemplate
		if template:
			DioramaRoomDressing.apply_ceiling_lighting(template, biome_id, template.room_type)


static func build_arena_shell(parent: Node3D, half_extent: float, biome_id: String) -> void:
	var shell := Node3D.new()
	shell.name = "FloorShell"
	parent.add_child(shell)
	var span := half_extent * 2.0 + SHELL_PADDING
	var floor_mat := BiomeRegistry.get_floor_material(biome_id)
	var wall_mat := BiomeRegistry.get_wall_material(biome_id)
	_add_slab(
		shell,
		"FloorSlab",
		Vector3(0.0, -CastleRoomConstants.FLOOR_THICKNESS * 0.5, 0.0),
		Vector3(span, CastleRoomConstants.FLOOR_THICKNESS, span),
		floor_mat,
		true
	)
	var ceiling_y := CastleRoomConstants.WALL_HEIGHT + CEILING_THICKNESS * 0.5
	_add_slab(
		shell,
		"CeilingSlab",
		Vector3(0.0, ceiling_y, 0.0),
		Vector3(span, CEILING_THICKNESS, span),
		wall_mat,
		true
	)
	var half_span := span * 0.5
	var arena_bounds := AABB(Vector3(-half_span, 0.0, -half_span), Vector3(span, 0.0, span))
	_build_perimeter_walls(shell, arena_bounds, wall_mat)
	DioramaRoomDressing.apply_shell_lighting(shell, arena_bounds, biome_id)
	DioramaRoomDressing.apply_arena_ceiling_lighting(shell, half_extent, biome_id)


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
	for child in parent.get_children():
		if child.name.begins_with("Shortcut"):
			var shortcut_bounds := _shortcut_corner_bounds(parent, child as Node3D)
			min_v.x = minf(min_v.x, shortcut_bounds[0].x)
			min_v.z = minf(min_v.z, shortcut_bounds[0].z)
			max_v.x = maxf(max_v.x, shortcut_bounds[1].x)
			max_v.z = maxf(max_v.z, shortcut_bounds[1].z)
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


static func _shortcut_corner_bounds(parent: Node3D, shortcut: Node3D) -> Array:
	var min_v := Vector3(INF, 0.0, INF)
	var max_v := Vector3(-INF, 0.0, -INF)
	for child in shortcut.get_children():
		if not child.get("room_width"):
			continue
		var half_w: float = float(child.get("room_width")) * 0.5
		var half_d: float = float(child.get("room_depth")) * 0.5
		for corner in [
			Vector3(-half_w, 0.0, -half_d),
			Vector3(half_w, 0.0, -half_d),
			Vector3(-half_w, 0.0, half_d),
			Vector3(half_w, 0.0, half_d),
		]:
			var local := parent.to_local(shortcut.to_global(corner))
			min_v.x = minf(min_v.x, local.x)
			min_v.z = minf(min_v.z, local.z)
			max_v.x = maxf(max_v.x, local.x)
			max_v.z = maxf(max_v.z, local.z)
	return [min_v, max_v]


static func _add_slab(
	parent: Node3D,
	node_name: String,
	center: Vector3,
	size: Vector3,
	material: Material,
	with_collision: bool
) -> void:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = center
	parent.add_child(body)

	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	if material:
		mesh_instance.material_override = material
	body.add_child(mesh_instance)

	if with_collision:
		var collision := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = size
		collision.shape = shape
		body.add_child(collision)


static func _add_wall_segment(
	parent: Node3D,
	center: Vector3,
	size: Vector3,
	material: Material,
	node_name: String
) -> void:
	var wall_body := StaticBody3D.new()
	wall_body.name = node_name
	wall_body.collision_layer = 1
	wall_body.collision_mask = 0
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
