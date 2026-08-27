extends Node3D


const NEAR_RING := 76.0
const FAR_RING := 118.0
const HORIZON_RING := 420.0
const HORIZON_LANDMARKS := 22
const GROUND_RADIUS := 2400.0

const GROUND_DROP := -26.0

const LEVEL_CLEARANCE := 34.0

const NEAR_HAZE := 0.20
const FAR_HAZE := 0.44

const BUILDINGS_PER_RING := 26
const SMOKE_STACKS := 7

const FIELD_INNER := LEVEL_CLEARANCE + 4.0
const FIELD_OUTER := 68.0

const GRASS_CLUMPS := 900
const TREE_COUNT := 44
const FENCE_RUNS := 26

const VILLAGER_COUNT := 18
const DOG_COUNT := 7
const VILLAGER_SPEED := 1.15
const DOG_SPEED := 2.6

const LANE_RADII: Array[float] = [42.0, 50.0, 58.0, 65.0]

var _walkers: Array[Dictionary] = []

const WALKER_HZ := 20.0

var _walker_accum := 0.0

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

	_build_ground()
	_build_fields(rng)
	_build_ring(rng, NEAR_RING, 1.0, "Near")
	_build_ring(rng, FAR_RING, 1.45, "Far")
	_build_horizon(rng)
	_build_smoke(rng, horizon_tint)
	_build_walkers(rng)


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


func _build_fields(rng: RandomNumberGenerator) -> void:
	var greens: Array[Material] = [_mat("grass"), _mat("grass_pale"), _mat("leaf"), _mat("leaf_warm")]
	var batch := PixelBoxBatch.new()

	for i in GRASS_CLUMPS:
		var angle := rng.randf() * TAU
		var t := sqrt(rng.randf())
		var dist := lerpf(FIELD_INNER, FIELD_OUTER, t)
		var w := rng.randf_range(0.7, 2.1)
		var h := rng.randf_range(0.35, 1.1)
		batch.add(
			Vector3(w, h, w * rng.randf_range(0.7, 1.3)),
			Vector3(cos(angle) * dist, GROUND_DROP + h * 0.5, sin(angle) * dist),
			greens[rng.randi() % greens.size()],
			Basis(Vector3.UP, rng.randf() * TAU)
		)

	var bark := _mat("timber")
	for i in TREE_COUNT:
		var angle := rng.randf() * TAU
		var dist := lerpf(FIELD_INNER + 6.0, FIELD_OUTER, sqrt(rng.randf()))
		var at := Vector3(cos(angle) * dist, GROUND_DROP, sin(angle) * dist)
		var trunk_h := rng.randf_range(2.4, 4.6)
		var crown := rng.randf_range(3.0, 5.2)
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
		var at := Vector3(cos(angle) * dist, GROUND_DROP, sin(angle) * dist)
		var facing := Basis(Vector3.UP, -angle + rng.randf_range(-0.4, 0.4))
		var posts := rng.randi_range(5, 11)
		var pitch := 1.8
		for post in posts:
			var along := (float(post) - float(posts) * 0.5) * pitch
			batch.add(
				Vector3(0.16, 1.1, 0.16),
				at + facing * Vector3(along, 0.55, 0.0),
				rail,
				facing
			)
		batch.add(
			Vector3(float(posts) * pitch, 0.12, 0.1),
			at + Vector3(0.0, 0.85, 0.0),
			rail,
			facing
		)

	var crop := _mat("crop")
	for plot in 7:
		var angle := rng.randf() * TAU
		var dist := lerpf(FIELD_INNER + 4.0, FIELD_OUTER - 6.0, rng.randf())
		var at := Vector3(cos(angle) * dist, GROUND_DROP, sin(angle) * dist)
		var facing := Basis(Vector3.UP, rng.randf() * TAU)
		var rows := rng.randi_range(4, 7)
		var row_len := rng.randf_range(8.0, 15.0)
		for row in rows:
			var across := (float(row) - float(rows - 1) * 0.5) * 1.3
			batch.add(
				Vector3(row_len, 0.75, 0.55),
				at + facing * Vector3(0.0, 0.38, across),
				crop,
				facing
			)

	var stone := _mat("stone")
	var timber := _mat("timber")
	var thatch := _mat("thatch")
	for i in 3:
		var angle := TAU * (float(i) + 0.4) / 3.0
		var dist := rng.randf_range(FIELD_INNER + 8.0, FIELD_OUTER - 8.0)
		var at := Vector3(cos(angle) * dist, GROUND_DROP, sin(angle) * dist)
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
			Vector3(-FIELD_OUTER * 1.2, GROUND_DROP - 4.0, -FIELD_OUTER * 1.2),
			Vector3(FIELD_OUTER * 2.4, 24.0, FIELD_OUTER * 2.4)
		)
	))


