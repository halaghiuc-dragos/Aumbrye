class_name HubDiorama
extends RefCounted

## Procedural pixel-diorama dressing for the hub plaza (HUB art pass).

const TILE_SIZE := 2.0
const FLOOR_WIDTH := 50.0
const FLOOR_DEPTH := 40.0

const ForgeFlickerScript := preload("res://scripts/hub/forge_light_flicker.gd")
const SceneLightingScript := preload("res://scripts/art/scene_lighting.gd")

const NPC_COLORS := {
	"blacksmith_aldric": Color(0.72, 0.38, 0.22),
	"merchant_elara": Color(0.28, 0.62, 0.42),
	"warden_mira": Color(0.38, 0.42, 0.78),
}

const SERVICE_TENTS := {
	"Blacksmith": {"width": 5.4, "depth": 5.0, "entrance": 2.2},
	"Merchant": {"width": 5.2, "depth": 4.8, "entrance": 2.4},
	"Storage": {"width": 5.6, "depth": 5.2, "entrance": 2.3},
	"QuestBoard": {"width": 4.2, "depth": 3.6, "entrance": 2.0},
}

const NORTH_PORTAL_Z := -17.0
const NORTH_PORTAL_X_MIN := -20.0
const NORTH_PORTAL_X_MAX := 20.0
const TRAINING_PORTAL_POS := Vector3(20.17, 0.0, 12.31)


static func apply(hub: Node3D) -> void:
	var mats := _load_materials()
	_style_environment(hub)
	_dress_floor(hub, mats)
	_dress_walls(hub, mats)
	_dress_portal(hub.get_node_or_null("CastlePortal"), mats, "castle")
	_dress_portal(hub.get_node_or_null("UmbralEndlessPortal"), mats, "umbral")
	_dress_portal(hub.get_node_or_null("UmbralWavesPortal"), mats, "umbral")
	_dress_portal(hub.get_node_or_null("ArenaDoor"), mats, "training")
	_dress_portal(hub.get_node_or_null("SkiesPortal"), mats, "skies")
	_dress_portal(hub.get_node_or_null("CathedralPortal"), mats, "cathedral")
	_dress_blacksmith(hub.get_node_or_null("Blacksmith"), mats)
	_dress_merchant(hub.get_node_or_null("Merchant"), mats)
	_dress_storage(hub.get_node_or_null("Storage"), mats)
	_dress_quest_board(hub.get_node_or_null("QuestBoard"), mats)
	_position_portals(hub)
	_spawn_fountain(hub, mats)
	_position_service_npcs(hub)
	_dress_npcs(hub)


static func _load_materials() -> Dictionary:
	return PixelDioramaStyle.make_hub_materials()


static func _style_environment(hub: Node3D) -> void:
	SceneLightingScript.apply_hub(hub)


static func _dress_floor(hub: Node3D, mats: Dictionary) -> void:
	var floor_body := hub.get_node_or_null("Floor") as StaticBody3D
	if floor_body == null:
		return
	var floor_mesh := floor_body.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if floor_mesh:
		floor_mesh.visible = false

	var tiles := Node3D.new()
	tiles.name = "DioramaTiles"
	hub.add_child(tiles)

	var cols := int(FLOOR_WIDTH / TILE_SIZE)
	var rows := int(FLOOR_DEPTH / TILE_SIZE)
	var origin_x := -FLOOR_WIDTH * 0.5 + TILE_SIZE * 0.5
	var origin_z := -FLOOR_DEPTH * 0.5 + TILE_SIZE * 0.5
	for row in rows:
		for col in cols:
			var alt := (row + col) % 2 == 1
			var mat: Material = mats.floor_alt if alt else mats.floor
			PixelDioramaStyle.add_box(
				tiles,
				Vector3(TILE_SIZE * 0.98, 0.12, TILE_SIZE * 0.98),
				Vector3(origin_x + col * TILE_SIZE, 0.06, origin_z + row * TILE_SIZE),
				mat
			)

	_spawn_accent_path(tiles, mats, origin_x, origin_z, cols, rows)
	_spawn_tent_door_pads(tiles, mats)


