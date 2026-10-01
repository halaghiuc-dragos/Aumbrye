class_name WavesOutdoorsDiorama
extends RefCounted


const TILE_SIZE := 2.0
const TILE_TOP := 0.12
const TILE_BED_DROP := 0.01
const TILE_BED_THICK := 0.2
const FLOOR_HALF := 105.0
const ARENA_HALF := 34.0
const TILE_FIELD_HALF := 62.0
const CASTLE_BACK_Z := -88.0
const MODULE_SIZE := 10.0


static func apply(root: Node3D) -> void:
	var mats := _load_materials()
	VisualLighting.apply_waves_outdoors(root)
	_build_floor(root, mats)
	_spawn_grass_patches(root, mats)
	_spawn_flowers(root, mats)
	_spawn_garden_beds(root, mats)
	_spawn_trees(root, mats)
	_spawn_hedges(root, mats)
	_spawn_birds(root)
	_build_castle_backdrop(root, mats)


static func _load_materials() -> Dictionary:
	var theme := PixelDioramaStyle.theme_from_biome(BiomeRegistry.BIOME_CASTLE)
	var grass := (
		(
			PixelDioramaStyle
			. make_surface_material(PixelDioramaStyle.SurfaceKind.FLOOR, theme)
			. duplicate()
		)
		as ShaderMaterial
	)
	grass.set_shader_parameter("color_base", Color(0.28, 0.52, 0.24))
	var grass_alt := grass.duplicate() as ShaderMaterial
	grass_alt.set_shader_parameter("color_base", Color(0.22, 0.46, 0.2))
	var grass_dark := grass.duplicate() as ShaderMaterial
	grass_dark.set_shader_parameter("color_base", Color(0.16, 0.34, 0.14))
	var flower_red := PixelDioramaStyle.make_glow_material(
		Color(0.92, 0.28, 0.32), Color(0.62, 0.14, 0.2), 0.55
	)
	var flower_yellow := PixelDioramaStyle.make_glow_material(
		Color(0.95, 0.82, 0.22), Color(0.7, 0.52, 0.12), 0.55
	)
	var flower_purple := PixelDioramaStyle.make_glow_material(
		Color(0.72, 0.38, 0.92), Color(0.42, 0.18, 0.6), 0.55
	)
	var flower_white := PixelDioramaStyle.make_glow_material(
		Color(0.92, 0.9, 0.82), Color(0.66, 0.64, 0.58), 0.45
	)
	for bloom in [flower_red, flower_yellow, flower_purple, flower_white]:
		PixelDioramaStyle.set_authored_param(bloom, "wind_sway", 0.45)
	var birch_trunk := (
		PixelDioramaStyle.make_prop_material(theme, false).duplicate() as ShaderMaterial
	)
	birch_trunk.set_shader_parameter("color_base", Color(0.82, 0.78, 0.72))
	birch_trunk.set_shader_parameter("color_shadow", Color(0.54, 0.5, 0.46))
	var blade := grass_dark.duplicate() as ShaderMaterial
	PixelDioramaStyle.set_authored_param(blade, "wind_sway", 0.55)
	var blade_alt := grass.duplicate() as ShaderMaterial
	PixelDioramaStyle.set_authored_param(blade_alt, "color_base", Color(0.34, 0.55, 0.26))
	PixelDioramaStyle.set_authored_param(blade_alt, "wind_sway", 0.62)
	var stem := grass_dark.duplicate() as ShaderMaterial
	PixelDioramaStyle.set_authored_param(stem, "wind_sway", 0.45)
	var floor_wet := (PixelDioramaStyle.make_floor_material(theme).duplicate()) as ShaderMaterial
	PixelDioramaStyle.set_authored_param(floor_wet, "wetness_response", 1.0)
	for turf in [grass, grass_alt, grass_dark]:
		PixelDioramaStyle.set_authored_param(turf, "wetness_response", 0.7)
	return {
		"floor": PixelDioramaSettings.track(floor_wet),
		"grass": grass,
		"grass_alt": grass_alt,
		"grass_dark": grass_dark,
		"blade": PixelDioramaSettings.track(blade),
		"blade_alt": PixelDioramaSettings.track(blade_alt),
		"stem": PixelDioramaSettings.track(stem),
		"wall": PixelDioramaStyle.make_wall_material(theme),
		"accent": PixelDioramaStyle.make_accent_material(theme),
		"wood": PixelDioramaStyle.make_prop_material(theme, false),
		"birch": birch_trunk,
		"flower_red": flower_red,
		"flower_yellow": flower_yellow,
		"flower_purple": flower_purple,
		"flower_white": flower_white,
	}


