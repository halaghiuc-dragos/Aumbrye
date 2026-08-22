extends RefCounted
class_name PixelDioramaHubStructures

## How far up the side of a tent the fabric reaches. Above this the side is open, so the anvil, the
## forge and the shopkeeper standing at them are all visible from the plaza.
const SIDE_SKIRT_RATIO := 0.42

## How far out from the wall a guy rope reaches before it meets its stake. Short enough that the
## stakes stay on the stall's own patch of ground and out of the walking lane in front of it.
const GUY_REACH := 0.95
## Roughly how far apart the roof battens sit. The real spacing is solved per panel so the ribs
## divide the panel evenly instead of leaving a wide gap at one edge.
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

	var fabric_mat: Material = mats.wall
	var pole_mat: Material = mats.wood
	var roof_mat: Material = mats.accent
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thickness := 0.22
	var floor_alt: Material = mats.get("floor_alt", mats.get("floor", pole_mat))

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

	var column_h := wall_height
	var corner_positions := [
		Vector3(-half_w + 0.22, column_h * 0.5, -half_d + 0.22),
		Vector3(half_w - 0.22, column_h * 0.5, -half_d + 0.22),
		Vector3(-half_w + 0.22, column_h * 0.5, half_d - 0.22),
		Vector3(half_w - 0.22, column_h * 0.5, half_d - 0.22),
	]
	for i in corner_positions.size():
		PixelDioramaStyle.add_portal_column(
			visuals, corner_positions[i], pole_mat, roof_mat, column_h, 0.48, "Corner%d" % i
		)

	# No doorway. The front is simply the side of the stall that is open — the two entry posts, the
	# lintel across them, its keystone and the buttresses read as a built door frame, which is a
	# thing a market stall does not have. The roof still lands on the four corner columns, so
	# nothing here was holding it up.

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

	# A market stall, not a house: closed at the back, open at the front, and only skirt-high down
	# the sides. Full-height fabric on three sides plus front lips is what made these read as little
	# buildings — you could not see the forge or the anvil inside one, and an NPC standing at his own
	# workbench was hidden behind a wall he visually clipped through.
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, -half_d),
		fabric_mat,
		"WallBack"
	)
	var skirt_h := wall_height * SIDE_SKIRT_RATIO
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(wall_thickness, skirt_h, depth),
		Vector3(-half_w, skirt_h * 0.5, 0.0),
		fabric_mat,
		"SkirtLeft"
	)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(wall_thickness, skirt_h, depth),
		Vector3(half_w, skirt_h * 0.5, 0.0),
		fabric_mat,
		"SkirtRight"
	)
	# The rail the side fabric hangs from, so the open gap above the skirt reads as deliberate.
	for side in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.1, 0.1, depth),
			Vector3(half_w * side, wall_height - 0.12, 0.0),
			pole_mat,
			"SideRail%s" % ("R" if side > 0.0 else "L")
		)

	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.55, 0.12, depth + 0.55),
		Vector3(0.0, 0.06, 0.0),
		floor_alt,
		"TentPad"
	)

	_add_tent_craft(visuals, pole_mat, roof_mat, width, depth, wall_height, roof_peak)

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
	# Nothing across the front at all: the two front lips used to carry collision with no fabric
	# drawn on them, so the clean opening had invisible walls in its corners.

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


## What turns four fabric planes into something somebody put up.
##
## A tent is canvas held down against the wind, and none of that was on it: no ropes, no stakes,
## nothing under the roof to stretch it over. The silhouette was right and every surface was a
## floating slab.
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

	# Guy ropes down each side, biased toward the back so they never cross the doorway.
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
	# And two off the back corners, which is where the pull actually is.
	for side in [-1.0, 1.0]:
		_add_guy_rope(
			visuals,
			pole_mat,
			Vector3(side * half_w * 0.62, wall_height - 0.1, -half_d),
			Vector3(side * half_w * 0.62, 0.0, -half_d - GUY_REACH),
			"GuyBack%s" % ("R" if side > 0.0 else "L")
		)

	# Battens under the canvas. Parented to the roof panels, so they take the slope for free.
	var front_span := width + 0.25
	for panel_name in ["RoofPanelFront", "RoofPanelBack"]:
		var panel := visuals.get_node_or_null(panel_name) as Node3D
		if panel == null:
			continue
		var slope_len: float = sqrt(half_d * half_d + roof_peak * roof_peak) + 0.15
		_add_battens(panel, pole_mat, front_span, slope_len, true)
	var side_span := depth + 0.25
	for panel_name in ["RoofPanelLeft", "RoofPanelRight"]:
		var panel := visuals.get_node_or_null(panel_name) as Node3D
		if panel == null:
			continue
		var slope_len: float = sqrt(half_w * half_w + roof_peak * roof_peak) + 0.15
		_add_battens(panel, pole_mat, side_span, slope_len, false)

	# A hem along the side and back eaves. The front already has its awning trim.
	for side in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.16, 0.14, depth + 0.25),
			Vector3(side * (half_w + 0.1), wall_height - 0.02, 0.0),
			roof_mat,
			"EaveHem%s" % ("R" if side > 0.0 else "L")
		)
	PixelDioramaStyle.add_box(
		visuals,
		Vector3(width + 0.25, 0.14, 0.16),
		Vector3(0.0, wall_height - 0.02, -(half_d + 0.1)),
		roof_mat,
		"EaveHemBack"
	)


## One rope, plus the peg it is pulling against.
##
## Built as a Y-long box turned onto the line between the two points, because a rope is the one
## thing here that is not axis-aligned and every other primitive in this file is.
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
	# Rotating +Y onto `delta`: about Z for a sideways pull, about X for a backwards one.
	if absf(delta.x) > absf(delta.z):
		rope.rotation.z = atan2(-delta.x, delta.y)
	else:
		rope.rotation.x = atan2(delta.z, delta.y)
	var peg := PixelDioramaStyle.add_box(
		visuals, Vector3(0.1, 0.42, 0.1), to + Vector3(0.0, 0.14, 0.0), mat, node_name + "Peg"
	)
	# Driven in leaning away from the pull, the way a peg is hammered.
	if absf(delta.x) > absf(delta.z):
		peg.rotation.z = signf(delta.x) * 0.32
	else:
		peg.rotation.x = -signf(delta.z) * 0.32


## Ribs across one roof panel, in the panel's own space so they inherit its slope.
##
## `along_x` picks which way the panel runs: the front and back panels are wide in X and sloped
## along Z, the side panels the other way round.
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
