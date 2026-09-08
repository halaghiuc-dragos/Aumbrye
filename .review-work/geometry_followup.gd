extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var blockout = load("res://scripts/dungeon/castle/castle_blockout.gd").new()
	blockout.kind = &"hall"
	blockout._apply_kind_spec()
	var defaults = [blockout.door_north, blockout.door_east, blockout.door_south, blockout.door_west]
	blockout.door_north = not defaults[0]
	blockout.door_east = not defaults[1]
	blockout.door_south = not defaults[2]
	blockout.door_west = not defaults[3]
	var requested = [blockout.door_north, blockout.door_east, blockout.door_south, blockout.door_west]
	blockout._rebuild()
	var actual = [blockout.door_north, blockout.door_east, blockout.door_south, blockout.door_west]
	print("FRESH_GEOMETRY_CHECK defaults=", defaults, " requested=", requested, " actual=", actual)
	var walls = blockout.get_node("Geometry/Walls")
	var lintels = []
	for child in walls.get_children():
		if child is CollisionShape3D and child.shape is BoxShape3D and absf(child.shape.size.y - 1.5) < 0.001:
			lintels.append({"bottom":child.position.y-child.shape.size.y*0.5,"top":child.position.y+child.shape.size.y*0.5})
	print("FRESH_LINTEL_CHECK door_height=4.5 wall_height=6 actual=", lintels)
	blockout.free()
	quit()
