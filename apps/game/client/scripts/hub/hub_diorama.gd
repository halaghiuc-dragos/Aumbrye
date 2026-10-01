class_name HubDiorama
extends RefCounted


const TILE_SIZE := 2.0
const TILE_TOP := 0.12
const TILE_BED_DROP := 0.01
const TILE_BED_THICK := 0.2
const WALL_COLLISION_HEIGHT := 5.0

const FLOOR_WIDTH := 50.0
const FLOOR_DEPTH := 40.0

const ForgeFlickerScript := preload("res://scripts/hub/forge_light_flicker.gd")

const SERVICE_TENTS := {
	"Blacksmith":
	{"width": 5.4, "depth": 5.2, "wall_height": 2.4, "entrance": 2.8, "roof_peak": 1.5},
	"Merchant":
	{"width": 5.2, "depth": 5.0, "wall_height": 2.4, "entrance": 2.8, "roof_peak": 1.4},
	"Storage":
	{"width": 5.4, "depth": 5.2, "wall_height": 2.5, "entrance": 2.8, "roof_peak": 1.35},
	"QuestBoard":
	{"width": 4.6, "depth": 4.4, "wall_height": 2.3, "entrance": 2.4, "roof_peak": 1.25},
}

const FOUNTAIN_POS := Vector3(0.0, 0.0, -7.0)
const GATE_ROW_Z := -17.0
const GATE_SPACING := 9.0
const GATE_COUNT := 4

const BLOOM_COLORS := [
	Color(0.76, 0.33, 0.34),
	Color(0.85, 0.63, 0.27),
	Color(0.60, 0.40, 0.66),
]
const BUNTING_Y := 6.2

const LANTERN_LIGHT_COLOR := Color(1.0, 0.72, 0.34)
const LANTERN_ENERGY := 0.55
const LANTERN_RANGE := 4.2


const BannerVaneScript := preload("res://scripts/art/world/banner_vane.gd")


static func apply(hub: Node3D) -> void:
	var mats := _load_materials()
	_style_environment(hub)
	_dress_floor(hub, mats)
	_dress_walls(hub, mats)
	_dress_portal(hub.get_node_or_null("CastlePortal"), mats, "castle")
	_dress_portal(hub.get_node_or_null("UmbralEndlessPortal"), mats, "umbral")
	_dress_portal(hub.get_node_or_null("UmbralWavesPortal"), mats, "umbral")
	_dress_portal(hub.get_node_or_null("ArenaDoor"), mats, "training")
	_dress_blacksmith(hub.get_node_or_null("Blacksmith"), mats)
	_dress_merchant(hub.get_node_or_null("Merchant"), mats)
	_dress_storage(hub.get_node_or_null("Storage"), mats)
	_dress_quest_board(hub.get_node_or_null("QuestBoard"), mats)
	_spawn_fountain(hub, mats)
	_dress_plaza(hub, mats)
	_spawn_growth_props(hub, mats)
	_merge_static_dressing(hub)
	HubFauna.apply(hub)
	_dress_npcs(hub)
	_position_npcs_from_content(hub)
	_wire_interact_feedback(hub)


## Folds each area's static models into one mesh per material: the hub is hundreds of pieces and
## would otherwise cost a draw call each. Things that move or flicker carry `no_merge`.
static func _merge_static_dressing(hub: Node3D) -> void:
	for area_name in ["PlazaDressing", "PlazaFountain", "GrowthProps", "DioramaFloorProps"]:
		var area := hub.get_node_or_null(area_name) as Node3D
		if area != null:
			PropMerger.merge_static(area)
	for service_name in SERVICE_TENTS.keys():
		var tent := hub.get_node_or_null("%s/DioramaVisuals" % service_name) as Node3D
		if tent != null:
			PropMerger.merge_static(tent)
	var parapet := hub.get_node_or_null("LandmarkWalls/TowerParapet") as Node3D
	if parapet != null:
		PropMerger.merge_static(parapet)


static func _load_materials() -> Dictionary:
	return PixelDioramaStyle.make_hub_materials()


static func _style_environment(hub: Node3D) -> void:
	if OS.has_environment("AUMBRYE_NO_ENV"):
		return
	VisualLighting.apply_hub(hub)


