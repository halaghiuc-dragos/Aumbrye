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
## Run the ground out to just inside the camera's default far plane (4000). Where the
## plate ends, the sky shows through beneath the true horizon as a flat band; the
## further out the edge is, the thinner that seam gets.
const GROUND_RADIUS := 3800.0

const GROUND_DROP := -26.0

## How far a road's surface stands above the surrounding ground, and how deep the slab
## that carries it is. The depth is what keeps crossings clean: see `_build_roads`.
const ROAD_TOP := 0.06

const LEVEL_CLEARANCE := 34.0


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

const UNIT_WIDTH := 6.4
const UNIT_DEPTH := 8.0
const EAVE_ONE := 5.6
const EAVE_TWO := 8.0

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


## Every terrain model is skinned from the skyline's own materials. A caller swaps a role for a
## different material (a block's roofing, a tree's leaf) and models with the same swaps share one
## MultiMesh.
var _queued: Dictionary = {}
var _skin_roles: Dictionary = {}


func _skin_map() -> Dictionary:
	if _skin_roles.is_empty():
		for role in [
			"stone", "stone_dark", "tile", "tile_grey", "thatch", "timber", "daub", "canvas", "canvas_red",
			"iron", "leaf", "leaf_warm", "grass", "grass_pale", "crop", "dirt", "cobble", "rock_far",
			"rock_pale", "snow",
		]:
			_skin_roles[role] = _mat(role)
		_skin_roles["wall"] = _mat("daub")
		_skin_roles["roof"] = _mat("tile")
		_skin_roles["foot"] = _mat("stone")
		_skin_roles["window"] = _window_mat()
	return _skin_roles


func _queue(id: String, xform: Transform3D, swaps: Dictionary = {}) -> void:
	var key := id
	for role in swaps:
		key += "|%s=%d" % [role, (swaps[role] as Material).get_instance_id()]
	if not _queued.has(key):
		var list: Array[Transform3D] = []
		_queued[key] = {"id": id, "swaps": swaps, "xforms": list}
	var entry: Dictionary = _queued[key]
	var transforms: Array[Transform3D] = entry["xforms"]
	transforms.append(xform)


## Draw everything queued so far as one MultiMesh per model and skin.
func _flush(group: String) -> void:
	var holder := Node3D.new()
	holder.name = group
	add_child(holder)
	for key in _queued:
		var entry: Dictionary = _queued[key]
		var materials := _skin_map().duplicate()
		materials.merge(entry["swaps"], true)
		var transforms: Array[Transform3D] = entry["xforms"]
		var placed := PropLibrary.scatter_themed(
			holder, entry["id"], PixelDioramaStyle.PaletteTheme.HUB, transforms,
			(entry["id"] as String).get_file().capitalize().replace(" ", ""), {"materials": materials}
		)
		if placed != null:
			_no_shadows(placed)
	_queued.clear()


static func _yaw_scale(yaw: float, scale_by: Vector3, at: Vector3) -> Transform3D:
	return Transform3D(Basis(Vector3.UP, yaw) * Basis.from_scale(scale_by), at)


