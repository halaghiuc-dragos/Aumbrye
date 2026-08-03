class_name HubDiorama
extends RefCounted

## Procedural pixel-diorama dressing for the hub plaza (HUB art pass).

const TILE_SIZE := 2.0
const FLOOR_WIDTH := 50.0
const FLOOR_DEPTH := 40.0

const NPC_COLORS := {
	"blacksmith_aldric": Color(0.72, 0.38, 0.22),
	"merchant_elara": Color(0.28, 0.62, 0.42),
	"warden_mira": Color(0.38, 0.42, 0.78),
}


static func apply(hub: Node3D) -> void:
	var mats := _load_materials()
	_style_environment(hub)
	_dress_floor(hub, mats)
	_dress_walls(hub, mats)
	_dress_portal(hub.get_node_or_null("CastlePortal"), mats, "castle")
	_dress_portal(hub.get_node_or_null("UmbralEndlessPortal"), mats, "umbral")
	_dress_portal(hub.get_node_or_null("UmbralWavesPortal"), mats, "umbral")
	_dress_arena(hub.get_node_or_null("ArenaDoor"), mats)
	_dress_blacksmith(hub.get_node_or_null("Blacksmith"), mats)
	_dress_merchant(hub.get_node_or_null("Merchant"), mats)
	_dress_storage(hub.get_node_or_null("Storage"), mats)
	_dress_quest_board(hub.get_node_or_null("QuestBoard"), mats)
	_dress_npcs(hub)


static func _load_materials() -> Dictionary:
	return PixelDioramaStyle.make_hub_materials()


static func _style_environment(hub: Node3D) -> void:
	var env_node := hub.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		hub.add_child(env_node)
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.42, 0.48, 0.58)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.55, 0.5, 0.45)
	env.ambient_light_energy = 0.45
	PixelDioramaSettings.configure_environment(env)
	env_node.environment = env

	var sun := hub.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun:
		sun.light_color = Color(1.0, 0.92, 0.82)
		sun.light_energy = 1.35
		sun.shadow_enabled = true


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


static func _dress_walls(hub: Node3D, mats: Dictionary) -> void:
	var walls := hub.get_node_or_null("LandmarkWalls") as Node3D
	if walls == null:
		return
	for child in walls.get_children():
		if child is MeshInstance3D:
			child.material_override = mats.wall
			_add_wall_trim(walls, child as MeshInstance3D, mats)


static func _add_wall_trim(parent: Node3D, wall: MeshInstance3D, mats: Dictionary) -> void:
	var trim := PixelDioramaStyle.add_box(
		parent,
		Vector3(wall.scale.x * 4.0, 0.25, wall.scale.z * 1.0 + 0.2),
		wall.position + Vector3(0.0, -2.25, 0.0),
		mats.accent,
		"%sTrim" % wall.name
	)
	trim.rotation = wall.rotation
	var crenel_count := int(wall.scale.x * 3.0)
	var span := wall.scale.x * 3.5
	for i in crenel_count:
		var t := (float(i) + 0.5) / float(crenel_count) - 0.5
		var bump := PixelDioramaStyle.add_box(
			parent,
			Vector3(0.55, 0.35, 0.55),
			wall.position + Vector3(t * span, 2.85, 0.0),
			mats.wall,
			"%sCrenel%d" % [wall.name, i]
		)
		bump.rotation = wall.rotation


static func _dress_portal(portal: Node3D, mats: Dictionary, theme: String) -> void:
	if portal == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(portal)
	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	portal.add_child(visuals)

	var frame_mat: Material = mats.accent if theme == "castle" else mats.umbral

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

	if theme == "castle":
		PixelDioramaStyle.add_box(visuals, Vector3(0.2, 3.0, 0.2), Vector3(-1.55, 1.6, 0.15), mats.accent, "TorchL")
		PixelDioramaStyle.add_box(visuals, Vector3(0.2, 3.0, 0.2), Vector3(1.55, 1.6, 0.15), mats.accent, "TorchR")
	else:
		PixelDioramaStyle.add_box(visuals, Vector3(3.2, 0.18, 0.18), Vector3(0.0, 0.2, 0.85), mats.umbral, "RuneRing")


static func _dress_arena(door: Node3D, mats: Dictionary) -> void:
	if door == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(door)
	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	door.add_child(visuals)

	PixelDioramaStyle.add_box(visuals, Vector3(0.5, 3.0, 0.5), Vector3(-1.4, 1.5, 0.0), mats.wall, "PostL")
	PixelDioramaStyle.add_box(visuals, Vector3(0.5, 3.0, 0.5), Vector3(1.4, 1.5, 0.0), mats.wall, "PostR")
	PixelDioramaStyle.add_box(visuals, Vector3(3.6, 0.4, 0.45), Vector3(0.0, 3.1, 0.0), mats.accent, "Header")
	PixelDioramaStyle.add_box(visuals, Vector3(2.4, 1.6, 0.1), Vector3(0.0, 1.2, 0.0), mats.roof, "Banner")
	PixelDioramaStyle.add_box(visuals, Vector3(3.4, 0.12, 1.4), Vector3(0.0, 0.06, 0.0), mats.floor_alt, "Pad")
	# Training dummy silhouette — feet on arena pad (pad top ~0.12)
	PixelDioramaStyle.add_box(visuals, Vector3(0.35, 1.6, 0.35), Vector3(2.2, 0.92, 0.8), mats.wood, "DummyPost")
	PixelDioramaStyle.add_box(visuals, Vector3(0.9, 0.9, 0.25), Vector3(2.2, 1.77, 0.8), mats.accent, "DummyTorso")