static func _build_floor(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("WavesOutdoorsFloor") != null:
		return
	var floor_body := StaticBody3D.new()
	floor_body.name = "WavesOutdoorsFloor"
	floor_body.collision_layer = 1
	floor_body.collision_mask = 0
	root.add_child(floor_body)

	var span := FLOOR_HALF * 2.0
	var options := {"materials": mats}
	# The arena paving is one stone; the hub's checker alternates two, so both map to the same.
	var paving_materials: Dictionary = mats.duplicate()
	paving_materials["floor_alt"] = mats.floor
	var paving_options := {"materials": paving_materials}
	# Ten-metre modules of turf, with paving (the hub's stone modules) under the arena itself.
	var grass: Array = [[] as Array[Transform3D], [] as Array[Transform3D]]
	var stone: Array = [[] as Array[Transform3D], [] as Array[Transform3D]]
	var modules := int(TILE_FIELD_HALF * 2.0 / MODULE_SIZE)
	var origin := -float(modules) * MODULE_SIZE * 0.5 + MODULE_SIZE * 0.5
	for column in modules:
		for row in modules:
			var centre := Vector3(origin + column * MODULE_SIZE, 0.0, origin + row * MODULE_SIZE)
			var bucket: Array = stone if Vector2(centre.x, centre.z).length() < ARENA_HALF + 4.0 else grass
			(bucket[(column + row) % 2] as Array[Transform3D]).append(Transform3D(Basis.IDENTITY, centre))
	for parity in 2:
		PropLibrary.scatter_themed(
			floor_body, "nature/grass_module_%d" % parity, PixelDioramaStyle.PaletteTheme.CASTLE,
			grass[parity] as Array[Transform3D], "Turf%d" % parity, options
		)
		PropLibrary.scatter_themed(
			floor_body, "hub/floor_module_%d" % parity, PixelDioramaStyle.PaletteTheme.CASTLE,
			stone[parity] as Array[Transform3D], "Paving%d" % parity, paving_options
		)
	var plate := Node3D.new()
	plate.name = "FarField"
	plate.position = Vector3(0.0, -0.01, 0.0)
	plate.scale = Vector3(span, 1.0, span)
	floor_body.add_child(plate)
	PropLibrary.attach_themed(plate, "nature/ground_plate", PixelDioramaStyle.PaletteTheme.CASTLE, options)

	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(span, 0.2, span)
	collision.shape = shape
	collision.position = Vector3(0.0, 0.1, 0.0)
	floor_body.add_child(collision)


static func _spawn_grass_patches(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("GrassPatches") != null:
		return
	var patches := Node3D.new()
	patches.name = "GrassPatches"
	root.add_child(patches)
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var by_variant: Array = [[] as Array[Transform3D], [] as Array[Transform3D], [] as Array[Transform3D]]
	for i in 260:
		var x := rng.randf_range(-FLOOR_HALF + 4.0, FLOOR_HALF - 4.0)
		var z := rng.randf_range(-FLOOR_HALF + 4.0, FLOOR_HALF - 8.0)
		if Vector2(x, z).length() < ARENA_HALF - 2.0:
			continue
		if absf(z - CASTLE_BACK_Z) < 12.0:
			continue
		_add_tuft(by_variant, rng, Vector3(x, 0.0, z), 1.0)
	for i in 90:
		var angle := rng.randf_range(0.0, TAU)
		var dist := rng.randf_range(11.0, ARENA_HALF - 2.5)
		_add_tuft(by_variant, rng, Vector3(cos(angle) * dist, 0.0, sin(angle) * dist), 0.62)
	for variant in by_variant.size():
		PropLibrary.scatter_themed(
			patches, "nature/tuft_%d" % variant, PixelDioramaStyle.PaletteTheme.CASTLE,
			by_variant[variant] as Array[Transform3D], "Tufts%d" % variant, {"materials": mats}
		)


static func _add_tuft(by_variant: Array, rng: RandomNumberGenerator, at: Vector3, tuft_scale: float) -> void:
	var variant := rng.randi_range(0, by_variant.size() - 1)
	var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * tuft_scale)
	(by_variant[variant] as Array[Transform3D]).append(Transform3D(basis, at))


static func _spawn_flowers(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("Flowers") != null:
		return
	var flowers := Node3D.new()
	flowers.name = "Flowers"
	root.add_child(flowers)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33112
	var colours: Array[String] = ["red", "yellow", "purple", "white"]
	var by_colour: Dictionary = {}
	for colour in colours:
		by_colour[colour] = [] as Array[Transform3D]
	for i in 110:
		var x := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 8.0)
		var z := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 12.0)
		if Vector2(x, z).length() < ARENA_HALF + 1.0:
			continue
		var colour: String = colours[rng.randi_range(0, colours.size() - 1)]
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3(1.0, rng.randf_range(0.7, 1.3), 1.0))
		(by_colour[colour] as Array[Transform3D]).append(Transform3D(basis, Vector3(x, 0.0, z)))
	for colour in colours:
		PropLibrary.scatter_themed(
			flowers, "nature/flower_%s" % colour, PixelDioramaStyle.PaletteTheme.CASTLE,
			by_colour[colour] as Array[Transform3D], "Flowers_%s" % colour, {"materials": mats}
		)