static func _spawn_accent_path(
	tiles: Node3D,
	mats: Dictionary,
	origin_x: float,
	origin_z: float,
	cols: int,
	rows: int
) -> void:
	var center_col: int = cols >> 1
	for row in rows:
		var col := center_col
		var z := origin_z + row * TILE_SIZE
		if z < -6.0 or z > 10.0:
			continue
		PixelDioramaStyle.add_box(
			tiles,
			Vector3(TILE_SIZE * 0.72, 0.14, TILE_SIZE * 0.72),
			Vector3(origin_x + col * TILE_SIZE, 0.08, z),
			mats.accent,
			"PathTile%d" % row
		)


static func _spawn_tent_door_pads(tiles: Node3D, mats: Dictionary) -> void:
	for service_name in SERVICE_TENTS.keys():
		var hub_pos: Vector3 = _service_world_position(service_name)
		var cfg: Dictionary = SERVICE_TENTS[service_name]
		var yaw: float = _service_yaw(service_name)
		var half_d: float = float(cfg.get("depth", 5.0)) * 0.5
		var door_dir: Vector3 = Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, yaw)
		var pad_pos: Vector3 = hub_pos + door_dir * (half_d + 0.55)
		PixelDioramaStyle.add_box(
			tiles,
			Vector3(float(cfg.get("entrance", 2.0)) + 0.4, 0.14, 1.2),
			Vector3(pad_pos.x, 0.08, pad_pos.z),
			mats.floor_alt,
			"%sDoorPad" % service_name
		)


static func _service_world_position(service_name: String) -> Vector3:
	match service_name:
		"Blacksmith":
			return Vector3(-18.0, 0.0, -4.0)
		"Merchant":
			return Vector3(-12.0, 0.0, 14.0)
		"Storage":
			return Vector3(0.0, 0.0, 14.0)
		"QuestBoard":
			return Vector3(12.0, 0.0, 14.0)
	return Vector3.ZERO


static func _plaza_facing_yaw(world_pos: Vector3) -> float:
	var to_plaza := Vector3(0.0, 0.0, 0.0) - world_pos
	to_plaza.y = 0.0
	if to_plaza.length_squared() < 0.001:
		return 0.0
	return atan2(to_plaza.x, to_plaza.z)


static func _service_yaw(service_name: String) -> float:
	return _plaza_facing_yaw(_service_world_position(service_name))


static func _north_portal_x(slot: int, count: int) -> float:
	if count <= 1:
		return 0.0
	return lerpf(NORTH_PORTAL_X_MIN, NORTH_PORTAL_X_MAX, float(slot) / float(count - 1))


static func _position_portals(hub: Node3D) -> void:
	var north_portal_names := [
		"CastlePortal",
		"UmbralEndlessPortal",
		"UmbralWavesPortal",
		"SkiesPortal",
		"CathedralPortal",
	]
	for i in north_portal_names.size():
		var portal := hub.get_node_or_null(north_portal_names[i]) as Node3D
		if portal == null:
			continue
		portal.position = Vector3(_north_portal_x(i, north_portal_names.size()), 0.0, NORTH_PORTAL_Z)
	var arena := hub.get_node_or_null("ArenaDoor") as Node3D
	if arena == null:
		return
	arena.position = TRAINING_PORTAL_POS
	var to_plaza := Vector3.ZERO - arena.position
	to_plaza.y = 0.0
	if to_plaza.length_squared() > 0.0001:
		arena.rotation.y = atan2(to_plaza.x, to_plaza.z)


static func _spawn_fountain(hub: Node3D, mats: Dictionary) -> void:
	if hub.get_node_or_null("PlazaFountain") != null:
		return
	PixelDioramaStyle.add_hub_fountain(hub, mats, Vector3(0.0, 0.0, -2.0))


