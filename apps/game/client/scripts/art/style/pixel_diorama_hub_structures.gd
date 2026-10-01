extends RefCounted
class_name PixelDioramaHubStructures

static func build_tent(
	parent: Node3D, mats: Dictionary, params: Dictionary, facing_yaw: float, _def: Dictionary
) -> Node3D:
	var width := float(params.get("width", 5.0))
	var depth := float(params.get("depth", 4.2))
	var wall_height := float(params.get("wall_height", 2.2))
	var roof_peak := float(params.get("roof_peak", 1.2))

	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	parent.add_child(visuals)
	visuals.rotation.y = facing_yaw
	# One Blender model per tent size (tools/blender/props_hub_tents.py).
	PropLibrary.attach_themed(
		visuals,
		"hub/tent_%d_%d_%d_%d" % [roundi(width * 100.0), roundi(depth * 100.0), roundi(wall_height * 100.0), roundi(roof_peak * 100.0)],
		PixelDioramaStyle.PaletteTheme.HUB,
		{"materials": mats}
	)
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thickness := 0.16

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


static func build_fountain(parent: Node3D, mats: Dictionary, position: Vector3) -> Node3D:
	var fountain := Node3D.new()
	fountain.name = "PlazaFountain"
	fountain.position = position
	parent.add_child(fountain)

	PropLibrary.attach_themed(
		fountain, "hub/fountain", PixelDioramaStyle.PaletteTheme.HUB, {"materials": mats}
	)

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


static func _make_fountain_particle_mesh(radius: float) -> Mesh:
	return PropLibrary.scaled_mesh("fx/droplet", Vector3.ONE * radius)


static func _make_fountain_particle_material(
	color: Color, emission_energy: float
) -> ShaderMaterial:
	var mat := PixelDioramaStyle.make_glow_material(color, color.darkened(0.18), emission_energy)
	PixelDioramaStyle.set_authored_param(mat, "color_core", color)
	PixelDioramaStyle.set_authored_param(mat, "color_edge", color.darkened(0.18))
	return PixelDioramaSettings.track(mat)


