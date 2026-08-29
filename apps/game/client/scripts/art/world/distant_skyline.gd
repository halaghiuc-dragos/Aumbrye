extends Node3D


const NEAR_RING := 76.0
const FAR_RING := 118.0
const HORIZON_RING := 760.0
const HORIZON_LANDMARKS := 22

## The mountain wall that closes the horizon. Far enough out that it reads as distance
## rather than as scenery you could walk to, and well inside GROUND_RADIUS so the range
## stands on the ground plate instead of floating off its edge. Three ranges, each one
## further back and taller than the last, because a single line of peaks reads as a
## painted backdrop and two overlapping ones read as depth.
const MOUNTAIN_RING := 2050.0
const MOUNTAIN_RANGES := 3
const MOUNTAIN_PEAKS := 26
## Boxes per peak. The range is voxel-stepped like everything else here, so this is
## also what decides how coarse the slopes look.
const MOUNTAIN_STEPS := 8
## Run the ground out to just inside the camera's default far plane (4000). Where the
## plate ends, the sky shows through beneath the true horizon as a flat band; the
## further out the edge is, the thinner that seam gets.
const GROUND_RADIUS := 3800.0

const GROUND_DROP := -26.0

## How far a road's surface stands above the surrounding ground, and how deep the slab
## that carries it is. The depth is what keeps crossings clean: see `_build_roads`.
const ROAD_TOP := 0.06
const ROAD_SLAB := 0.6

const LEVEL_CLEARANCE := 34.0

const NEAR_HAZE := 0.20
const FAR_HAZE := 0.44

const SMOKE_STACKS := 7

## Seed for the town plan. Fixed, so the village behind the hub is the same village
## every time the player sees it.
const TOWN_SEED := 20259

## Bands at or past this index are only ever read as shapes against the sky, so they
## are built as silhouettes: no windows, no chimneys, a handful of boxes each.
const SILHOUETTE_BAND := 4

## Bands at or past this index drop the per-window and per-chimney detail but keep
## their massing.
const SIMPLE_BAND := 2

## How far the planned town reaches, for the batches' visibility bounds.
const VILLAGE_EXTENT := 420.0

const FIELD_INNER := LEVEL_CLEARANCE + 4.0
const FIELD_OUTER := 68.0

## Scatter counts are attempts, not results: anything that would land on a street or a
## building is dropped, so these run higher than the number that ends up on screen.
const GRASS_CLUMPS := 1400
const TREE_COUNT := 70
const FENCE_RUNS := 36

const VILLAGER_COUNT := 92
const PEASANT_COUNT := 46
const SOLDIER_PAIRS := 14
const HORSEMAN_COUNT := 17
const CART_COUNT := 11
const DOG_COUNT := 16

const VILLAGER_SPEED := 1.15
const SOLDIER_SPEED := 1.35
const HORSEMAN_SPEED := 4.6
## A loaded cart moves at the walk of the horse pulling it, not at a rider's trot.
const CART_SPEED := 1.9
const DOG_SPEED := 2.6

var _materials: Dictionary = {}

var _window_material: StandardMaterial3D
var _last_night := -1.0


func _window_mat() -> StandardMaterial3D:
	if _window_material == null:
		_window_material = StandardMaterial3D.new()
		_window_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_window_material.disable_receive_shadows = true
		_window_material.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
		_window_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_window_material.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		_window_material.albedo_color = Color(1.0, 0.74, 0.36, 0.0)
	return _window_material


func _light_windows() -> void:
	if _window_material == null:
		return
	var night := DayNightService.night_amount()
	if absf(night - _last_night) < 0.004:
		return
	_last_night = night
	var col := _window_material.albedo_color
	_window_material.albedo_color = Color(col.r, col.g, col.b, night)


func _surface(
	base: Color, shadow: Color, accent: Color, cells_per_metre: float = 2.4
) -> Material:
	var key := "%s_%s_%s_%.2f" % [
		base.to_html(false), shadow.to_html(false), accent.to_html(false), cells_per_metre
	]
	if _materials.has(key):
		return _materials[key]
	var mat := (
		PixelDioramaStyle
		. make_surface_material(PixelDioramaStyle.SurfaceKind.WALL, PixelDioramaStyle.PaletteTheme.HUB, 0.5)
		. duplicate()
	) as ShaderMaterial
	PixelDioramaStyle.set_authored_param(mat, "color_base", base)
	PixelDioramaStyle.set_authored_param(mat, "color_shadow", shadow)
	PixelDioramaStyle.set_authored_param(mat, "color_accent", accent)
	mat.set_shader_parameter("use_tile_atlas", false)
	mat.set_shader_parameter("pixel_scale", cells_per_metre * 4.0)
	mat.set_shader_parameter("detail_near", 120.0)
	mat.set_shader_parameter("detail_far", 520.0)
	_materials[key] = mat
	return mat


func _mat(kind_name: String) -> Material:
	match kind_name:
		"stone":
			return _surface(Color(0.56, 0.53, 0.47), Color(0.37, 0.34, 0.31), Color(0.66, 0.62, 0.55), 2.2)
		"stone_dark":
			return _surface(Color(0.40, 0.38, 0.36), Color(0.26, 0.24, 0.23), Color(0.50, 0.47, 0.44), 2.2)
		"daub":
			return _surface(Color(0.78, 0.72, 0.59), Color(0.55, 0.50, 0.41), Color(0.86, 0.80, 0.67), 3.0)
		"tile":
			return _surface(Color(0.48, 0.23, 0.17), Color(0.30, 0.14, 0.11), Color(0.58, 0.31, 0.21), 5.0)
		"tile_grey":
			return _surface(Color(0.34, 0.33, 0.37), Color(0.21, 0.20, 0.24), Color(0.44, 0.43, 0.47), 5.0)
		"thatch":
			return _surface(Color(0.60, 0.47, 0.24), Color(0.40, 0.30, 0.15), Color(0.70, 0.56, 0.31), 4.4)
		"timber":
			return _surface(Color(0.31, 0.21, 0.14), Color(0.19, 0.13, 0.09), Color(0.39, 0.27, 0.18), 4.0)
		"grass":
			return _surface(Color(0.25, 0.36, 0.16), Color(0.16, 0.25, 0.10), Color(0.33, 0.45, 0.20), 1.1)
		"grass_pale":
			return _surface(Color(0.35, 0.43, 0.20), Color(0.23, 0.30, 0.13), Color(0.45, 0.52, 0.25), 1.1)
		"leaf":
			return _surface(Color(0.21, 0.34, 0.15), Color(0.12, 0.21, 0.09), Color(0.30, 0.43, 0.19), 3.2)
		"leaf_warm":
			return _surface(Color(0.32, 0.35, 0.14), Color(0.19, 0.22, 0.09), Color(0.43, 0.44, 0.19), 3.2)
		"crop":
			return _surface(Color(0.66, 0.58, 0.24), Color(0.45, 0.39, 0.15), Color(0.77, 0.69, 0.32), 4.0)
		"canvas":
			return _surface(Color(0.72, 0.64, 0.50), Color(0.51, 0.45, 0.35), Color(0.80, 0.72, 0.57), 3.6)
		"canvas_red":
			return _surface(Color(0.58, 0.30, 0.26), Color(0.38, 0.19, 0.17), Color(0.68, 0.38, 0.32), 3.6)
		"cloth":
			return _surface(Color(0.47, 0.27, 0.21), Color(0.30, 0.17, 0.13), Color(0.57, 0.35, 0.26), 6.0)
		"cloth_blue":
			return _surface(Color(0.25, 0.30, 0.48), Color(0.15, 0.19, 0.31), Color(0.33, 0.39, 0.60), 6.0)
		"iron":
			return PixelDioramaStyle.make_metal_material(Color(0.40, 0.42, 0.46), 0.40)
		"skin":
			return _surface(Color(0.74, 0.56, 0.42), Color(0.54, 0.39, 0.29), Color(0.82, 0.64, 0.49), 6.0)
		"pelt":
			return _surface(Color(0.39, 0.28, 0.18), Color(0.25, 0.18, 0.12), Color(0.49, 0.36, 0.23), 6.0)
		"dirt":
			return _surface(Color(0.44, 0.36, 0.26), Color(0.30, 0.24, 0.17), Color(0.53, 0.44, 0.32), 1.8)
		"cobble":
			return _surface(Color(0.46, 0.44, 0.42), Color(0.31, 0.30, 0.29), Color(0.55, 0.53, 0.50), 3.4)
		# The mountains are kilometres off, so they are painted the way distance paints
		# them: desaturated toward the sky and with a very coarse cell, because a metre
		# of pixel detail on something 2.4km away is a metre nobody can resolve.
		"rock_far":
			return _surface(Color(0.33, 0.36, 0.44), Color(0.22, 0.25, 0.32), Color(0.40, 0.43, 0.51), 0.18)
		"rock_pale":
			return _surface(Color(0.44, 0.46, 0.52), Color(0.31, 0.33, 0.39), Color(0.52, 0.54, 0.59), 0.18)
		"snow":
			return _surface(Color(0.84, 0.87, 0.93), Color(0.64, 0.69, 0.79), Color(0.93, 0.95, 0.99), 0.18)
	return _mat("stone")