## A Blender hub prop (tools/blender/props_hub_*.py) placed under `parent`. `mats` is the hub's
## material set; `extra` overrides or adds roles for this one piece (a bloom colour, a sooted canvas).
static func _place(
	parent: Node3D,
	id: String,
	mats: Dictionary,
	node_name: String,
	pos: Vector3 = Vector3.ZERO,
	yaw: float = 0.0,
	extra: Dictionary = {},
	prop_scale: Vector3 = Vector3.ONE
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = pos
	holder.rotation.y = yaw
	holder.scale = prop_scale
	parent.add_child(holder)
	var materials := mats.duplicate()
	materials.merge(extra, true)
	PropLibrary.attach_themed(holder, "hub/" + id, PixelDioramaStyle.PaletteTheme.HUB, {"materials": materials})
	return holder


static func _dress_floor(hub: Node3D, mats: Dictionary) -> void:
	var floor_body := hub.get_node_or_null("Floor") as StaticBody3D
	if floor_body == null:
		return
	floor_body.set_meta("surface", "stone")
	var floor_mesh := floor_body.get_node_or_null("MeshInstance3D") as MeshInstance3D
	if floor_mesh:
		floor_mesh.visible = false

	# Ten-metre paving modules, alternating their checker so the pattern runs unbroken.
	var by_parity: Array = [[] as Array[Transform3D], [] as Array[Transform3D]]
	for column in int(FLOOR_WIDTH / 10.0):
		for row in int(FLOOR_DEPTH / 10.0):
			(by_parity[(column + row) % 2] as Array[Transform3D]).append(
				Transform3D(
					Basis.IDENTITY,
					Vector3(-FLOOR_WIDTH * 0.5 + 5.0 + column * 10.0, 0.0, -FLOOR_DEPTH * 0.5 + 5.0 + row * 10.0)
				)
			)
	for parity in 2:
		PropLibrary.scatter_themed(
			hub, "hub/floor_module_%d" % parity, PixelDioramaStyle.PaletteTheme.HUB,
			by_parity[parity] as Array[Transform3D], "DioramaTiles%d" % parity, {"materials": mats}
		)

	var tiles := Node3D.new()
	tiles.name = "DioramaFloorProps"
	hub.add_child(tiles)
	_spawn_tent_door_pads(tiles, mats, hub)


static func _spawn_tent_door_pads(tiles: Node3D, mats: Dictionary, hub: Node3D) -> void:
	for service_name in SERVICE_TENTS.keys():
		var hub_pos: Vector3 = _service_world_position(hub, service_name)
		var cfg: Dictionary = SERVICE_TENTS[service_name]
		var yaw: float = _service_yaw(hub, service_name)
		var half_d: float = float(cfg.get("depth", 5.0)) * 0.5
		var door_dir: Vector3 = Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, yaw)
		var pad_pos: Vector3 = hub_pos + door_dir * (half_d + 0.55)
		_place(
			tiles, "door_pad", mats, "%sDoorPad" % service_name, Vector3(pad_pos.x, 0.0, pad_pos.z), yaw, {},
			Vector3(float(cfg.get("entrance", 2.0)) + 0.4, 1.0, 1.0)
		)


static func _service_world_position(hub: Node3D, service_name: String) -> Vector3:
	var node := hub.get_node_or_null(service_name) as Node3D
	return node.position if node else Vector3.ZERO


static func _plaza_facing_yaw(world_pos: Vector3) -> float:
	var to_plaza := Vector3(0.0, 0.0, 0.0) - world_pos
	to_plaza.y = 0.0
	if to_plaza.length_squared() < 0.001:
		return 0.0
	return atan2(to_plaza.x, to_plaza.z)


static func _service_yaw(hub: Node3D, service_name: String) -> float:
	return _plaza_facing_yaw(_service_world_position(hub, service_name))


static func _spawn_fountain(hub: Node3D, mats: Dictionary) -> void:
	if hub.get_node_or_null("PlazaFountain") != null:
		return
	PixelDioramaStyle.add_hub_fountain(hub, mats, FOUNTAIN_POS)


static func _dress_plaza(hub: Node3D, mats: Dictionary) -> void:
	if hub.get_node_or_null("PlazaDressing") != null:
		return
	var dressing := Node3D.new()
	dressing.name = "PlazaDressing"
	hub.add_child(dressing)
	_spawn_gate_braziers(dressing, mats)
	_spawn_banner_avenue(dressing, mats)
	_spawn_market_clutter(dressing, mats)
	_spawn_planting(dressing, mats)
	_spawn_fountain_benches(dressing, mats)
	_spawn_bunting(dressing, mats)
	_spawn_market_carts(dressing, mats)
	_spawn_woodpiles(dressing, mats)
	_spawn_stall_planters(hub, dressing, mats)
	_spawn_grim_dressing(dressing, mats)


static func _spawn_grim_dressing(parent: Node3D, mats: Dictionary) -> void:
	var iron := PixelDioramaStyle.make_metal_material(Color(0.23, 0.23, 0.27), 0.34)

	for i in 4:
		var sx := -1.0 if i % 2 == 0 else 1.0
		var z := -13.5 if i < 2 else -5.5
		_spawn_broken_column(parent, mats, Vector3(sx * 20.8, 0.0, z), i)

	for spot in [
		Vector3(-3.9, 0.0, -11.2),
		Vector3(3.9, 0.0, -11.2),
		Vector3(-20.6, 0.0, 12.8),
		Vector3(20.6, 0.0, 12.8),
	]:
		_spawn_votive_cairn(parent, mats, spot)

	for x in [0.0, -9.0, 9.0, -18.5, 18.5]:
		_spawn_railing(parent, mats, iron, Vector3(x, 0.0, GATE_ROW_Z - 1.35))


static func _spawn_broken_column(parent: Node3D, mats: Dictionary, base: Vector3, index: int) -> void:
	_place(parent, "broken_column_%d" % index, mats, "BrokenColumn%d" % index, base, float(index) * 0.7)


static func _spawn_votive_cairn(parent: Node3D, mats: Dictionary, base: Vector3) -> void:
	var root := _place(parent, "votive_cairn", mats, "VotiveCairn%s" % str(base), base)
	var glow := OmniLight3D.new()
	glow.name = "CairnGlow"
	glow.light_color = Color(1.0, 0.74, 0.4)
	glow.light_energy = 0.55
	glow.omni_range = 3.4
	glow.shadow_enabled = false
	glow.position = Vector3(0.0, 0.85, 0.0)
	glow.add_to_group(NightLights.GROUP)
	root.add_child(glow)