## A run of `length` metres made of tiles `tile` long, laid along `dir` starting at `start`.
func _queue_run(id: String, start: Vector3, dir: Vector3, length: float, tile: float, cross: Vector3, swaps: Dictionary = {}) -> void:
	var count := maxi(1, ceili(length / tile))
	var pitch := length / float(count)
	var yaw := atan2(-dir.z, dir.x)
	for i in count:
		var at := start + dir * (pitch * (float(i) + 0.5))
		_queue(id, _yaw_scale(yaw, Vector3(pitch / tile, cross.y, cross.z), at), swaps)


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

	_queue("skyline/tower_cliff", _yaw_scale(0.0, Vector3(LEVEL_CLEARANCE / 40.0, 1.0, LEVEL_CLEARANCE / 40.0), Vector3.ZERO))
	_flush("TowerShaft")

	var hedge_rng := RandomNumberGenerator.new()
	hedge_rng.seed = 4471
	for i in 34:
		var angle := TAU * hedge_rng.randf()
		var dist := hedge_rng.randf_range(FIELD_INNER, GROUND_RADIUS * 0.72)
		var length := hedge_rng.randf_range(14.0, 44.0)
		var yaw := hedge_rng.randf() * TAU
		var dir := Vector3(cos(yaw), 0.0, -sin(yaw))
		var centre := Vector3(cos(angle) * dist, GROUND_DROP, sin(angle) * dist)
		_queue_run("skyline/hedge", centre - dir * length * 0.5, dir, length, 4.0, Vector3(1.0, 1.0, 1.0))
	_flush("Hedgerows")


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
	var clumps: Array[String] = ["skyline/clump_a", "skyline/clump_b", "skyline/clump_c"]
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
		_queue(
			clumps[rng.randi() % clumps.size()],
			_yaw_scale(rng.randf() * TAU, Vector3(w, h / 0.7, w), Vector3(spot.x, GROUND_DROP, spot.y))
		)

	var autumn := {"leaf": _mat("leaf_warm")}
	var trees: Array[String] = ["skyline/oak_a", "skyline/oak_b", "skyline/oak_c", "skyline/oak_a", "skyline/pine_a", "skyline/pine_b"]
	for i in TREE_COUNT:
		var angle := rng.randf() * TAU
		var dist := lerpf(FIELD_INNER + 6.0, FIELD_OUTER, sqrt(rng.randf()))
		var spot := Vector2(cos(angle) * dist, sin(angle) * dist)
		var crown := rng.randf_range(3.0, 5.2)
		# A tree owns its ground: claiming it stops a crop strip being sown in its shade.
		if not plan.try_reserve(spot, 0.0, Vector2(crown, crown), "tree"):
			continue
		var scale_by := crown / 4.3
		_queue(
			trees[rng.randi() % trees.size()],
			_yaw_scale(rng.randf() * TAU, Vector3(scale_by, scale_by * rng.randf_range(0.9, 1.15), scale_by), Vector3(spot.x, GROUND_DROP, spot.y)),
			autumn if rng.randf() < 0.3 else {}
		)
		if rng.randf() < 0.35:
			var bush := Vector2(spot.x + rng.randf_range(-2.0, 2.0), spot.y + rng.randf_range(-2.0, 2.0))
			if plan.is_clear(bush, 0.0, Vector2(1.2, 1.2)):
				_queue(
					"skyline/shrub_a" if rng.randf() < 0.5 else "skyline/shrub_b",
					_yaw_scale(rng.randf() * TAU, Vector3.ONE * rng.randf_range(0.8, 1.4), Vector3(bush.x, GROUND_DROP, bush.y))
				)

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
		var facing := Basis(Vector3.UP, yaw)
		var at := Vector3(spot.x, GROUND_DROP, spot.y)
		for bay in posts:
			var along := (float(bay) + 0.5 - float(posts) * 0.5) * pitch
			_queue("skyline/fence", Transform3D(facing, at + facing * Vector3(along, 0.0, 0.0)))

	_build_cultivation(rng, plan)

	for i in 3:
		var angle := TAU * (float(i) + 0.4) / 3.0
		var dist := rng.randf_range(FIELD_INNER + 8.0, FIELD_OUTER - 8.0)
		var spot := Vector2(cos(angle) * dist, sin(angle) * dist)
		if not plan.try_reserve(spot, 0.0, Vector2(3.2, 3.2), "well"):
			continue
		_queue(
			"skyline/well",
			_yaw_scale(rng.randf() * TAU, Vector3.ONE, Vector3(spot.x, GROUND_DROP, spot.y))
		)
	_flush("Fields")


