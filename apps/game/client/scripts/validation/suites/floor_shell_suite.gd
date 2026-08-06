extends "res://scripts/validation/validation_suite.gd"

const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")
const CastleBlockoutScript := preload("res://scripts/dungeon/castle/castle_blockout.gd")
const CastleRoomSceneScript := preload("res://scripts/dungeon/castle/castle_room_scene.gd")


func get_category() -> String:
	return "floor_shell"


func run() -> void:
	await _test_navmesh_excludes_walls()
	await _test_navmesh_excludes_cover()
	_test_navmesh_agent_params()
	await _test_single_bake_per_room()
	await _test_cover_survives_door_change()
	_test_door_has_lintel()
	await _test_per_room_ceiling()
	await _test_hide_walls()
	_test_grid_quantum()
	await _test_biome_precedence()


func _make_blockout(
	width: float = 20.0, depth: float = 20.0, four_doors: bool = true
) -> CastleBlockout:
	var blockout := CastleBlockoutScript.new()
	blockout.room_width = width
	blockout.room_depth = depth
	if four_doors:
		blockout.door_north = true
		blockout.door_south = true
		blockout.door_east = true
		blockout.door_west = true
	var root := Node3D.new()
	ctx.owner.add_child(root)
	root.add_child(blockout)
	await ctx.await_frame()
	return blockout


func _nav_points(blockout: CastleBlockout) -> PackedVector3Array:
	return blockout.get_nav_mesh_vertices_local()


func _test_navmesh_excludes_walls() -> void:
	var start := Time.get_ticks_msec()
	var blockout := await _make_blockout(20.0, 20.0, false)
	blockout.finalize_geometry()
	await ctx.await_frame()
	var points := _nav_points(blockout)
	var margin := CastleRoomConstants.WALL_THICKNESS * 0.5 + 0.45 + 0.25
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	var ok := points.size() > 0
	if ok:
		for point in points:
			if absf(point.x) >= half_w - margin or absf(point.z) >= half_d - margin:
				ok = false
				break
	blockout.get_parent().queue_free()
	ctx.timed_record(
		"floor_shell.navmesh_excludes_walls",
		get_category(),
		ok,
		"navmesh vertices stay inset from wall planes",
		start,
		"FSH-01"
	)


func _test_navmesh_excludes_cover() -> void:
	var start := Time.get_ticks_msec()
	var blockout := await _make_blockout(16.0, 16.0, false)
	blockout.add_cover_obstacle(Vector3(-2.0, 0.0, -2.0), Vector3(1.2, 2.4, 1.2))
	blockout.add_cover_obstacle(Vector3(2.0, 0.0, 2.0), Vector3(1.2, 2.4, 1.2))
	blockout.add_cover_obstacle(Vector3(0.0, 0.0, 0.0), Vector3(1.2, 2.4, 1.2))
	blockout.finalize_geometry()
	await ctx.await_frame()
	var points := _nav_points(blockout)
	var boxes := blockout.get_cover_aabbs_local()
	var ok := points.size() > 0 and boxes.size() == 3
	if ok:
		for point in points:
			for box in boxes:
				if box.has_point(point):
					ok = false
					break
			if not ok:
				break
	blockout.get_parent().queue_free()
	ctx.timed_record(
		"floor_shell.navmesh_excludes_cover",
		get_category(),
		ok,
		"navmesh vertices avoid cover AABBs",
		start,
		"FSH-01"
	)


func _test_navmesh_agent_params() -> void:
	var start := Time.get_ticks_msec()
	var blockout := CastleBlockoutScript.new()
	var root := Node3D.new()
	ctx.owner.add_child(root)
	root.add_child(blockout)
	blockout.finalize_geometry()
	await ctx.await_frame()
	var nav_mesh: NavigationMesh = blockout.get_node("NavigationRegion3D").navigation_mesh
	var ok: bool = (
		nav_mesh.agent_radius >= 0.45
		and nav_mesh.agent_height >= 1.8
		and nav_mesh.agent_max_climb >= 0.5
		and nav_mesh.cell_size <= 0.25
	)
	root.queue_free()
	ctx.timed_record(
		"floor_shell.navmesh_agent_params",
		get_category(),
		ok,
		"navmesh agent radius/height/climb/cell_size match contract",
		start,
		"FSH-01"
	)


func _test_single_bake_per_room() -> void:
	var start := Time.get_ticks_msec()
	var blockout := await _make_blockout()
	blockout._nav_bake_count = 0
	blockout.door_north = true
	blockout.door_south = true
	blockout.door_east = true
	blockout.door_west = true
	blockout.add_cover_obstacle(Vector3(1.0, 0.0, 1.0), Vector3(1.2, 2.4, 1.2))
	blockout.finalize_geometry()
	var ok := blockout.get_nav_bake_count() == 1
	blockout.get_parent().queue_free()
	ctx.timed_record(
		"floor_shell.single_bake_per_room",
		get_category(),
		ok,
		"finalize_geometry performs exactly one navmesh bake",
		start,
		"FSH-03"
	)


