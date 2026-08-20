extends RefCounted
class_name DioramaRoomDressing

## Procedural pixel-diorama props spawned at runtime per biome + room template.

const ROOM_SUFFIXES := [
	"entrance",
	"stairs",
	"courtyard",
	"hall",
	"treasure",
	"secret",
	"arena",
	"boss",
	"puzzle",
]

## How much of a prop's shortest side is taken off each corner.
const PROP_BEVEL_RATIO := 0.16

static var _shadow_omni_budget: int = 0
static var _max_shadow_omnis: int = 2
static var _torch_flicker: Dictionary = {}


static func apply_to_room(room: RoomTemplate, biome_id: String, room_seed: int = 0) -> void:
	var blockout := room.get_blockout()
	if blockout == null:
		return
	var prop_rng := RandomNumberGenerator.new()
	prop_rng.seed = room_seed if room_seed != 0 else room.room_id.hash()
	var props := _ensure_props_root(room)
	if props.get_node_or_null("DioramaDressing") != null:
		return
	var dressing := Node3D.new()
	dressing.name = "DioramaDressing"
	props.add_child(dressing)
	var suffix := _room_suffix(room.template_id)
	var floor_mat := BiomeRegistry.get_floor_material(biome_id)
	var wall_mat := BiomeRegistry.get_wall_material(biome_id)
	var accent_mat := BiomeRegistry.get_accent_material(biome_id)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	if room.room_type == "obstacle":
		_spawn_obstacle_course(dressing, half_w, half_d, floor_mat, wall_mat, accent_mat, biome_id)
		return
	match suffix:
		"entrance":
			_spawn_entrance(dressing, half_w, half_d, wall_mat, accent_mat, biome_id)
		"boss":
			_spawn_boss(dressing, half_w, half_d, wall_mat, accent_mat, biome_id)
		"courtyard":
			_spawn_courtyard(dressing, half_w, half_d, floor_mat, accent_mat, biome_id)
		"hall":
			_spawn_hall(dressing, half_w, half_d, wall_mat, accent_mat, biome_id)
		"treasure":
			_spawn_treasure(dressing, accent_mat, biome_id)
		"secret":
			_spawn_secret(dressing, half_w, half_d, accent_mat, biome_id)
		"stairs":
			_spawn_stairs(dressing, half_w, half_d, accent_mat, biome_id)
		"arena":
			_spawn_arena(dressing, half_w, half_d, wall_mat, accent_mat, biome_id)
		"puzzle":
			_spawn_puzzle(dressing, accent_mat, biome_id)
		_:
			_spawn_generic_corners(dressing, half_w, half_d, accent_mat, biome_id, prop_rng)
	# C-195: `prop_rng` was created, seeded from the room seed, and passed to exactly **one** of the
	# ten branches — so nine of ten room kinds placed identical props at identical positions on
	# every seed, forever. A dungeon whose layout is procedural and whose rooms are pixel-identical
	# between runs reads as a rebuilt corridor rather than a new place.
	#
	# Rather than rewrite nine spawn functions, the variation is applied to what they produced:
	# a small seeded yaw and ground offset per free-standing prop. Wall-anchored and lighting props
	# are exempt by name — a sconce that drifts off its wall is worse than a sconce that repeats.
	_apply_seeded_prop_variation(dressing, prop_rng)


## C-195: props that must not move — anything mounted to a surface, and anything that carries a
## light, since both read as broken the moment they drift.
const VARIATION_EXEMPT_TOKENS := [
	"Torch", "Sconce", "Light", "Wall", "Pillar", "Column", "Door", "Stair", "Altar", "Banner"
]

const VARIATION_YAW_DEGREES := 9.0
const VARIATION_OFFSET := 0.16


static func _apply_seeded_prop_variation(
	dressing: Node3D, prop_rng: RandomNumberGenerator
) -> void:
	if dressing == null or prop_rng == null:
		return
	for child in dressing.get_children():
		var prop := child as Node3D
		if prop == null:
			continue
		var exempt := false
		for token in VARIATION_EXEMPT_TOKENS:
			if prop.name.contains(token):
				exempt = true
				break
		if exempt:
			continue
		prop.rotation.y += deg_to_rad(
			prop_rng.randf_range(-VARIATION_YAW_DEGREES, VARIATION_YAW_DEGREES)
		)
		prop.position.x += prop_rng.randf_range(-VARIATION_OFFSET, VARIATION_OFFSET)
		prop.position.z += prop_rng.randf_range(-VARIATION_OFFSET, VARIATION_OFFSET)