## Draw the strips the plan set aside for cultivation. Each one fills its own reserved
## footprint exactly -- the furrows are laid out across `size.y` and stop at its edge --
## so what is drawn is the ground that was checked, not an approximation of it.
func _build_cultivation(rng: RandomNumberGenerator, plan: VillagePlan) -> void:
	for field in plan.fields:
		var centre: Vector2 = field["c"]
		var size: Vector2 = field["size"]
		var kind: String = field["kind"]
		var at := Vector3(centre.x, GROUND_DROP, centre.y)
		var yaw := -(field["yaw"] as float)
		var facing := Basis(Vector3.UP, yaw)
		match kind:
			"crop":
				# Whole furrows only, so the last one lands inside the plot rather than
				# hanging over the headland.
				var pitch := 1.35
				var rows := maxi(2, int(size.y / pitch))
				var length := size.x * 0.94
				for row in rows:
					var across := (float(row) - float(rows - 1) * 0.5) * pitch
					var start := at + facing * Vector3(-length * 0.5, 0.0, across)
					_queue_run(
						"skyline/crop_row", start, facing * Vector3.RIGHT, length, 2.0,
						Vector3(1.0, rng.randf_range(0.9, 1.25), 0.9)
					)
			"orchard":
				var cols := maxi(2, int(size.x / 4.2))
				var lines := maxi(2, int(size.y / 4.2))
				for cx in cols:
					for cz in lines:
						var lx := (float(cx) - float(cols - 1) * 0.5) * (size.x / float(cols))
						var lz := (float(cz) - float(lines - 1) * 0.5) * (size.y / float(lines))
						var base := at + facing * Vector3(lx, 0.0, lz)
						var crown := rng.randf_range(2.0, 3.0) / 2.5
						_queue("skyline/orchard_tree", _yaw_scale(rng.randf() * TAU, Vector3.ONE * crown, base))
			_:
				# Paddock: grazing inside a post-and-rail fence.
				var nx := maxi(1, ceili(size.x * 0.92 / 4.0))
				var nz := maxi(1, ceili(size.y * 0.92 / 4.0))
				for ix in nx:
					for iz in nz:
						var lx := (float(ix) + 0.5 - float(nx) * 0.5) * (size.x * 0.92 / float(nx))
						var lz := (float(iz) + 0.5 - float(nz) * 0.5) * (size.y * 0.92 / float(nz))
						_queue(
							"skyline/grazing",
							_yaw_scale(
								yaw, Vector3(size.x * 0.92 / float(nx) / 4.0, 1.0, size.y * 0.92 / float(nz) / 4.0),
								at + facing * Vector3(lx, 0.0, lz)
							)
						)
				for side in [-1.0, 1.0]:
					var posts := maxi(2, int(size.x / 2.0))
					var bay := size.x / float(posts)
					for post in posts:
						var along := (float(post) + 0.5 - float(posts) * 0.5) * bay
						_queue(
							"skyline/fence",
							_yaw_scale(yaw, Vector3(bay / 1.8, 1.0, 1.0), at + facing * Vector3(along, 0.0, side * size.y * 0.46))
						)


## Which layer a street rank is drawn on, lowest first. The stone high street is the
## bottom layer: where a dirt lane crosses it, the mud is what you see.
static func _road_layer(rank: int) -> float:
	match rank:
		0:
			return 0.0
		2:
			return 1.0
	return 2.0


## Lay the streets down as runs of cobble or rutted dirt. These are the same polylines the plan
## seats every building on and the crowd walks, so what you see is genuinely the street the
## villagers are on.
func _build_roads(plan: VillagePlan) -> void:
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
		# The high street through the middle of town is metalled; the rest is mud.
		var style := "cobble" if rank == 0 else "dirt"
		for i in points.size() - 1:
			var a := points[i]
			var b := points[i + 1]
			var span := b - a
			var length := span.length()
			if length <= 0.01:
				continue
			var dir := Vector3(span.x, 0.0, span.y) / length
			# Segments meet end to end rather than overlapping: two co-planar slabs of
			# the same street would z-fight each other exactly as two streets did.
			_queue_run(
				"skyline/road_" + style, Vector3(a.x, y, a.y), dir, length, 4.0, Vector3(1.0, 1.0, width)
			)
			# The corner left by the turn is filled by a patch at the joint, set a hair
			# lower so it hides under the segments instead of arguing with them.
			if i + 2 < points.size():
				var next := points[i + 2] - b
				if next.length() > 0.01:
					var bearing := span.normalized() + next.normalized()
					if bearing.length() > 0.001:
						_queue(
							"skyline/joint_" + style,
							_yaw_scale(-atan2(bearing.y, bearing.x), Vector3(width, 1.0, width), Vector3(b.x, y - 0.004, b.y))
						)
	_flush("Streets")