static func _spawn_garden_beds(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("GardenBeds") != null:
		return
	var beds := Node3D.new()
	beds.name = "GardenBeds"
	root.add_child(beds)
	for offset in [-18.0, 18.0]:
		var bed := Node3D.new()
		bed.name = "Bed_%d" % int(offset)
		bed.position = Vector3(offset, 0.0, ARENA_HALF - 6.0)
		beds.add_child(bed)
		PropLibrary.attach_themed(bed, "nature/garden_bed", PixelDioramaStyle.PaletteTheme.CASTLE, {"materials": mats})


static func _spawn_trees(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("Trees") != null:
		return
	var trees := Node3D.new()
	trees.name = "Trees"
	root.add_child(trees)
	var rng := RandomNumberGenerator.new()
	rng.seed = 44021
	var species_ids: Array[String] = ["oak", "pine", "birch", "bush", "flowering_tree"]
	var by_species: Dictionary = {}
	for id in species_ids:
		by_species[id] = [] as Array[Transform3D]
	for i in 64:
		var x := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 8.0)
		var z := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 16.0)
		if Vector2(x, z).length() < ARENA_HALF + 3.0:
			continue
		var species: String = species_ids[rng.randi_range(0, species_ids.size() - 1)]
		var tree_scale := rng.randf_range(0.75, 1.45)
		var basis := Basis(Vector3.UP, rng.randf_range(0.0, TAU)).scaled(Vector3.ONE * tree_scale)
		(by_species[species] as Array[Transform3D]).append(Transform3D(basis, Vector3(x, 0.0, z)))
	for species in species_ids:
		PropLibrary.scatter_themed(
			trees, "nature/%s" % species, PixelDioramaStyle.PaletteTheme.CASTLE,
			by_species[species] as Array[Transform3D], "Trees_%s" % species, {"materials": mats}
		)


static func _spawn_hedges(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("Hedges") != null:
		return
	var hedges := Node3D.new()
	hedges.name = "Hedges"
	root.add_child(hedges)
	var placements: Array[Transform3D] = []
	for side in [-1.0, 1.0]:
		for i in 14:
			var t := float(i) / 13.0
			var x := lerpf(-ARENA_HALF - 8.0, ARENA_HALF + 8.0, t)
			placements.append(Transform3D(Basis.IDENTITY, Vector3(x, 0.0, float(side) * (ARENA_HALF + 5.0))))
	PropLibrary.scatter_themed(
		hedges, "nature/hedge", PixelDioramaStyle.PaletteTheme.CASTLE, placements, "HedgeRow", {"materials": mats}
	)


static func _spawn_birds(root: Node3D) -> void:
	if root.get_node_or_null("Birds") != null:
		return
	var birds := Node3D.new()
	birds.name = "Birds"
	root.add_child(birds)
	var rng := RandomNumberGenerator.new()
	rng.seed = 77102
	for i in 28:
		var bird := Node3D.new()
		bird.name = "Bird_%d" % i
		bird.add_to_group("waves_bird")
		var home := Vector3(
			rng.randf_range(-55.0, 55.0), rng.randf_range(7.0, 16.0), rng.randf_range(-45.0, 45.0)
		)
		bird.position = home
		bird.set_meta("home_x", home.x)
		bird.set_meta("home_y", home.y)
		bird.set_meta("home_z", home.z)
		bird.set_meta("orbit_radius", rng.randf_range(3.5, 11.0))
		bird.set_meta("orbit_speed", rng.randf_range(0.25, 0.85))
		bird.set_meta("orbit_phase", rng.randf() * TAU)
		bird.set_meta("wing_phase", rng.randf() * TAU)
		PropLibrary.attach_themed(bird, "nature/bird", PixelDioramaStyle.PaletteTheme.CASTLE)
		birds.add_child(bird)


static func _build_castle_backdrop(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("CastleBackdrop") != null:
		return
	var castle := Node3D.new()
	castle.name = "CastleBackdrop"
	castle.position = Vector3(0.0, 0.0, CASTLE_BACK_Z)
	root.add_child(castle)
	PropLibrary.attach_themed(
		castle, "nature/castle_backdrop", PixelDioramaStyle.PaletteTheme.CASTLE, {"materials": mats}
	)


