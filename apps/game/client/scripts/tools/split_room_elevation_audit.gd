extends Node3D

const CastleBlockoutScript := preload("res://scripts/dungeon/castle/castle_blockout.gd")
const CastleRoomConstantsScript := preload("res://scripts/dungeon/castle/castle_room_constants.gd")

var _failures := 0


func _ready() -> void:
	var blockout := CastleBlockoutScript.new()
	blockout.name = "SplitElevationAuditBlockout"
	blockout.shape = &"split"
	blockout.room_width = 16.0
	blockout.room_depth = 20.0
	blockout.build_ceiling = false
	blockout.door_north = true
	blockout.door_south = true
	blockout.door_east = true
	blockout.door_west = true
	add_child(blockout)
	blockout.set_navigation_map(get_world_3d().navigation_map)
	blockout.add_height_stairs(6, Vector2i(0, -1), 0.5)
	blockout.finalize_geometry()

	_expect(
		is_equal_approx(
			blockout.socket_landing_height(CastleRoomConstantsScript.Direction.NORTH), 3.0
		),
		"north split socket must land on the raised floor"
	)
	_expect(
		is_zero_approx(blockout.socket_landing_height(CastleRoomConstantsScript.Direction.SOUTH)),
		"south split socket must remain on the lower floor"
	)
	_expect(
		is_zero_approx(blockout.socket_landing_height(CastleRoomConstantsScript.Direction.EAST)),
		"east split socket must enter the lower floor"
	)
	_expect(
		is_zero_approx(blockout.socket_landing_height(CastleRoomConstantsScript.Direction.WEST)),
		"west split socket must enter the lower floor"
	)

	await get_tree().physics_frame
	await get_tree().physics_frame
	await get_tree().physics_frame
	var state := get_world_3d().direct_space_state
	var raised_opening := _ray_hits(state, Vector3(0.0, 3.1, -11.0), Vector3(0.0, 3.1, -8.0))
	var raised_sill := _ray_hits(state, Vector3(0.0, 1.0, -11.0), Vector3(0.0, 1.0, -8.0))
	_expect(not raised_opening, "raised doorway aperture must be walkable at its landing height")
	_expect(raised_sill, "raised doorway must retain a solid sill below its landing height")
	_expect(not _ray_hits(state, Vector3(0.0, 1.0, 11.0), Vector3(0.0, 1.0, 8.0)), "south doorway aperture must be open")
	_expect(not _ray_hits(state, Vector3(9.0, 1.0, 0.5), Vector3(7.0, 1.0, 0.5)), "east doorway aperture must be open")
	_expect(not _ray_hits(state, Vector3(-9.0, 1.0, 0.5), Vector3(-7.0, 1.0, 0.5)), "west doorway aperture must be open")
	_expect(_floor_height_at(state, Vector3(0.0, 0.0, -9.0)) > 2.9, "north entry must land on the raised surface")
	_expect(_floor_height_at(state, Vector3(0.0, 0.0, 9.0)) < 0.1, "south entry must land on the lower surface")
	_expect(_floor_height_at(state, Vector3(7.0, 0.0, 0.5)) < 0.1, "east entry must land on the lower surface")
	_expect(_floor_height_at(state, Vector3(-7.0, 0.0, 0.5)) < 0.1, "west entry must land on the lower surface")

	# Both levels and every stair tread are StaticBody collision geometry, the source passed to
	# `CastleBlockout`'s navigation bake during an assembled dungeon. Check the physical surfaces
	# here; a standalone headless World3D intentionally has no registered navigation map.
	var surface_heights := _collision_surface_heights(blockout)
	_expect(_contains_height(surface_heights, 0.0), "lower split surface must exist for navigation")
	_expect(_contains_height(surface_heights, 3.0), "raised doorway landing must exist for navigation")
	_expect(_contains_height(surface_heights, 1.5), "transition stairs must bridge both elevations")

	print("SPLIT ROOM ELEVATION RESULT %d failures" % _failures)
	get_tree().quit(0 if _failures == 0 else 1)


func _ray_hits(state: PhysicsDirectSpaceState3D, from: Vector3, to: Vector3) -> bool:
	var query := PhysicsRayQueryParameters3D.create(from, to, 1)
	return not state.intersect_ray(query).is_empty()


func _floor_height_at(state: PhysicsDirectSpaceState3D, position_value: Vector3) -> float:
	var query := PhysicsRayQueryParameters3D.create(position_value + Vector3.UP * 8.0, position_value - Vector3.UP)
	var hit := state.intersect_ray(query)
	return float(hit.get("position", Vector3(0.0, -100.0, 0.0)).y)


func _collision_surface_heights(root: Node) -> Array[float]:
	var heights: Array[float] = []
	for child in root.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D:
			var box := child.shape as BoxShape3D
			heights.append(child.global_position.y + box.size.y * 0.5)
		heights.append_array(_collision_surface_heights(child))
	return heights


func _contains_height(heights: Array[float], expected: float) -> bool:
	for height in heights:
		if absf(height - expected) < 0.05:
			return true
	return false


func _expect(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	push_error("Split room elevation audit: %s" % message)
