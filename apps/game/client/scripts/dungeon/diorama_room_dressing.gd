extends RefCounted
class_name DioramaRoomDressing

## Procedural pixel-diorama props spawned at runtime per biome + room template.

const ROOM_SUFFIXES := [
	"entrance", "stairs", "courtyard", "hall", "treasure", "secret",
	"arena", "boss", "puzzle",
]


static func apply_to_room(room: RoomTemplate, biome_id: String) -> void:
	var blockout := room.get_blockout()
	if blockout == null:
		return
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
			_spawn_generic_corners(dressing, half_w, half_d, accent_mat, biome_id)


static func apply_to_waves_arena(parent: Node3D, biome_id: String = BiomeRegistry.BIOME_UMBRAL) -> void:
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


static func _spawn_entrance(parent: Node3D, half_w: float, half_d: float, wall_mat: Material, accent_mat: Material, biome_id: String) -> void:
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.0, 0.0, -half_d + 1.2), wall_mat, 2.8)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.0, 0.0, -half_d + 1.2), wall_mat, 2.8)
	_spawn_brazier(parent, Vector3(-half_w + 2.2, 0.0, half_d - 1.5), accent_mat, biome_id)
	_spawn_brazier(parent, Vector3(half_w - 2.2, 0.0, half_d - 1.5), accent_mat, biome_id)
	_add_biome_banner(parent, Vector3(0.0, 0.0, -half_d + 0.6), accent_mat, 2.4, 1.2)


static func _spawn_boss(parent: Node3D, half_w: float, half_d: float, wall_mat: Material, accent_mat: Material, biome_id: String) -> void:
	_add_box(parent, Vector3(0.0, 0.08, half_d - 2.5), Vector3(half_w * 1.4, 0.16, 2.0), accent_mat, "BossPlatform")
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.2, 0.0, -half_d + 1.2), wall_mat, 3.2)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.2, 0.0, -half_d + 1.2), wall_mat, 3.2)
	_spawn_brazier(parent, Vector3(-half_w + 2.0, 0.0, half_d - 1.8), accent_mat, biome_id, 0.7)
	_spawn_brazier(parent, Vector3(half_w - 2.0, 0.0, half_d - 1.8), accent_mat, biome_id, 0.7)
	_add_spot(parent, Vector3(0.0, 4.5, half_d - 2.5), accent_mat, 1.2, biome_id)


static func _spawn_courtyard(parent: Node3D, half_w: float, half_d: float, floor_mat: Material, accent_mat: Material, biome_id: String) -> void:
	_spawn_prop_cluster(parent, Vector3(-half_w + 2.0, 0.0, -half_d + 2.0), floor_mat, accent_mat, biome_id, 0)
	_spawn_prop_cluster(parent, Vector3(half_w - 2.0, 0.0, -half_d + 2.0), floor_mat, accent_mat, biome_id, 1)
	_spawn_prop_cluster(parent, Vector3(-half_w + 2.0, 0.0, half_d - 2.0), floor_mat, accent_mat, biome_id, 2)
	_spawn_prop_cluster(parent, Vector3(half_w - 2.0, 0.0, half_d - 2.0), floor_mat, accent_mat, biome_id, 3)
	_add_box(parent, Vector3(0.0, 0.05, 0.0), Vector3(2.5, 0.1, 2.5), accent_mat, "CenterPlinth")


static func _spawn_hall(parent: Node3D, half_w: float, half_d: float, wall_mat: Material, accent_mat: Material, biome_id: String) -> void:
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


static func _spawn_secret(parent: Node3D, half_w: float, _half_d: float, accent_mat: Material, biome_id: String) -> void:
	_add_box(parent, Vector3(-half_w + 0.6, 1.2, 0.0), Vector3(0.35, 2.4, 2.2), accent_mat, "SecretPanel")
	_add_spot(parent, Vector3(-half_w + 1.0, 2.0, 0.0), accent_mat, 0.4, biome_id)


static func _spawn_stairs(parent: Node3D, half_w: float, half_d: float, accent_mat: Material, _biome_id: String) -> void:
	if parent.get_parent() != null and parent.get_parent().get_node_or_null("StairRamp") != null:
		return
	_add_box(parent, Vector3(0.0, 0.35, half_d - 2.0), Vector3(half_w * 0.5, 0.7, 3.0), accent_mat, "StairRampAccent")
	_spawn_wall_sconce(parent, Vector3(-half_w + 0.5, 1.6, 0.0), accent_mat, "")
	_spawn_wall_sconce(parent, Vector3(half_w - 0.5, 1.6, 0.0), accent_mat, "")