## Turn the plan into geometry. Each plot is built inside its own planned footprint --
## nothing here invents a size of its own -- which is what carries the planner's
## no-overlap guarantee through to what actually gets drawn.
func _build_town(plan: VillagePlan) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = TOWN_SEED ^ 0x5f3a
	# The church, castle, windmill and market are Blender models of their own; houses are placed
	# as instances of a handful of Blender terrace units.
	var landmarks := Node3D.new()
	landmarks.name = "Landmarks"
	add_child(landmarks)

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

		match kind:
			# Landmarks take the plot's own bearing, not the street-facing one. Their long
			# axis is their local X, which is the axis the plan reserved -- pointing them
			# at the street instead ran the church's nave across the ring gap and through
			# the carriageways on both sides of it.
			"church":
				_place_landmark(landmarks, "skyline/church", origin, world_yaw)
			"castle":
				_place_landmark(landmarks, "skyline/castle", origin, world_yaw)
			"windmill":
				_place_landmark(landmarks, "skyline/windmill", origin, world_yaw)
			_:
				if band >= SILHOUETTE_BAND:
					_add_silhouette(rng, origin, world_yaw, size)
				else:
					_add_terrace(rng, origin, world_yaw, front_yaw, size, band, kind)

	if not plan.plaza.is_empty():
		var plaza_c: Vector2 = plan.plaza["c"]
		_place_market(
			landmarks,
			rng,
			Vector3(plaza_c.x, GROUND_DROP, plaza_c.y),
			-(plan.plaza["yaw"] as float)
		)

	_no_shadows(landmarks)
	_flush("Houses")