static func apply_to_waves_arena(
	parent: Node3D, biome_id: String = BiomeRegistry.BIOME_UMBRAL
) -> void:
	if parent.get_node_or_null("DioramaDressing") != null:
		return
	var dressing := Node3D.new()
	dressing.name = "DioramaDressing"
	parent.add_child(dressing)
	var accent_mat := BiomeRegistry.get_accent_material(biome_id)
	var wall_mat := BiomeRegistry.get_wall_material(biome_id)
	var half := 18.0
	_spawn_corner_pillar(dressing, Vector3(-half, 0.0, -half), wall_mat, 2.4)
	_spawn_corner_pillar(dressing, Vector3(half, 0.0, -half), wall_mat, 2.4)
	_spawn_corner_pillar(dressing, Vector3(-half, 0.0, half), wall_mat, 2.4)
	_spawn_corner_pillar(dressing, Vector3(half, 0.0, half), wall_mat, 2.4)
	_spawn_brazier(dressing, Vector3(-6.0, 0.0, -half + 1.5), accent_mat, biome_id, 0.55)
	_spawn_brazier(dressing, Vector3(6.0, 0.0, -half + 1.5), accent_mat, biome_id, 0.55)
	_spawn_brazier(dressing, Vector3(-6.0, 0.0, half - 1.5), accent_mat, biome_id, 0.55)
	_spawn_brazier(dressing, Vector3(6.0, 0.0, half - 1.5), accent_mat, biome_id, 0.55)
	_add_biome_banner(dressing, Vector3(0.0, 0.0, -half + 0.8), accent_mat, 3.2, 1.6)


static func apply_ceiling_lighting(
	room: RoomTemplate, biome_id: String, lighting_role: String = ""
) -> void:
	_begin_room_torch_pass(biome_id)
	var blockout := room.get_blockout()
	if blockout == null:
		return
	var props := _ensure_props_root(room)
	if props.get_node_or_null("CeilingLighting") != null:
		return
	var lights := Node3D.new()
	lights.name = "CeilingLighting"
	props.add_child(lights)
	var accent_mat := BiomeRegistry.get_accent_material(biome_id)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	var torch_y := CastleRoomConstants.WALL_HEIGHT - 0.35
	var spacing_scale := 1.0
	match lighting_role:
		"trap", "hazard":
			spacing_scale = 1.35
		"boss":
			spacing_scale = 0.85
		"empty", "rest":
			spacing_scale = 0.75
	var spacing := clampf(
		minf(blockout.room_width, blockout.room_depth) * 0.52 * spacing_scale, 6.0, 8.5
	)
	var x := -half_w + spacing
	while x <= half_w - 1.0:
		var z := -half_d + spacing
		while z <= half_d - 1.0:
			_spawn_ceiling_torch(lights, Vector3(x, torch_y, z), accent_mat, biome_id)
			z += spacing
		x += spacing
	_spawn_wall_midpoint_torches(lights, half_w, half_d, accent_mat, biome_id)
	_spawn_room_center_fill(lights, half_w, half_d, biome_id)


## Validation fixture: hall torch pass without a RoomTemplate.
static func spawn_hall_torches_fixture(
	parent: Node3D, biome_id: String, half_w: float, half_d: float
) -> void:
	_begin_room_torch_pass(biome_id)
	var accent_mat := BiomeRegistry.get_accent_material(biome_id)
	var torch_y := CastleRoomConstants.WALL_HEIGHT - 0.35
	_spawn_ceiling_torch(parent, Vector3(0.0, torch_y, 0.0), accent_mat, biome_id)
	_spawn_ceiling_torch(parent, Vector3(-4.0, torch_y, 0.0), accent_mat, biome_id)
	_spawn_ceiling_torch(parent, Vector3(4.0, torch_y, 0.0), accent_mat, biome_id)
	_spawn_wall_midpoint_torches(parent, half_w, half_d, accent_mat, biome_id)