static func _dress_walls(hub: Node3D, mats: Dictionary) -> void:
	var walls := hub.get_node_or_null("LandmarkWalls") as Node3D
	if walls == null:
		return
	for child in walls.get_children():
		if child is MeshInstance3D:
			child.visible = false
		elif child.name == "TowerParapet":
			child.queue_free()

	var parapet_root := Node3D.new()
	parapet_root.name = "TowerParapet"
	walls.add_child(parapet_root)

	var half_w := FLOOR_WIDTH * 0.5 - 0.5
	var half_d := FLOOR_DEPTH * 0.5 - 0.5
	var parapet_h := 1.55
	var parapet_thick := 0.72
	var north_south_len := half_w * 2.0
	var east_west_len := half_d * 2.0

	_add_tower_parapet_run(
		parapet_root,
		mats,
		Vector3(0.0, parapet_h * 0.5, -half_d),
		north_south_len,
		parapet_thick,
		parapet_h,
		0.0,
		"NorthParapet"
	)
	_add_tower_parapet_run(
		parapet_root,
		mats,
		Vector3(0.0, parapet_h * 0.5, half_d),
		north_south_len,
		parapet_thick,
		parapet_h,
		0.0,
		"SouthParapet"
	)
	_add_tower_parapet_run(
		parapet_root,
		mats,
		Vector3(half_w, parapet_h * 0.5, 0.0),
		east_west_len,
		parapet_thick,
		parapet_h,
		PI * 0.5,
		"EastParapet"
	)
	_add_tower_parapet_run(
		parapet_root,
		mats,
		Vector3(-half_w, parapet_h * 0.5, 0.0),
		east_west_len,
		parapet_thick,
		parapet_h,
		PI * 0.5,
		"WestParapet"
	)

	for corner in [
		Vector3(-half_w, 0.0, -half_d),
		Vector3(half_w, 0.0, -half_d),
		Vector3(half_w, 0.0, half_d),
		Vector3(-half_w, 0.0, half_d),
	]:
		_add_corner_turret(parapet_root, mats, corner, parapet_h)

	var wall_collision := walls.get_node_or_null("WallCollision") as StaticBody3D
	if wall_collision == null:
		wall_collision = StaticBody3D.new()
		wall_collision.name = "WallCollision"
		walls.add_child(wall_collision)
	else:
		for child in wall_collision.get_children():
			child.queue_free()
	wall_collision.collision_layer = 1
	wall_collision.collision_mask = 0

	_add_wall_collision_box(wall_collision, "ColNorth", Vector3(0.0, 2.5, -20.0), Vector3(48.0, 5.0, 1.0))
	_add_wall_collision_box(wall_collision, "ColSouth", Vector3(0.0, 2.5, 18.0), Vector3(48.0, 5.0, 1.0))
	_add_wall_collision_box(wall_collision, "ColEast", Vector3(24.0, 2.5, 0.0), Vector3(1.0, 5.0, 40.0))
	_add_wall_collision_box(wall_collision, "ColWest", Vector3(-24.0, 2.5, 0.0), Vector3(1.0, 5.0, 40.0))

	_add_perimeter_accents(walls, mats, parapet_h)


static func _add_tower_parapet_run(
	parent: Node3D,
	mats: Dictionary,
	center: Vector3,
	length: float,
	thickness: float,
	height: float,
	yaw: float,
	node_name: String
) -> void:
	var run := Node3D.new()
	run.name = node_name
	run.position = center
	run.rotation.y = yaw
	parent.add_child(run)

	PixelDioramaStyle.add_box(run, Vector3(length, height, thickness), Vector3.ZERO, mats.wall, "Walkway")
	PixelDioramaStyle.add_box(
		run,
		Vector3(length + 0.18, 0.14, thickness + 0.14),
		Vector3(0.0, height * 0.5 + 0.07, 0.0),
		mats.accent,
		"Coping"
	)

	var merlon_w := 0.82
	var merlon_gap := 0.52
	var merlon_h := 0.48
	var count := maxi(2, int(length / (merlon_w + merlon_gap)))
	for i in count:
		var t := (float(i) + 0.5) / float(count) - 0.5
		PixelDioramaStyle.add_box(
			run,
			Vector3(merlon_w, merlon_h, thickness + 0.1),
			Vector3(t * length, height * 0.5 + merlon_h * 0.5 + 0.08, 0.0),
			mats.wall,
			"Merlon%d" % i
		)