func _add_roof(
	batch: PixelBoxBatch,
	at: Vector3,
	half_w: float,
	half_d: float,
	peak: float,
	facing: Basis,
	roof: Material,
	gable: Material,
	timber: Material,
	gable_ends: int = 0
) -> float:
	var eave := 0.35
	var slope_len := sqrt(half_w * half_w + peak * peak)
	var slope_angle := atan2(peak, half_w)
	for sx in [-1.0, 1.0]:
		var panel := facing * Basis(Vector3.BACK, -sx * slope_angle)
		batch.add(
			Vector3(slope_len + eave, 0.22, half_d * 2.0 + eave * 2.0),
			at + facing * Vector3(sx * half_w * 0.5, peak * 0.5, 0.0),
			roof,
			panel
		)
		batch.add(
			Vector3(slope_len + eave, 0.16, 0.2),
			at + facing * Vector3(sx * half_w * 0.5, peak * 0.5, 0.0)
			+ panel * Vector3(0.0, -0.12, half_d + eave),
			timber,
			panel
		)
		batch.add(
			Vector3(slope_len + eave, 0.16, 0.2),
			at + facing * Vector3(sx * half_w * 0.5, peak * 0.5, 0.0)
			+ panel * Vector3(0.0, -0.12, -(half_d + eave)),
			timber,
			panel
		)
	batch.add(
		Vector3(0.3, 0.26, half_d * 2.0 + eave * 2.0),
		at + facing * Vector3(0.0, peak, 0.0),
		timber,
		facing
	)
	var steps := 6
	var seg_h := peak / float(steps)
	var sides: Array = [-1.0, 1.0]
	if gable_ends == 2:
		sides = []
	elif gable_ends < 0:
		sides = [-1.0]
	elif gable_ends > 0:
		sides = [1.0]
	for end_side in sides:
		for i in steps:
			var t := float(i) / float(steps)
			var seg_w := half_w * 2.0 * (1.0 - t) * 0.97
			if seg_w <= 0.06:
				continue
			batch.add(
				Vector3(seg_w, seg_h * 1.04, 0.3),
				at + facing * Vector3(0.0, seg_h * (float(i) + 0.5), end_side * half_d),
				gable,
				facing
			)
	return at.y + peak


func build(horizon_tint: Color) -> void:
	if get_child_count() > 0:
		return
	var rng := RandomNumberGenerator.new()
	rng.seed = 20259

	var plan := VillagePlan.new()
	plan.generate(TOWN_SEED)

	_build_ground()
	_build_fields(rng, plan)
	_build_roads(plan)
	_build_town(plan)
	_build_mountains(rng)
	_build_horizon(rng)
	_build_smoke(rng, horizon_tint)
	_build_walkers(rng, plan)


func _build_ground() -> void:
	var grass := _mat("grass")
	var plate := MeshInstance3D.new()
	plate.name = "Plain"
	plate.mesh = _annulus(LEVEL_CLEARANCE, GROUND_RADIUS)
	plate.material_override = grass
	plate.position = Vector3(0.0, GROUND_DROP, 0.0)
	plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(plate)

	var rock := _mat("stone")
	var shaft := MeshInstance3D.new()
	shaft.name = "TowerShaft"
	var cliff := CylinderMesh.new()
	cliff.top_radius = LEVEL_CLEARANCE
	cliff.bottom_radius = LEVEL_CLEARANCE * 1.18
	cliff.height = absf(GROUND_DROP) + 4.0
	cliff.radial_segments = 40
	cliff.cap_top = false
	cliff.cap_bottom = false
	shaft.mesh = cliff
	shaft.material_override = rock
	shaft.position = Vector3(0.0, GROUND_DROP * 0.5 - 2.0, 0.0)
	shaft.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(shaft)

	var hedge := _mat("leaf")
	var batch := PixelBoxBatch.new()
	var hedge_rng := RandomNumberGenerator.new()
	hedge_rng.seed = 4471
	for i in 34:
		var angle := TAU * hedge_rng.randf()
		var dist := hedge_rng.randf_range(FIELD_INNER, GROUND_RADIUS * 0.72)
		var length := hedge_rng.randf_range(14.0, 44.0)
		var yaw := hedge_rng.randf() * TAU
		batch.add(
			Vector3(length, 1.4, 1.1),
			Vector3(cos(angle) * dist, GROUND_DROP + 0.7, sin(angle) * dist),
			hedge,
			Basis(Vector3.UP, yaw)
		)
	_no_shadows(batch.commit(
		self,
		"Hedgerows",
		AABB(
			Vector3(-GROUND_RADIUS, GROUND_DROP - 4.0, -GROUND_RADIUS),
			Vector3(GROUND_RADIUS * 2.0, 12.0, GROUND_RADIUS * 2.0)
		)
	))


static func _no_shadows(root: Node3D) -> Node3D:
	for child in root.get_children():
		var gi := child as GeometryInstance3D
		if gi:
			gi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return root


static func _annulus(inner: float, outer: float, segments: int = 64) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var indices := PackedInt32Array()
	for i in segments + 1:
		var a := TAU * float(i) / float(segments)
		var dir := Vector3(cos(a), 0.0, sin(a))
		verts.append(dir * inner)
		verts.append(dir * outer)
		normals.append(Vector3.UP)
		normals.append(Vector3.UP)
	for i in segments:
		var base := i * 2
		indices.append_array([base, base + 1, base + 3, base, base + 3, base + 2])
	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Ground cover: grass, trees, hedgerows and the cultivated strips. Everything here is
