extends RefCounted
class_name PixelDioramaHubStructures

const GUY_REACH := 0.95
const BATTEN_SPACING := 0.95


static func build_tent(
	parent: Node3D, mats: Dictionary, params: Dictionary, facing_yaw: float, def: Dictionary
) -> Node3D:
	var width := float(params.get("width", 5.0))
	var depth := float(params.get("depth", 4.2))
	var wall_height := float(params.get("wall_height", 2.2))
	var roof_peak := float(params.get("roof_peak", 1.2))

	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	parent.add_child(visuals)
	visuals.rotation.y = facing_yaw

	var canvas: Material = mats.get("canvas", mats.wall)
	var canvas_dark: Material = mats.get("canvas_dark", canvas)
	var pole_mat: Material = mats.wood
	var trim_mat: Material = mats.accent
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thickness := 0.16
	var floor_alt: Material = mats.get("floor_alt", mats.get("floor", pole_mat))
	var ridge_y := wall_height + roof_peak

	for raw in def.get("parts", []):
		if not raw is Dictionary:
			continue
		var part: Dictionary = raw
		var mat := PixelDioramaStyle._resolve_structure_material(mats, str(part.get("mat", "wall")))
		PixelDioramaStyle.add_box(
			visuals,
			PixelDioramaStyle._vec3_from_array(part.get("size"), Vector3.ONE),
			PixelDioramaStyle._vec3_from_array(part.get("pos")),
			mat,
			str(part.get("name", ""))
		)

	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.45, 0.12, depth + 0.45),
		Vector3(0.0, 0.06, 0.0),
		floor_alt,
		"TentPad"
	)

	for sx in [-1.0, 1.0]:
		for sz in [-1.0, 1.0]:
			PixelDioramaStyle.add_box(
				visuals,
				Vector3(0.16, wall_height, 0.16),
				Vector3(sx * (half_w - 0.08), wall_height * 0.5, sz * (half_d - 0.08)),
				pole_mat,
				"Pole%s%s" % ["R" if sx > 0.0 else "L", "F" if sz > 0.0 else "B"]
			)
	for sx in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.14, 0.14, depth + 0.3),
			Vector3(sx * half_w, wall_height + 0.05, 0.0),
			pole_mat,
			"Eave%s" % ("R" if sx > 0.0 else "L")
		)
	for sz in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.18, ridge_y, 0.18),
			Vector3(0.0, ridge_y * 0.5, sz * (half_d - 0.1)),
			pole_mat,
			"KingPost%s" % ("F" if sz > 0.0 else "B")
		)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(0.16, 0.16, depth + 0.55),
		Vector3(0.0, ridge_y, 0.0),
		pole_mat,
		"Ridge"
	)

	var slope_len := sqrt(half_w * half_w + roof_peak * roof_peak)
	var slope_angle := atan2(roof_peak, half_w)
	for sx in [-1.0, 1.0]:
		var panel := PixelDioramaStyle.add_box(
			visuals,
			Vector3(slope_len + 0.24, 0.1, depth + 0.5),
			Vector3(sx * half_w * 0.5, wall_height + roof_peak * 0.5, 0.0),
			canvas,
			"RoofPanel%s" % ("R" if sx > 0.0 else "L")
		)
		panel.rotation.z = -sx * slope_angle
		_add_battens(panel, pole_mat, depth + 0.5, slope_len + 0.24, false)
		var stripes := maxi(2, int((depth + 0.5) / 1.15))
		for i in stripes:
			var t := (float(i) + 0.5) / float(stripes)
			PixelDioramaStyle.add_box(
				panel,
				Vector3(slope_len + 0.26, 0.04, 0.34),
				Vector3(0.0, 0.06, -(depth + 0.5) * 0.5 + (depth + 0.5) * t),
				canvas_dark,
				"Stripe%d" % i
			)

	for sx in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(wall_thickness, wall_height, depth),
			Vector3(sx * half_w, wall_height * 0.5, 0.0),
			canvas,
			"Wall%s" % ("R" if sx > 0.0 else "L")
		)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, -half_d),
		canvas,
		"WallBack"
	)
	_add_wall_seams(visuals, canvas_dark, width, wall_height, wall_thickness, half_w, half_d)
	_add_gable(visuals, canvas_dark, width, wall_height, roof_peak, -half_d, wall_thickness, "GableBack")

	for sx in [-1.0, 1.0]:
		var barge := PixelDioramaStyle.add_box(
			visuals,
			Vector3(slope_len + 0.2, 0.16, 0.14),
			Vector3(sx * half_w * 0.5, wall_height + roof_peak * 0.5 + 0.08, half_d + 0.26),
			trim_mat,
			"Barge%s" % ("R" if sx > 0.0 else "L")
		)
		barge.rotation.z = -sx * slope_angle
	var scallops := maxi(3, int(width / 0.62))
	for i in scallops:
		var t := (float(i) + 0.5) / float(scallops)
		var x := -half_w + width * t
		var drop := 0.16 + 0.12 * sin(t * PI)
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(width / float(scallops) * 0.86, drop, 0.1),
			Vector3(x, wall_height - drop * 0.5 + 0.06, half_d + 0.2),
			trim_mat,
			"Valance%d" % i
		)
	for sx in [-1.0, 1.0]:
		var flap := PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.5, wall_height * 0.82, 0.12),
			Vector3(sx * (half_w - 0.32), wall_height * 0.41, half_d - 0.1),
			canvas,
			"Flap%s" % ("R" if sx > 0.0 else "L")
		)
		flap.rotation.y = -sx * 0.42
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.2, 0.1, 0.1),
			Vector3(sx * (half_w - 0.12), wall_height * 0.56, half_d - 0.06),
			pole_mat,
			"FlapTie%s" % ("R" if sx > 0.0 else "L")
		)

	_add_tent_craft(visuals, pole_mat, trim_mat, width, depth, wall_height, roof_peak)

	var collision_root := parent.get_node_or_null("TentCollision") as StaticBody3D
	if collision_root == null:
		collision_root = StaticBody3D.new()
		collision_root.name = "TentCollision"
		parent.add_child(collision_root)
	else:
		for child in collision_root.get_children():
			child.queue_free()
	collision_root.collision_layer = 1
	collision_root.collision_mask = 0
	collision_root.rotation.y = facing_yaw

	PixelDioramaStyle.add_collision_box(
		collision_root,
		Vector3(width, wall_height + roof_peak, wall_thickness),
		Vector3(0.0, (wall_height + roof_peak) * 0.5, -half_d),
		"ColBack"
	)
	PixelDioramaStyle.add_collision_box(
		collision_root,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(-half_w, wall_height * 0.5, 0.0),
		"ColLeft"
	)
	PixelDioramaStyle.add_collision_box(
		collision_root,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(half_w, wall_height * 0.5, 0.0),
		"ColRight"
	)

	return visuals