static func _spawn_wall_midpoint_torches(
	parent: Node3D, half_w: float, half_d: float, accent_mat: Material, biome_id: String
) -> void:
	var wall_y := CastleRoomConstants.WALL_HEIGHT * 0.5
	var inset := 0.55
	_spawn_wall_torch(parent, Vector3(0.0, wall_y, -half_d + inset), accent_mat, biome_id)
	_spawn_wall_torch(parent, Vector3(0.0, wall_y, half_d - inset), accent_mat, biome_id)
	_spawn_wall_torch(parent, Vector3(-half_w + inset, wall_y, 0.0), accent_mat, biome_id)
	_spawn_wall_torch(parent, Vector3(half_w - inset, wall_y, 0.0), accent_mat, biome_id)


static func _spawn_room_center_fill(
	parent: Node3D, half_w: float, half_d: float, biome_id: String
) -> void:
	var light := OmniLight3D.new()
	light.name = "RoomCenterFill"
	light.position = Vector3(0.0, CastleRoomConstants.WALL_HEIGHT * 0.42, 0.0)
	VisualLighting.configure_soft_omni(
		light,
		_biome_light_color(biome_id).lerp(Color(0.92, 0.86, 0.78), 0.35),
		VisualLighting.ROOM_FILL_ENERGY,
		maxf(minf(half_w, half_d) * 1.75, 9.0),
		false
	)
	parent.add_child(light)


static func apply_shell_lighting(shell: Node3D, bounds: AABB, biome_id: String) -> void:
	if shell.get_node_or_null("ShellLighting") != null:
		return
	_begin_room_torch_pass(biome_id)
	var lights := Node3D.new()
	lights.name = "ShellLighting"
	shell.add_child(lights)
	var accent_mat := BiomeRegistry.get_accent_material(biome_id)
	var spacing := VisualLighting.SHELL_TORCH_SPACING
	var torch_y := CastleRoomConstants.WALL_HEIGHT - 0.4
	var min_x := bounds.position.x + spacing * 0.5
	var min_z := bounds.position.z + spacing * 0.5
	var max_x := bounds.position.x + bounds.size.x - spacing * 0.5
	var max_z := bounds.position.z + bounds.size.z - spacing * 0.5
	var x := min_x
	while x <= max_x:
		var z := min_z
		while z <= max_z:
			_spawn_ceiling_torch(lights, Vector3(x, torch_y, z), accent_mat, biome_id)
			z += spacing
		x += spacing


static func apply_arena_ceiling_lighting(
	parent: Node3D, half_extent: float, biome_id: String
) -> void:
	if parent.get_node_or_null("CeilingLighting") != null:
		return
	var lights := Node3D.new()
	lights.name = "CeilingLighting"
	parent.add_child(lights)
	var accent_mat := BiomeRegistry.get_accent_material(biome_id)
	var torch_y := CastleRoomConstants.WALL_HEIGHT - 0.35
	var inset := 2.5
	_spawn_ceiling_torch(
		lights, Vector3(-half_extent + inset, torch_y, -half_extent + inset), accent_mat, biome_id
	)
	_spawn_ceiling_torch(
		lights, Vector3(half_extent - inset, torch_y, -half_extent + inset), accent_mat, biome_id
	)
	_spawn_ceiling_torch(
		lights, Vector3(-half_extent + inset, torch_y, half_extent - inset), accent_mat, biome_id
	)
	_spawn_ceiling_torch(
		lights, Vector3(half_extent - inset, torch_y, half_extent - inset), accent_mat, biome_id
	)
	_spawn_ceiling_torch(lights, Vector3(0.0, torch_y, 0.0), accent_mat, biome_id)


static func _ensure_props_root(room: RoomTemplate) -> Node3D:
	var props := room.get_node_or_null("Props") as Node3D
	if props == null:
		props = Node3D.new()
		props.name = "Props"
		room.add_child(props)
	return props


static func _room_suffix(template_id: String) -> String:
	for suffix in ROOM_SUFFIXES:
		if template_id.ends_with("_%s" % suffix):
			return suffix
	return ""