## checked against the town plan before it is drawn -- the scatter with `is_clear`, the
## bigger pieces by claiming their ground with `try_reserve` -- so nothing in this pass
## can land on a carriageway or inside a building. The crop strips are not scattered at
## all: they are the plots the plan already reserved for them.
func _build_fields(rng: RandomNumberGenerator, plan: VillagePlan) -> void:
	var greens: Array[Material] = [_mat("grass"), _mat("grass_pale"), _mat("leaf"), _mat("leaf_warm")]
	var batch := PixelBoxBatch.new()

	for i in GRASS_CLUMPS:
		var angle := rng.randf() * TAU
		var t := sqrt(rng.randf())
		var dist := lerpf(FIELD_INNER, FIELD_OUTER, t)
		var w := rng.randf_range(0.7, 2.1)
		var h := rng.randf_range(0.35, 1.1)
		var spot := Vector2(cos(angle) * dist, sin(angle) * dist)
		# Tufts are only a metre across, but a tuft growing through cobbles is exactly
		# the sort of thing the eye picks out, so they get the same test as everything else.
		if not plan.is_clear(spot, angle, Vector2(w + 0.6, w + 0.6)):
			continue
		batch.add(
			Vector3(w, h, w * rng.randf_range(0.7, 1.3)),
			Vector3(spot.x, GROUND_DROP + h * 0.5, spot.y),
			greens[rng.randi() % greens.size()],
			Basis(Vector3.UP, rng.randf() * TAU)
		)

	var bark := _mat("timber")
	for i in TREE_COUNT:
		var angle := rng.randf() * TAU
		var dist := lerpf(FIELD_INNER + 6.0, FIELD_OUTER, sqrt(rng.randf()))
		var spot := Vector2(cos(angle) * dist, sin(angle) * dist)
		var crown := rng.randf_range(3.0, 5.2)
		# A tree owns its ground: claiming it stops a crop strip being sown in its shade.
		if not plan.try_reserve(spot, 0.0, Vector2(crown, crown), "tree"):
			continue
		var at := Vector3(spot.x, GROUND_DROP, spot.y)
		var trunk_h := rng.randf_range(2.4, 4.6)
		var leaf: Material = greens[rng.randi() % greens.size()]
		batch.add(Vector3(0.7, trunk_h, 0.7), at + Vector3(0.0, trunk_h * 0.5, 0.0), bark)
		batch.add(
			Vector3(crown, crown * 0.7, crown), at + Vector3(0.0, trunk_h + crown * 0.3, 0.0), leaf
		)
		batch.add(
			Vector3(crown * 0.65, crown * 0.5, crown * 0.65),
			at + Vector3(0.0, trunk_h + crown * 0.78, 0.0),
			leaf
		)

	var rail := _mat("timber")
	for i in FENCE_RUNS:
		var angle := rng.randf() * TAU
		var dist := rng.randf_range(FIELD_INNER + 4.0, FIELD_OUTER - 4.0)
		var spot := Vector2(cos(angle) * dist, sin(angle) * dist)
		var posts := rng.randi_range(5, 11)
		var pitch := 1.8
		var run := float(posts) * pitch
		var yaw := -angle + rng.randf_range(-0.4, 0.4)
		# The plan works in XZ where +angle turns the other way from Godot's Y rotation,
		# so the bearing is negated on the way back out to the planner.
		if not plan.try_reserve(spot, -yaw, Vector2(run, 1.4), "fence"):
			continue
		var at := Vector3(spot.x, GROUND_DROP, spot.y)
		var facing := Basis(Vector3.UP, yaw)
		for post in posts:
			var along := (float(post) - float(posts) * 0.5) * pitch
			batch.add(
				Vector3(0.16, 1.1, 0.16),
				at + facing * Vector3(along, 0.55, 0.0),
				rail,
				facing
			)
		batch.add(
			Vector3(run, 0.12, 0.1),
			at + Vector3(0.0, 0.85, 0.0),
			rail,
			facing
		)

	_build_cultivation(rng, plan, batch)

	var stone := _mat("stone")
	var timber := _mat("timber")
	var thatch := _mat("thatch")
	for i in 3:
		var angle := TAU * (float(i) + 0.4) / 3.0
		var dist := rng.randf_range(FIELD_INNER + 8.0, FIELD_OUTER - 8.0)
		var spot := Vector2(cos(angle) * dist, sin(angle) * dist)
		if not plan.try_reserve(spot, 0.0, Vector2(3.2, 3.2), "well"):
			continue
		var at := Vector3(spot.x, GROUND_DROP, spot.y)
		var facing := Basis(Vector3.UP, rng.randf() * TAU)
		for side in [Vector3(1, 0, 0), Vector3(-1, 0, 0), Vector3(0, 0, 1), Vector3(0, 0, -1)]:
			var along := Vector3(side.z, 0.0, side.x)
			batch.add(
				Vector3(1.6, 0.85, 0.3) if absf(side.x) > 0.5 else Vector3(0.3, 0.85, 1.6),
				at + Vector3(0.0, 0.43, 0.0) + facing * (side * 0.72 + along * 0.0),
				stone,
				facing
			)
		for post in [-1.0, 1.0]:
			batch.add(
				Vector3(0.22, 2.1, 0.22),
				at + Vector3(0.0, 1.05, 0.0) + facing * Vector3(post * 0.75, 0.0, 0.0),
				timber,
				facing
			)
		batch.add(Vector3(2.2, 0.25, 2.0), at + Vector3(0.0, 2.2, 0.0), thatch, facing)

	_no_shadows(batch.commit(
		self,
		"Fields",
		AABB(
			Vector3(-VILLAGE_EXTENT, GROUND_DROP - 4.0, -VILLAGE_EXTENT),
			Vector3(VILLAGE_EXTENT * 2.0, 24.0, VILLAGE_EXTENT * 2.0)
		)
	))


## Draw the strips the plan set aside for cultivation. Each one fills its own reserved
## footprint exactly -- the furrows are laid out across `size.y` and stop at its edge --
## so what is drawn is the ground that was checked, not an approximation of it.
func _build_cultivation(
	rng: RandomNumberGenerator, plan: VillagePlan, batch: PixelBoxBatch
) -> void:
	var crop := _mat("crop")
	var greens: Array[Material] = [_mat("grass"), _mat("grass_pale")]
	var leaf: Array[Material] = [_mat("leaf"), _mat("leaf_warm")]
	var bark := _mat("timber")
	for field in plan.fields:
		var centre: Vector2 = field["c"]
		var size: Vector2 = field["size"]
		var kind: String = field["kind"]
		var at := Vector3(centre.x, GROUND_DROP, centre.y)
		var facing := Basis(Vector3.UP, -(field["yaw"] as float))
		match kind:
			"crop":
				# Whole furrows only, so the last one lands inside the plot rather than
				# hanging over the headland.
				var pitch := 1.35
				var rows := maxi(2, int(size.y / pitch))
				for row in rows:
					var across := (float(row) - float(rows - 1) * 0.5) * pitch
					batch.add(
						Vector3(size.x * 0.94, rng.randf_range(0.6, 0.85), 0.55),
						at + facing * Vector3(0.0, 0.38, across),
						crop,
						facing
					)
			"orchard":
				var cols := maxi(2, int(size.x / 4.2))
				var lines := maxi(2, int(size.y / 4.2))
				for cx in cols:
					for cz in lines:
						var lx := (float(cx) - float(cols - 1) * 0.5) * (size.x / float(cols))
						var lz := (float(cz) - float(lines - 1) * 0.5) * (size.y / float(lines))
						var base := at + facing * Vector3(lx, 0.0, lz)
						var crown := rng.randf_range(2.0, 3.0)
						batch.add(Vector3(0.5, 2.0, 0.5), base + Vector3(0.0, 1.0, 0.0), bark)
						batch.add(
							Vector3(crown, crown * 0.8, crown),
							base + Vector3(0.0, 2.0 + crown * 0.35, 0.0),
							leaf[rng.randi() % leaf.size()]
						)
			_:
				# Paddock: grazing inside a post-and-rail fence.
				batch.add(
					Vector3(size.x * 0.92, 0.22, size.y * 0.92),
					at + Vector3(0.0, 0.11, 0.0),
					greens[rng.randi() % greens.size()],
					facing
				)
				for side in [-1.0, 1.0]:
					var posts := maxi(2, int(size.x / 2.0))
					for post in posts:
						var along := (float(post) - float(posts - 1) * 0.5) * (size.x / float(posts))
						batch.add(
							Vector3(0.16, 1.05, 0.16),
							at + facing * Vector3(along, 0.52, side * size.y * 0.46),
							bark,
							facing
						)
					batch.add(
						Vector3(size.x * 0.94, 0.12, 0.1),
						at + facing * Vector3(0.0, 0.82, side * size.y * 0.46),
						bark,
						facing
					)