static func _add_wall_seams(
	parent: Node3D,
	mat: Material,
	width: float,
	wall_height: float,
	thickness: float,
	half_w: float,
	half_d: float
) -> void:
	for sx in [-1.0, 1.0]:
		var seams := maxi(2, int(half_d * 2.0 / 1.15))
		for i in seams:
			var t := (float(i) + 0.5) / float(seams)
			PixelDioramaStyle.add_box(
				parent,
				Vector3(thickness + 0.05, wall_height, 0.1),
				Vector3(sx * half_w, wall_height * 0.5, -half_d + half_d * 2.0 * t),
				mat,
				"Seam%s%d" % ["R" if sx > 0.0 else "L", i]
			)
		PixelDioramaStyle.add_box(
			parent,
			Vector3(thickness + 0.07, 0.12, half_d * 2.0),
			Vector3(sx * half_w, 0.16, 0.0),
			mat,
			"Hem%s" % ("R" if sx > 0.0 else "L")
		)
	var back_seams := maxi(2, int(width / 1.15))
	for i in back_seams:
		var t := (float(i) + 0.5) / float(back_seams)
		PixelDioramaStyle.add_box(
			parent,
			Vector3(0.1, wall_height, thickness + 0.05),
			Vector3(-width * 0.5 + width * t, wall_height * 0.5, -half_d),
			mat,
			"SeamBack%d" % i
		)


static func _add_gable(
	parent: Node3D,
	mat: Material,
	width: float,
	base_y: float,
	peak_h: float,
	z: float,
	thickness: float,
	node_prefix: String
) -> void:
	var steps := 5
	var seg_h := peak_h / float(steps)
	for i in steps:
		var t := float(i) / float(steps)
		var seg_w := width * (1.0 - t) * 0.96
		if seg_w <= 0.05:
			continue
		PixelDioramaStyle.add_box(
			parent,
			Vector3(seg_w, seg_h, thickness),
			Vector3(0.0, base_y + seg_h * (float(i) + 0.5), z),
			mat,
			"%sStep%d" % [node_prefix, i]
		)