## `HubGrowthService` unlocks entries from run progress -- a banner, a trophy hall, a
## working forge -- and until now the hub never visibly changed when they did; the growth was a
## list in a menu nobody walked past. Each entry's own `anchor`/`prop` fields (authored in
## `content/ui/hub_growth.json` for exactly this) now build a real object near the area they name.
## Two entries sharing an anchor (`banner_row` after `banner_first_clear`) offset along a row
## instead of overlapping, so the plaza visibly accumulates rather than one prop replacing another.
static func _spawn_growth_props(hub: Node3D, mats: Dictionary) -> void:
	if hub.get_node_or_null("GrowthProps") != null:
		return
	var root := Node3D.new()
	root.name = "GrowthProps"
	hub.add_child(root)
	var slot_by_anchor: Dictionary = {}
	for entry in HubGrowthService.get_all():
		var entry_id := str(entry.get("id", ""))
		var anchor := str(entry.get("anchor", "courtyard"))
		var slot := int(slot_by_anchor.get(anchor, 0))
		slot_by_anchor[anchor] = slot + 1
		if not HubGrowthService.is_unlocked(entry_id):
			continue
		var base := _growth_anchor_position(hub, anchor) + Vector3(float(slot) * 1.7, 0.0, 0.0)
		match str(entry.get("prop", "")):
			"banner":
				_spawn_growth_banner(root, mats, base, entry_id)
			"trophy":
				_spawn_growth_trophy(root, mats, base, entry_id)
			"marker":
				_spawn_growth_marker(root, mats, base, entry_id)
			"shelf":
				_spawn_growth_shelf(root, mats, base, entry_id)
			"forge":
				_spawn_growth_workshop(root, mats, base, entry_id)
			"board":
				_spawn_growth_board(root, mats, base, entry_id)
			"shrine":
				_spawn_votive_cairn(root, mats, base)
		var growth_root := root.get_child(root.get_child_count() - 1) as Node3D
		if growth_root and str(entry.get("prop", "")) in ["shelf", "marker"]:
			_add_growth_interaction(growth_root, entry)
	PropMerger.merge_static(root)


static func _add_growth_interaction(growth_root: Node3D, entry: Dictionary) -> void:
	var entry_id := str(entry.get("id", ""))
	var prop := str(entry.get("prop", ""))
	if entry_id == "" or prop not in ["shelf", "marker"]:
		return
	var area := HubInteractable.new()
	area.name = "InteractArea"
	area.interact_id = "growth:%s:%s" % [prop, entry_id]
	area.display_name = "Archive" if prop == "shelf" else "Record Stone"
	area.collision_layer = 0
	area.collision_mask = 2
	var shape := CollisionShape3D.new()
	shape.name = "CollisionShape3D"
	var box := BoxShape3D.new()
	box.size = Vector3(2.2, 2.4, 2.0)
	shape.shape = box
	shape.position = Vector3(0.0, 1.1, 0.0)
	area.add_child(shape)
	growth_root.add_child(area)


static func reconcile_growth_props(hub: Node3D) -> void:
	var existing := hub.get_node_or_null("GrowthProps")
	if existing != null:
		hub.remove_child(existing)
		existing.queue_free()
	_spawn_growth_props(hub, _load_materials())


## No literal "great hall" or "undercroft" room exists in this hub -- it is one plaza. `workshop`
## and `undercroft` read off the Blacksmith/Storage tents already anchoring the plaza's two back
## corners; `great_hall` and `courtyard` are fixed open spots (north wall / south of the fountain)
## chosen clear of the columns, cairns, carts and gate row `_spawn_grim_dressing()`/`_dress_plaza()`
## already seat.
static func _growth_anchor_position(hub: Node3D, anchor: String) -> Vector3:
	match anchor:
		"workshop":
			return _service_world_position(hub, "Blacksmith") + Vector3(2.8, 0.0, 1.6)
		"undercroft":
			return _service_world_position(hub, "Storage") + Vector3(-2.8, 0.0, 1.6)
		"great_hall":
			return Vector3(-4.0, 0.0, -13.0)
		_:
			return Vector3(-4.0, 0.0, 10.5)