static func _add_corner_turret(
	parent: Node3D,
	mats: Dictionary,
	corner_pos: Vector3,
	parapet_h: float
) -> void:
	var turret_h := parapet_h + 2.45
	PixelDioramaStyle.add_box(
		parent,
		Vector3(1.35, turret_h, 1.35),
		corner_pos + Vector3(0.0, turret_h * 0.5, 0.0),
		mats.wall,
		"Turret%s" % str(corner_pos)
	)
	PixelDioramaStyle.add_box(
		parent,
		Vector3(1.55, 0.16, 1.55),
		corner_pos + Vector3(0.0, turret_h + 0.08, 0.0),
		mats.accent,
		"TurretCap%s" % str(corner_pos)
	)
	for i in 4:
		var angle := float(i) * TAU / 4.0
		var offset := Vector3(cos(angle), 0.0, sin(angle)) * 0.62
		PixelDioramaStyle.add_box(
			parent,
			Vector3(0.42, 0.38, 0.42),
			corner_pos + offset + Vector3(0.0, turret_h + 0.34, 0.0),
			mats.wall,
			"TurretMerlon%d_%s" % [i, str(corner_pos)]
		)


static func _add_wall_collision_box(
	parent: StaticBody3D,
	node_name: String,
	center: Vector3,
	size: Vector3
) -> void:
	var shape_node := CollisionShape3D.new()
	shape_node.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = center
	parent.add_child(shape_node)


static func _add_perimeter_accents(parent: Node3D, mats: Dictionary, parapet_h: float) -> void:
	var accent_y := parapet_h + 1.35
	for side in [
		{"pos": Vector3(-18.0, accent_y, -19.2), "name": "BannerN1"},
		{"pos": Vector3(18.0, accent_y, -19.2), "name": "BannerN2"},
	]:
		PixelDioramaStyle.add_box(
			parent,
			Vector3(0.35, 1.1, 0.12),
			side.pos,
			mats.accent,
			side.name
		)


static func _dress_portal(portal: Node3D, mats: Dictionary, theme: String) -> void:
	if portal == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(portal)
	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	portal.add_child(visuals)

	var frame_mat: Material = _portal_frame_material(mats, theme)

	PixelDioramaStyle.add_box(visuals, Vector3(0.45, 3.2, 0.45), Vector3(-1.55, 1.6, 0.0), frame_mat, "PillarL")
	PixelDioramaStyle.add_box(visuals, Vector3(0.45, 3.2, 0.45), Vector3(1.55, 1.6, 0.0), frame_mat, "PillarR")
	PixelDioramaStyle.add_box(visuals, Vector3(3.8, 0.45, 0.55), Vector3(0.0, 3.35, 0.0), frame_mat, "Lintel")
	PixelDioramaStyle.add_portal_interior(
		visuals,
		Vector2(2.6, 2.2),
		Vector3(0.0, 1.5, 0.02),
		theme
	)
	PixelDioramaStyle.add_box(visuals, Vector3(3.6, 0.14, 1.6), Vector3(0.0, 0.07, 0.0), mats.floor, "Pad")

	_add_portal_theme_accents(visuals, mats, theme)

	var portal_light := OmniLight3D.new()
	portal_light.name = "PortalGlow"
	var light_color: Color = _portal_light_color(theme)
	portal_light.light_color = light_color
	portal_light.light_energy = 0.8 if theme == "cathedral" else 0.85
	portal_light.omni_range = 3.5
	portal_light.position = Vector3(0.0, 1.6, 0.6)
	visuals.add_child(portal_light)