static func build_fountain(parent: Node3D, mats: Dictionary, position: Vector3) -> Node3D:
	var fountain := Node3D.new()
	fountain.name = "PlazaFountain"
	fountain.position = position
	parent.add_child(fountain)

	var water_mat := PixelDioramaStyle.make_water_material(Color(0.36, 0.58, 0.82))
	var stone_mat: Material = mats.wall
	var accent_mat: Material = mats.accent

	PixelDioramaStyle.add_cylinder(fountain, 2.35, 2.55, 0.22, Vector3(0.0, 0.11, 0.0), water_mat, "PoolRim")
	PixelDioramaStyle.add_cylinder(fountain, 1.85, 1.95, 0.16, Vector3(0.0, 0.2, 0.0), water_mat, "PoolWater")
	PixelDioramaStyle.add_cylinder(fountain, 0.42, 0.55, 0.95, Vector3(0.0, 0.62, 0.0), stone_mat, "Pedestal")
	PixelDioramaStyle.add_cylinder(fountain, 0.18, 0.24, 0.35, Vector3(0.0, 1.18, 0.0), accent_mat, "Spout")

	var droplet_mesh := _make_fountain_particle_mesh(0.14)
	var droplet_mat := _make_fountain_particle_material(Color(0.55, 0.82, 1.0, 0.9), 1.1)
	var mist_mat := _make_fountain_particle_material(Color(0.78, 0.92, 1.0, 0.45), 0.35)

	var spray := CPUParticles3D.new()
	spray.name = "WaterSpray"
	spray.position = Vector3(0.0, 1.55, 0.0)
	spray.emitting = true
	spray.amount = 88
	spray.lifetime = 1.15
	spray.one_shot = false
	spray.preprocess = 1.0
	spray.explosiveness = 0.12
	spray.randomness = 0.4
	spray.direction = Vector3(0.0, 1.0, 0.0)
	spray.spread = 18.0
	spray.flatness = 0.1
	spray.gravity = Vector3(0.0, -9.8, 0.0)
	spray.initial_velocity_min = 4.8
	spray.initial_velocity_max = 7.2
	spray.scale_amount_min = 0.1
	spray.scale_amount_max = 0.2
	spray.color = Color(0.62, 0.86, 1.0, 0.92)
	spray.mesh = droplet_mesh
	spray.material_override = droplet_mat
	spray.visibility_aabb = AABB(Vector3(-2.5, -2.0, -2.5), Vector3(5.0, 7.5, 5.0))
	fountain.add_child(spray)

	var fall := CPUParticles3D.new()
	fall.name = "WaterFall"
	fall.position = Vector3(0.0, 1.85, 0.0)
	fall.emitting = true
	fall.amount = 64
	fall.lifetime = 1.35
	fall.one_shot = false
	fall.preprocess = 1.0
	fall.explosiveness = 0.08
	fall.randomness = 0.55
	fall.direction = Vector3(0.0, 1.0, 0.0)
	fall.spread = 42.0
	fall.flatness = 0.3
	fall.gravity = Vector3(0.0, -12.0, 0.0)
	fall.initial_velocity_min = 2.8
	fall.initial_velocity_max = 5.2
	fall.scale_amount_min = 0.07
	fall.scale_amount_max = 0.14
	fall.color = Color(0.48, 0.74, 0.98, 0.82)
	fall.mesh = droplet_mesh
	fall.material_override = droplet_mat
	fall.visibility_aabb = AABB(Vector3(-2.5, -2.0, -2.5), Vector3(5.0, 7.5, 5.0))
	fountain.add_child(fall)

	var mist := CPUParticles3D.new()
	mist.name = "WaterMist"
	mist.position = Vector3(0.0, 1.25, 0.0)
	mist.emitting = true
	mist.amount = 32
	mist.lifetime = 1.35
	mist.one_shot = false
	mist.preprocess = 0.8
	mist.direction = Vector3(0.0, 1.0, 0.0)
	mist.spread = 55.0
	mist.flatness = 0.5
	mist.gravity = Vector3(0.0, -3.5, 0.0)
	mist.initial_velocity_min = 0.5
	mist.initial_velocity_max = 1.6
	mist.scale_amount_min = 0.16
	mist.scale_amount_max = 0.28
	mist.color = Color(0.85, 0.94, 1.0, 0.4)
	mist.mesh = _make_fountain_particle_mesh(0.22)
	mist.material_override = mist_mat
	mist.visibility_aabb = AABB(Vector3(-2.5, -2.0, -2.5), Vector3(5.0, 7.5, 5.0))
	fountain.add_child(mist)

	var glow := OmniLight3D.new()
	glow.name = "WaterGlow"
	glow.light_color = Color(0.62, 0.82, 1.0)
	glow.light_energy = 0.42
	glow.omni_range = 3.2
	glow.position = Vector3(0.0, 0.85, 0.0)
	fountain.add_child(glow)
	AudioDirector.attach_loop_emitter(fountain, "fountain", 8.0)

	return fountain