static func _dress_blacksmith(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(building)
	var visuals := PixelDioramaStyle.add_hub_tent(building, mats, 5.4, 5.0, 2.5, 2.2, 1.35)
	PixelDioramaStyle.add_box(visuals, Vector3(1.2, 1.0, 1.2), Vector3(1.4, 0.5, -0.8), mats.forge, "Forge")
	PixelDioramaStyle.add_box(visuals, Vector3(0.5, 1.8, 0.5), Vector3(1.4, 1.4, -0.8), mats.wall, "Chimney")
	PixelDioramaStyle.add_box(visuals, Vector3(0.7, 0.35, 0.5), Vector3(-0.8, 0.55, 0.6), mats.accent, "Anvil")
	PixelDioramaStyle.add_box(visuals, Vector3(2.0, 0.85, 0.75), Vector3(-1.2, 0.42, -0.4), mats.wood, "Workbench")
	PixelDioramaStyle.add_box(visuals, Vector3(0.25, 0.9, 0.25), Vector3(-2.0, 0.45, -0.4), mats.accent, "ToolRack")


static func _dress_merchant(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(building)
	var visuals := PixelDioramaStyle.add_hub_tent(building, mats, 5.2, 4.8, 2.6, 2.4, 1.1)
	for i in 5:
		var stripe_mat: Material = mats.accent if i % 2 == 0 else mats.floor
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.85, 0.1, 0.18),
			Vector3(-1.8 + i * 0.9, 2.15, 2.15),
			stripe_mat,
			"Awning%d" % i
		)
	PixelDioramaStyle.add_box(visuals, Vector3(3.2, 0.95, 0.65), Vector3(0.0, 0.48, 1.0), mats.wood, "Counter")
	PixelDioramaStyle.add_box(visuals, Vector3(0.65, 0.65, 0.65), Vector3(-1.3, 0.32, 1.2), mats.accent, "CrateA")
	PixelDioramaStyle.add_box(visuals, Vector3(0.65, 0.65, 0.65), Vector3(1.3, 0.32, 1.2), mats.accent, "CrateB")
	PixelDioramaStyle.add_box(visuals, Vector3(2.4, 1.4, 0.3), Vector3(-1.8, 1.05, -0.2), mats.wood, "ShelfL")
	PixelDioramaStyle.add_box(visuals, Vector3(2.4, 1.4, 0.3), Vector3(1.8, 1.05, -0.2), mats.wood, "ShelfR")


static func _dress_storage(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(building)
	var visuals := PixelDioramaStyle.add_hub_tent(building, mats, 5.6, 5.2, 2.8, 2.3, 1.0)
	PixelDioramaStyle.add_box(visuals, Vector3(3.4, 1.8, 0.35), Vector3(0.0, 0.9, -1.0), mats.wood, "ShelfBack")
	for i in 3:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.85, 0.5, 0.5),
			Vector3(-1.1 + i * 1.1, 1.2, 1.0),
			mats.accent,
			"Crate%d" % i
		)
	PixelDioramaStyle.add_cylinder(visuals, 0.4, 0.4, 1.0, Vector3(-1.8, 0.5, -0.6), mats.wood, "BarrelA")
	PixelDioramaStyle.add_cylinder(visuals, 0.4, 0.4, 1.0, Vector3(1.8, 0.5, -0.6), mats.wood, "BarrelB")


static func _dress_quest_board(board: Node3D, mats: Dictionary) -> void:
	if board == null:
		return
	PixelDioramaStyle.hide_legacy_meshes(board)
	var visuals := PixelDioramaStyle.add_hub_tent(board, mats, 4.2, 3.6, 2.2, 2.0, 0.85)
	PixelDioramaStyle.add_box(visuals, Vector3(2.8, 1.8, 0.16), Vector3(0.0, 1.35, 0.35), mats.accent, "Board")
	for i in 4:
		PixelDioramaStyle.add_box(
			visuals,
			Vector3(0.5, 0.65, 0.04),
			Vector3(-0.9 + i * 0.6, 1.25 + (i % 2) * 0.22, 0.48),
			mats.paper,
			"Notice%d" % i
		)
	PixelDioramaStyle.add_box(visuals, Vector3(0.45, 0.45, 0.45), Vector3(1.3, 0.22, 0.5), mats.wood, "BenchCrate")


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