func _build_ring(
	rng: RandomNumberGenerator, radius: float, size_scale: float, tag: String
) -> void:
	var wall := _mat("daub")
	var roof: Material = _mat("tile") if tag == "Near" else _mat("thatch")
	var batch := PixelBoxBatch.new()
	var top := GROUND_DROP
	var church_bay := rng.randi_range(0, BUILDINGS_PER_RING - 1)
	@warning_ignore("integer_division")
	var market_bay := (church_bay + BUILDINGS_PER_RING / 2) % BUILDINGS_PER_RING
	var gate_bay := (church_bay + 6) % BUILDINGS_PER_RING
	var castle_bay := (church_bay + 13) % BUILDINGS_PER_RING
	for i in BUILDINGS_PER_RING:
		var angle := TAU * float(i) / float(BUILDINGS_PER_RING)
		var facing_in := -angle
		if tag == "Near":
			var wall_at := Vector3(cos(angle) * (radius - 9.0), top, sin(angle) * (radius - 9.0))
			var bay_len := TAU * (radius - 9.0) / float(BUILDINGS_PER_RING)
			_add_town_wall(batch, wall_at, facing_in, bay_len * 1.06, size_scale, i == gate_bay)
		if i == church_bay:
			_add_church(
				batch, rng, Vector3(cos(angle) * radius, top, sin(angle) * radius),
				facing_in, size_scale
			)
			continue
		if i == market_bay and tag == "Near":
			_add_market(batch, rng, Vector3(cos(angle) * radius, top, sin(angle) * radius), facing_in)
			continue
		if i == castle_bay:
			var castle_r := radius + 34.0 * size_scale
			_add_castle(
				batch, rng,
				Vector3(cos(angle) * castle_r, top, sin(angle) * castle_r),
				facing_in, size_scale
			)
			continue
		var dist := radius * rng.randf_range(0.94, 1.1)
		var wobble := rng.randf_range(-0.35, 0.35) / float(BUILDINGS_PER_RING) * TAU
		var origin := Vector3(cos(angle + wobble) * dist, top, sin(angle + wobble) * dist)
		_add_house(batch, rng, origin, facing_in, wall, roof, size_scale)
		if rng.randf() < 0.6:
			_add_house(
				batch,
				rng,
				Vector3(cos(angle + wobble) * (dist + 11.0 * size_scale), top, sin(angle + wobble) * (dist + 11.0 * size_scale)),
				facing_in + PI,
				wall,
				roof,
				size_scale
			)
	if tag == "Near":
		for i in 2:
			var angle := TAU * (float(i) + 0.35) / 2.0
			_add_windmill(
				batch,
				Vector3(cos(angle) * (radius + 22.0), top, sin(angle) * (radius + 22.0)),
				-angle,
				size_scale
			)
	_no_shadows(batch.commit(
		self,
		"%sRing" % tag,
		AABB(
			Vector3(-radius * 1.6, GROUND_DROP - 4.0, -radius * 1.6),
			Vector3(radius * 3.2, 110.0 * size_scale, radius * 3.2)
		)
	))