static func _make_fountain_particle_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 4
	return mesh


static func _make_fountain_particle_material(
	color: Color, emission_energy: float
) -> ShaderMaterial:
	var mat := PixelDioramaStyle.make_glow_material(color, color.darkened(0.18), emission_energy)
	PixelDioramaStyle.set_authored_param(mat, "color_core", color)
	PixelDioramaStyle.set_authored_param(mat, "color_edge", color.darkened(0.18))
	return PixelDioramaSettings.track(mat)


static func _add_tent_craft(
	visuals: Node3D,
	pole_mat: Material,
	roof_mat: Material,
	width: float,
	depth: float,
	wall_height: float,
	roof_peak: float
) -> void:
	var half_w := width * 0.5
	var half_d := depth * 0.5

	for side in [-1.0, 1.0]:
		for i in 2:
			var z := -half_d * 0.62 + float(i) * half_d * 0.78
			_add_guy_rope(
				visuals,
				pole_mat,
				Vector3(side * half_w, wall_height - 0.1, z),
				Vector3(side * (half_w + GUY_REACH), 0.0, z),
				"Guy%s%d" % ["R" if side > 0.0 else "L", i]
			)
	for side in [-1.0, 1.0]:
		_add_guy_rope(
			visuals,
			pole_mat,
			Vector3(side * half_w * 0.62, wall_height + roof_peak * 0.5, -half_d),
			Vector3(side * half_w * 0.62, 0.0, -half_d - GUY_REACH),
			"GuyBack%s" % ("R" if side > 0.0 else "L")
		)

	for side in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.16, 0.14, depth + 0.5),
			Vector3(side * (half_w + 0.12), wall_height - 0.02, 0.0),
			roof_mat,
			"EaveHem%s" % ("R" if side > 0.0 else "L")
		)
	for sz in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.2, 0.28, 0.2),
			Vector3(0.0, wall_height + roof_peak + 0.2, sz * (half_d + 0.24)),
			roof_mat,
			"Finial%s" % ("F" if sz > 0.0 else "B")
		)


static func _add_guy_rope(
	visuals: Node3D, mat: Material, from: Vector3, to: Vector3, node_name: String
) -> void:
	var delta := to - from
	var length := delta.length()
	if length < 0.05:
		return
	var rope := PixelDioramaStyle.add_box(
		visuals, Vector3(0.07, length, 0.07), (from + to) * 0.5, mat, node_name
	)
	if absf(delta.x) > absf(delta.z):
		rope.rotation.z = atan2(-delta.x, delta.y)
	else:
		rope.rotation.x = atan2(delta.z, delta.y)
	var peg := PixelDioramaStyle.add_box(
		visuals, Vector3(0.1, 0.42, 0.1), to + Vector3(0.0, 0.14, 0.0), mat, node_name + "Peg"
	)
	if absf(delta.x) > absf(delta.z):
		peg.rotation.z = signf(delta.x) * 0.32
	else:
		peg.rotation.x = -signf(delta.z) * 0.32


static func _add_battens(
	panel: Node3D, mat: Material, span: float, slope_len: float, along_x: bool
) -> void:
	var count := maxi(2, int(round(span / BATTEN_SPACING)) - 1)
	for i in count:
		var t := float(i + 1) / float(count + 1)
		var offset := -span * 0.5 + span * t
		var size := (
			Vector3(0.09, 0.07, slope_len) if along_x else Vector3(slope_len, 0.07, 0.09)
		)
		var pos := (
			Vector3(offset, -0.07, 0.0) if along_x else Vector3(0.0, -0.07, offset)
		)
		PixelDioramaStyle.add_box(panel, size, pos, mat, "Batten%d" % i)