static func _spawn_entrance(
	parent: Node3D,
	half_w: float,
	half_d: float,
	wall_mat: Material,
	accent_mat: Material,
	biome_id: String
) -> void:
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.0, 0.0, -half_d + 1.2), wall_mat, 2.8)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.0, 0.0, -half_d + 1.2), wall_mat, 2.8)
	_spawn_brazier(parent, Vector3(-half_w + 2.2, 0.0, half_d - 1.5), accent_mat, biome_id)
	_spawn_brazier(parent, Vector3(half_w - 2.2, 0.0, half_d - 1.5), accent_mat, biome_id)
	_add_biome_banner(parent, Vector3(0.0, 0.0, -half_d + 0.6), accent_mat, 2.4, 1.2)


static func _spawn_boss(
	parent: Node3D,
	half_w: float,
	half_d: float,
	wall_mat: Material,
	accent_mat: Material,
	biome_id: String
) -> void:
	_add_box(
		parent,
		Vector3(0.0, 0.08, half_d - 2.5),
		Vector3(half_w * 1.4, 0.16, 2.0),
		accent_mat,
		"BossPlatform"
	)
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.2, 0.0, -half_d + 1.2), wall_mat, 3.2)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.2, 0.0, -half_d + 1.2), wall_mat, 3.2)
	_spawn_brazier(parent, Vector3(-half_w + 2.0, 0.0, half_d - 1.8), accent_mat, biome_id, 0.7)
	_spawn_brazier(parent, Vector3(half_w - 2.0, 0.0, half_d - 1.8), accent_mat, biome_id, 0.7)
	_add_spot(parent, Vector3(0.0, 4.5, half_d - 2.5), accent_mat, 1.2, biome_id)


static func _spawn_courtyard(
	parent: Node3D,
	half_w: float,
	half_d: float,
	floor_mat: Material,
	accent_mat: Material,
	biome_id: String
) -> void:
	_spawn_prop_cluster(
		parent, Vector3(-half_w + 2.0, 0.0, -half_d + 2.0), floor_mat, accent_mat, biome_id, 0
	)
	_spawn_prop_cluster(
		parent, Vector3(half_w - 2.0, 0.0, -half_d + 2.0), floor_mat, accent_mat, biome_id, 1
	)
	_spawn_prop_cluster(
		parent, Vector3(-half_w + 2.0, 0.0, half_d - 2.0), floor_mat, accent_mat, biome_id, 2
	)
	_spawn_prop_cluster(
		parent, Vector3(half_w - 2.0, 0.0, half_d - 2.0), floor_mat, accent_mat, biome_id, 3
	)
	_add_box(parent, Vector3(0.0, 0.05, 0.0), Vector3(2.5, 0.1, 2.5), accent_mat, "CenterPlinth")


static func _spawn_hall(
	parent: Node3D,
	half_w: float,
	half_d: float,
	wall_mat: Material,
	accent_mat: Material,
	biome_id: String
) -> void:
	var z := -half_d + 2.0
	while z <= half_d - 2.0:
		_spawn_wall_sconce(parent, Vector3(-half_w + 0.5, 1.4, z), accent_mat, biome_id)
		_spawn_wall_sconce(parent, Vector3(half_w - 0.5, 1.4, z), accent_mat, biome_id)
		z += 3.5
	_spawn_corner_pillar(parent, Vector3(-half_w + 0.8, 0.0, 0.0), wall_mat, 2.6)
	_spawn_corner_pillar(parent, Vector3(half_w - 0.8, 0.0, 0.0), wall_mat, 2.6)


static func _spawn_treasure(parent: Node3D, accent_mat: Material, biome_id: String) -> void:
	_add_box(parent, Vector3(0.0, 0.25, 1.5), Vector3(1.6, 0.5, 1.2), accent_mat, "Pedestal")
	_add_spot(parent, Vector3(0.0, 2.5, 1.5), accent_mat, 0.65, biome_id)


static func _spawn_secret(
	parent: Node3D, half_w: float, _half_d: float, accent_mat: Material, biome_id: String
) -> void:
	_add_box(
		parent, Vector3(-half_w + 0.6, 1.2, 0.0), Vector3(0.35, 2.4, 2.2), accent_mat, "SecretPanel"
	)
	_add_spot(parent, Vector3(-half_w + 1.0, 2.0, 0.0), accent_mat, 0.4, biome_id)