## Lay the streets down as flat ribbons of dirt or cobble. These are the same
## polylines the plan used to seat every building and the same ones the crowd walks,
## so what you see is genuinely the street the villagers are on.
## Which layer a street rank is drawn on, lowest first. The stone high street is the
## bottom layer: where a dirt lane crosses it, the mud is what you see.
static func _road_layer(rank: int) -> float:
	match rank:
		0:
			return 0.0
		2:
			return 1.0
	return 2.0


func _build_roads(plan: VillagePlan) -> void:
	var batch := PixelBoxBatch.new()
	# Ribbons that share a height fight for the same pixels wherever two streets cross,
	# which is what made the junctions flicker and tear. Each street is given its own
	# layer instead -- dirt over stone, and every street within a rank on its own sliver
	# -- so a crossing resolves as one surface lying over another: the mud of a lane
	# runs across the cobbles, the way an unmetalled road actually crosses a paved one.
	#
	# The layers are only centimetres apart, but the slabs are deep. That is deliberate:
	# a slab's *top* is its layer height and the rest of it hangs below ground, so the
	# lower road at a crossing sits wholly inside the upper one rather than poking a
	# corner up through its surface. Thin slabs on stepped heights would intersect.
	var rank_index: Dictionary = {}
	for road in plan.roads:
		var points: PackedVector2Array = road["points"]
		var width: float = road["width"]
		var rank: int = road["rank"]
		var nth: int = int(rank_index.get(rank, 0))
		rank_index[rank] = nth + 1
		var y := GROUND_DROP + ROAD_TOP + _road_layer(rank) * 0.05 + float(nth) * 0.006
		y -= ROAD_SLAB * 0.5
		# The high street through the middle of town is metalled; the rest is mud.
		var surface: Material = _mat("cobble") if rank == 0 else _mat("dirt")
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var span := b - a
			var length := span.length()
			if length <= 0.01:
				continue
			var mid := (a + b) * 0.5
			# Segments meet end to end rather than overlapping: two co-planar boxes of
			# the same street would z-fight each other exactly as two streets did.
			batch.add(
				Vector3(length, ROAD_SLAB, width),
				Vector3(mid.x, y, mid.y),
				surface,
				Basis(Vector3.UP, -atan2(span.y, span.x))
			)
			# The corner left by the turn is filled by a patch at the joint, set a hair
			# lower so it hides under the segments instead of arguing with them.
			if i + 2 < points.size():
				var next := points[i + 2] - b
				if next.length() > 0.01:
					var bearing := (span.normalized() + next.normalized())
					if bearing.length() > 0.001:
						batch.add(
							Vector3(width, ROAD_SLAB, width),
							Vector3(b.x, y - 0.004, b.y),
							surface,
							Basis(Vector3.UP, -atan2(bearing.y, bearing.x))
						)
	_no_shadows(batch.commit(
		self,
		"Streets",
		AABB(
			Vector3(-VILLAGE_EXTENT, GROUND_DROP - 2.0, -VILLAGE_EXTENT),
			Vector3(VILLAGE_EXTENT * 2.0, 8.0, VILLAGE_EXTENT * 2.0)
		)
	))


## Turn the plan into geometry. Each plot is built inside its own planned footprint --
## nothing here invents a size of its own -- which is what carries the planner's
## no-overlap guarantee through to what actually gets drawn.
func _build_town(plan: VillagePlan) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED ^ 0x5f3a
	# One batch per detail tier, so a near building and a far silhouette never share a
	# draw call and the far ones can be culled as a group.
	var near_batch := PixelBoxBatch.new()
	var far_batch := PixelBoxBatch.new()

	for plot in plan.plots:
		var centre_2d: Vector2 = plot["c"]
		var size: Vector2 = plot["size"]
		var band: int = plot["band"]
		var kind: String = plot["kind"]
		var face: Vector2 = plot["face"]
		var origin := Vector3(centre_2d.x, GROUND_DROP, centre_2d.y)
		# The plan works in XZ where +angle turns one way; Godot's Y rotation turns the
		# other, so every planned bearing is negated on the way in.
		var world_yaw := -(plot["yaw"] as float)
		var front_yaw := -atan2(face.y, face.x)
		var batch: PixelBoxBatch = far_batch if band >= SIMPLE_BAND else near_batch

		match kind:
			# Landmarks take the plot's own bearing, not the street-facing one. Their long
			# axis is their local X, which is the axis the plan reserved -- pointing them
			# at the street instead ran the church's nave across the ring gap and through
			# the carriageways on both sides of it.
			"church":
				_add_church(batch, rng, origin, world_yaw, 1.15)
			"castle":
				_add_castle(batch, rng, origin, world_yaw, 1.0)
			"windmill":
				_add_windmill(batch, origin, world_yaw, 1.0)
			_:
				if band >= SILHOUETTE_BAND:
					_add_silhouette(batch, rng, origin, world_yaw, size)
				else:
					_add_terrace(batch, rng, origin, world_yaw, front_yaw, size, band, kind)

	if not plan.plaza.is_empty():
		var plaza_c: Vector2 = plan.plaza["c"]
		_add_market(
			near_batch,
			rng,
			Vector3(plaza_c.x, GROUND_DROP, plaza_c.y),
			-(plan.plaza["yaw"] as float)
		)

	var near_aabb := AABB(
		Vector3(-VILLAGE_EXTENT, GROUND_DROP - 4.0, -VILLAGE_EXTENT),
		Vector3(VILLAGE_EXTENT * 2.0, 90.0, VILLAGE_EXTENT * 2.0)
	)
	_no_shadows(near_batch.commit(self, "TownNear", near_aabb))
	_no_shadows(far_batch.commit(self, "TownFar", near_aabb))