func _test_cover_survives_door_change() -> void:
	var start := Time.get_ticks_msec()
	var blockout := await _make_blockout(16.0, 16.0, false)
	blockout.add_cover_obstacle(Vector3(0.0, 0.0, 0.0), Vector3(1.2, 2.4, 1.2))
	blockout.finalize_geometry()
	var cover_before := blockout.get_node("CoverObstacles").get_child_count()
	blockout.door_north = true
	blockout.finalize_geometry()
	var cover_after := blockout.get_node("CoverObstacles").get_child_count()
	var ok := cover_before == 1 and cover_after == 1
	blockout.get_parent().queue_free()
	ctx.timed_record(
		"floor_shell.cover_survives_door_change",
		get_category(),
		ok,
		"cover obstacles survive door flag changes",
		start,
		"FSH-02"
	)


func _test_door_has_lintel() -> void:
	var start := Time.get_ticks_msec()
	var blockout := CastleBlockoutScript.new()
	blockout.room_width = 16.0
	blockout.room_depth = 12.0
	blockout.door_north = true
	var root := Node3D.new()
	ctx.owner.add_child(root)
	root.add_child(blockout)
	blockout._rebuild()
	var shapes := blockout.count_wall_collision_shapes()
	var lintel_h := CastleRoomConstants.WALL_HEIGHT - CastleRoomConstants.DOOR_HEIGHT
	var ok := shapes == 6 and lintel_h > 0.0
	root.queue_free()
	ctx.timed_record(
		"floor_shell.door_has_lintel",
		get_category(),
		ok,
		"door wall has side segments plus lintel collision",
		start,
		"FSH-06"
	)


func _test_per_room_ceiling() -> void:
	var start := Time.get_ticks_msec()
	var blockout := await _make_blockout(16.0, 12.0, false)
	blockout.build_ceiling = false
	blockout.finalize_geometry()
	blockout.build_ceiling = true
	blockout.finalize_geometry()
	await ctx.await_frame()
	var ceiling := blockout.get_node_or_null("Geometry/Ceiling") as StaticBody3D
	var ok := ceiling != null
	if ok:
		var collision := ceiling.get_node_or_null("CollisionShape3D") as CollisionShape3D
		ok = collision != null and collision.position.y >= CastleRoomConstants.WALL_HEIGHT
	blockout.get_parent().queue_free()
	ctx.timed_record(
		"floor_shell.per_room_ceiling",
		get_category(),
		ok,
		"blockout builds a ceiling collider at wall_height",
		start,
		"FSH-04"
	)


func _test_hide_walls() -> void:
	var start := Time.get_ticks_msec()
	var blockout := await _make_blockout(16.0, 12.0, true)
	blockout.hide_walls = false
	blockout.finalize_geometry()
	var colliders_visible := blockout.count_wall_collision_shapes()
	var meshes_visible := blockout.count_wall_meshes()
	blockout.hide_walls = true
	blockout.finalize_geometry()
	var colliders_hidden := blockout.count_wall_collision_shapes()
	var meshes_hidden := blockout.count_wall_meshes()
	var ok := colliders_visible > 0 and colliders_hidden == colliders_visible and meshes_hidden == 0
	blockout.get_parent().queue_free()
	ctx.timed_record(
		"floor_shell.hide_walls",
		get_category(),
		ok,
		"hide_walls removes meshes but keeps wall colliders",
		start,
		"FSH-12"
	)


func _test_grid_quantum() -> void:
	var start := Time.get_ticks_msec()
	var grid := CastleRoomConstants.GRID_UNIT
	var ok := true
	for kind in RoomTemplateCatalogScript.KIND_SPECS:
		var spec: Dictionary = RoomTemplateCatalogScript.KIND_SPECS[kind]
		var width: float = float(spec.get("width", 0.0))
		var depth: float = float(spec.get("depth", 0.0))
		if (
			not is_zero_approx(fmod(width, grid))
			or not is_zero_approx(fmod(depth, grid))
		):
			ok = false
			break
	ctx.timed_record(
		"floor_shell.grid_quantum",
		get_category(),
		ok,
		"every KIND_SPECS width and depth is a multiple of GRID_UNIT",
		start,
		"FSH-11"
	)


func _test_biome_precedence() -> void:
	var start := Time.get_ticks_msec()
	var prev_biome := RunFlow.current_biome_id
	RunFlow.current_biome_id = "poison_swamp"
	var room: Node = load("res://scenes/rooms/crystal/crystal_courtyard.tscn").instantiate()
	var blockout := room.get_node("CastleBlockout") as CastleBlockout
	blockout.floor_material = null
	blockout.wall_material = null
	blockout.accent_material = null
	var root := Node3D.new()
	ctx.owner.add_child(root)
	root.add_child(room)
	await ctx.await_frame()
	var wall_path := ""
	if blockout.wall_material:
		wall_path = blockout.wall_material.resource_path
	var ok := "crystal" in wall_path
	RunFlow.current_biome_id = prev_biome
	root.queue_free()
	ctx.timed_record(
		"floor_shell.biome_precedence",
		get_category(),
		ok,
		"crystal_courtyard keeps crystal materials when RunFlow biome mismatches",
		start,
		"FSH-07"
	)