static func _portal_frame_material(mats: Dictionary, theme: String) -> Material:
	match theme:
		"castle":
			return mats.accent
		"umbral":
			return mats.umbral
		"training":
			return mats.training
		"skies":
			return mats.dragon
		"cathedral":
			return mats.cathedral
	return mats.accent


static func _portal_light_color(theme: String) -> Color:
	match theme:
		"castle":
			return Color(0.85, 0.72, 0.45)
		"training":
			return Color(1.0, 0.58, 0.18)
		"skies":
			return Color(1.0, 0.42, 0.14)
		"cathedral":
			return Color(1.0, 0.94, 0.68)
		_:
			return Color(0.62, 0.38, 0.92)


static func _add_portal_theme_accents(visuals: Node3D, mats: Dictionary, theme: String) -> void:
	match theme:
		"castle":
			PixelDioramaStyle.add_box(visuals, Vector3(0.2, 3.0, 0.2), Vector3(-1.55, 1.6, 0.15), mats.accent, "TorchL")
			PixelDioramaStyle.add_box(visuals, Vector3(0.2, 3.0, 0.2), Vector3(1.55, 1.6, 0.15), mats.accent, "TorchR")
		"umbral":
			PixelDioramaStyle.add_box(visuals, Vector3(3.2, 0.18, 0.18), Vector3(0.0, 0.2, 0.85), mats.umbral, "RuneRing")
		"training":
			PixelDioramaStyle.add_box(visuals, Vector3(0.22, 0.22, 0.22), Vector3(-1.0, 0.22, 0.75), mats.training, "EmberL")
			PixelDioramaStyle.add_box(visuals, Vector3(0.22, 0.22, 0.22), Vector3(1.0, 0.22, 0.75), mats.training, "EmberR")
			PixelDioramaStyle.add_box(visuals, Vector3(0.18, 2.8, 0.18), Vector3(-1.55, 1.6, 0.12), mats.training, "TorchL")
			PixelDioramaStyle.add_box(visuals, Vector3(0.18, 2.8, 0.18), Vector3(1.55, 1.6, 0.12), mats.training, "TorchR")
		"skies":
			PixelDioramaStyle.add_box(visuals, Vector3(0.28, 0.55, 0.28), Vector3(-0.55, 3.72, 0.0), mats.dragon, "HornL")
			PixelDioramaStyle.add_box(visuals, Vector3(0.28, 0.55, 0.28), Vector3(0.55, 3.72, 0.0), mats.dragon, "HornR")
			PixelDioramaStyle.add_box(visuals, Vector3(0.85, 0.12, 0.55), Vector3(-1.55, 1.9, 0.18), mats.dragon, "WingL")
			PixelDioramaStyle.add_box(visuals, Vector3(0.85, 0.12, 0.55), Vector3(1.55, 1.9, 0.18), mats.dragon, "WingR")
			PixelDioramaStyle.add_box(visuals, Vector3(0.35, 0.35, 0.35), Vector3(0.0, 0.28, 0.82), mats.forge, "DragonEye")
		"cathedral":
			PixelDioramaStyle.add_box(visuals, Vector3(0.22, 0.75, 0.18), Vector3(0.0, 3.55, 0.12), mats.cathedral, "CrossV")
			PixelDioramaStyle.add_box(visuals, Vector3(0.65, 0.18, 0.18), Vector3(0.0, 3.82, 0.12), mats.cathedral, "CrossH")
			PixelDioramaStyle.add_box(visuals, Vector3(0.2, 2.9, 0.2), Vector3(-1.55, 1.6, 0.12), mats.cathedral, "PillarTrimL")
			PixelDioramaStyle.add_box(visuals, Vector3(0.2, 2.9, 0.2), Vector3(1.55, 1.6, 0.12), mats.cathedral, "PillarTrimR")