## A terrace of houses filling exactly the planned frontage. The run is split into
## whole units across `size.x`, so the block ends where the plot ends rather than
## wherever the last random width happened to land.
func _add_terrace(
	batch: PixelBoxBatch,
	rng: RandomNumberGenerator,
	centre: Vector3,
	yaw: float,
	front_yaw: float,
	size: Vector2,
	band: int,
	kind: String
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var front := Basis(Vector3.UP, front_yaw)
	var timber := _mat("timber")
	var footing := _mat("stone")
	var simple := band >= SIMPLE_BAND

	# Town centre builds upward; the outskirts sprawl low and thatched.
	var storeys := 2 if band == 0 and rng.randf() < 0.72 else 1
	var eave := (3.2 + 2.4 * float(storeys)) * rng.randf_range(0.92, 1.08)
	if kind == "barn":
		eave = rng.randf_range(4.6, 5.8)
	var depth: float = size.y
	var peak := depth * rng.randf_range(0.4, 0.54)

	# Roofing and walling are chosen once for the whole block. Rolling them per unit
	# made a single terrace come out half red and half slate, which reads as noise
	# rather than as a row of houses.
	var roof_roll := rng.randf()
	var block_roof: Material
	if band <= 1:
		block_roof = _mat("tile") if roof_roll < 0.62 else _mat("tile_grey")
	else:
		block_roof = _mat("thatch") if roof_roll < 0.72 else _mat("tile")
	var block_wall: Material = _mat("daub") if rng.randf() < 0.74 else _mat("stone")

	var unit_target := 6.4 if kind == "terrace" else 8.2
	var run: int = clampi(int(round(size.x / unit_target)), 1, 6)
	var unit: float = size.x / float(run)
	var half_d := depth * 0.5
	var offset := -size.x * 0.5

	for i in run:
		var at: Vector3 = centre + facing * Vector3(offset + unit * 0.5, 0.0, 0.0)
		var half_w := unit * 0.5
		# One house in a row is occasionally re-roofed or re-fronted; most are not.
		var roof_mat: Material = block_roof
		var wall_mat: Material = block_wall
		if rng.randf() < 0.16:
			wall_mat = _mat("stone") if block_wall == _mat("daub") else _mat("daub")

		batch.add(
			Vector3(unit, 0.6, depth + 0.3),
			at + Vector3(0.0, 0.3, 0.0),
			footing,
			facing
		)
		batch.add(
			Vector3(unit - 0.18, eave, depth - 0.18),
			at + Vector3(0.0, eave * 0.5, 0.0),
			wall_mat,
			facing
		)
		if not simple:
			# Exposed frame: a sill band and the corner posts.
			batch.add(
				Vector3(unit, 0.24, depth + 0.12),
				at + Vector3(0.0, eave - 0.12, 0.0),
				timber,
				facing
			)
			if storeys == 2:
				batch.add(
					Vector3(unit + 0.16, 0.22, depth + 0.2),
					at + Vector3(0.0, eave * 0.52, 0.0),
					timber,
					facing
				)
			for px in [-1.0, 1.0]:
				for pz in [-1.0, 1.0]:
					batch.add(
						Vector3(0.26, eave, 0.26),
						at + Vector3(0.0, eave * 0.5, 0.0)
						+ facing * Vector3(px * (half_w - 0.13), 0.0, pz * (half_d - 0.13)),
						timber,
						facing
					)

		var ends := 2
		if run == 1:
			ends = 0
		elif i == 0:
			ends = -1
		elif i == run - 1:
			ends = 1
		var ridge := _add_roof(
			batch,
			at + Vector3(0.0, eave, 0.0),
			half_d,
			half_w,
			peak,
			facing * Basis(Vector3.UP, PI * 0.5),
			roof_mat,
			wall_mat,
			timber,
			ends
		)

		if not simple and rng.randf() < 0.75:
			var stack := peak + 1.5
			batch.add(
				Vector3(0.8, stack, 0.8),
				at + Vector3(0.0, ridge - peak + stack * 0.5, 0.0)
				+ facing * Vector3(half_w * 0.55, 0.0, 0.0),
				footing,
				facing
			)

		# Windows go on the street-facing wall, which is the whole point of fronting a road.
		var lights := 1 if simple else rng.randi_range(2, 3)
		for pane in lights:
			if rng.randf() < 0.3:
				continue
			var storey_h := eave * (0.32 if (storeys == 1 or rng.randf() < 0.5) else 0.68)
			_add_window(
				batch,
				at + Vector3(0.0, storey_h, 0.0)
				+ front * Vector3(
					(float(pane) - float(lights - 1) * 0.5) * unit * 0.4, 0.0, half_d
				),
				1.0,
				front,
				rng
			)
		offset += unit


## The far bands, where a building is only ever a shape against the sky. Four boxes
## and a roof -- no windows, no frame, no chimney -- because none of it resolves at
## this range and all of it would cost the same as the town centre.
func _add_silhouette(
	batch: PixelBoxBatch,
	rng: RandomNumberGenerator,
	centre: Vector3,
	yaw: float,
	size: Vector2
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var wall: Material = _mat("daub") if rng.randf() < 0.5 else _mat("stone")
	var roof: Material = _mat("thatch") if rng.randf() < 0.6 else _mat("tile_grey")
	# Taller than a near cottage on purpose: at this distance a squat box disappears
	# into the ground haze instead of reading as a roofline.
	var eave := rng.randf_range(4.6, 6.8)
	var peak := size.y * rng.randf_range(0.42, 0.58)
	batch.add(
		Vector3(size.x, eave, size.y),
		centre + Vector3(0.0, eave * 0.5, 0.0),
		wall,
		facing
	)
	_add_roof(
		batch,
		centre + Vector3(0.0, eave, 0.0),
		size.y * 0.5,
		size.x * 0.5,
		peak,
		facing * Basis(Vector3.UP, PI * 0.5),
		roof,
		wall,
		wall,
		0
	)


func _add_window(
	batch: PixelBoxBatch,
	at: Vector3,
	size_scale: float,
	facing: Basis,
	rng: RandomNumberGenerator
) -> void:
	batch.add(
		Vector3(
			rng.randf_range(0.6, 0.85) * size_scale, rng.randf_range(0.7, 0.95) * size_scale, 0.16
		),
		at,
		_window_mat(),
		facing
	)


func _add_castle(
	batch: PixelBoxBatch,
	rng: RandomNumberGenerator,
	origin: Vector3,
	yaw: float,
	size_scale: float
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var stone := _mat("stone_dark")
	var trim := _mat("stone")
	var roof := _mat("tile_grey")
	var bailey := 20.0 * size_scale
	var wall_h := 6.5 * size_scale
	for side in [Vector3(0, 0, 1), Vector3(0, 0, -1), Vector3(1, 0, 0), Vector3(-1, 0, 0)]:
		batch.add(
			Vector3(bailey, wall_h, 1.8 * size_scale) if absf(side.z) > 0.5
			else Vector3(1.8 * size_scale, wall_h, bailey),
			origin + Vector3(0.0, wall_h * 0.5, 0.0) + facing * (side * bailey * 0.5),
			stone,
			facing
		)
	for corner in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		var t_h := wall_h * 1.7
		var at: Vector3 = origin + facing * (corner * bailey * 0.5)
		batch.add(
			Vector3(4.4 * size_scale, t_h, 4.4 * size_scale),
			at + Vector3(0.0, t_h * 0.5, 0.0),
			stone,
			facing
		)
		batch.add(
			Vector3(5.0 * size_scale, 0.5 * size_scale, 5.0 * size_scale),
			at + Vector3(0.0, t_h + 0.25 * size_scale, 0.0),
			trim,
			facing
		)
		_add_roof(
			batch, at + Vector3(0.0, t_h + 0.5 * size_scale, 0.0),
			2.0 * size_scale, 2.0 * size_scale, 5.0 * size_scale, facing, roof, stone, trim, 2
		)
	var keep_w := 11.0 * size_scale
	var keep_h := rng.randf_range(20.0, 28.0) * size_scale
	batch.add(
		Vector3(keep_w + 2.0, 2.4 * size_scale, keep_w + 2.0),
		origin + Vector3(0.0, 1.2 * size_scale, 0.0),
		trim,
		facing
	)
	batch.add(Vector3(keep_w, keep_h, keep_w), origin + Vector3(0.0, keep_h * 0.5, 0.0), stone, facing)
	for storey in 3:
		var y := keep_h * (0.3 + float(storey) * 0.22)
		batch.add(
			Vector3(keep_w + 0.6, 0.4 * size_scale, keep_w + 0.6),
			origin + Vector3(0.0, y, 0.0),
			trim,
			facing
		)
		for pane in 2:
			batch.add(
				Vector3(0.9 * size_scale, 1.8 * size_scale, 0.16),
				origin + Vector3(0.0, y + 2.2 * size_scale, 0.0)
				+ facing * Vector3((float(pane) - 0.5) * keep_w * 0.44, 0.0, keep_w * 0.52),
				_window_mat(),
				facing
			)
	batch.add(
		Vector3(keep_w + 1.6, 1.0 * size_scale, keep_w + 1.6),
		origin + Vector3(0.0, keep_h + 0.5 * size_scale, 0.0),
		trim,
		facing
	)
	for corner in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		var turret_h := 5.0 * size_scale
		var at: Vector3 = origin + facing * (corner * keep_w * 0.44)
		batch.add(
			Vector3(2.6 * size_scale, turret_h, 2.6 * size_scale),
			at + Vector3(0.0, keep_h + 1.0 * size_scale + turret_h * 0.5, 0.0),
			stone,
			facing
		)
		_add_roof(
			batch, at + Vector3(0.0, keep_h + 1.0 * size_scale + turret_h, 0.0),
			1.2 * size_scale, 1.2 * size_scale, 3.4 * size_scale, facing, roof, stone, trim, 2
		)
	var hall_at: Vector3 = origin + facing * Vector3(0.0, 0.0, -bailey * 0.28)
	batch.add(
		Vector3(bailey * 0.7, wall_h * 1.3, 7.0 * size_scale),
		hall_at + Vector3(0.0, wall_h * 0.65, 0.0),
		trim,
		facing
	)
	_add_roof(
		batch, hall_at + Vector3(0.0, wall_h * 1.3, 0.0),
		3.5 * size_scale, bailey * 0.35, 4.0 * size_scale, facing, roof, trim, _mat("timber")
	)


func _add_church(
	batch: PixelBoxBatch,
	rng: RandomNumberGenerator,
	origin: Vector3,
	yaw: float,
	size_scale: float
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var stone := _mat("stone")
	var roof := _mat("tile_grey")
	var nave_w := 8.0 * size_scale
	var nave_l := 20.0 * size_scale
	var nave_h := 9.0 * size_scale
	batch.add(Vector3(nave_l, 1.0, nave_w + 1.0), origin + Vector3(0.0, 0.5, 0.0), stone, facing)
	batch.add(Vector3(nave_l, nave_h, nave_w), origin + Vector3(0.0, nave_h * 0.5, 0.0), stone, facing)
	_add_roof(batch, origin + Vector3(0.0, nave_h, 0.0), nave_w * 0.5, nave_l * 0.5, nave_w * 0.45, facing, roof, stone, _mat("timber"))
	for side in [-1.0, 1.0]:
		var aisle_h := nave_h * 0.55
		var at: Vector3 = origin + facing * Vector3(0.0, 0.0, side * (nave_w * 0.5 + 2.0 * size_scale))
		batch.add(
			Vector3(nave_l * 0.86, aisle_h, 4.0 * size_scale),
			at + Vector3(0.0, aisle_h * 0.5, 0.0),
			stone,
			facing
		)
		_add_roof(
			batch, at + Vector3(0.0, aisle_h, 0.0), 2.0 * size_scale, nave_l * 0.43,
			1.5 * size_scale, facing, roof, stone, _mat("timber")
		)
	var bays := 5
	for bay in bays:
		var t := (float(bay) + 0.5) / float(bays) - 0.5
		for side in [-1.0, 1.0]:
			batch.add(
				Vector3(1.0 * size_scale, nave_h * 0.8, 1.4 * size_scale),
				origin + Vector3(0.0, nave_h * 0.4, 0.0)
				+ facing * Vector3(t * nave_l, 0.0, side * (nave_w * 0.5 + 4.4 * size_scale)),
				stone,
				facing
			)
	var tower_w := 6.5 * size_scale
	var tower_h := nave_h * 2.1
	var tower_at: Vector3 = origin + facing * Vector3(-nave_l * 0.5 - tower_w * 0.4, 0.0, 0.0)
	batch.add(
		Vector3(tower_w, tower_h, tower_w), tower_at + Vector3(0.0, tower_h * 0.5, 0.0), stone, facing
	)
	for side in [-1.0, 1.0]:
		batch.add(
			Vector3(1.6 * size_scale, 3.0 * size_scale, 0.2),
			tower_at + Vector3(0.0, tower_h * 0.82, 0.0)
			+ facing * Vector3(side * tower_w * 0.5, 0.0, 0.0),
			_mat("stone_dark"),
			facing
		)
	batch.add(
		Vector3(tower_w + 1.0, 0.7 * size_scale, tower_w + 1.0),
		tower_at + Vector3(0.0, tower_h + 0.35 * size_scale, 0.0),
		stone,
		facing
	)
	for corner in [Vector3(1, 0, 1), Vector3(1, 0, -1), Vector3(-1, 0, 1), Vector3(-1, 0, -1)]:
		batch.add(
			Vector3(1.0 * size_scale, 1.6 * size_scale, 1.0 * size_scale),
			tower_at + Vector3(0.0, tower_h + 1.4 * size_scale, 0.0)
			+ facing * (corner * tower_w * 0.42),
			stone,
			facing
		)
	var spire_h := tower_h * 0.75
	var steps := 8
	for i in steps:
		var t := float(i) / float(steps)
		batch.add(
			Vector3(tower_w * (1.0 - t * 0.92), spire_h / float(steps) * 1.05, tower_w * (1.0 - t * 0.92)),
			tower_at + Vector3(0.0, tower_h + 1.0 * size_scale + spire_h * (t + 0.5 / float(steps)), 0.0),
			roof,
			facing
		)
	if rng.randf() < 1.0:
		batch.add(
			Vector3(0.24, 1.6 * size_scale, 0.24),
			tower_at + Vector3(0.0, tower_h + spire_h + 2.0 * size_scale, 0.0),
			_mat("iron"),
			facing
		)


## The mountain range on the horizon line. Built as stepped voxel pyramids in the same
## idiom as everything else in the diorama, in three concentric ranges so the near
## peaks break the skyline of the far ones.
##
## The taper is concave (`pow(1 - t, 1.4)`) rather than linear: a straight-sided taper
## gives a spoil heap, and it is the steepening toward the summit that makes the shape
## read as a mountain at all from this far off.
func _build_mountains(rng: RandomNumberGenerator) -> void:
	var batch := PixelBoxBatch.new()
	var rock := _mat("rock_far")
	var scree := _mat("rock_pale")
	var snow := _mat("snow")
	var base_y := GROUND_DROP
	var reach := 0.0
	var tallest := 0.0
	for range_index in MOUNTAIN_RANGES:
		var depth := MOUNTAIN_RING * (1.0 + float(range_index) * 0.15)
		# Further back means taller, so the back ranges show over the front ones rather
		# than being hidden by them.
		var lift := 1.0 + float(range_index) * 0.3
		# And it means more peaks, because there is more horizon to fill at that radius.
		var peaks := MOUNTAIN_PEAKS + range_index * 6
		for i in peaks:
			var angle := TAU * (float(i) + rng.randf_range(-0.45, 0.45)) / float(peaks)
			var dist := depth * rng.randf_range(0.93, 1.09)
			var height := rng.randf_range(150.0, 300.0) * lift
			var width := height * rng.randf_range(1.4, 2.2)
			var at := Vector3(cos(angle) * dist, base_y, sin(angle) * dist)
			var facing := Basis(Vector3.UP, rng.randf() * TAU)
			# Only the higher peaks hold snow, and the line sits lower on the taller
			# ones -- the same rule the real thing follows.
			var snow_line := 1.2 if height < 250.0 else rng.randf_range(0.62, 0.8)
			# The summit is offset from the base so the peak is not dead centre, which
			# is what makes a stack of boxes read as a ridge rather than as a ziggurat.
			var drift := Vector3(rng.randf_range(-0.16, 0.16), 0.0, rng.randf_range(-0.12, 0.12))
			for step in MOUNTAIN_STEPS:
				var t := float(step) / float(MOUNTAIN_STEPS)
				var shrink := pow(1.0 - t, 1.4)
				var w := width * shrink
				if w < 4.0:
					continue
				var slab := height / float(MOUNTAIN_STEPS) * 1.06
				var y := base_y + height * (t + 0.5 / float(MOUNTAIN_STEPS))
				var surface := rock
				if t >= snow_line:
					surface = snow
				elif t >= snow_line - 0.14:
					surface = scree
				batch.add(
					Vector3(w, slab, w * 0.74),
					Vector3(at.x, y, at.z) + facing * (drift * width * t),
					surface,
					facing
				)
			reach = maxf(reach, dist + width)
			tallest = maxf(tallest, height)
	_no_shadows(batch.commit(
		self,
		"Mountains",
		AABB(
			Vector3(-reach, base_y - 10.0, -reach),
			Vector3(reach * 2.0, tallest + 40.0, reach * 2.0)
		)
	))


func _build_horizon(rng: RandomNumberGenerator) -> void:
	var batch := PixelBoxBatch.new()
	var stone := _mat("stone_dark")
	var roof := _mat("tile_grey")
	var top := GROUND_DROP
	for i in HORIZON_LANDMARKS:
		var angle := TAU * (float(i) + rng.randf_range(-0.4, 0.4)) / float(HORIZON_LANDMARKS)
		var dist := HORIZON_RING * rng.randf_range(0.8, 1.5)
		var at := Vector3(cos(angle) * dist, top, sin(angle) * dist)
		var facing := Basis(Vector3.UP, -angle)
		var scale_up := dist / HORIZON_RING
		match rng.randi() % 3:
			0:
				var w := rng.randf_range(50.0, 110.0) * scale_up
				var h := rng.randf_range(14.0, 26.0) * scale_up
				batch.add(Vector3(w, h, 22.0 * scale_up), at + Vector3(0.0, h * 0.5, 0.0), stone, facing)
				for t in rng.randi_range(1, 3):
					var th := h * rng.randf_range(1.1, 1.7)
					batch.add(
						Vector3(9.0 * scale_up, th, 9.0 * scale_up),
						at + Vector3(0.0, th * 0.5, 0.0)
						+ facing * Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.0, 0.0),
						stone,
						facing
					)
					batch.add(
						Vector3(11.0 * scale_up, 8.0 * scale_up, 11.0 * scale_up),
						at + Vector3(0.0, th + 4.0 * scale_up, 0.0)
						+ facing * Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.0, 0.0),
						roof,
						facing
					)
			1:
				var steps := rng.randi_range(3, 5)
				var base_w := rng.randf_range(60.0, 130.0) * scale_up
				var total := rng.randf_range(24.0, 50.0) * scale_up
				for step in steps:
					var t := float(step) / float(steps)
					batch.add(
						Vector3(base_w * (1.0 - t * 0.78), total / float(steps) * 1.04, base_w * 0.6 * (1.0 - t * 0.7)),
						at + Vector3(0.0, total * (t + 0.5 / float(steps)), 0.0)
						+ facing * Vector3(rng.randf_range(-6.0, 6.0) * scale_up, 0.0, 0.0),
						stone,
						facing
					)
			_:
				var h2 := rng.randf_range(18.0, 34.0) * scale_up
				batch.add(
					Vector3(12.0 * scale_up, h2, 12.0 * scale_up),
					at + Vector3(0.0, h2 * 0.5, 0.0), stone, facing
				)
				_add_roof(
					batch, at + Vector3(0.0, h2, 0.0), 6.0 * scale_up, 6.0 * scale_up,
					14.0 * scale_up, facing, roof, stone, stone
				)
	_no_shadows(batch.commit(
		self,
		"HorizonRing",
		AABB(
			Vector3(-HORIZON_RING * 2.0, GROUND_DROP - 10.0, -HORIZON_RING * 2.0),
			Vector3(HORIZON_RING * 4.0, 220.0, HORIZON_RING * 4.0)
		)
	))


func _add_market(
	batch: PixelBoxBatch, rng: RandomNumberGenerator, origin: Vector3, yaw: float
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var stone := _mat("stone")
	var timber := _mat("timber")
	batch.add(Vector3(7.0, 0.5, 7.0), origin + Vector3(0.0, 0.25, 0.0), stone, facing)
	batch.add(Vector3(5.6, 0.9, 5.6), origin + Vector3(0.0, 0.7, 0.0), stone, facing)
	batch.add(Vector3(4.2, 0.4, 4.2), origin + Vector3(0.0, 1.2, 0.0), _mat("stone_dark"), facing)
	batch.add(Vector3(1.2, 2.6, 1.2), origin + Vector3(0.0, 2.4, 0.0), stone, facing)
	batch.add(Vector3(2.2, 0.5, 2.2), origin + Vector3(0.0, 3.9, 0.0), stone, facing)
	for i in 6:
		var angle := TAU * float(i) / 6.0 + rng.randf_range(-0.2, 0.2)
		var dist := rng.randf_range(8.0, 11.0)
		var at: Vector3 = origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var tent_facing := Basis(Vector3.UP, -angle)
		var canvas: Material = _mat("canvas") if i % 2 == 0 else _mat("canvas_red")
		var w := rng.randf_range(3.6, 5.2)
		var d := rng.randf_range(3.2, 4.4)
		for cx in [-1.0, 1.0]:
			for cz in [-1.0, 1.0]:
				batch.add(
					Vector3(0.2, 2.4, 0.2),
					at + Vector3(0.0, 1.2, 0.0) + tent_facing * Vector3(cx * w * 0.5, 0.0, cz * d * 0.5),
					timber,
					tent_facing
				)
		batch.add(
			Vector3(w, 0.8, d * 0.4),
			at + Vector3(0.0, 0.9, 0.0) + tent_facing * Vector3(0.0, 0.0, d * 0.35),
			timber,
			tent_facing
		)
		_add_roof(batch, at + Vector3(0.0, 2.4, 0.0), w * 0.5, d * 0.5, d * 0.55, tent_facing, canvas, canvas, timber)
		for crate in rng.randi_range(1, 3):
			batch.add(
				Vector3(0.8, 0.8, 0.8),
				at + Vector3(0.0, 0.4, 0.0)
				+ tent_facing * Vector3(rng.randf_range(-w * 0.4, w * 0.4), 0.0, -d * 0.3),
				timber,
				tent_facing
			)


func _add_windmill(batch: PixelBoxBatch, origin: Vector3, yaw: float, size_scale: float) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var stone := _mat("stone")
	var timber := _mat("timber")
	var h := 11.0 * size_scale
	for i in 3:
		var t := float(i) / 3.0
		batch.add(
			Vector3(5.0 * size_scale * (1.0 - t * 0.3), h / 3.0 * 1.02, 5.0 * size_scale * (1.0 - t * 0.3)),
			origin + Vector3(0.0, h * (t + 1.0 / 6.0), 0.0),
			stone,
			facing
		)
	_add_roof(
		batch, origin + Vector3(0.0, h, 0.0), 2.0 * size_scale, 2.0 * size_scale,
		2.2 * size_scale, facing, _mat("thatch"), stone, timber
	)
	for i in 4:
		var sail := Basis(Vector3.UP, yaw) * Basis(Vector3.FORWARD, TAU * float(i) / 4.0 + 0.4)
		batch.add(
			Vector3(1.6 * size_scale, 9.0 * size_scale, 0.25),
			origin + Vector3(0.0, h * 0.86, 0.0)
			+ facing * Vector3(0.0, 0.0, 3.2 * size_scale)
			+ sail * Vector3(0.0, 4.5 * size_scale, 0.0),
			timber,
			sail
		)


## Populate the streets. Counts are budgets, not targets: the whole crowd is a fixed
## number of MultiMesh instances, so this is the one knob that decides what the
## background costs per frame.
func _build_walkers(rng: RandomNumberGenerator, plan: VillagePlan) -> void:
	var crowd := VillageCrowd.new()
	crowd.name = "Villagers"
	add_child(crowd)
	crowd.configure(GROUND_DROP)
	# The carriageway widths go across with the polylines: they are what decides how far
	# either direction of traffic keeps off the centreline, and therefore whether two
	# people meeting on a lane pass each other or walk through each other.
	var widths := PackedFloat32Array()
	for road in plan.roads:
		widths.append(float(road["width"]))
	crowd.set_routes(plan.routes, widths)
	if crowd.route_count() == 0:
		return

	# Weight the traffic toward the streets the player can actually see. Spread evenly,
	# a hundred figures over seven kilometres of lane works out at one person every
	# ninety metres, which reads as a deserted town.
	var pool: PackedInt32Array = PackedInt32Array()
	for i in crowd.route_count():
		var radius := crowd.route_mean_radius(i)
		var weight := 6 if radius < 90.0 else (3 if radius < 150.0 else 1)
		for w in weight:
			pool.append(i)

	var coats: Array[String] = ["cloth", "cloth_blue", "canvas", "timber"]
	for i in VILLAGER_COUNT:
		var coat: String = coats[rng.randi() % coats.size()]
		crowd.add_agent(
			VillageCrowd.villager_parts(coat, "skin"),
			pool[rng.randi() % pool.size()],
			rng.randf(),
			VILLAGER_SPEED * rng.randf_range(0.8, 1.25),
			2.6,
			0.42,
			1.1
		)
	for i in PEASANT_COUNT:
		crowd.add_agent(
			VillageCrowd.peasant_parts("cloth", "skin", "canvas" if rng.randf() < 0.5 else "crop"),
			pool[rng.randi() % pool.size()],
			rng.randf(),
			VILLAGER_SPEED * rng.randf_range(0.65, 0.95),
			2.4,
			0.42,
			1.3
		)
	# Soldiers walk in pairs, a few metres apart on the same street.
	for i in SOLDIER_PAIRS:
		var route: int = pool[rng.randi() % pool.size()]
		var at := rng.randf()
		var pace := SOLDIER_SPEED * rng.randf_range(0.94, 1.06)
		for member in 2:
			crowd.add_agent(
				VillageCrowd.soldier_parts("cloth", "skin", "iron"),
				route,
				at + float(member) * 0.004,
				pace,
				2.7,
				0.44,
				1.2
			)
	for i in HORSEMAN_COUNT:
		crowd.add_agent(
			VillageCrowd.horseman_parts(
				"cloth_blue" if rng.randf() < 0.5 else "canvas_red", "skin", "pelt"
			),
			pool[rng.randi() % pool.size()],
			rng.randf(),
			HORSEMAN_SPEED * rng.randf_range(0.85, 1.2),
			1.9,
			0.45,
			# A horse is nearly two metres nose to tail before the rider's knees.
			3.6,
			VillageCrowd.BAND_HORSE
		)
	# Carts keep to the wider streets: a wagon down a three-metre outer lane would be
	# straddling the verges on both sides however it is placed, so this goes on the
	# carriageway width rather than on how far out the lane happens to be.
	var cart_pool := PackedInt32Array()
	for i in crowd.route_count():
		if crowd.route_width(i) >= VillageCrowd.CART_ROAD_WIDTH and crowd.route_mean_radius(i) < 200.0:
			cart_pool.append(i)
	if cart_pool.is_empty():
		cart_pool = pool
	var loads: Array[String] = ["crop", "timber", "canvas"]
	# One cart per street, taken in turn. Two carts sharing a lane can meet head on, and
	# nothing about a four-metre road lets two wagons pass -- so they are never given
	# the chance to. There are more streets wide enough than there are carts.
	var cart_route := rng.randi() % cart_pool.size()
	for i in mini(CART_COUNT, cart_pool.size()):
		var route_for_cart: int = cart_pool[cart_route % cart_pool.size()]
		cart_route += 1
		crowd.add_agent(
			VillageCrowd.cart_parts(
				"cloth" if rng.randf() < 0.6 else "canvas_red",
				"skin",
				"pelt",
				"timber",
				loads[rng.randi() % loads.size()]
			),
			route_for_cart,
			rng.randf(),
			CART_SPEED * rng.randf_range(0.85, 1.15),
			1.7,
			0.34,
			# Horse, shafts and wagon together run to about eight metres of street.
			8.4,
			VillageCrowd.BAND_CART
		)
	for i in DOG_COUNT:
		crowd.add_agent(
			VillageCrowd.dog_parts("pelt"),
			pool[rng.randi() % pool.size()],
			rng.randf(),
			DOG_SPEED * rng.randf_range(0.75, 1.3),
			3.4,
			0.55,
			1.0
		)

	var materials := {}
	for key in [
		"cloth", "cloth_blue", "canvas", "canvas_red", "crop", "timber", "skin", "pelt", "iron"
	]:
		materials[key] = _mat(key)
	crowd.commit(
		materials,
		AABB(
			Vector3(-VILLAGE_EXTENT, GROUND_DROP - 2.0, -VILLAGE_EXTENT),
			Vector3(VILLAGE_EXTENT * 2.0, 12.0, VILLAGE_EXTENT * 2.0)
		)
	)


func _build_smoke(rng: RandomNumberGenerator, horizon_tint: Color) -> void:
	if PixelDioramaSettings.particle_quality <= 0:
		return
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 2.0
	mat.direction = Vector3.UP
	mat.spread = 8.0
	mat.initial_velocity_min = 3.0
	mat.initial_velocity_max = 5.5
	mat.gravity = Vector3(0.0, 1.4, 0.0)
	mat.scale_min = 4.0
	mat.scale_max = 9.0
	var ramp := Gradient.new()
	var smoke := Color(0.28, 0.26, 0.28).lerp(horizon_tint, 0.45)
	ramp.set_color(0, Color(smoke.r, smoke.g, smoke.b, 0.5))
	ramp.set_color(1, Color(smoke.r, smoke.g, smoke.b, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex

	var puff := BoxMesh.new()
	puff.size = Vector3.ONE
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.disable_receive_shadows = true
	puff_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	puff.material = puff_mat

	for i in SMOKE_STACKS:
		var angle := TAU * (float(i) + rng.randf()) / float(SMOKE_STACKS)
		var dist := rng.randf_range(NEAR_RING * 0.9, FAR_RING * 0.9)
		var column := GPUParticles3D.new()
		column.name = "Furnace%d" % i
		column.position = Vector3(
			cos(angle) * dist, GROUND_DROP + rng.randf_range(10.0, 26.0), sin(angle) * dist
		)
		column.amount = maxi(3, int(9 * PixelDioramaSettings.particle_amount_scale()))
		column.lifetime = 14.0
		column.randomness = 0.6
		column.visibility_aabb = AABB(Vector3(-40.0, -10.0, -40.0), Vector3(80.0, 120.0, 80.0))
		column.draw_pass_1 = puff
		column.process_material = mat
		add_child(column)


func _process(_delta: float) -> void:
	if not is_visible_in_tree():
		return
	_light_windows()
	_drive_smoke()


func _drive_smoke() -> void:
	var wind := WindService.wind_vector()
	for child in get_children():
		var column := child as GPUParticles3D
		if column == null:
			continue
		var mat := column.process_material as ParticleProcessMaterial
		if mat:
			mat.gravity = Vector3(wind.x * 2.4, 1.4, wind.z * 2.4)
		return