## A terrace of houses filling exactly the planned frontage. The run is split into
## whole units across `size.x`, so the block ends where the plot ends rather than
## wherever the last random width happened to land.
func _add_terrace(
	rng: RandomNumberGenerator,
	centre: Vector3,
	yaw: float,
	front_yaw: float,
	size: Vector2,
	band: int,
	kind: String
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	# The house models face +z, which is the street side; a plot that faces the other way round
	# is turned half a circle.
	var turn := yaw if cos(front_yaw - yaw) > 0.0 else yaw + PI
	var simple := band >= SIMPLE_BAND

	# Town centre builds upward; the outskirts sprawl low and thatched.
	var storeys := 2 if band == 0 and rng.randf() < 0.72 else 1
	var eave := (3.2 + 2.4 * float(storeys)) * rng.randf_range(0.92, 1.08)
	if kind == "barn":
		eave = rng.randf_range(4.6, 5.8)
	var depth: float = size.y

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
	var offset := -size.x * 0.5
	var model := "skyline/barn" if kind == "barn" else ("skyline/house_far" if simple else "skyline/house_%d" % storeys)
	var model_width := 8.2 if kind == "barn" else UNIT_WIDTH
	var model_eave := 5.2 if kind == "barn" else (EAVE_TWO if storeys == 2 else EAVE_ONE)

	for i in run:
		var at: Vector3 = centre + facing * Vector3(offset + unit * 0.5, 0.0, 0.0)
		# One house in a row is occasionally re-roofed or re-fronted; most are not.
		var wall_mat: Material = block_wall
		if rng.randf() < 0.16:
			wall_mat = _mat("stone") if block_wall == _mat("daub") else _mat("daub")
		_queue(
			model,
			_yaw_scale(turn, Vector3(unit / model_width, eave / model_eave, depth / UNIT_DEPTH), at),
			{"wall": wall_mat, "roof": block_roof}
		)
		offset += unit


## A Blender landmark standing at `origin`, turned to the plot's bearing and skinned with the
## skyline's own stone, tile and timber.
func _place_landmark(parent: Node3D, id: String, origin: Vector3, yaw: float, overrides: Dictionary = {}) -> Node3D:
	var holder := Node3D.new()
	holder.name = id.get_file().capitalize().replace(" ", "")
	holder.position = origin
	holder.rotation.y = yaw
	parent.add_child(holder)
	var materials := {
		"stone": _mat("stone"), "stone_dark": _mat("stone_dark"), "tile_grey": _mat("tile_grey"),
		"thatch": _mat("thatch"), "timber": _mat("timber"), "canvas": _mat("canvas"),
		"canvas_red": _mat("canvas_red"), "iron": _mat("iron"), "window": _window_mat(),
	}
	materials.merge(overrides, true)
	PropLibrary.attach_themed(holder, id, PixelDioramaStyle.PaletteTheme.HUB, {"materials": materials})
	return holder


func _place_market(parent: Node3D, rng: RandomNumberGenerator, origin: Vector3, yaw: float) -> void:
	_place_landmark(parent, "skyline/market_plaza", origin, yaw)
	for i in 6:
		var angle := TAU * float(i) / 6.0 + rng.randf_range(-0.2, 0.2)
		var dist := rng.randf_range(8.0, 11.0)
		var at: Vector3 = origin + Vector3(cos(angle) * dist, 0.0, sin(angle) * dist)
		var width := rng.randf_range(3.6, 5.2)
		var depth := rng.randf_range(3.2, 4.4)
		var stall := _place_landmark(
			parent, "skyline/market_stall", at, -angle,
			{"canvas": _mat("canvas") if i % 2 == 0 else _mat("canvas_red")}
		)
		stall.scale = Vector3(width / 4.4, 1.0, depth / 3.8)


## The far bands, where a building is only ever a shape against the sky: a body and a roof, no
## frame and no chimney, because none of it resolves at this range.
func _add_silhouette(rng: RandomNumberGenerator, centre: Vector3, yaw: float, size: Vector2) -> void:
	var wall: Material = _mat("daub") if rng.randf() < 0.5 else _mat("stone")
	var roof: Material = _mat("thatch") if rng.randf() < 0.6 else _mat("tile_grey")
	# Taller than a near cottage on purpose: at this distance a squat box disappears
	# into the ground haze instead of reading as a roofline.
	var eave := rng.randf_range(4.6, 6.8)
	_queue(
		"skyline/house_far",
		_yaw_scale(yaw, Vector3(size.x / UNIT_WIDTH, eave / EAVE_ONE, size.y / UNIT_DEPTH), centre),
		{"wall": wall, "roof": roof}
	)


## The mountain range on the horizon line, in three concentric ranges so the near peaks break the
## skyline of the far ones. Each peak is a faceted Blender mountain scaled to its own height.
func _build_mountains(rng: RandomNumberGenerator) -> void:
	var base_y := GROUND_DROP
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
			# Only the higher peaks hold snow, and the line sits lower on the taller
			# ones -- the same rule the real thing follows.
			var model := "skyline/mountain_bare"
			if height >= 250.0:
				model = "skyline/mountain_high" if rng.randf() < 0.5 else "skyline/mountain_low"
			_queue(
				model,
				_yaw_scale(rng.randf() * TAU, Vector3(width / 100.0, height / 100.0, width / 100.0), at)
			)
	_flush("Mountains")


func _build_horizon(rng: RandomNumberGenerator) -> void:
	for i in HORIZON_LANDMARKS:
		var angle := TAU * (float(i) + rng.randf_range(-0.4, 0.4)) / float(HORIZON_LANDMARKS)
		var dist := HORIZON_RING * rng.randf_range(0.8, 1.5)
		var at := Vector3(cos(angle) * dist, GROUND_DROP, sin(angle) * dist)
		var yaw := -angle
		var scale_up := dist / HORIZON_RING
		match rng.randi() % 3:
			0:
				var w := rng.randf_range(50.0, 110.0) * scale_up
				var h := rng.randf_range(14.0, 26.0) * scale_up
				_queue("skyline/horizon_keep", _yaw_scale(yaw, Vector3(w / 80.0, h / 20.0, scale_up), at))
			1:
				var base_w := rng.randf_range(60.0, 130.0) * scale_up
				var total := rng.randf_range(24.0, 50.0) * scale_up
				_queue("skyline/horizon_hill", _yaw_scale(yaw, Vector3(base_w / 100.0, total / 40.0, base_w / 100.0), at))
			_:
				var tall := (rng.randf_range(18.0, 34.0) + 14.0) * scale_up
				_queue("skyline/horizon_tower", _yaw_scale(yaw, Vector3.ONE * (tall / 41.0), at))
	_flush("HorizonRing")


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


var _smoke_material: ParticleProcessMaterial


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
	_smoke_material = mat

	var puff := PropLibrary.bare_mesh("fx/smoke_puff").duplicate() as ArrayMesh
	var puff_mat := StandardMaterial3D.new()
	puff_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	puff_mat.vertex_color_use_as_albedo = true
	puff_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	puff_mat.disable_receive_shadows = true
	puff_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	puff.surface_set_material(0, puff_mat)

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


## Every furnace column shares one process material, so writing it once moves them all.
func _drive_smoke() -> void:
	if _smoke_material == null:
		return
	var wind := WindService.wind_vector()
	_smoke_material.gravity = Vector3(wind.x * 2.4, 1.4, wind.z * 2.4)
