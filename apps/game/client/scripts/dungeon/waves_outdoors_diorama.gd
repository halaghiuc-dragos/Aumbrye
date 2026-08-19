class_name WavesOutdoorsDiorama
extends RefCounted

## Aumbrye Outskirts garden — large open meadow for Umbral Waves (no ceiling).

const TILE_SIZE := 2.0
const FLOOR_HALF := 105.0
const ARENA_HALF := 34.0
const CASTLE_BACK_Z := -88.0


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
	var birch_trunk := (
		PixelDioramaStyle.make_prop_material(theme, false).duplicate() as ShaderMaterial
	)
	birch_trunk.set_shader_parameter("color_base", Color(0.82, 0.78, 0.72))
	birch_trunk.set_shader_parameter("color_shadow", Color(0.54, 0.5, 0.46))
	return {
		"floor": PixelDioramaStyle.make_floor_material(theme),
		"grass": grass,
		"grass_alt": grass_alt,
		"grass_dark": grass_dark,
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
	var tiles := Node3D.new()
	tiles.name = "Tiles"
	floor_body.add_child(tiles)

	var cols := int(span / TILE_SIZE)
	var rows := int(span / TILE_SIZE)
	var origin_x := -FLOOR_HALF + TILE_SIZE * 0.5
	var origin_z := -FLOOR_HALF + TILE_SIZE * 0.5
	for row in rows:
		for col in cols:
			var dist := Vector2(origin_x + col * TILE_SIZE, origin_z + row * TILE_SIZE).length()
			var alt := (row + col) % 2 == 1
			var mat: Material = mats.grass_alt if alt else mats.grass
			if dist < ARENA_HALF + 4.0:
				mat = mats.floor
			PixelDioramaStyle.add_box(
				tiles,
				Vector3(TILE_SIZE * 0.98, 0.12, TILE_SIZE * 0.98),
				Vector3(origin_x + col * TILE_SIZE, 0.06, origin_z + row * TILE_SIZE),
				mat
			)

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
	for i in 320:
		var x := rng.randf_range(-FLOOR_HALF + 4.0, FLOOR_HALF - 4.0)
		var z := rng.randf_range(-FLOOR_HALF + 4.0, FLOOR_HALF - 8.0)
		if Vector2(x, z).length() < ARENA_HALF - 2.0:
			continue
		if absf(z - CASTLE_BACK_Z) < 12.0:
			continue
		var h := rng.randf_range(0.14, 0.48)
		var mat: Material = mats.grass_dark if rng.randf() > 0.55 else mats.accent
		PixelDioramaStyle.add_box(
			patches, Vector3(0.1, h, 0.1), Vector3(x, h * 0.5, z), mat, "GrassBlade_%d" % i
		)


static func _spawn_flowers(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("Flowers") != null:
		return
	var flowers := Node3D.new()
	flowers.name = "Flowers"
	root.add_child(flowers)
	var rng := RandomNumberGenerator.new()
	rng.seed = 33112
	var palette: Array[Material] = [
		mats.flower_red, mats.flower_yellow, mats.flower_purple, mats.flower_white
	]
	for i in 110:
		var x := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 8.0)
		var z := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 12.0)
		if Vector2(x, z).length() < ARENA_HALF + 1.0:
			continue
		var mat: Material = palette[rng.randi_range(0, palette.size() - 1)]
		var stem_h := rng.randf_range(0.22, 0.42)
		PixelDioramaStyle.add_box(
			flowers,
			Vector3(0.06, stem_h, 0.06),
			Vector3(x, stem_h * 0.5, z),
			mats.grass_dark,
			"Stem_%d" % i
		)
		PixelDioramaStyle.add_box(
			flowers, Vector3(0.18, 0.14, 0.18), Vector3(x, stem_h + 0.08, z), mat, "Bloom_%d" % i
		)


