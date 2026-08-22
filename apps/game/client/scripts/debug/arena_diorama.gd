class_name ArenaDiorama
extends RefCounted

## Procedural dressing for the training combat arena.

const TILE_SIZE := 2.0
const FLOOR_SIZE := 30.0
const WALL_HEIGHT := 5.0
const HUB_RETURN_Z := -6.0


static func apply(arena: Node3D) -> void:
	var mats := _load_materials()
	VisualLighting.apply_arena(arena)
	_dress_floor(arena, mats)
	_dress_walls(arena, mats)
	_dress_hub_return(arena.get_node_or_null("HubReturn"), mats)
	_add_arena_accent_lights(arena)


static func _load_materials() -> Dictionary:
	var theme := PixelDioramaStyle.theme_from_biome(BiomeRegistry.BIOME_CASTLE)
	var floor_alt := (
		(
			PixelDioramaStyle
			. make_surface_material(PixelDioramaStyle.SurfaceKind.FLOOR, theme)
			. duplicate()
		)
		as ShaderMaterial
	)
	var palette := PixelDioramaStyle.get_palette(theme)
	floor_alt.set_shader_parameter(
		"color_base", palette[PixelDioramaStyle.PaletteSlot.FLOOR_SHADOW]
	)
	return {
		"floor": PixelDioramaStyle.make_floor_material(theme),
		"floor_alt": floor_alt,
		"wall": PixelDioramaStyle.make_wall_material(theme),
		"accent": PixelDioramaStyle.make_accent_material(theme),
		"wood": PixelDioramaStyle.make_prop_material(theme, false),
	}


static func _dress_floor(arena: Node3D, mats: Dictionary) -> void:
	var floor_body := arena.get_node_or_null("Floor") as StaticBody3D
	if floor_body:
		var floor_mesh := floor_body.get_node_or_null("MeshInstance3D") as MeshInstance3D
		if floor_mesh:
			floor_mesh.visible = false

	if arena.get_node_or_null("DioramaTiles") != null:
		return

	var tiles := Node3D.new()
	tiles.name = "DioramaTiles"
	arena.add_child(tiles)

	var half := FLOOR_SIZE * 0.5
	var cols := int(FLOOR_SIZE / TILE_SIZE)
	var rows := int(FLOOR_SIZE / TILE_SIZE)
	var origin_x := -half + TILE_SIZE * 0.5
	var origin_z := -half + TILE_SIZE * 0.5
	for row in rows:
		for col in cols:
			var alt := (row + col) % 2 == 1
			var mat: Material = mats.floor_alt if alt else mats.floor
			PixelDioramaStyle.add_box(
				tiles,
				Vector3(TILE_SIZE * 0.98, 0.12, TILE_SIZE * 0.98),
				Vector3(origin_x + col * TILE_SIZE, 0.06, origin_z + row * TILE_SIZE),
				mat
			)

	# The gold "lane" that used to run down the middle of the arena is gone. Its tiles sat 3cm proud
	# of the floor, so the training area read as having a raised yellow kerb through it — the same
	# strip the hub plaza had. Nothing on the arena floor stands above floor level now.


static func _dress_walls(arena: Node3D, mats: Dictionary) -> void:
	var walls := arena.get_node_or_null("ArenaWalls") as Node3D
	if walls == null:
		walls = Node3D.new()
		walls.name = "ArenaWalls"
		arena.add_child(walls)

	var half := FLOOR_SIZE * 0.5
	var span := FLOOR_SIZE
	var thickness := 1.0
	var wall_y := WALL_HEIGHT * 0.5

	for side in [
		{
			"name": "NorthWall",
			"pos": Vector3(0.0, wall_y, -half),
			"size": Vector3(span, WALL_HEIGHT, thickness)
		},
		{
			"name": "SouthWall",
			"pos": Vector3(0.0, wall_y, half),
			"size": Vector3(span, WALL_HEIGHT, thickness)
		},
		{
			"name": "EastWall",
			"pos": Vector3(half, wall_y, 0.0),
			"size": Vector3(thickness, WALL_HEIGHT, span)
		},
		{
			"name": "WestWall",
			"pos": Vector3(-half, wall_y, 0.0),
			"size": Vector3(thickness, WALL_HEIGHT, span)
		},
	]:
		var existing := walls.get_node_or_null(side.name) as MeshInstance3D
		if existing == null:
			existing = PixelDioramaStyle.add_box(walls, side.size, side.pos, mats.wall, side.name)
		else:
			existing.position = side.pos

	var wall_collision := walls.get_node_or_null("WallCollision") as StaticBody3D
	if wall_collision == null:
		wall_collision = StaticBody3D.new()
		wall_collision.name = "WallCollision"
		walls.add_child(wall_collision)
	else:
		for child in wall_collision.get_children():
			child.queue_free()
	wall_collision.collision_layer = 1
	wall_collision.collision_mask = 0

	_add_wall_collision_box(
		wall_collision,
		"ColNorth",
		Vector3(0.0, wall_y, -half),
		Vector3(span, WALL_HEIGHT, thickness)
	)
	_add_wall_collision_box(
		wall_collision,
		"ColSouth",
		Vector3(0.0, wall_y, half),
		Vector3(span, WALL_HEIGHT, thickness)
	)
	_add_wall_collision_box(
		wall_collision, "ColEast", Vector3(half, wall_y, 0.0), Vector3(thickness, WALL_HEIGHT, span)
	)
	_add_wall_collision_box(
		wall_collision,
		"ColWest",
		Vector3(-half, wall_y, 0.0),
		Vector3(thickness, WALL_HEIGHT, span)
	)

	for side_name in ["NorthWall", "SouthWall"]:
		var banner_x := -8.0 if side_name == "NorthWall" else 8.0
		var banner_z := -half + 0.35 if side_name == "NorthWall" else half - 0.35
		PixelDioramaStyle.add_box(
			walls,
			Vector3(0.35, 1.1, 0.12),
			Vector3(banner_x, 3.2, banner_z),
			mats.accent,
			"%sBanner" % side_name
		)


static func _add_wall_collision_box(
	parent: StaticBody3D, node_name: String, center: Vector3, size: Vector3
) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = center
	parent.add_child(shape_node)


static func _dress_hub_return(portal: Node3D, mats: Dictionary) -> void:
	if portal == null:
		return
	var def := PortalCatalog.resolve("hub_return")
	PixelDioramaStyle.build_portal(portal, def, 1.0, mats)


static func _add_arena_accent_lights(arena: Node3D) -> void:
	if arena.get_node_or_null("ArenaAccentLights") != null:
		return
	var lights := Node3D.new()
	lights.name = "ArenaAccentLights"
	arena.add_child(lights)

	for corner in [
		Vector3(-10.0, 3.2, -10.0),
		Vector3(10.0, 3.2, -10.0),
		Vector3(-10.0, 3.2, 10.0),
		Vector3(10.0, 3.2, 10.0)
	]:
		var torch := OmniLight3D.new()
		torch.light_color = Color(1.0, 0.78, 0.45)
		torch.light_energy = 0.55
		torch.omni_range = 7.5
		torch.position = corner
		lights.add_child(torch)