static func _spawn_growth_banner(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	var root := _place(parent, "growth_banner_pole", mats, "GrowthBanner_%s" % node_name, base)
	var vane := Node3D.new()
	vane.name = "Vane"
	vane.set_script(BannerVaneScript)
	vane.set_meta(PropMerger.NO_MERGE_META, true)
	root.add_child(vane)
	_place(vane, "banner_cloth_growth", mats, "Cloth")


static func _spawn_growth_trophy(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	_place(parent, "growth_trophy", mats, "GrowthTrophy_%s" % node_name, base)


static func _spawn_growth_marker(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	var root := _place(parent, "growth_marker", mats, "GrowthMarker_%s" % node_name, base)
	root.set_meta("growth_entry", node_name)
	root.set_meta("growth_kind", "record")


static func _spawn_growth_shelf(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	var root := _place(parent, "growth_shelf", mats, "GrowthShelf_%s" % node_name, base)
	root.set_meta("growth_entry", node_name)
	root.set_meta("growth_kind", "archive")


static func _spawn_growth_board(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	_place(parent, "growth_board", mats, "GrowthBoard_%s" % node_name, base)


static func _spawn_railing(parent: Node3D, mats: Dictionary, iron: Material, centre: Vector3) -> void:
	_place(parent, "railing", mats, "Railing%s" % str(centre), centre, 0.0, {"hub_iron": iron})


static func _spawn_gate_braziers(parent: Node3D, mats: Dictionary) -> void:
	var first_x := -GATE_SPACING * (GATE_COUNT - 1) * 0.5
	for gate in GATE_COUNT:
		var gate_x := first_x + gate * GATE_SPACING
		_spawn_brazier(
			parent,
			mats,
			Vector3(gate_x + 2.6, 0.0, GATE_ROW_Z + 2.4),
			"Gate%dBrazier" % gate
		)


static func _spawn_brazier(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	var root := _place(parent, "brazier", mats, node_name, base)
	var coals := root.get_node_or_null("Coals") as MeshInstance3D
	if coals != null:
		coals.set_meta(PropMerger.NO_MERGE_META, true)
	var light := OmniLight3D.new()
	light.name = "BrazierLight"
	light.light_color = Color(1.0, 0.62, 0.26)
	light.light_energy = 1.05
	light.omni_range = 6.5
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.7, 0.0)
	light.add_to_group(NightLights.GROUP)
	root.add_child(light)
	LightEmbers.attach(root, Vector3(0.0, 1.6, 0.0), light.light_color, 2.0, 1.6)
	var flicker := ForgeFlickerScript.new()
	flicker.name = "BrazierFlicker"
	root.add_child(flicker)
	flicker.setup(light, coals)


static func _spawn_growth_workshop(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	var root := _place(parent, "growth_workshop", mats, "GrowthWorkshop_%s" % node_name, base)
	_spawn_brazier(root, mats, Vector3(1.45, 0.0, 0.1), "Forge")
	if node_name == "workshop_annex":
		var worker := Node3D.new()
		worker.name = "AnnexSmith"
		worker.position = Vector3(-0.72, 0.0, 0.76)
		worker.rotation.y = PI
		root.add_child(worker)
		DioramaCharacterSkin.build_preview_body(worker, _npc_appearance("blacksmith"))


# Porch lanterns for a service tent.
#
# The tents each carried one lamp, tucked inside against the back wall, so at dusk the plaza was a
# ring of dark canvas with a glow somewhere behind it and no light on the ground anyone walks on.
# These sit outside: a pair on posts flanking the entrance and one hung under each eave. They are in
# the `NightLights` group like everything else, so they come up through the dusk ramp on their own
# stagger rather than all together.
static func _spawn_tent_lanterns(
	visuals: Node3D, mats: Dictionary, width: float, depth: float, wall_height: float
) -> void:
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var root := Node3D.new()
	root.name = "TentLanterns"
	visuals.add_child(root)
	for raw_side in [-1.0, 1.0]:
		var side: float = raw_side
		var side_tag: String = "R" if side > 0.0 else "L"
		# The entrance pair, on their own posts just clear of the guy ropes. The post model's arm
		# reaches toward +x, so the right-hand post is turned half way round to reach back in.
		var post_x := side * (half_w + 0.5)
		var post_z := half_d + 0.45
		var post_top := wall_height + 0.5
		_place(
			root, "porch_post", mats, "PorchPost%s" % side_tag, Vector3(post_x, 0.0, post_z),
			PI if side > 0.0 else 0.0, {}, Vector3(1.0, post_top / 3.0, 1.0)
		)
		_spawn_tent_lantern(
			root,
			mats,
			Vector3(post_x - side * 0.32, post_top - 0.34, post_z),
			"PorchLantern%s" % side_tag,
			0.85
		)
		# One under each eave, so the flanks of the tent are lit as well as its face.
		_spawn_tent_lantern(
			root,
			mats,
			Vector3(side * (half_w + 0.12), wall_height - 0.12, 0.0),
			"EaveLantern%s" % side_tag,
			0.6
		)


static func _spawn_tent_lantern(
	parent: Node3D, mats: Dictionary, at: Vector3, node_name: String, strength: float
) -> void:
	_place(parent, "lantern", mats, node_name + "Fixture", at)
	var lamp := OmniLight3D.new()
	lamp.name = node_name
	lamp.light_color = LANTERN_LIGHT_COLOR
	lamp.light_energy = LANTERN_ENERGY * strength
	lamp.omni_range = LANTERN_RANGE
	lamp.shadow_enabled = false
	lamp.position = at
	lamp.add_to_group(NightLights.GROUP)
	parent.add_child(lamp)
	VisualLighting.attach_flicker(lamp, 0.08, 5.5)
	LightEmbers.attach(parent, at + Vector3(0.0, 0.14, 0.0), LANTERN_LIGHT_COLOR, 0.35, 0.45)


static func _spawn_banner_avenue(parent: Node3D, mats: Dictionary) -> void:
	for i in 4:
		var z := -2.0 + i * 4.5
		for side in [-1.0, 1.0]:
			var root := _place(
				parent, "banner_avenue_pole", mats, "Banner%d%s" % [i, "R" if side > 0.0 else "L"],
				Vector3(side * 5.5, 0.0, z)
			)
			var vane := Node3D.new()
			vane.name = "Vane"
			vane.set_script(BannerVaneScript)
			vane.set_meta(PropMerger.NO_MERGE_META, true)
			root.add_child(vane)
			_place(vane, "banner_cloth_avenue", mats, "Cloth")


static func _spawn_market_clutter(parent: Node3D, mats: Dictionary) -> void:
	var spots := [
		{"pos": Vector3(-12.6, 0.0, 1.6), "seed": 0},
		{"pos": Vector3(12.6, 0.0, 1.6), "seed": 1},
		{"pos": Vector3(-14.6, 0.0, 11.4), "seed": 2},
		{"pos": Vector3(14.6, 0.0, 11.4), "seed": 3},
		{"pos": Vector3(-20.5, 0.0, 3.0), "seed": 4},
		{"pos": Vector3(20.5, 0.0, 3.0), "seed": 5},
	]
	for spot in spots:
		var index: int = spot["seed"]
		_place(parent, "market_clutter", mats, "Clutter%d" % index, spot["pos"], float(index) * 1.1)


static func _spawn_planting(parent: Node3D, mats: Dictionary) -> void:
	var spots := [
		{"pos": Vector3(-22.0, 0.0, -10.5), "scale": 1.0},
		{"pos": Vector3(22.0, 0.0, -10.5), "scale": 1.15},
		{"pos": Vector3(-22.2, 0.0, 16.0), "scale": 1.2},
		{"pos": Vector3(22.2, 0.0, 16.0), "scale": 1.0},
		{"pos": Vector3(-10.8, 0.0, 15.6), "scale": 0.85},
		{"pos": Vector3(10.8, 0.0, 15.6), "scale": 0.95},
	]
	for i in spots.size():
		var spot: Dictionary = spots[i]
		_spawn_planter_tree(parent, mats, spot["pos"], float(spot["scale"]), "PlanterTree%d" % i)

	for i in 4:
		var x := -16.5 + i * 11.0
		_spawn_flower_trough(
			parent,
			mats,
			Vector3(x, 0.0, 16.4),
			BLOOM_COLORS[i % BLOOM_COLORS.size()],
			"SouthTrough%d" % i
		)


static func _spawn_planter_tree(
	parent: Node3D, mats: Dictionary, base: Vector3, height_scale: float, node_name: String
) -> void:
	_place(parent, "planter_tree", mats, node_name, base, 0.0, {}, Vector3.ONE * height_scale)


static func _spawn_flower_trough(
	parent: Node3D, mats: Dictionary, base: Vector3, bloom: Color, node_name: String
) -> void:
	_place(parent, "flower_trough", mats, node_name, base, 0.0, {"bloom": PixelDioramaStyle.make_material(bloom)})


static func _spawn_fountain_benches(parent: Node3D, mats: Dictionary) -> void:
	var radius := 3.9
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var offset := Vector3(sin(angle), 0.0, cos(angle)) * radius
		_spawn_bench(
			parent,
			mats,
			FOUNTAIN_POS + offset,
			angle + PI,
			"FountainBench%d" % i
		)


static func _spawn_bench(
	parent: Node3D, mats: Dictionary, base: Vector3, yaw: float, node_name: String
) -> void:
	_place(parent, "bench", mats, node_name, base, yaw)


static func _spawn_bunting(parent: Node3D, mats: Dictionary) -> void:
	for i in 4:
		var z := -2.0 + i * 4.5
		_spawn_lantern_cord(parent, mats, Vector3(-5.5, 0.0, z), Vector3(5.5, 0.0, z), "Bunting%d" % i)


static func _spawn_lantern_cord(
	parent: Node3D, mats: Dictionary, from: Vector3, to: Vector3, node_name: String
) -> void:
	var root := _place(
		parent, "lantern_cord", mats, node_name, (from + to) * 0.5, atan2(to.x - from.x, to.z - from.z)
	)
	var span := from.distance_to(to)
	var count := 5
	for i in count:
		var t := float(i + 1) / float(count + 1)
		var z := -span * 0.5 + span * t
		var drop := 0.2 + float(i % 2) * 0.1
		var glass_pos := Vector3(0.0, BUNTING_Y - drop - 0.24, z)
		var lamp := OmniLight3D.new()
		lamp.name = "LanternLight%d" % i
		lamp.light_color = LANTERN_LIGHT_COLOR
		lamp.light_energy = LANTERN_ENERGY
		lamp.omni_range = LANTERN_RANGE
		lamp.shadow_enabled = false
		lamp.position = glass_pos
		lamp.add_to_group(NightLights.GROUP)
		root.add_child(lamp)
		LightEmbers.attach(root, glass_pos + Vector3(0.0, 0.16, 0.0), LANTERN_LIGHT_COLOR, 0.4, 0.5)


static func _spawn_market_carts(parent: Node3D, mats: Dictionary) -> void:
	_spawn_cart(parent, mats, Vector3(-9.2, 0.0, 4.8), -0.5, "CartWest")
	_spawn_cart(parent, mats, Vector3(9.2, 0.0, 4.8), 0.5, "CartEast")


static func _spawn_cart(
	parent: Node3D, mats: Dictionary, base: Vector3, yaw: float, node_name: String
) -> void:
	_place(parent, "cart", mats, node_name, base, yaw)


static func _spawn_woodpiles(parent: Node3D, mats: Dictionary) -> void:
	_spawn_woodpile(parent, mats, Vector3(-12.6, 0.0, -5.4), 0.35, "WoodpileForge")
	_spawn_woodpile(parent, mats, Vector3(-11.0, 0.0, 8.5), -0.3, "WoodpileStore")


static func _spawn_woodpile(
	parent: Node3D, mats: Dictionary, base: Vector3, yaw: float, node_name: String
) -> void:
	_place(parent, "woodpile", mats, node_name, base, yaw)


static func _spawn_stall_planters(hub: Node3D, parent: Node3D, mats: Dictionary) -> void:
	for service_name in SERVICE_TENTS.keys():
		var cfg: Dictionary = SERVICE_TENTS[service_name]
		var origin: Vector3 = _service_world_position(hub, service_name)
		var yaw: float = _service_yaw(hub, service_name)
		var door_dir := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, yaw)
		var across_dir := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, yaw)
		var out: float = float(cfg["depth"]) * 0.5 + 0.5
		var across: float = float(cfg["entrance"]) * 0.5 + 0.75
		for side in [-1.0, 1.0]:
			_spawn_pot(
				parent,
				mats,
				origin + door_dir * out + across_dir * (side * across),
				BLOOM_COLORS[int(absf(side) + across) % BLOOM_COLORS.size()],
				"%sPot%s" % [service_name, "R" if side > 0.0 else "L"]
			)


static func _spawn_pot(
	parent: Node3D, mats: Dictionary, base: Vector3, bloom: Color, node_name: String
) -> void:
	_place(parent, "pot", mats, node_name, base, 0.0, {"bloom": PixelDioramaStyle.make_material(bloom)})


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

	PixelDioramaStyle.add_castle_parapet_run(
		parapet_root,
		mats,
		Vector3(0.0, parapet_h * 0.5, -half_d),
		north_south_len,
		parapet_thick,
		parapet_h,
		0.0,
		"NorthParapet"
	)
	PixelDioramaStyle.add_castle_parapet_run(
		parapet_root,
		mats,
		Vector3(0.0, parapet_h * 0.5, half_d),
		north_south_len,
		parapet_thick,
		parapet_h,
		0.0,
		"SouthParapet"
	)
	PixelDioramaStyle.add_castle_parapet_run(
		parapet_root,
		mats,
		Vector3(half_w, parapet_h * 0.5, 0.0),
		east_west_len,
		parapet_thick,
		parapet_h,
		PI * 0.5,
		"EastParapet"
	)
	PixelDioramaStyle.add_castle_parapet_run(
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
		PixelDioramaStyle.add_castle_corner_turret(parapet_root, mats, corner, parapet_h)

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

	PixelDioramaStyle.add_castle_parapet_collision(
		wall_collision, half_w, half_d, parapet_thick, WALL_COLLISION_HEIGHT
	)


const PORTAL_HUM_DB := -15.0
const PORTAL_HUM_RANGE := 17.0
const PORTAL_HUM_NAME := "PortalHum"


static func _dress_portal(portal: Node3D, mats: Dictionary, theme: String) -> void:
	if portal == null:
		return
	if not portal.visible:
		return
	var def := PortalCatalog.resolve(theme)
	PixelDioramaStyle.build_portal(portal, def, 1.0, mats)
	_attach_portal_hum(portal, theme)


static func _attach_portal_hum(portal: Node3D, theme: String) -> void:
	if portal.has_node(PORTAL_HUM_NAME):
		return
	var path := "res://assets/audio/sfx/portal_hum_%s.ogg" % theme
	if not ResourceLoader.exists(path):
		return
	var stream := load(path) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer3D.new()
	player.name = PORTAL_HUM_NAME
	player.stream = stream
	player.bus = &"SFX"
	player.volume_db = PORTAL_HUM_DB
	player.max_distance = PORTAL_HUM_RANGE
	player.unit_size = 4.0
	player.attenuation_model = AudioStreamPlayer3D.ATTENUATION_INVERSE_SQUARE_DISTANCE
	player.autoplay = true
	portal.add_child(player)


static func _dress_blacksmith(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	var hub := building.get_parent() as Node3D
	PixelDioramaStyle.hide_legacy_meshes(building)
	var sooted := (mats.canvas as ShaderMaterial).duplicate() as ShaderMaterial
	sooted.set_shader_parameter("color_base", Color(0.40, 0.34, 0.29))
	sooted.set_shader_parameter("color_shadow", Color(0.24, 0.20, 0.18))
	sooted.set_shader_parameter("color_accent", Color(0.47, 0.39, 0.32))
	var tent_mats := mats.duplicate()
	tent_mats.canvas = sooted

	var yaw := _service_yaw(hub, "Blacksmith")
	var cfg: Dictionary = SERVICE_TENTS["Blacksmith"]
	var width: float = cfg["width"]
	var depth: float = cfg["depth"]
	var wall_height: float = cfg["wall_height"]
	var entrance_width: float = cfg["entrance"]
	var roof_peak: float = cfg["roof_peak"]
	var visuals := PixelDioramaStyle.add_hub_tent(
		building, tent_mats, width, depth, wall_height, entrance_width, roof_peak, yaw
	)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	var back := -depth * 0.5 + 0.9
	_place(dressing, "dressing_blacksmith", tent_mats, "Interior")
	var forge := dressing.get_node("Interior/Forge") as MeshInstance3D
	forge.set_meta(PropMerger.NO_MERGE_META, true)
	var forge_mat := (mats.forge as Material).duplicate()
	for surface in forge.mesh.get_surface_count():
		forge.set_surface_override_material(surface, forge_mat)

	var forge_light := OmniLight3D.new()
	forge_light.name = "ForgeLight"
	forge_light.light_color = Color(1.0, 0.55, 0.22)
	forge_light.light_energy = 1.15
	forge_light.omni_range = 4.5
	forge_light.position = Vector3(1.3, 1.1, back)
	forge_light.add_to_group(NightLights.GROUP)
	dressing.add_child(forge_light)
	LightEmbers.attach(dressing, Vector3(1.3, 1.0, back), forge_light.light_color, 1.6, 1.2)

	var flicker := ForgeFlickerScript.new()
	flicker.name = "ForgeFlicker"
	dressing.add_child(flicker)
	flicker.setup(forge_light, forge)

	_spawn_tent_lanterns(visuals, mats, width, depth, wall_height)
	_add_ridge_sign(visuals, depth * 0.5, wall_height + roof_peak, mats)
	_position_door_interact(building, width, depth, wall_height, wall_height + roof_peak, yaw)


static func _dress_merchant(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	var hub := building.get_parent() as Node3D
	PixelDioramaStyle.hide_legacy_meshes(building)
	var yaw := _service_yaw(hub, "Merchant")
	var cfg: Dictionary = SERVICE_TENTS["Merchant"]
	var width: float = cfg["width"]
	var depth: float = cfg["depth"]
	var wall_height: float = cfg["wall_height"]
	var entrance_width: float = cfg["entrance"]
	var roof_peak: float = cfg["roof_peak"]
	var half_d := depth * 0.5
	var visuals := PixelDioramaStyle.add_hub_tent(
		building, mats, width, depth, wall_height, entrance_width, roof_peak, yaw
	)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	var back := -half_d + 0.6
	_place(dressing, "dressing_merchant", mats, "Interior")

	var lantern := OmniLight3D.new()
	lantern.name = "LanternLight"
	lantern.light_color = Color(1.0, 0.82, 0.55)
	lantern.light_energy = 0.7
	lantern.omni_range = 3.8
	lantern.position = Vector3(0.0, wall_height - 0.2, back + 1.0)
	lantern.add_to_group(NightLights.GROUP)
	dressing.add_child(lantern)
	LightEmbers.attach(dressing, lantern.position, lantern.light_color, 0.5, 0.6)

	_spawn_tent_lanterns(visuals, mats, width, depth, wall_height)
	_add_ridge_sign(visuals, depth * 0.5, wall_height + roof_peak, mats)
	_position_door_interact(building, width, depth, wall_height, wall_height + roof_peak, yaw)


static func _dress_storage(building: Node3D, mats: Dictionary) -> void:
	if building == null:
		return
	var hub := building.get_parent() as Node3D
	PixelDioramaStyle.hide_legacy_meshes(building)
	var yaw := _service_yaw(hub, "Storage")
	var cfg: Dictionary = SERVICE_TENTS["Storage"]
	var width: float = cfg["width"]
	var depth: float = cfg["depth"]
	var wall_height: float = cfg["wall_height"]
	var entrance_width: float = cfg["entrance"]
	var roof_peak: float = cfg["roof_peak"]
	var visuals := PixelDioramaStyle.add_hub_tent(
		building, mats, width, depth, wall_height, entrance_width, roof_peak, yaw
	)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	var back := -depth * 0.5 + 0.4
	_place(dressing, "dressing_storage", mats, "Interior")

	var lamp := OmniLight3D.new()
	lamp.name = "StorageLight"
	lamp.light_color = Color(1.0, 0.80, 0.48)
	lamp.light_energy = 0.55
	lamp.omni_range = 3.5
	lamp.position = Vector3(0.0, wall_height - 0.15, back + 1.0)
	lamp.add_to_group(NightLights.GROUP)
	dressing.add_child(lamp)
	LightEmbers.attach(dressing, lamp.position, lamp.light_color, 0.5, 0.6)

	_spawn_tent_lanterns(visuals, mats, width, depth, wall_height)
	_add_ridge_sign(visuals, depth * 0.5, wall_height + roof_peak, mats)
	_position_door_interact(building, width, depth, wall_height, wall_height + roof_peak, yaw)


static func _dress_quest_board(board: Node3D, mats: Dictionary) -> void:
	if board == null:
		return
	var hub := board.get_parent() as Node3D
	PixelDioramaStyle.hide_legacy_meshes(board)
	var yaw := _service_yaw(hub, "QuestBoard")
	var cfg: Dictionary = SERVICE_TENTS["QuestBoard"]
	var width: float = cfg["width"]
	var depth: float = cfg["depth"]
	var wall_height: float = cfg["wall_height"]
	var entrance_width: float = cfg["entrance"]
	var roof_peak: float = cfg["roof_peak"]
	var half_d := depth * 0.5
	var visuals := PixelDioramaStyle.add_hub_tent(
		board, mats, width, depth, wall_height, entrance_width, roof_peak, yaw
	)
	var dressing := Node3D.new()
	dressing.name = "Dressing"
	visuals.add_child(dressing)

	var back := -half_d + 0.2
	_place(dressing, "dressing_questboard", mats, "Interior")

	var paper_light := OmniLight3D.new()
	paper_light.name = "QuestLight"
	paper_light.light_color = Color(0.95, 0.88, 0.72)
	paper_light.light_energy = 0.5
	paper_light.omni_range = 3.2
	paper_light.position = Vector3(0.0, 1.9, back + 0.9)
	paper_light.add_to_group(NightLights.GROUP)
	dressing.add_child(paper_light)
	LightEmbers.attach(dressing, paper_light.position, paper_light.light_color, 0.5, 0.6)

	_spawn_tent_lanterns(visuals, mats, width, depth, wall_height)
	_add_ridge_sign(visuals, depth * 0.5, wall_height + roof_peak, mats)
	_position_door_interact(board, width, depth, wall_height, wall_height + roof_peak, yaw)


static func _add_ridge_sign(
	visuals: Node3D, half_depth: float, ridge_y: float, mats: Dictionary
) -> void:
	_place(visuals, "ridge_sign", mats, "RidgeSign", Vector3(0.0, ridge_y - 0.1, half_depth + 0.3))


static func _position_door_interact(
	building: Node3D,
	width: float,
	depth: float,
	wall_height: float,
	ridge_y: float,
	facing_yaw: float
) -> void:
	var area := building.get_node_or_null("InteractArea") as Area3D
	if area == null:
		return
	var half_d := depth * 0.5
	var door_dir := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, facing_yaw)
	var zone_depth := depth * 0.66
	var centre_offset := -half_d + zone_depth * 0.5 + 0.1
	area.position = door_dir * centre_offset + Vector3(0.0, wall_height * 0.5, 0.0)
	area.rotation.y = facing_yaw

	var shape_node := area.get_node_or_null("CollisionShape3D") as CollisionShape3D
	if shape_node == null:
		return
	shape_node.transform = Transform3D.IDENTITY
	var box := shape_node.shape as BoxShape3D
	if box == null:
		box = BoxShape3D.new()
		shape_node.shape = box
	box.size = Vector3(width - 0.4, wall_height, zone_depth)
	shape_node.position = Vector3.ZERO

	var label := building.get_node_or_null("Label") as Label3D
	if label:
		label.position = door_dir * (half_d + 0.3) + Vector3(0.0, ridge_y + 0.85, 0.0)


static func _wire_interact_feedback(hub: Node3D) -> void:
	var service_map := {
		"Blacksmith": "DioramaVisuals/RidgeSign/SignBacking",
		"Merchant": "DioramaVisuals/RidgeSign/SignBacking",
		"Storage": "DioramaVisuals/RidgeSign/SignBacking",
		"QuestBoard": "DioramaVisuals/RidgeSign/SignBacking",
	}
	for service_name in service_map.keys():
		var building := hub.get_node_or_null(service_name) as Node3D
		if building == null:
			continue
		var area := building.get_node_or_null("InteractArea") as HubInteractable
		if area == null:
			continue
		var ridge := building.get_node_or_null(service_map[service_name]) as Node3D
		if ridge != null:
			area.highlight_target = area.get_path_to(ridge)

	var portal_names := [
		"CastlePortal",
		"UmbralEndlessPortal",
		"UmbralWavesPortal",
		"ArenaDoor",
	]
	for portal_name in portal_names:
		var portal := hub.get_node_or_null(portal_name) as Node3D
		if portal == null:
			continue
		var portal_area := portal.get_node_or_null("InteractArea") as HubInteractable
		if portal_area == null:
			continue
		var glow := portal.get_node_or_null("DioramaVisuals/PortalGlow") as Node3D
		if glow != null:
			portal_area.highlight_target = portal_area.get_path_to(glow)


static func _dress_npcs(hub: Node3D) -> void:
	for child in hub.get_children():
		if not child.is_in_group("hub_npc"):
			continue
		_style_npc(child as Node3D)


static func _position_npcs_from_content(hub: Node3D) -> void:
	for npc in hub.get_children():
		if not npc.is_in_group("hub_npc"):
			continue
		var npc_id := ""
		var npc_node := npc as NpcBase
		if npc_node != null:
			npc_id = npc_node.get_npc_id()
		elif "npc_id" in npc:
			npc_id = str(npc.get("npc_id"))
		if npc_id == "":
			continue
		var def := NpcCatalog.get_definition(npc_id)
		var pos: Variant = def.get("position", null)
		if pos is Dictionary:
			(npc as Node3D).position = Vector3(
				float(pos.get("x", 0.0)), float(pos.get("y", 0.0)), float(pos.get("z", 0.0))
			)


static func _style_npc(npc: Node3D) -> void:
	var npc_id := ""
	if npc.has_method("get_npc_id"):
		npc_id = str(npc.call("get_npc_id"))
	elif "npc_id" in npc:
		npc_id = str(npc.get("npc_id"))

	var body := npc.get_node_or_null("Body") as MeshInstance3D
	if body:
		body.visible = false

	var existing := npc.get_node_or_null("DioramaBody")
	if existing:
		existing.free()

	var visuals := Node3D.new()
	visuals.name = "DioramaBody"
	npc.add_child(visuals)
	DioramaCharacterSkin.build_preview_body(visuals, _npc_appearance(npc_id))


static func _npc_appearance(npc_id: String) -> Dictionary:
	var authored: Variant = NpcCatalog.get_definition(npc_id).get("appearance", null)
	if authored is Dictionary and not (authored as Dictionary).is_empty():
		_warn_unknown_appearance(npc_id, authored as Dictionary)
		return authored as Dictionary
	return CharacterAppearance.default_profile()


static func _warn_unknown_appearance(npc_id: String, authored: Dictionary) -> void:
	var clean := CharacterAppearance.sanitize(authored)
	for key: String in authored:
		if not clean.has(key):
			continue
		if not (authored[key] is String):
			continue
		if str(clean[key]) != str(authored[key]):
			push_warning(
				"HubDiorama: npc %s appearance.%s = %s is not a known value, using %s"
				% [npc_id, key, authored[key], clean[key]]
			)