func _add_house(
	batch: PixelBoxBatch,
	rng: RandomNumberGenerator,
	origin: Vector3,
	yaw: float,
	_wall: Material,
	_roof: Material,
	size_scale: float
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var timber := _mat("timber")
	var footing := _mat("stone")
	var roof_roll := rng.randf()
	var roof_mat: Material = (
		_mat("thatch") if roof_roll < 0.45
		else (_mat("tile") if roof_roll < 0.8 else _mat("tile_grey"))
	)
	var wall_mat: Material = _mat("daub") if rng.randf() < 0.72 else _mat("stone")

	var run := rng.randi_range(2, 4)
	var depth := rng.randf_range(5.0, 6.4) * size_scale
	var eave := rng.randf_range(4.2, 5.4) * size_scale
	var peak := depth * rng.randf_range(0.42, 0.55)
	var post := 0.32 * size_scale
	var offset := 0.0
	for i in run:
		var w := rng.randf_range(4.2, 5.8) * size_scale
		var at: Vector3 = origin + facing * Vector3(offset + w * 0.5, 0.0, 0.0)
		var half_w := w * 0.5
		var half_d := depth * 0.5

		batch.add(
			Vector3(w + post, 0.7 * size_scale, depth + post),
			at + Vector3(0.0, 0.35 * size_scale, 0.0),
			footing,
			facing
		)
		for px in [-1.0, 1.0]:
			for pz in [-1.0, 1.0]:
				batch.add(
					Vector3(post, eave, post),
					at + Vector3(0.0, eave * 0.5, 0.0)
					+ facing * Vector3(px * (half_w - post * 0.5), 0.0, pz * (half_d - post * 0.5)),
					timber,
					facing
				)
		batch.add(
			Vector3(w - post, eave, depth - post),
			at + Vector3(0.0, eave * 0.5, 0.0),
			wall_mat,
			facing
		)
		batch.add(
			Vector3(w + post * 0.6, 0.26 * size_scale, depth + post * 0.6),
			at + Vector3(0.0, eave - 0.13 * size_scale, 0.0),
			timber,
			facing
		)
		batch.add(
			Vector3(w + post * 0.3, 0.2 * size_scale, depth + post * 0.3),
			at + Vector3(0.0, eave * 0.52, 0.0),
			timber,
			facing
		)
		var ends := 0
		if run == 1:
			ends = 0
		elif i == 0:
			ends = -1
		elif i == run - 1:
			ends = 1
		else:
			ends = 2
		var ridge := _add_roof(
			batch, at + Vector3(0.0, eave, 0.0), half_d, half_w, peak,
			facing * Basis(Vector3.UP, PI * 0.5), roof_mat, wall_mat, timber, ends
		)
		if rng.randf() < 0.8:
			var stack := peak + 1.4 * size_scale
			batch.add(
				Vector3(0.85 * size_scale, stack, 0.85 * size_scale),
				at + Vector3(0.0, ridge - peak + stack * 0.5, 0.0)
				+ facing * Vector3(half_w * 0.55, 0.0, 0.0),
				footing,
				facing
			)
		batch.add(
			Vector3(1.0 * size_scale, 2.1 * size_scale, 0.2),
			at + Vector3(0.0, 1.05 * size_scale + 0.7 * size_scale, 0.0)
			+ facing * Vector3(-w * 0.24, 0.0, half_d),
			timber,
			facing
		)
		var lights := rng.randi_range(1, 2)
		for pane in lights:
			batch.add(
				Vector3(0.75 * size_scale, 0.85 * size_scale, 0.16),
				(
					at
					+ Vector3(0.0, eave * 0.66, 0.0)
					+ facing * Vector3(
						(float(pane) - float(lights - 1) * 0.5) * w * 0.34 + w * 0.16, 0.0, half_d
					)
				),
				_window_mat(),
				facing
			)
		offset += w + 0.22 * size_scale


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
					var th := h * rng.randf_range(1.6, 2.6)
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
				var total := rng.randf_range(40.0, 90.0) * scale_up
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
				var h2 := rng.randf_range(30.0, 60.0) * scale_up
				batch.add(
					Vector3(12.0 * scale_up, h2, 12.0 * scale_up),
					at + Vector3(0.0, h2 * 0.5, 0.0), stone, facing
				)
				_add_roof(
					batch, at + Vector3(0.0, h2, 0.0), 6.0 * scale_up, 6.0 * scale_up,
					26.0 * scale_up, facing, roof, stone, stone
				)
	_no_shadows(batch.commit(
		self,
		"HorizonRing",
		AABB(
			Vector3(-HORIZON_RING * 2.0, GROUND_DROP - 10.0, -HORIZON_RING * 2.0),
			Vector3(HORIZON_RING * 4.0, 220.0, HORIZON_RING * 4.0)
		)
	))


func _add_town_wall(
	batch: PixelBoxBatch, origin: Vector3, yaw: float, length: float, size_scale: float, gate: bool
) -> void:
	var facing := Basis(Vector3.UP, yaw)
	var stone := _mat("stone_dark")
	var wall_h := 7.0 * size_scale
	var thick := 2.2 * size_scale
	batch.add(Vector3(length, wall_h, thick), origin + Vector3(0.0, wall_h * 0.5, 0.0), stone, facing)
	var merlons := maxi(4, int(length / (2.6 * size_scale)))
	for m in merlons:
		var t := (float(m) + 0.5) / float(merlons) - 0.5
		batch.add(
			Vector3(1.4 * size_scale, 1.5 * size_scale, thick + 0.3),
			origin + Vector3(0.0, wall_h + 0.75 * size_scale, 0.0) + facing * Vector3(t * length, 0.0, 0.0),
			stone,
			facing
		)
	var tower_h := wall_h * 1.6


	if not gate:
		return
	for side in [-1.0, 1.0]:
		batch.add(
			Vector3(3.4 * size_scale, tower_h * 1.1, thick + 2.0 * size_scale),
			origin + Vector3(0.0, tower_h * 0.55, 0.0) + facing * Vector3(side * 4.0 * size_scale, 0.0, 0.0),
			stone,
			facing
		)
	batch.add(
		Vector3(5.0 * size_scale, 2.4 * size_scale, thick + 2.0 * size_scale),
		origin + Vector3(0.0, wall_h + 1.2 * size_scale, 0.0),
		stone,
		facing
	)
	batch.add(
		Vector3(4.2 * size_scale, wall_h * 0.7, 0.3),
		origin + Vector3(0.0, wall_h * 0.35, 0.0) + facing * Vector3(0.0, 0.0, thick * 0.5 + 1.0),
		_mat("timber"),
		facing
	)


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


func _build_walkers(rng: RandomNumberGenerator) -> void:
	var root := Node3D.new()
	root.name = "Villagers"
	add_child(root)
	var coats: Array[Material] = [_mat("cloth"), _mat("cloth_blue"), _mat("thatch"), _mat("timber")]
	var skin := _mat("skin")
	var pelt := _mat("pelt")

	for i in VILLAGER_COUNT:
		var lane := LANE_RADII[i % LANE_RADII.size()]
		_add_walker(
			root,
			rng,
			lane + rng.randf_range(-2.5, 2.5),
			coats[rng.randi() % coats.size()],
			skin,
			VILLAGER_SPEED * rng.randf_range(0.8, 1.25),
			false,
			"Villager%d" % i
		)
	for i in DOG_COUNT:
		var lane := LANE_RADII[i % LANE_RADII.size()]
		_add_walker(
			root,
			rng,
			lane + rng.randf_range(-4.0, 4.0),
			pelt,
			pelt,
			DOG_SPEED * rng.randf_range(0.75, 1.3),
			true,
			"Dog%d" % i
		)


func _add_walker(
	root: Node3D,
	rng: RandomNumberGenerator,
	lane: float,
	body_mat: Material,
	head_mat: Material,
	speed: float,
	four_legged: bool,
	node_name: String
) -> void:
	var walker := Node3D.new()
	walker.name = node_name
	root.add_child(walker)

	var legs: Array[Node3D] = []
	var arms: Array[Node3D] = []
	if four_legged:
		PixelDioramaStyle.add_box(
			walker, Vector3(0.42, 0.38, 0.92), Vector3(0.0, 0.56, 0.0), body_mat, "Body"
		)
		PixelDioramaStyle.add_box(
			walker, Vector3(0.3, 0.3, 0.34), Vector3(0.0, 0.72, 0.6), head_mat, "Head"
		)
		PixelDioramaStyle.add_box(
			walker, Vector3(0.12, 0.12, 0.4), Vector3(0.0, 0.72, -0.6), body_mat, "Tail"
		)
		for lx in [-1.0, 1.0]:
			for lz in [-1.0, 1.0]:
				legs.append(
					_add_leg(
						walker, body_mat, Vector3(lx * 0.15, 0.36, lz * 0.3), Vector3(0.13, 0.4, 0.13)
					)
				)
	else:
		var cloth := _mat("cloth") if rng.randf() < 0.5 else _mat("cloth_blue")
		PixelDioramaStyle.add_box(
			walker, Vector3(0.46, 0.62, 0.3), Vector3(0.0, 1.24, 0.0), body_mat, "Torso"
		)
		PixelDioramaStyle.add_box(
			walker, Vector3(0.5, 0.34, 0.34), Vector3(0.0, 1.02, 0.0), cloth, "Tunic"
		)
		PixelDioramaStyle.add_box(
			walker, Vector3(0.5, 0.08, 0.34), Vector3(0.0, 1.16, 0.0), _mat("timber"), "Belt"
		)
		PixelDioramaStyle.add_box(
			walker, Vector3(0.26, 0.26, 0.26), Vector3(0.0, 1.68, 0.0), head_mat, "Head"
		)
		if rng.randf() < 0.25:
			PixelDioramaStyle.add_box(
				walker, Vector3(0.3, 0.16, 0.3), Vector3(0.0, 1.82, 0.0), _mat("iron"), "Helm"
			)
			PixelDioramaStyle.add_box(
				walker, Vector3(0.5, 0.3, 0.34), Vector3(0.0, 1.4, 0.0), _mat("iron"), "Mail"
			)
		for side in [-1.0, 1.0]:
			arms.append(
				_add_leg(
					walker, body_mat, Vector3(side * 0.3, 1.5, 0.0), Vector3(0.14, 0.52, 0.16)
				)
			)
			legs.append(
				_add_leg(
					walker, cloth, Vector3(side * 0.13, 0.92, 0.0), Vector3(0.16, 0.92, 0.18)
				)
			)

	_walkers.append({
		"node": walker,
		"legs": legs,
		"arms": arms,
		"lane": lane,
		"angle": rng.randf() * TAU,
		"speed": speed * (1.0 if rng.randf() < 0.5 else -1.0),
		"stride": 2.6 if four_legged else 1.55,
		"leg_len": 0.4 if four_legged else 0.92,
		"pause_in": rng.randf_range(6.0, 26.0),
		"paused": 0.0,
		"gait": rng.randf_range(0.9, 1.12),
		"travelled": rng.randf() * 40.0,
	})


func _add_leg(walker: Node3D, mat: Material, hip: Vector3, size: Vector3) -> Node3D:
	var pivot := Node3D.new()
	pivot.position = hip
	walker.add_child(pivot)
	PixelDioramaStyle.add_box(pivot, size, Vector3(0.0, -size.y * 0.5, 0.0), mat, "Limb")
	return pivot


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


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_light_windows()
	_drive_smoke()
	_walker_accum += delta
	var step := 1.0 / WALKER_HZ
	if _walker_accum >= step:
		_drive_walkers(_walker_accum)
		_walker_accum = 0.0


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


func _drive_walkers(delta: float) -> void:
	for walker in _walkers:
		var node: Node3D = walker["node"]
		if not is_instance_valid(node):
			continue
		var lane: float = walker["lane"]

		var paused: float = walker["paused"]
		if paused > 0.0:
			walker["paused"] = maxf(0.0, paused - delta)
		else:
			walker["pause_in"] = float(walker["pause_in"]) - delta
			if float(walker["pause_in"]) <= 0.0:
				walker["paused"] = randf_range(1.5, 5.0)
				walker["pause_in"] = randf_range(10.0, 34.0)
		var moving := 1.0 if float(walker["paused"]) <= 0.0 else 0.0

		var speed: float = float(walker["speed"]) * moving
		var travelled: float = float(walker["travelled"]) + absf(speed) * delta
		walker["travelled"] = travelled
		var angle: float = float(walker["angle"]) + speed / maxf(lane, 1.0) * delta
		walker["angle"] = angle
		node.position = Vector3(cos(angle) * lane, GROUND_DROP, sin(angle) * lane)
		node.rotation.y = -angle + (PI * 0.5 if speed >= 0.0 else -PI * 0.5)

		var phase := travelled * float(walker["stride"]) * float(walker["gait"])
		var swing := sin(phase)
		var legs: Array = walker["legs"]
		for i in legs.size():
			var leg := legs[i] as Node3D
			if is_instance_valid(leg):
				leg.rotation.x = sin(phase + PI * float(i % 2)) * 0.52 * moving
		var arms: Array = walker["arms"]
		for i in arms.size():
			var arm := arms[i] as Node3D
			if is_instance_valid(arm):
				arm.rotation.x = -sin(phase + PI * float(i % 2)) * 0.38 * moving
		node.position.y += absf(swing) * 0.05 * moving