static func _spawn_arena(parent: Node3D, half_w: float, half_d: float, wall_mat: Material, accent_mat: Material, biome_id: String) -> void:
	_add_box(parent, Vector3(0.0, 0.04, 0.0), Vector3(half_w * 1.2, 0.08, half_d * 1.2), accent_mat, "ArenaRing")
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.0, 0.0, -half_d + 1.0), wall_mat, 2.2)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.0, 0.0, -half_d + 1.0), wall_mat, 2.2)
	_spawn_brazier(parent, Vector3(0.0, 0.0, -half_d + 1.5), accent_mat, biome_id, 0.5)


static func _spawn_puzzle(parent: Node3D, accent_mat: Material, biome_id: String) -> void:
	_add_box(parent, Vector3(0.0, 0.5, 0.0), Vector3(1.2, 1.0, 1.2), accent_mat, "PuzzleCore")
	for i in 4:
		var angle := float(i) / 4.0 * TAU
		_add_box(parent, Vector3(cos(angle) * 2.5, 0.2, sin(angle) * 2.5), Vector3(0.6, 0.4, 0.6), accent_mat, "PuzzleOrb_%d" % i)
	_spawn_brazier(parent, Vector3(0.0, 0.0, 2.8), accent_mat, biome_id, 0.45)


static func _spawn_generic_corners(parent: Node3D, half_w: float, half_d: float, accent_mat: Material, biome_id: String) -> void:
	_spawn_brazier(parent, Vector3(-half_w + 1.5, 0.0, -half_d + 1.5), accent_mat, biome_id, 0.4)
	_spawn_brazier(parent, Vector3(half_w - 1.5, 0.0, half_d - 1.5), accent_mat, biome_id, 0.4)


static func _spawn_corner_pillar(parent: Node3D, pos: Vector3, mat: Material, height: float) -> void:
	_add_box(parent, pos + Vector3(0.0, height * 0.5, 0.0), Vector3(0.7, height, 0.7), mat, "Pillar")


static func _spawn_brazier(parent: Node3D, pos: Vector3, accent_mat: Material, biome_id: String, energy: float = 0.6) -> void:
	_add_box(parent, pos + Vector3(0.0, 0.35, 0.0), Vector3(0.45, 0.7, 0.45), accent_mat, "Brazier")
	var light := OmniLight3D.new()
	light.name = "BrazierLight"
	light.position = pos + Vector3(0.0, 1.1, 0.0)
	light.light_color = _biome_light_color(biome_id)
	light.light_energy = energy
	light.omni_range = 5.0
	parent.add_child(light)


static func _spawn_wall_sconce(parent: Node3D, pos: Vector3, accent_mat: Material, biome_id: String) -> void:
	_add_box(parent, pos, Vector3(0.25, 0.5, 0.35), accent_mat, "Sconce")
	if biome_id != "":
		var light := OmniLight3D.new()
		light.position = pos + Vector3(0.35, 0.0, 0.0)
		light.light_color = _biome_light_color(biome_id)
		light.light_energy = 0.35
		light.omni_range = 3.5
		parent.add_child(light)


static func _spawn_prop_cluster(parent: Node3D, pos: Vector3, floor_mat: Material, accent_mat: Material, biome_id: String, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome_id) + rng_seed * 97
	var count := 2 + rng.randi_range(0, 1)
	for i in count:
		var offset := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		var size := Vector3(rng.randf_range(0.4, 0.9), rng.randf_range(0.3, 0.8), rng.randf_range(0.4, 0.9))
		var mat: Material = accent_mat if i == 0 else floor_mat
		_add_box(parent, pos + offset + Vector3(0.0, size.y * 0.5, 0.0), size, mat, "Cluster_%d" % i)


static func _add_biome_banner(parent: Node3D, pos: Vector3, accent_mat: Material, width: float, height: float) -> void:
	_add_box(parent, pos + Vector3(0.0, height * 0.5 + 0.5, 0.0), Vector3(0.12, height + 1.0, 0.12), accent_mat, "BannerPole")
	_add_box(parent, pos + Vector3(0.0, height * 0.5 + 1.2, 0.0), Vector3(width, height, 0.08), accent_mat, "Banner")


static func _add_box(parent: Node3D, pos: Vector3, size: Vector3, mat: Material, node_name: String) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_instance.mesh = box
	mesh_instance.position = pos
	if mat:
		mesh_instance.material_override = mat
	parent.add_child(mesh_instance)
	return mesh_instance


static func _add_spot(parent: Node3D, pos: Vector3, accent_mat: Material, energy: float, biome_id: String = "") -> void:
	var light := SpotLight3D.new()
	light.position = pos
	light.rotation_degrees = Vector3(90.0, 0.0, 0.0)
	light.light_energy = energy
	light.spot_range = 10.0
	light.spot_angle = 35.0
	light.light_color = _material_light_color(accent_mat, biome_id)
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


static func _biome_light_color(biome_id: String) -> Color:
	var profile := BiomeRegistry.get_lighting_profile(biome_id)
	return profile.get("ambient_color", Color(0.9, 0.75, 0.5))