static func _spawn_stairs(
	parent: Node3D, half_w: float, half_d: float, accent_mat: Material, biome_id: String
) -> void:
	if parent.get_parent() != null and parent.get_parent().get_node_or_null("StairRamp") != null:
		return
	_add_box(
		parent,
		Vector3(0.0, 0.35, half_d - 2.0),
		Vector3(half_w * 0.5, 0.7, 3.0),
		accent_mat,
		"StairRampAccent"
	)
	_spawn_wall_sconce(parent, Vector3(-half_w + 0.5, 1.6, 0.0), accent_mat, biome_id)
	_spawn_wall_sconce(parent, Vector3(half_w - 0.5, 1.6, 0.0), accent_mat, biome_id)


static func _spawn_arena(
	parent: Node3D,
	half_w: float,
	half_d: float,
	wall_mat: Material,
	accent_mat: Material,
	biome_id: String
) -> void:
	_add_box(
		parent,
		Vector3(0.0, 0.04, 0.0),
		Vector3(half_w * 1.2, 0.08, half_d * 1.2),
		accent_mat,
		"ArenaRing"
	)
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.0, 0.0, -half_d + 1.0), wall_mat, 2.2)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.0, 0.0, -half_d + 1.0), wall_mat, 2.2)
	_spawn_brazier(parent, Vector3(0.0, 0.0, -half_d + 1.5), accent_mat, biome_id, 0.5)


static func _spawn_puzzle(parent: Node3D, accent_mat: Material, biome_id: String) -> void:
	_add_box(parent, Vector3(0.0, 0.5, 0.0), Vector3(1.2, 1.0, 1.2), accent_mat, "PuzzleCore")
	for i in 4:
		var angle := float(i) / 4.0 * TAU
		_add_box(
			parent,
			Vector3(cos(angle) * 2.5, 0.2, sin(angle) * 2.5),
			Vector3(0.6, 0.4, 0.6),
			accent_mat,
			"PuzzleOrb_%d" % i
		)
	_spawn_brazier(parent, Vector3(0.0, 0.0, 2.8), accent_mat, biome_id, 0.45)


static func _spawn_obstacle_course(
	parent: Node3D,
	half_w: float,
	half_d: float,
	floor_mat: Material,
	wall_mat: Material,
	accent_mat: Material,
	biome_id: String
) -> void:
	# Raised platforms (jump), narrow gaps (dash), and low barriers.
	_add_obstacle_block(
		parent, Vector3(-3.5, 0.55, -1.0), Vector3(2.8, 1.1, 2.8), floor_mat, "ObstaclePlatformA"
	)
	_add_obstacle_block(
		parent, Vector3(3.5, 0.9, 1.5), Vector3(2.4, 1.8, 2.4), floor_mat, "ObstaclePlatformB"
	)
	_add_obstacle_block(
		parent,
		Vector3(0.0, 0.35, half_d - 3.0),
		Vector3(half_w * 0.55, 0.7, 1.2),
		wall_mat,
		"ObstacleLowWall"
	)
	_add_obstacle_block(
		parent,
		Vector3(-half_w + 2.2, 0.75, 0.0),
		Vector3(1.0, 1.5, half_d * 0.45),
		wall_mat,
		"ObstacleDividerL"
	)
	_add_obstacle_block(
		parent,
		Vector3(half_w - 2.2, 0.75, 0.0),
		Vector3(1.0, 1.5, half_d * 0.45),
		wall_mat,
		"ObstacleDividerR"
	)
	_add_obstacle_block(
		parent,
		Vector3(0.0, 0.25, -half_d + 2.5),
		Vector3(1.6, 0.5, 1.6),
		accent_mat,
		"ObstacleDashPillar"
	)
	_spawn_brazier(parent, Vector3(-half_w + 1.8, 0.0, half_d - 1.8), accent_mat, biome_id, 0.5)
	_spawn_brazier(parent, Vector3(half_w - 1.8, 0.0, half_d - 1.8), accent_mat, biome_id, 0.5)