static func _dress_blacksmith(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(building)
	var dark_wall := mats.wall.duplicate() as ShaderMaterial
	dark_wall.set_shader_parameter("color_base", Color(0.32, 0.28, 0.24))
	dark_wall.set_shader_parameter("color_shadow", Color(0.2, 0.16, 0.14))
	var tent_mats := mats.duplicate()
	tent_mats.wall = dark_wall

	var yaw := _service_yaw("Blacksmith")
	var visuals := PixelDioramaStyle.add_hub_tent(building, tent_mats, 5.4, 5.0, 2.5, 2.2, 1.35, yaw)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	var forge_mat := (mats.forge as StandardMaterial3D).duplicate()
	var forge := PixelDioramaStyle.add_box(dressing, Vector3(1.2, 1.0, 1.2), Vector3(1.4, 0.5, -0.8), forge_mat, "Forge")
	PixelDioramaStyle.add_box(dressing, Vector3(0.5, 1.8, 0.5), Vector3(1.4, 1.4, -0.8), mats.wall, "Chimney")
	PixelDioramaStyle.add_box(dressing, Vector3(0.7, 0.35, 0.5), Vector3(-0.8, 0.55, -0.6), mats.accent, "Anvil")
	PixelDioramaStyle.add_box(dressing, Vector3(2.0, 0.85, 0.75), Vector3(-1.2, 0.42, -1.2), mats.wood, "Workbench")
	PixelDioramaStyle.add_box(dressing, Vector3(0.25, 0.9, 0.25), Vector3(-2.0, 0.45, -1.0), mats.accent, "ToolRack")

	var forge_light := OmniLight3D.new()
	forge_light.name = "ForgeLight"
	forge_light.light_color = Color(1.0, 0.55, 0.22)
	forge_light.light_energy = 1.15
	forge_light.omni_range = 4.5
	forge_light.position = Vector3(1.4, 1.2, -0.8)
	dressing.add_child(forge_light)

	var flicker := ForgeFlickerScript.new()
	flicker.name = "ForgeFlicker"
	dressing.add_child(flicker)
	flicker.setup(forge_light, forge)

	_add_ridge_sign(visuals, "Blacksmith", 3.85, mats.accent)
	_position_door_interact(building, 5.0, 2.2, yaw)


static func _dress_merchant(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(building)
	var yaw := _service_yaw("Merchant")
	var depth := 4.8
	var half_d := depth * 0.5
	var visuals := PixelDioramaStyle.add_hub_tent(building, mats, 5.2, depth, 2.6, 2.4, 1.1, yaw)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	for i in 5:
		var stripe_mat: Material = mats.accent if i % 2 == 0 else mats.floor
		PixelDioramaStyle.add_box(
			dressing,
			Vector3(0.85, 0.1, 0.18),
			Vector3(-1.8 + i * 0.9, 2.15, half_d - 0.12),
			stripe_mat,
			"Awning%d" % i
		)
	PixelDioramaStyle.add_box(dressing, Vector3(3.2, 0.95, 0.65), Vector3(0.0, 0.48, -0.8), mats.wood, "Counter")
	PixelDioramaStyle.add_box(dressing, Vector3(0.65, 0.65, 0.65), Vector3(-1.3, 0.32, -1.4), mats.accent, "CrateA")
	PixelDioramaStyle.add_box(dressing, Vector3(0.65, 0.65, 0.65), Vector3(1.3, 0.32, -1.5), mats.accent, "CrateB")
	PixelDioramaStyle.add_box(dressing, Vector3(2.4, 1.4, 0.3), Vector3(-1.8, 1.05, -1.0), mats.wood, "ShelfL")
	PixelDioramaStyle.add_box(dressing, Vector3(2.4, 1.4, 0.3), Vector3(1.8, 1.05, -1.0), mats.wood, "ShelfR")

	var lantern := OmniLight3D.new()
	lantern.name = "LanternLight"
	lantern.light_color = Color(1.0, 0.82, 0.55)
	lantern.light_energy = 0.7
	lantern.omni_range = 3.8
	lantern.position = Vector3(0.0, 2.0, half_d - 0.5)
	dressing.add_child(lantern)

	_add_ridge_sign(visuals, "Merchant", 3.5, mats.accent)
	_position_door_interact(building, depth, 2.4, yaw)


static func _dress_storage(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(building)
	var yaw := _service_yaw("Storage")
	var depth := 5.2
	var visuals := PixelDioramaStyle.add_hub_tent(building, mats, 5.6, depth, 2.8, 2.3, 1.0, yaw)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	PixelDioramaStyle.add_box(dressing, Vector3(3.4, 1.8, 0.35), Vector3(0.0, 0.9, -1.4), mats.wood, "ShelfBack")
	for i in 3:
		PixelDioramaStyle.add_box(
			dressing,
			Vector3(0.85, 0.5, 0.5),
			Vector3(-1.1 + i * 1.1, 1.2, -1.2),
			mats.accent,
			"Crate%d" % i
		)
	PixelDioramaStyle.add_cylinder(dressing, 0.4, 0.4, 1.0, Vector3(-1.8, 0.5, -1.0), mats.wood, "BarrelA")
	PixelDioramaStyle.add_cylinder(dressing, 0.4, 0.4, 1.0, Vector3(1.8, 0.5, -1.0), mats.wood, "BarrelB")

	var lamp := OmniLight3D.new()
	lamp.name = "StorageLight"
	lamp.light_color = Color(0.72, 0.82, 0.95)
	lamp.light_energy = 0.55
	lamp.omni_range = 3.5
	lamp.position = Vector3(0.0, 2.2, -0.6)
	dressing.add_child(lamp)

	_add_ridge_sign(visuals, "Storage", 3.8, mats.accent)
	_position_door_interact(
		building,
		depth,
		2.3,
		yaw,
		Vector3(2.3 + 1.0, 3.0, 3.0)
	)


static func _dress_quest_board(board: Node3D, mats: Dictionary) -> void:
	if board == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(board)
	var yaw := _service_yaw("QuestBoard")
	var depth := 3.6
	var half_d := depth * 0.5
	var visuals := PixelDioramaStyle.add_hub_tent(board, mats, 4.2, depth, 2.2, 2.0, 0.85, yaw)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	PixelDioramaStyle.add_box(dressing, Vector3(2.8, 1.8, 0.16), Vector3(0.0, 1.35, half_d - 0.25), mats.accent, "Board")
	for i in 4:
		PixelDioramaStyle.add_box(
			dressing,
			Vector3(0.5, 0.65, 0.04),
			Vector3(-0.9 + i * 0.6, 1.25 + (i % 2) * 0.22, half_d - 0.12),
			mats.paper,
			"Notice%d" % i
		)
	PixelDioramaStyle.add_box(dressing, Vector3(0.45, 0.45, 0.45), Vector3(1.3, 0.22, -0.4), mats.wood, "BenchCrate")

	var paper_light := OmniLight3D.new()
	paper_light.name = "QuestLight"
	paper_light.light_color = Color(0.95, 0.88, 0.72)
	paper_light.light_energy = 0.5
	paper_light.omni_range = 3.2
	paper_light.position = Vector3(0.0, 1.8, half_d - 0.4)
	dressing.add_child(paper_light)

	_add_ridge_sign(visuals, "Quests", 3.05, mats.accent)
	_position_door_interact(board, depth, 2.0, yaw)


static func _add_ridge_sign(visuals: Node3D, label_text: String, ridge_y: float, mat: Material) -> void:
	var sign_root := Node3D.new()
	sign_root.name = "RidgeSign"
	sign_root.position = Vector3(0.0, ridge_y + 0.72, 0.0)
	visuals.add_child(sign_root)
	PixelDioramaStyle.add_box(sign_root, Vector3(1.6, 0.35, 0.12), Vector3(0.0, 0.25, 0.08), mat, "SignBacking")
	var label := Label3D.new()
	label.name = "SignLabel"
	label.text = label_text
	label.font_size = 22
	label.position = Vector3(0.0, 0.55, 0.12)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	sign_root.add_child(label)


static func _position_door_interact(
	building: Node3D,
	depth: float,
	entrance_width: float,
	facing_yaw: float,
	box_size: Vector3 = Vector3.ZERO
) -> void:
	var area := building.get_node_or_null("InteractArea") as Area3D
	if area == null:
		return
	var half_d := depth * 0.5
	var door_dir := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, facing_yaw)
	var interact_offset := half_d + 0.75
	if box_size != Vector3.ZERO:
		interact_offset = half_d + box_size.z * 0.42
	area.position = door_dir * interact_offset + Vector3(0.0, 1.35, 0.0)
	area.rotation.y = facing_yaw

	var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	shape_node.transform = Transform3D.IDENTITY
	var box := shape_node.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		shape_node.shape = box
	if box_size == Vector3.ZERO:
		box.size = Vector3(entrance_width + 0.6, 2.5, 2.4)
	else:
		box.size = box_size
	shape_node.position = Vector3.ZERO

	var label := building.get_node_or_null("Label") as Label3D
	if label:
		label.position = door_dir * (half_d + 0.35) + Vector3(0.0, 4.55, 0.0)


static func _position_service_npcs(hub: Node3D) -> void:
	var blacksmith := hub.get_node_or_null("NpcAldric") as Node3D
	if blacksmith:
		var bs_yaw := _service_yaw("Blacksmith")
		var bs_door := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, bs_yaw)
		var bs_pos := _service_world_position("Blacksmith")
		blacksmith.position = bs_pos + bs_door * 3.1
		blacksmith.rotation.y = bs_yaw + PI

	var merchant := hub.get_node_or_null("NpcElara") as Node3D
	if merchant:
		var m_yaw := _service_yaw("Merchant")
		var m_door := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, m_yaw)
		var m_pos := _service_world_position("Merchant")
		merchant.position = m_pos + m_door * 2.8
		merchant.rotation.y = m_yaw + PI

	var mira := hub.get_node_or_null("NpcMira") as Node3D
	if mira:
		var q_yaw := _service_yaw("QuestBoard")
		var q_door := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, q_yaw)
		var q_pos := _service_world_position("QuestBoard")
		mira.position = q_pos + q_door * 2.6
		mira.rotation.y = q_yaw + PI


