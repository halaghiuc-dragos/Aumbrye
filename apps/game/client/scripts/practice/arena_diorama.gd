class_name ArenaDiorama
extends RefCounted


const TILE_SIZE := 2.0
const TILE_TOP := 0.12
const TILE_BED_DROP := 0.01
const TILE_BED_THICK := 0.2
const FLOOR_SIZE := 30.0
const WALL_HEIGHT := 5.0

const PARAPET_HEIGHT := 1.55
const PARAPET_THICKNESS := 0.72

const CORNER_BOWL_Y := 2.1


static func apply(arena: Node3D) -> void:
	var mats := _load_materials()
	VisualLighting.apply_arena(arena)
	_dress_floor(arena, mats)
	_dress_walls(arena, mats)
	_dress_hub_return(arena.get_node_or_null("HubReturn"), mats)
	_add_arena_accent_lights(arena, mats)


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
	# Ten-metre paving modules, the same stone as the hub's plaza.
	var by_parity: Array = [[] as Array[Transform3D], [] as Array[Transform3D]]
	var modules := int(FLOOR_SIZE / 10.0)
	var origin := -float(modules) * 5.0 + 5.0
	for column in modules:
		for row in modules:
			(by_parity[(column + row) % 2] as Array[Transform3D]).append(
				Transform3D(Basis.IDENTITY, Vector3(origin + column * 10.0, 0.0, origin + row * 10.0))
			)
	for parity in 2:
		PropLibrary.scatter_themed(
			tiles, "hub/floor_module_%d" % parity, PixelDioramaStyle.PaletteTheme.CASTLE,
			by_parity[parity] as Array[Transform3D], "Paving%d" % parity, {"materials": mats}
		)


static func _dress_walls(arena: Node3D, mats: Dictionary) -> void:
	var walls := arena.get_node_or_null("ArenaWalls") as Node3D
	if walls == null:
		walls = Node3D.new()
		walls.name = "ArenaWalls"
		arena.add_child(walls)
	var existing_parapet := walls.get_node_or_null("TowerParapet")
	if existing_parapet:
		existing_parapet.queue_free()
	for child in walls.get_children():
		if child is MeshInstance3D:
			child.visible = false

	var parapet := Node3D.new()
	parapet.name = "TowerParapet"
	walls.add_child(parapet)

	var half := FLOOR_SIZE * 0.5
	var span := FLOOR_SIZE

	for run in [
		{"pos": Vector3(0.0, PARAPET_HEIGHT * 0.5, -half), "yaw": 0.0, "name": "NorthParapet"},
		{"pos": Vector3(0.0, PARAPET_HEIGHT * 0.5, half), "yaw": 0.0, "name": "SouthParapet"},
		{"pos": Vector3(half, PARAPET_HEIGHT * 0.5, 0.0), "yaw": PI * 0.5, "name": "EastParapet"},
		{"pos": Vector3(-half, PARAPET_HEIGHT * 0.5, 0.0), "yaw": PI * 0.5, "name": "WestParapet"},
	]:
		PixelDioramaStyle.add_castle_parapet_run(
			parapet, mats, run.pos, span, PARAPET_THICKNESS, PARAPET_HEIGHT, run.yaw, run.name
		)

	for corner in [
		Vector3(-half, 0.0, -half),
		Vector3(half, 0.0, -half),
		Vector3(half, 0.0, half),
		Vector3(-half, 0.0, half),
	]:
		PixelDioramaStyle.add_castle_corner_turret(parapet, mats, corner, PARAPET_HEIGHT)

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

	PixelDioramaStyle.add_castle_parapet_collision(
		wall_collision, half, half, PARAPET_THICKNESS, WALL_HEIGHT
	)


static func _dress_hub_return(portal: Node3D, mats: Dictionary) -> void:
	if portal == null:
		return
	var def := PortalCatalog.resolve("hub_return")
	PixelDioramaStyle.build_portal(portal, def, 1.0, mats)


static func _make_corner_brazier(parent: Node3D, mats: Dictionary, base: Vector3) -> Node3D:
	var root := Node3D.new()
	root.name = "CornerBrazier%s" % str(base)
	root.position = Vector3(base.x, 0.0, base.z)
	parent.add_child(root)
	# The plaza brazier stretched to the arena's taller stand, its coals in the ember colour.
	var stand := Node3D.new()
	stand.name = "Stand"
	stand.scale = Vector3(1.1, CORNER_BOWL_Y / 1.5, 1.1)
	root.add_child(stand)
	PropLibrary.attach_themed(
		stand, "hub/brazier", PixelDioramaStyle.PaletteTheme.CASTLE,
		{"materials": mats}
	)
	return root


static func _add_arena_accent_lights(arena: Node3D, mats: Dictionary) -> void:
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
		var brazier := _make_corner_brazier(lights, mats, corner)
		var torch := OmniLight3D.new()
		torch.name = "CornerTorchLight"
		torch.light_color = Color(1.0, 0.78, 0.45)
		torch.light_energy = 0.55
		torch.omni_range = 7.5
		torch.shadow_enabled = false
		torch.position = Vector3(0.0, CORNER_BOWL_Y + 0.18, 0.0)
		torch.add_to_group(NightLights.GROUP)
		brazier.add_child(torch)
		LightEmbers.attach(
			brazier, Vector3(0.0, CORNER_BOWL_Y + 0.1, 0.0), torch.light_color, 1.4, 1.2
		)