static func _spawn_garden_beds(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("GardenBeds") != null:
		return
	var beds := Node3D.new()
	beds.name = "GardenBeds"
	root.add_child(beds)
	for offset in [-18.0, 18.0]:
		PixelDioramaStyle.add_box(
			beds,
			Vector3(8.0, 0.12, 3.2),
			Vector3(offset, 0.06, ARENA_HALF - 6.0),
			mats.grass_dark,
			"BedSoil_%d" % int(offset)
		)
		var rng := RandomNumberGenerator.new()
		rng.seed = int(offset) * 17
		for i in 12:
			var lx: float = float(offset) + rng.randf_range(-3.5, 3.5)
			var lz: float = ARENA_HALF - 6.0 + rng.randf_range(-1.2, 1.2)
			var bloom_mat: Material = mats.flower_red if i % 3 == 0 else mats.flower_yellow
			PixelDioramaStyle.add_box(
				beds,
				Vector3(0.16, 0.12, 0.16),
				Vector3(lx, 0.22, lz),
				bloom_mat,
				"BedFlower_%d_%d" % [int(offset), i]
			)


static func _spawn_trees(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("Trees") != null:
		return
	var trees := Node3D.new()
	trees.name = "Trees"
	root.add_child(trees)
	var rng := RandomNumberGenerator.new()
	rng.seed = 44021
	for i in 64:
		var x := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 8.0)
		var z := rng.randf_range(-FLOOR_HALF + 8.0, FLOOR_HALF - 16.0)
		if Vector2(x, z).length() < ARENA_HALF + 3.0:
			continue
		var species := rng.randi_range(0, 4)
		var scale := rng.randf_range(0.75, 1.45)
		_spawn_tree_species(trees, Vector3(x, 0.0, z), mats, species, scale, i)


static func _spawn_tree_species(
	parent: Node3D, pos: Vector3, mats: Dictionary, species: int, scale: float, index: int
) -> void:
	var tree := Node3D.new()
	tree.name = "Tree_%d" % index
	tree.position = pos
	parent.add_child(tree)
	match species:
		0:
			_spawn_oak_tree(tree, mats, scale)
		1:
			_spawn_pine_tree(tree, mats, scale)
		2:
			_spawn_birch_tree(tree, mats, scale)
		3:
			_spawn_bush_cluster(tree, mats, scale)
		_:
			_spawn_flowering_tree(tree, mats, scale)


static func _spawn_oak_tree(parent: Node3D, mats: Dictionary, scale: float) -> void:
	var trunk_h := 2.4 * scale
	PixelDioramaStyle.add_box(
		parent,
		Vector3(0.45 * scale, trunk_h, 0.45 * scale),
		Vector3(0.0, trunk_h * 0.5, 0.0),
		mats.wood,
		"Trunk"
	)
	PixelDioramaStyle.add_box(
		parent,
		Vector3(2.4 * scale, 1.7 * scale, 2.4 * scale),
		Vector3(0.0, trunk_h + 0.75 * scale, 0.0),
		mats.grass,
		"Canopy"
	)


static func _spawn_pine_tree(parent: Node3D, mats: Dictionary, scale: float) -> void:
	var trunk_h := 3.2 * scale
	PixelDioramaStyle.add_box(
		parent,
		Vector3(0.28 * scale, trunk_h, 0.28 * scale),
		Vector3(0.0, trunk_h * 0.5, 0.0),
		mats.wood,
		"Trunk"
	)
	for layer in 3:
		var layer_scale := 1.0 - float(layer) * 0.22
		PixelDioramaStyle.add_box(
			parent,
			Vector3(1.6 * scale * layer_scale, 0.9 * scale, 1.6 * scale * layer_scale),
			Vector3(0.0, trunk_h + 0.35 * scale + float(layer) * 0.75 * scale, 0.0),
			mats.grass_dark,
			"PineLayer_%d" % layer
		)


static func _spawn_birch_tree(parent: Node3D, mats: Dictionary, scale: float) -> void:
	var trunk_h := 2.8 * scale
	PixelDioramaStyle.add_box(
		parent,
		Vector3(0.22 * scale, trunk_h, 0.22 * scale),
		Vector3(0.0, trunk_h * 0.5, 0.0),
		mats.birch,
		"Trunk"
	)
	PixelDioramaStyle.add_box(
		parent,
		Vector3(1.5 * scale, 1.1 * scale, 1.5 * scale),
		Vector3(0.0, trunk_h + 0.55 * scale, 0.0),
		mats.grass_alt,
		"Canopy"
	)


static func _spawn_bush_cluster(parent: Node3D, mats: Dictionary, scale: float) -> void:
	for i in 3:
		var angle := float(i) / 3.0 * TAU
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.55 * scale
		PixelDioramaStyle.add_box(
			parent,
			Vector3(1.1 * scale, 0.8 * scale, 1.1 * scale),
			offset + Vector3(0.0, 0.45 * scale, 0.0),
			mats.grass_dark if i % 2 == 0 else mats.grass,
			"Bush_%d" % i
		)


static func _spawn_flowering_tree(parent: Node3D, mats: Dictionary, scale: float) -> void:
	var trunk_h := 2.0 * scale
	PixelDioramaStyle.add_box(
		parent,
		Vector3(0.35 * scale, trunk_h, 0.35 * scale),
		Vector3(0.0, trunk_h * 0.5, 0.0),
		mats.wood,
		"Trunk"
	)
	PixelDioramaStyle.add_box(
		parent,
		Vector3(1.8 * scale, 1.3 * scale, 1.8 * scale),
		Vector3(0.0, trunk_h + 0.6 * scale, 0.0),
		mats.flower_purple,
		"BloomCanopy"
	)


static func _spawn_hedges(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("Hedges") != null:
		return
	var hedges := Node3D.new()
	hedges.name = "Hedges"
	root.add_child(hedges)
	var hedge_mat: Material = mats.grass_dark
	for side in [-1.0, 1.0]:
		for i in 14:
			var t := float(i) / 13.0
			var x := lerpf(-ARENA_HALF - 8.0, ARENA_HALF + 8.0, t)
			var z: float = float(side) * (ARENA_HALF + 5.0)
			PixelDioramaStyle.add_box(
				hedges,
				Vector3(2.2, 0.9, 1.2),
				Vector3(x, 0.45, z),
				hedge_mat,
				"Hedge_%s_%d" % [str(side), i]
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
		var body := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(0.32, 0.1, 0.5)
		body.mesh = mesh
		body.name = "Body"
		bird.add_child(body)
		var wing_l := MeshInstance3D.new()
		var wing_mesh := BoxMesh.new()
		wing_mesh.size = Vector3(0.5, 0.05, 0.16)
		wing_l.mesh = wing_mesh
		wing_l.name = "WingL"
		wing_l.position = Vector3(-0.26, 0.0, 0.0)
		bird.add_child(wing_l)
		var wing_r := wing_l.duplicate() as MeshInstance3D
		wing_r.name = "WingR"
		wing_r.position = Vector3(0.26, 0.0, 0.0)
		bird.add_child(wing_r)
		birds.add_child(bird)


static func _build_castle_backdrop(root: Node3D, mats: Dictionary) -> void:
	if root.get_node_or_null("CastleBackdrop") != null:
		return
	var castle := Node3D.new()
	castle.name = "CastleBackdrop"
	castle.position = Vector3(0.0, 0.0, CASTLE_BACK_Z)
	root.add_child(castle)

	var wall_h := 12.0
	var span := 52.0
	PixelDioramaStyle.add_box(
		castle, Vector3(span, wall_h, 1.2), Vector3(0.0, wall_h * 0.5, 0.0), mats.wall, "MainWall"
	)
	for tower_x in [-span * 0.42, span * 0.42]:
		PixelDioramaStyle.add_box(
			castle,
			Vector3(3.6, wall_h + 3.5, 3.6),
			Vector3(tower_x, (wall_h + 3.5) * 0.5, 0.4),
			mats.wall,
			"Tower"
		)
		PixelDioramaStyle.add_box(
			castle,
			Vector3(4.0, 0.55, 4.0),
			Vector3(tower_x, wall_h + 3.75, 0.4),
			mats.accent,
			"TowerCap"
		)
	for i in 11:
		var t := float(i) / 10.0
		var x := lerpf(-span * 0.5 + 1.0, span * 0.5 - 1.0, t)
		PixelDioramaStyle.add_box(
			castle,
			Vector3(1.5, 1.3, 1.0),
			Vector3(x, wall_h + 0.65, 0.2),
			mats.accent,
			"Merlon_%d" % i
		)
	PixelDioramaStyle.add_box(
		castle, Vector3(5.0, 6.5, 2.2), Vector3(0.0, 3.25, 1.2), mats.accent, "Gatehouse"
	)
