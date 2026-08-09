extends RefCounted
class_name PixelDioramaHubStructures


static func build_tent(
	parent: Node3D, mats: Dictionary, params: Dictionary, facing_yaw: float, def: Dictionary
) -> Node3D:
	var width := float(params.get("width", 5.0))
	var depth := float(params.get("depth", 4.2))
	var wall_height := float(params.get("wall_height", 2.2))
	var entrance_width := float(params.get("entrance_width", 1.8))
	var roof_peak := float(params.get("roof_peak", 1.2))

	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	parent.add_child(visuals)
	visuals.rotation.y = facing_yaw

	var fabric_mat: Material = mats.wall
	var pole_mat: Material = mats.wood
	var roof_mat: Material = mats.accent
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thickness := 0.22
	var lip_width := (width - entrance_width) * 0.5
	var lip_z := half_d - wall_thickness * 0.5
	var floor_alt: Material = mats.get("floor_alt", mats.get("floor", pole_mat))

	for raw in def.get("parts", []):
		if not raw is Dictionary:
			continue
		var part: Dictionary = raw
		var mat := _resolve_structure_material(mats, str(part.get("mat", "wall")))
		PixelDioramaStyle.add_box(
			visuals,
			_vec3_from_array(part.get("size"), Vector3.ONE),
			_vec3_from_array(part.get("pos")),
			mat,
			str(part.get("name", ""))
		)

	var column_h := wall_height
	var corner_positions := [
		Vector3(-half_w + 0.22, column_h * 0.5, -half_d + 0.22),
		Vector3(half_w - 0.22, column_h * 0.5, -half_d + 0.22),
		Vector3(-half_w + 0.22, column_h * 0.5, half_d - 0.22),
		Vector3(half_w - 0.22, column_h * 0.5, half_d - 0.22),
	]
	for i in corner_positions.size():
		add_portal_column(
			visuals, corner_positions[i], pole_mat, roof_mat, column_h, 0.48, "Corner%d" % i
		)

	var entrance_z := lip_z - 0.08
	var col_x := entrance_width * 0.5 + 0.22
	add_portal_column(
		visuals,
		Vector3(-col_x, wall_height * 0.5, entrance_z),
		pole_mat,
		roof_mat,
		wall_height,
		0.42,
		"EntryL"
	)
	add_portal_column(
		visuals,
		Vector3(col_x, wall_height * 0.5, entrance_z),
		pole_mat,
		roof_mat,
		wall_height,
		0.42,
		"EntryR"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(entrance_width + 1.1, 0.42, 0.55),
		Vector3(0.0, wall_height + 0.21, entrance_z - 0.12),
		pole_mat,
		"EntryLintel"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(0.28, 0.28, 0.28),
		Vector3(0.0, wall_height + 0.52, entrance_z - 0.1),
		roof_mat,
		"EntryKeystone"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(0.3, wall_height * 0.85, 0.28),
		Vector3(-col_x + 0.35, wall_height * 0.42, entrance_z + 0.12),
		pole_mat,
		"EntryButtressL"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(0.3, wall_height * 0.85, 0.28),
		Vector3(col_x - 0.35, wall_height * 0.42, entrance_z + 0.12),
		pole_mat,
		"EntryButtressR"
	)

	var ridge_y := wall_height + roof_peak
	PixelDioramaStyle.add_box(
		visuals, Vector3(width + 0.42, 0.18, 0.18), Vector3(0.0, ridge_y, 0.0), roof_mat, "Ridge"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.22, 0.08, 0.08),
		Vector3(0.0, ridge_y + 0.1, 0.0),
		pole_mat,
		"RidgeCap"
	)

	var front_slope_len := sqrt(half_d * half_d + roof_peak * roof_peak)
	var front_slope_angle := atan2(roof_peak, half_d)
	var front_roof := PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.25, 0.1, front_slope_len + 0.15),
		Vector3(0.0, wall_height + roof_peak * 0.5, half_d * 0.5),
		fabric_mat,
		"RoofPanelFront"
	)
	front_roof.rotation.x = front_slope_angle
	var back_roof := PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.25, 0.1, front_slope_len + 0.15),
		Vector3(0.0, wall_height + roof_peak * 0.5, -half_d * 0.5),
		fabric_mat,
		"RoofPanelBack"
	)
	back_roof.rotation.x = -front_slope_angle

	var side_slope_len := sqrt(half_w * half_w + roof_peak * roof_peak)
	var side_slope_angle := atan2(roof_peak, half_w)
	var left_roof := PixelDioramaStyle.add_box(
		visuals,
		Vector3(side_slope_len + 0.15, 0.1, depth + 0.25),
		Vector3(-half_w * 0.5, wall_height + roof_peak * 0.5, 0.0),
		fabric_mat,
		"RoofPanelLeft"
	)
	left_roof.rotation.z = side_slope_angle
	var right_roof := PixelDioramaStyle.add_box(
		visuals,
		Vector3(side_slope_len + 0.15, 0.1, depth + 0.25),
		Vector3(half_w * 0.5, wall_height + roof_peak * 0.5, 0.0),
		fabric_mat,
		"RoofPanelRight"
	)
	right_roof.rotation.z = -side_slope_angle

	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.5, 0.14, 0.5),
		Vector3(0.0, 0.38, half_d + 0.18),
		roof_mat,
		"AwningTrim"
	)

	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, -half_d),
		fabric_mat,
		"WallBack"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(-half_w, wall_height * 0.5, 0.0),
		fabric_mat,
		"WallLeft"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(half_w, wall_height * 0.5, 0.0),
		fabric_mat,
		"WallRight"
	)

	if lip_width > 0.15:
		var lip_left_x := -half_w + lip_width * 0.5
		var lip_right_x := half_w - lip_width * 0.5
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(lip_left_x, wall_height * 0.5, lip_z),
			fabric_mat,
			"WallFrontLipL"
		)
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(lip_right_x, wall_height * 0.5, lip_z),
			fabric_mat,
			"WallFrontLipR"
		)

	var flap_h := wall_height * 0.55
	var flap_z := half_d - wall_thickness * 0.35
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(0.12, flap_h, 0.08),
		Vector3(-entrance_width * 0.25, flap_h * 0.5, flap_z),
		fabric_mat,
		"FlapL"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(0.12, flap_h, 0.08),
		Vector3(entrance_width * 0.25, flap_h * 0.5, flap_z),
		fabric_mat,
		"FlapR"
	)

	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.55, 0.12, depth + 0.55),
		Vector3(0.0, 0.06, 0.0),
		floor_alt,
		"TentPad"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.35, 0.08, depth + 0.35),
		Vector3(0.0, 0.14, 0.0),
		roof_mat,
		"TentPadTrim"
	)

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
		Vector3(width, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, -half_d),
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
	if lip_width > 0.15:
		PixelDioramaStyle.add_collision_box(
			collision_root,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(-half_w + lip_width * 0.5, wall_height * 0.5, lip_z),
			"ColFrontLipL"
		)
		PixelDioramaStyle.add_collision_box(
			collision_root,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(half_w - lip_width * 0.5, wall_height * 0.5, lip_z),
			"ColFrontLipR"
		)

	return visuals

static func build_fountain(parent: Node3D, mats: Dictionary, position: Vector3) -> Node3D:
	var fountain := Node3D.new()
	fountain.name = "PlazaFountain"
	fountain.position = position
	parent.add_child(fountain)

	var water_mat := PixelDioramaStyle.make_material(Color(0.42, 0.68, 0.92, 0.85))
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