static func _spawn_generic_corners(
	parent: Node3D,
	half_w: float,
	half_d: float,
	accent_mat: Material,
	biome_id: String,
	prop_rng: RandomNumberGenerator = null
) -> void:
	var jitter_a := 0.0
	var jitter_b := 0.0
	if prop_rng != null:
		jitter_a = prop_rng.randf_range(-0.8, 0.8)
		jitter_b = prop_rng.randf_range(-0.8, 0.8)
	_spawn_brazier(
		parent,
		Vector3(-half_w + 1.5 + jitter_a, 0.0, -half_d + 1.5 + jitter_b),
		accent_mat,
		biome_id,
		0.4
	)
	_spawn_brazier(
		parent,
		Vector3(half_w - 1.5 - jitter_b, 0.0, half_d - 1.5 - jitter_a),
		accent_mat,
		biome_id,
		0.4
	)


static func _spawn_corner_pillar(
	parent: Node3D, pos: Vector3, mat: Material, height: float
) -> void:
	_add_box(
		parent, pos + Vector3(0.0, height * 0.5, 0.0), Vector3(0.7, height, 0.7), mat, "Pillar"
	)


static func _spawn_brazier(
	parent: Node3D, pos: Vector3, accent_mat: Material, biome_id: String, energy: float = 0.7
) -> void:
	var brazier := Node3D.new()
	brazier.name = "Brazier"
	brazier.position = pos
	parent.add_child(brazier)
	_add_box(brazier, Vector3(0.0, 0.35, 0.0), Vector3(0.45, 0.7, 0.45), accent_mat, "BrazierMesh")
	var light := OmniLight3D.new()
	light.name = "BrazierLight"
	light.position = Vector3(0.0, 1.1, 0.0)
	_configure_torch_light(light, _biome_light_color(biome_id), energy, 9.0, brazier)
	AudioDirector.attach_loop_emitter(brazier, "brazier", 6.0)


static func _spawn_wall_sconce(
	parent: Node3D, pos: Vector3, accent_mat: Material, biome_id: String
) -> void:
	# C-197: this drew a 0.25 x 0.5 x 0.35 box and then `_spawn_wall_torch` drew a 0.22 x 0.42 x 0.28
	# box at the **same position** — fully enclosed by the first, never visible, and carrying its own
	# bevelled mesh, material override and draw call. Where a torch is spawned it *is* the sconce;
	# the bracket box is only needed when there is no torch to stand in for it.
	if biome_id != "":
		_spawn_wall_torch(parent, pos, accent_mat, biome_id)
		return
	_add_box(parent, pos, Vector3(0.25, 0.5, 0.35), accent_mat, "Sconce")


static func _spawn_wall_torch(
	parent: Node3D, pos: Vector3, accent_mat: Material, biome_id: String
) -> void:
	_add_box(parent, pos, Vector3(0.22, 0.42, 0.28), accent_mat, "WallTorch")
	var light := OmniLight3D.new()
	light.name = "WallTorchLight"
	light.position = pos + Vector3(0.0, 0.05, 0.0)
	_configure_torch_light(
		light,
		_biome_light_color(biome_id),
		VisualLighting.WALL_TORCH_ENERGY,
		VisualLighting.WALL_TORCH_RANGE,
		parent
	)
	_add_torch_embers(parent, pos + Vector3(0.0, 0.16, 0.0), _biome_light_color(biome_id))


static func _spawn_ceiling_torch(
	parent: Node3D, pos: Vector3, accent_mat: Material, biome_id: String
) -> void:
	_add_box(parent, pos, Vector3(0.35, 0.25, 0.35), accent_mat, "CeilingTorch")
	var light := OmniLight3D.new()
	light.name = "CeilingTorchOmni"
	light.position = pos + Vector3(0.0, -0.18, 0.0)
	_configure_torch_light(
		light,
		_biome_light_color(biome_id),
		VisualLighting.TORCH_OMNI_ENERGY,
		VisualLighting.TORCH_OMNI_RANGE,
		parent
	)
	_add_torch_embers(parent, pos + Vector3(0.0, -0.1, 0.0), _biome_light_color(biome_id))