static func _dress_npcs(hub: Node3D) -> void:
	for child in hub.get_children():
		if not child.is_in_group("hub_npc"):
			continue
		_style_npc(child as Node3D)


static func _style_npc(npc: Node3D) -> void:
	var npc_id := ""
	if npc.has_method("get_npc_id"):
		npc_id = str(npc.call("get_npc_id"))
	elif "npc_id" in npc:
		npc_id = str(npc.get("npc_id"))

	var body_color: Color = NPC_COLORS.get(npc_id, Color(0.55, 0.48, 0.42))
	var body_mat := PixelDioramaStyle.make_material(body_color)
	var accent_mat := PixelDioramaStyle.make_material(body_color.lightened(0.18))

	var body := npc.get_node_or_null("Body") as MeshInstance3D
	if body:
		body.visible = false

	var existing := npc.get_node_or_null("DioramaBody")
	if existing:
		existing.queue_free()

	var visuals := Node3D.new()
	visuals.name = "DioramaBody"
	npc.add_child(visuals)
	PixelDioramaStyle.add_box(visuals, Vector3(0.75, 1.1, 0.45), Vector3(0.0, 0.55, 0.0), body_mat, "Torso")
	PixelDioramaStyle.add_box(visuals, Vector3(0.42, 0.42, 0.42), Vector3(0.0, 1.35, 0.0), accent_mat, "Head")
	PixelDioramaStyle.add_box(visuals, Vector3(0.85, 0.18, 0.5), Vector3(0.0, 0.08, 0.0), accent_mat, "Feet")