## Rising embers over a torch.
##
## A torch was a lit box: the flicker on the light was the only thing saying it was on fire. A
## handful of embers costs one emitter per torch and is what makes a corridor of them read as a
## living space rather than a corridor of lamps.
##
## Deliberately small. A dungeon floor can hold a couple of dozen torches, so the count per
## emitter is what keeps the total sane — and the whole thing sits behind the particle-quality
## setting, which zeroes it on the lowest tier.
const TORCH_EMBER_COUNT := 7


## C-196: this built a BoxMesh, ParticleProcessMaterial, Gradient, GradientTexture1D and
## StandardMaterial3D per torch. A floor carries 36-44 torches (C-176), so ~200 resources were
## allocated where ten would do — and because every emitter got its own StandardMaterial3D, none of
## them batched. Everything except the tint is identical, and within a floor the tint is identical
## too, so the whole set is cached by tint.
static var _ember_cache: Dictionary = {}


static func clear_ember_cache() -> void:
	_ember_cache.clear()


static func _ember_assets(tint: Color) -> Dictionary:
	var key := tint.to_html(false)
	if _ember_cache.has(key):
		return _ember_cache[key]
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.05, 0.05, 0.05)
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_SPHERE
	mat.emission_sphere_radius = 0.11
	mat.direction = Vector3(0.0, 1.0, 0.0)
	mat.spread = 22.0
	mat.initial_velocity_min = 0.35
	mat.initial_velocity_max = 0.85
	# Slight upward gravity: embers ride the heat rather than falling back.
	mat.gravity = Vector3(0.0, 0.28, 0.0)
	mat.damping_min = 0.2
	mat.damping_max = 0.6
	mat.scale_min = 0.5
	mat.scale_max = 1.1
	# Fade from the flame's own colour out to nothing as they cool.
	var ramp := Gradient.new()
	ramp.set_color(0, Color(tint.r, tint.g, tint.b, 0.95))
	ramp.set_color(1, Color(tint.r * 0.6, tint.g * 0.25, tint.b * 0.1, 0.0))
	var ramp_tex := GradientTexture1D.new()
	ramp_tex.gradient = ramp
	mat.color_ramp = ramp_tex
	# A plain unshaded material that takes its colour from the particle, not the diorama surface
	# shader: that shader reads a world-space pattern and has no notion of per-particle colour, so
	# the ramp above would never reach the screen through it.
	var ember_mat := StandardMaterial3D.new()
	ember_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ember_mat.vertex_color_use_as_albedo = true
	ember_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ember_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	ember_mat.disable_receive_shadows = true
	ember_mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	chunk.material = ember_mat
	var assets := {"mesh": chunk, "process": mat}
	_ember_cache[key] = assets
	return assets


static func _add_torch_embers(parent: Node3D, pos: Vector3, tint: Color) -> void:
	if PixelDioramaSettings.particle_quality <= 0:
		return
	var assets := _ember_assets(tint)
	var embers := GPUParticles3D.new()
	embers.name = "TorchEmbers"
	embers.position = pos
	embers.amount = maxi(2, int(TORCH_EMBER_COUNT * PixelDioramaSettings.particle_amount_scale()))
	embers.lifetime = 2.4
	embers.randomness = 0.7
	embers.visibility_aabb = AABB(Vector3(-0.8, -0.4, -0.8), Vector3(1.6, 3.2, 1.6))
	embers.draw_pass_1 = assets["mesh"]
	embers.process_material = assets["process"]
	parent.add_child(embers)


static func _add_obstacle_block(
	parent: Node3D, pos: Vector3, size: Vector3, mat: Material, node_name: String
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.position = pos
	parent.add_child(body)
	var mesh_instance := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	if mat:
		mesh_instance.material_override = mat
	body.add_child(mesh_instance)
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


static func _spawn_prop_cluster(
	parent: Node3D,
	pos: Vector3,
	floor_mat: Material,
	accent_mat: Material,
	biome_id: String,
	rng_seed: int
) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome_id) + rng_seed * 97
	var count := 2 + rng.randi_range(0, 1)
	for i in count:
		var offset := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		var size := Vector3(
			rng.randf_range(0.4, 0.9), rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 0.9)
		)
		var mat: Material = accent_mat if i == 0 else floor_mat
		_add_box(
			parent, pos + offset + Vector3(0.0, size.y * 0.5, 0.0), size, mat, "Cluster_%d" % i
		)


static func _add_biome_banner(
	parent: Node3D, pos: Vector3, accent_mat: Material, width: float, height: float
) -> void:
	_add_box(
		parent,
		pos + Vector3(0.0, height * 0.5 + 0.5, 0.0),
		Vector3(0.12, height + 1.0, 0.12),
		accent_mat,
		"BannerPole"
	)
	_add_box(
		parent,
		pos + Vector3(0.0, height * 0.5 + 1.2, 0.0),
		Vector3(width, height, 0.08),
		accent_mat,
		"Banner"
	)


static func _add_box(
	parent: Node3D, pos: Vector3, size: Vector3, mat: Material, node_name: String
) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	# Chamfered, not a raw box. Every torch, brazier, pillar, banner and chest in the dungeon comes
	# through here, and as plain BoxMeshes they read as shipping crates standing next to characters
	# that are now properly sculpted. The cut is proportional so a small prop is not swallowed by it.
	var bevel: float = minf(size.x, minf(size.y, size.z)) * PROP_BEVEL_RATIO
	mesh_instance.mesh = PixelDioramaStyle.bevel_box_mesh(size, bevel)
	mesh_instance.position = pos
	if mat:
		mesh_instance.material_override = mat
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_spot(
	parent: Node3D, pos: Vector3, accent_mat: Material, energy: float, biome_id: String = ""
) -> void:
	var light := OmniLight3D.new()
	light.name = "AccentFill"
	light.position = pos
	VisualLighting.configure_soft_omni(
		light, _material_light_color(accent_mat, biome_id), energy * 0.9, 10.0, false
	)
	parent.add_child(light)


static func _material_light_color(mat: Material, biome_id: String = "") -> Color:
	if mat is ShaderMaterial:
		var shader_mat: ShaderMaterial = mat
		for param_name in ["color_accent", "color_base", "base_color"]:
			var value: Variant = shader_mat.get_shader_parameter(param_name)
			if value is Color:
				return value
	if mat is StandardMaterial3D:
		return (mat as StandardMaterial3D).albedo_color
	if biome_id != "":
		return _biome_light_color(biome_id)
	return Color(0.9, 0.75, 0.5)


## C-176: `_begin_room_torch_pass` reset `_shadow_omni_budget` to 0, so `max_shadow_omnis` — a
## single small number (default 2) authored once per biome — was spent *per room*. A 28-room floor
## therefore produced up to 56 shadow-casting omni lights rather than 2, which is the opposite of
## what a budget named for the whole lighting profile means and is the most expensive thing a
## pixel-diorama floor can do.
##
## The counter is reset once per floor by `begin_floor_lighting_pass()`; the per-room call now only
## refreshes the flicker config, which genuinely is per-biome.
static func begin_floor_lighting_pass(biome_id: String) -> void:
	_torch_flicker = VisualLighting.get_torch_config_for_biome(biome_id)
	_max_shadow_omnis = int(_torch_flicker.get("max_shadow_omnis", 2))
	_shadow_omni_budget = 0


static func _begin_room_torch_pass(biome_id: String) -> void:
	_torch_flicker = VisualLighting.get_torch_config_for_biome(biome_id)
	_max_shadow_omnis = int(_torch_flicker.get("max_shadow_omnis", 2))


static func _take_shadow_slot() -> bool:
	var cast_shadows := _shadow_omni_budget < _max_shadow_omnis
	if cast_shadows:
		_shadow_omni_budget += 1
	return cast_shadows


static func _configure_torch_light(
	light: OmniLight3D, color: Color, energy: float, light_range: float, parent: Node
) -> void:
	parent.add_child(light)
	VisualLighting.configure_soft_omni(light, color, energy, light_range, _take_shadow_slot())
	_attach_torch_flicker(light)


static func _attach_torch_flicker(light: OmniLight3D) -> void:
	VisualLighting.attach_flicker(
		light,
		float(_torch_flicker.get("flicker", 0.12)),
		float(_torch_flicker.get("flicker_hz", 7.5))
	)


static func _biome_light_color(biome_id: String) -> Color:
	return VisualLighting.get_torch_config_for_biome(biome_id).get(
		"color", Color(0.9, 0.75, 0.5)
	)
