class_name HubDiorama
extends RefCounted

## Procedural pixel-diorama dressing for the hub plaza (HUB art pass).
##
## Nothing here stands proud of the floor. A gold "accent path" of raised tiles used to run down the
## middle of the plaza — 3cm above the surrounding stone, each with its own collider — and it read
## as a strip of yellow kerbstones the player kept walking into rather than as a path.

const TILE_SIZE := 2.0
const FLOOR_WIDTH := 50.0
const FLOOR_DEPTH := 40.0

const ForgeFlickerScript := preload("res://scripts/hub/forge_light_flicker.gd")

## The one place the stall dimensions live. `_spawn_tent_door_pads` lays the threshold slabs from
## this table and each `_dress_*` builds its tent from it, so a resized stall cannot end up with its
## doorstep still cut for the old footprint.
##
## `entrance` no longer frames anything — the stalls have no door frame, and the whole front is
## open. It survives as the width of the threshold slab and the span the planters flank, which is
## the walk-in the player actually reads.
const SERVICE_TENTS := {
	"Blacksmith":
	{"width": 7.7, "depth": 7.0, "wall_height": 3.2, "entrance": 3.2, "roof_peak": 1.7},
	"Merchant":
	{"width": 7.5, "depth": 6.8, "wall_height": 3.3, "entrance": 3.4, "roof_peak": 1.45},
	"Storage":
	{"width": 7.9, "depth": 7.2, "wall_height": 3.5, "entrance": 3.3, "roof_peak": 1.35},
	"QuestBoard":
	{"width": 6.0, "depth": 5.1, "wall_height": 2.9, "entrance": 2.9, "roof_peak": 1.15},
}

const NORTH_WALL_Z := -17.0
const PORTAL_WALL_SPACING := 6.0
const PORTAL_WALL_X_START := 12.0
const FOUNTAIN_POS := Vector3(0.0, 0.0, -7.0)
## Where the six gates stand, and how far apart. The row is symmetric about x = 0 and evenly
## spaced; the plaza dressing is laid out from the same numbers so the braziers cannot drift out of
## step with the doors they flank (they are the node positions in `scenes/hub/hub.tscn`).
const GATE_ROW_Z := -17.0
const GATE_SPACING := 7.0
const GATE_COUNT := 6

## The hub palette is stone, timber and rust — there is no green anywhere in it, so the planting
## brings its own. Kept desaturated on purpose: a saturated leaf green next to `#9e8566` flagstone
## reads as a prop from a different game.
const LEAF_DARK := Color(0.24, 0.33, 0.22)
const LEAF_LIGHT := Color(0.33, 0.44, 0.26)
## One bloom colour per trough, cycled. Three is enough to look planted rather than tiled.
const BLOOM_COLORS := [
	Color(0.76, 0.33, 0.34),
	Color(0.85, 0.63, 0.27),
	Color(0.60, 0.40, 0.66),
]
## Where the light cord hangs.
##
## The orbit camera is a `SpringArm3D` and pulls in only for things on its collision mask; the cord
## has no collision, so at full zoom and full upward pitch the camera went straight through it. That
## worst case puts the lens at 5.28m (pivot 1.60 + 5.2m arm at 45 degrees), measured, so the cord
## clears it and the lowest lantern still hangs above it. The poles were grown to match — the cord
## is tied to them, and bunting floating above its own poles would be worse than the clipping.
const BUNTING_Y := 6.2
## Lowest point of any lantern, for the clearance check: cord minus the longest drop, the cap and
## half the glass.
const CAMERA_MAX_Y := 5.28
const BANNER_POLE_TOP := 6.45


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
	_spawn_fountain(hub, mats)
	_dress_plaza(hub, mats)
	HubFauna.apply(hub)
	_dress_npcs(hub)
	_position_npcs_from_content(hub)
	_wire_interact_feedback(hub)


static func _load_materials() -> Dictionary:
	return PixelDioramaStyle.make_hub_materials()


static func _style_environment(hub: Node3D) -> void:
	if OS.has_environment("AUMBRYE_NO_ENV"):
		return
	VisualLighting.apply_hub(hub)


static func _dress_floor(hub: Node3D, mats: Dictionary) -> void:
	var floor_body := hub.get_node_or_null("Floor") as StaticBody3D
	if floor_body == null:
		return
	floor_body.set_meta("surface", "stone")
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

	_spawn_tent_door_pads(tiles, mats, hub)


static func _spawn_tent_door_pads(tiles: Node3D, mats: Dictionary, hub: Node3D) -> void:
	for service_name in SERVICE_TENTS.keys():
		var hub_pos: Vector3 = _service_world_position(hub, service_name)
		var cfg: Dictionary = SERVICE_TENTS[service_name]
		var yaw: float = _service_yaw(hub, service_name)
		var half_d: float = float(cfg.get("depth", 5.0)) * 0.5
		var door_dir: Vector3 = Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, yaw)
		var pad_pos: Vector3 = hub_pos + door_dir * (half_d + 0.55)
		# Flush with the floor tiles (top at 0.12), not standing 3cm proud of them. The threshold
		# is a change of colour, not a step to trip over.
		PixelDioramaStyle.add_box(
			tiles,
			Vector3(float(cfg.get("entrance", 2.0)) + 0.4, 0.12, 1.2),
			Vector3(pad_pos.x, 0.06, pad_pos.z),
			mats.floor_alt,
			"%sDoorPad" % service_name
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


## Everything in the plaza that is not a door or a shop.
##
## The hub was a flat floor, six doors and four tents — correct, and completely inert. This is the
## dressing that makes it read as a place people live in: fire either side of every gate, banners
## down the central axis, and the working clutter of a market around the stalls.
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


## A brazier either side of every gate. These are the hub's light sources as much as its decoration
## — a row of warm fires along the north wall is what gives the plaza depth after dark, and the
## flicker is the same script the forge uses.
static func _spawn_gate_braziers(parent: Node3D, mats: Dictionary) -> void:
	var first_x := -GATE_SPACING * (GATE_COUNT - 1) * 0.5
	for gate in GATE_COUNT:
		var gate_x := first_x + gate * GATE_SPACING
		for side in [-1.0, 1.0]:
			_spawn_brazier(
				parent,
				mats,
				Vector3(gate_x + side * 2.6, 0.0, GATE_ROW_Z + 2.4),
				"Gate%dBrazier%s" % [gate, "R" if side > 0.0 else "L"]
			)


static func _spawn_brazier(
	parent: Node3D, mats: Dictionary, base: Vector3, node_name: String
) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = base
	parent.add_child(root)
	PixelDioramaStyle.add_box(
		root, Vector3(0.62, 0.16, 0.62), Vector3(0.0, 0.08, 0.0), mats.wall, "Foot"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(0.22, 1.0, 0.22), Vector3(0.0, 0.66, 0.0), mats.wood, "Stem"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(0.7, 0.34, 0.7), Vector3(0.0, 1.32, 0.0), mats.accent, "Bowl"
	)
	var coals := PixelDioramaStyle.add_box(
		root, Vector3(0.5, 0.2, 0.5), Vector3(0.0, 1.52, 0.0), mats.training, "Coals"
	)
	var light := OmniLight3D.new()
	light.name = "BrazierLight"
	light.light_color = Color(1.0, 0.62, 0.26)
	light.light_energy = 1.05
	light.omni_range = 6.5
	# Shadows off: a dozen shadow-casting omnis in one plaza is a cost the look does not need, and
	# the braziers are ambience rather than the key light.
	light.shadow_enabled = false
	light.position = Vector3(0.0, 1.7, 0.0)
	root.add_child(light)
	var flicker := ForgeFlickerScript.new()
	flicker.name = "BrazierFlicker"
	root.add_child(flicker)
	flicker.setup(light, coals)


## Banner poles down the middle of the plaza, framing the walk from the spawn to the gates.
static func _spawn_banner_avenue(parent: Node3D, mats: Dictionary) -> void:
	for i in 4:
		var z := -2.0 + i * 4.5
		for side in [-1.0, 1.0]:
			var root := Node3D.new()
			root.name = "Banner%d%s" % [i, "R" if side > 0.0 else "L"]
			root.position = Vector3(side * 5.5, 0.0, z)
			parent.add_child(root)
			PixelDioramaStyle.add_box(
				root, Vector3(0.62, 0.24, 0.62), Vector3(0.0, 0.12, 0.0), mats.wall, "Base"
			)
			# A stone collar over the foot, the way a mast is wedged rather than simply standing in
			# a socket.
			PixelDioramaStyle.add_box(
				root, Vector3(0.42, 0.2, 0.42), Vector3(0.0, 0.32, 0.0), mats.wall, "Collar"
			)
			var pole_h := BANNER_POLE_TOP - 0.24
			PixelDioramaStyle.add_box(
				root,
				Vector3(0.2, pole_h, 0.2),
				Vector3(0.0, 0.24 + pole_h * 0.5, 0.0),
				mats.wood,
				"Pole"
			)
			# The banner stays at eye level where it can be read. Only the light cord went up.
			PixelDioramaStyle.add_box(
				root, Vector3(0.9, 0.16, 0.16), Vector3(0.0, 3.5, 0.0), mats.wood, "Crossbar"
			)
			PixelDioramaStyle.add_box(
				root, Vector3(0.8, 1.7, 0.06), Vector3(0.0, 2.6, 0.0), mats.accent, "Cloth"
			)
			# Iron bands up the shaft: a pole this tall is a spliced mast, not one grown timber.
			for band in 2:
				PixelDioramaStyle.add_box(
					root,
					Vector3(0.26, 0.1, 0.26),
					Vector3(0.0, 4.3 + band * 1.0, 0.0),
					mats.wall,
					"Band%d" % band
				)
			# The cleat the light cord is actually tied off to.
			PixelDioramaStyle.add_box(
				root, Vector3(0.5, 0.14, 0.14), Vector3(0.0, BUNTING_Y, 0.0), mats.wood, "Cleat"
			)
			PixelDioramaStyle.add_box(
				root,
				Vector3(0.24, 0.24, 0.24),
				Vector3(0.0, BANNER_POLE_TOP + 0.12, 0.0),
				mats.training,
				"Finial"
			)


## Crates, barrels and sacks around the stalls, so the shops look stocked rather than staged.
static func _spawn_market_clutter(parent: Node3D, mats: Dictionary) -> void:
	var spots := [
		# Pulled in off the doorway: the planted pots either side of a stall door stand where these
		# two used to, and a barrel through a flowerpot is worse than either.
		{"pos": Vector3(-12.6, 0.0, 1.6), "seed": 0},
		{"pos": Vector3(12.6, 0.0, 1.6), "seed": 1},
		{"pos": Vector3(-14.6, 0.0, 11.4), "seed": 2},
		{"pos": Vector3(14.6, 0.0, 11.4), "seed": 3},
		{"pos": Vector3(-20.5, 0.0, 3.0), "seed": 4},
		{"pos": Vector3(20.5, 0.0, 3.0), "seed": 5},
	]
	for spot in spots:
		var origin: Vector3 = spot["pos"]
		var index: int = spot["seed"]
		var root := Node3D.new()
		root.name = "Clutter%d" % index
		root.position = origin
		parent.add_child(root)
		PixelDioramaStyle.add_box(
			root, Vector3(0.8, 0.8, 0.8), Vector3(0.0, 0.4, 0.0), mats.wood, "Crate"
		)
		PixelDioramaStyle.add_box(
			root, Vector3(0.66, 0.66, 0.66), Vector3(0.62, 1.13, 0.18), mats.wood, "CrateTop"
		)
		PixelDioramaStyle.add_box(
			root, Vector3(0.56, 0.9, 0.56), Vector3(-0.85, 0.45, 0.3), mats.accent, "Barrel"
		)
		PixelDioramaStyle.add_box(
			root, Vector3(0.72, 0.42, 0.6), Vector3(0.3, 0.21, -0.85), mats.floor_alt, "Sack"
		)


## Trees in stone troughs, out at the edges where the plaza was emptiest. They are the only thing
## in the hub taller than a stall that is not a wall or a portal, which is what stops the middle
## distance reading as flat.
##
## Boxes rather than a cone or a sphere: a smooth canopy sitting next to banded pixel geometry reads
## as an imported asset, and every other silhouette here is built from slabs.
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

	# Flower troughs along the south wall, which the player faces on every walk back from the gates.
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
	var root := Node3D.new()
	root.name = node_name
	root.position = base
	parent.add_child(root)
	var leaf_dark := PixelDioramaStyle.make_material(LEAF_DARK)
	var leaf_light := PixelDioramaStyle.make_material(LEAF_LIGHT)
	PixelDioramaStyle.add_box(
		root, Vector3(1.9, 0.44, 1.9), Vector3(0.0, 0.22, 0.0), mats.wall, "Trough"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(1.55, 0.14, 1.55), Vector3(0.0, 0.48, 0.0), mats.floor_alt, "Soil"
	)
	var trunk_h := 1.5 * height_scale
	PixelDioramaStyle.add_box(
		root,
		Vector3(0.34, trunk_h, 0.34),
		Vector3(0.0, 0.5 + trunk_h * 0.5, 0.0),
		mats.wood,
		"Trunk"
	)
	var canopy := 0.5 + trunk_h
	PixelDioramaStyle.add_box(
		root, Vector3(2.5, 0.72, 2.5), Vector3(0.0, canopy + 0.36, 0.0), leaf_dark, "CanopyLow"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(1.95, 0.64, 1.95), Vector3(0.2, canopy + 0.94, -0.14), leaf_light, "CanopyMid"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(1.25, 0.52, 1.25), Vector3(-0.16, canopy + 1.44, 0.18), leaf_dark, "CanopyTop"
	)


static func _spawn_flower_trough(
	parent: Node3D, mats: Dictionary, base: Vector3, bloom: Color, node_name: String
) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = base
	parent.add_child(root)
	var leaf := PixelDioramaStyle.make_material(LEAF_LIGHT)
	var bloom_mat := PixelDioramaStyle.make_material(bloom)
	PixelDioramaStyle.add_box(
		root, Vector3(2.3, 0.46, 0.78), Vector3(0.0, 0.23, 0.0), mats.wood, "Trough"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(2.05, 0.12, 0.6), Vector3(0.0, 0.5, 0.0), mats.floor_alt, "Soil"
	)
	for i in 5:
		var x := -0.82 + i * 0.41
		# Staggered heights, so the row is a planting rather than a fence.
		var h := 0.34 + float((i * 7) % 3) * 0.12
		PixelDioramaStyle.add_box(
			root, Vector3(0.3, h, 0.3), Vector3(x, 0.56 + h * 0.5, 0.0), leaf, "Leaf%d" % i
		)
		PixelDioramaStyle.add_box(
			root,
			Vector3(0.17, 0.17, 0.17),
			Vector3(x, 0.62 + h, 0.02),
			bloom_mat,
			"Bloom%d" % i
		)


## Benches ringing the fountain, facing it. The fountain was the one thing in the plaza worth
## standing still for and there was nowhere to do it.
static func _spawn_fountain_benches(parent: Node3D, mats: Dictionary) -> void:
	# Ring radius clears the pool rim (2.55) with room to walk between the two.
	var radius := 3.9
	for i in 4:
		var angle := TAU * float(i) / 4.0
		var offset := Vector3(sin(angle), 0.0, cos(angle)) * radius
		_spawn_bench(
			parent,
			mats,
			FOUNTAIN_POS + offset,
			# Backs to the plaza, seats toward the water.
			angle + PI,
			"FountainBench%d" % i
		)


static func _spawn_bench(
	parent: Node3D, mats: Dictionary, base: Vector3, yaw: float, node_name: String
) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = base
	root.rotation.y = yaw
	parent.add_child(root)
	PixelDioramaStyle.add_box(
		root, Vector3(2.0, 0.16, 0.6), Vector3(0.0, 0.46, 0.0), mats.wood, "Seat"
	)
	for side in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			root,
			Vector3(0.18, 0.46, 0.54),
			Vector3(side * 0.78, 0.23, 0.0),
			mats.wall,
			"Leg%s" % ("R" if side > 0.0 else "L")
		)
	PixelDioramaStyle.add_box(
		root, Vector3(2.0, 0.46, 0.12), Vector3(0.0, 0.79, -0.24), mats.wood, "Back"
	)


## Lantern cords strung across the avenue, level with the banner crossbars. Strung across rather
## than along: the poles already carry cloth between chest and head height, and a cord running pole
## to pole down the same side would hang through it.
static func _spawn_bunting(parent: Node3D, mats: Dictionary) -> void:
	for i in 4:
		var z := -2.0 + i * 4.5
		_spawn_lantern_cord(parent, mats, Vector3(-5.5, 0.0, z), Vector3(5.5, 0.0, z), "Bunting%d" % i)


static func _spawn_lantern_cord(
	parent: Node3D, mats: Dictionary, from: Vector3, to: Vector3, node_name: String
) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = (from + to) * 0.5
	root.rotation.y = atan2(to.x - from.x, to.z - from.z)
	parent.add_child(root)
	var span := from.distance_to(to)
	PixelDioramaStyle.add_box(
		root, Vector3(0.07, 0.07, span), Vector3(0.0, BUNTING_Y, 0.0), mats.wood, "Cord"
	)
	# Emissive glass, but no OmniLight each: the plaza already carries twelve brazier lights, and
	# twenty more point lights for decoration is a cost the look does not need.
	var glass := PixelDioramaStyle.make_custom_emissive(Color(1.0, 0.72, 0.34), 1.25)
	var count := 5
	for i in count:
		var t := float(i + 1) / float(count + 1)
		var z := -span * 0.5 + span * t
		# Alternate the drop so the row reads as slung, not as a shelf. Kept short: the whole point
		# of the height is that the camera passes under the lowest lantern, not through it.
		var drop := 0.2 + float(i % 2) * 0.1
		PixelDioramaStyle.add_box(
			root,
			Vector3(0.05, drop, 0.05),
			Vector3(0.0, BUNTING_Y - drop * 0.5, z),
			mats.wood,
			"Hanger%d" % i
		)
		PixelDioramaStyle.add_box(
			root,
			Vector3(0.3, 0.09, 0.3),
			Vector3(0.0, BUNTING_Y - drop - 0.04, z),
			mats.accent,
			"Cap%d" % i
		)
		PixelDioramaStyle.add_box(
			root,
			Vector3(0.26, 0.3, 0.26),
			Vector3(0.0, BUNTING_Y - drop - 0.24, z),
			glass,
			"Glass%d" % i
		)


## A handcart parked outside each of the two busiest stalls, tipped onto its handles the way a
## cart is left when it is not being pulled.
static func _spawn_market_carts(parent: Node3D, mats: Dictionary) -> void:
	# Pulled further in each time the stalls grew: the storage tent's eaves now reach past x=-12.
	_spawn_cart(parent, mats, Vector3(-9.2, 0.0, 4.8), -0.5, "CartWest")
	_spawn_cart(parent, mats, Vector3(9.2, 0.0, 4.8), 0.5, "CartEast")


static func _spawn_cart(
	parent: Node3D, mats: Dictionary, base: Vector3, yaw: float, node_name: String
) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = base
	root.rotation.y = yaw
	parent.add_child(root)
	PixelDioramaStyle.add_box(
		root, Vector3(2.3, 0.24, 1.25), Vector3(0.0, 0.78, 0.0), mats.wood, "Bed"
	)
	for side in [-1.0, 1.0]:
		PixelDioramaStyle.add_box(
			root,
			Vector3(2.3, 0.42, 0.12),
			Vector3(0.0, 1.05, side * 0.57),
			mats.wood,
			"Rail%s" % ("R" if side > 0.0 else "L")
		)
	PixelDioramaStyle.add_box(
		root, Vector3(0.12, 0.42, 1.25), Vector3(-1.09, 1.05, 0.0), mats.wood, "Headboard"
	)
	for side in [-1.0, 1.0]:
		var wheel := PixelDioramaStyle.add_cylinder(
			root,
			0.44,
			0.44,
			0.16,
			Vector3(0.35, 0.44, side * 0.68),
			mats.accent,
			"Wheel%s" % ("R" if side > 0.0 else "L")
		)
		# `add_cylinder` builds them standing on end; a wheel is the same cylinder laid over.
		wheel.rotation.x = PI * 0.5
	PixelDioramaStyle.add_box(
		root, Vector3(0.14, 0.14, 1.15), Vector3(0.35, 0.66, 0.0), mats.wall, "Axle"
	)
	# The handles run down to the ground at the front, which is what parks it.
	for side in [-1.0, 1.0]:
		var handle := PixelDioramaStyle.add_box(
			root,
			Vector3(1.5, 0.12, 0.12),
			Vector3(-1.72, 0.42, side * 0.48),
			mats.wood,
			"Handle%s" % ("R" if side > 0.0 else "L")
		)
		handle.rotation.z = 0.48
	# Something in the bed, so it reads as in use rather than abandoned.
	PixelDioramaStyle.add_box(
		root, Vector3(0.62, 0.62, 0.62), Vector3(-0.35, 1.21, 0.0), mats.floor_alt, "Sack"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(0.5, 0.5, 0.5), Vector3(0.45, 1.15, 0.22), mats.accent, "Crate"
	)


## Split logs stacked against the stalls that would actually burn them.
static func _spawn_woodpiles(parent: Node3D, mats: Dictionary) -> void:
	_spawn_woodpile(parent, mats, Vector3(-12.6, 0.0, -5.4), 0.35, "WoodpileForge")
	_spawn_woodpile(parent, mats, Vector3(-11.0, 0.0, 8.5), -0.3, "WoodpileStore")


static func _spawn_woodpile(
	parent: Node3D, mats: Dictionary, base: Vector3, yaw: float, node_name: String
) -> void:
	var root := Node3D.new()
	root.name = node_name
	root.position = base
	root.rotation.y = yaw
	parent.add_child(root)
	var bark := PixelDioramaStyle.make_material(Color(0.36, 0.26, 0.18))
	var rows := 3
	for row in rows:
		# Each row one log shorter, so the stack has a slumped profile instead of a brick wall.
		var count := 4 - row
		for i in count:
			var log_mesh := PixelDioramaStyle.add_cylinder(
				root,
				0.13,
				0.13,
				1.5,
				Vector3(0.0, 0.15 + row * 0.27, -0.36 + i * 0.27 + row * 0.13),
				bark if (i + row) % 2 == 0 else mats.wood,
				"Log%d_%d" % [row, i]
			)
			log_mesh.rotation.z = PI * 0.5


## Two planted pots flanking every stall door, placed from the same table the doorstep slabs are
## cut from so they cannot drift off the threshold when a stall is resized.
static func _spawn_stall_planters(hub: Node3D, parent: Node3D, mats: Dictionary) -> void:
	for service_name in SERVICE_TENTS.keys():
		var cfg: Dictionary = SERVICE_TENTS[service_name]
		var origin: Vector3 = _service_world_position(hub, service_name)
		var yaw: float = _service_yaw(hub, service_name)
		var door_dir := Vector3(0.0, 0.0, 1.0).rotated(Vector3.UP, yaw)
		var across_dir := Vector3(1.0, 0.0, 0.0).rotated(Vector3.UP, yaw)
		var out: float = float(cfg["depth"]) * 0.5 + 0.5
		# Clear of the doorstep slab, which is `entrance + 0.4` wide.
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
	var root := Node3D.new()
	root.name = node_name
	root.position = base
	parent.add_child(root)
	var leaf := PixelDioramaStyle.make_material(LEAF_DARK)
	var bloom_mat := PixelDioramaStyle.make_material(bloom)
	PixelDioramaStyle.add_box(
		root, Vector3(0.62, 0.5, 0.62), Vector3(0.0, 0.25, 0.0), mats.accent, "Pot"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(0.5, 0.1, 0.5), Vector3(0.0, 0.53, 0.0), mats.floor_alt, "Soil"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(0.54, 0.46, 0.54), Vector3(0.0, 0.79, 0.0), leaf, "Shrub"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(0.34, 0.3, 0.34), Vector3(0.04, 1.12, -0.03), leaf, "ShrubTop"
	)
	PixelDioramaStyle.add_box(
		root, Vector3(0.16, 0.16, 0.16), Vector3(-0.1, 1.2, 0.12), bloom_mat, "Bloom"
	)


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

	_add_wall_collision_box(
		wall_collision, "ColNorth", Vector3(0.0, 2.5, -20.0), Vector3(48.0, 5.0, 1.0)
	)
	_add_wall_collision_box(
		wall_collision, "ColSouth", Vector3(0.0, 2.5, 18.0), Vector3(48.0, 5.0, 1.0)
	)
	_add_wall_collision_box(
		wall_collision, "ColEast", Vector3(24.0, 2.5, 0.0), Vector3(1.0, 5.0, 40.0)
	)
	_add_wall_collision_box(
		wall_collision, "ColWest", Vector3(-24.0, 2.5, 0.0), Vector3(1.0, 5.0, 40.0)
	)

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

	PixelDioramaStyle.add_box(
		run, Vector3(length, height, thickness), Vector3.ZERO, mats.wall, "Walkway"
	)
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
	parent: Node3D, mats: Dictionary, corner_pos: Vector3, parapet_h: float
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
	parent: StaticBody3D, node_name: String, center: Vector3, size: Vector3
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
			parent, Vector3(0.35, 1.1, 0.12), side.pos, mats.accent, side.name
		)


## Volume and falloff for a portal's hum. Quiet enough to be atmosphere rather than a sound
## effect, and audible from about the distance at which the portal frame fills the screen.
const PORTAL_HUM_DB := -15.0
const PORTAL_HUM_RANGE := 17.0
const PORTAL_HUM_NAME := "PortalHum"


static func _dress_portal(portal: Node3D, mats: Dictionary, theme: String) -> void:
	if portal == null:
		return
	var def := PortalCatalog.resolve(theme)
	PixelDioramaStyle.build_portal(portal, def, 1.0, mats)
	_attach_portal_hum(portal, theme)


## Every realm has its own portal hum, tuned to the fundamental its audio manifest declares — but
## nothing in the game ever played one, so all six hub portals stood in silence. Each is a looping
## positional source on the portal itself, which also means walking between them cross-fades by
## itself as the player moves.
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
	var dark_wall := mats.wall.duplicate() as ShaderMaterial
	dark_wall.set_shader_parameter("color_base", Color(0.32, 0.28, 0.24))
	dark_wall.set_shader_parameter("color_shadow", Color(0.2, 0.16, 0.14))
	var tent_mats := mats.duplicate()
	tent_mats.wall = dark_wall

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

	var forge_mat := (mats.forge as Material).duplicate()
	var forge := PixelDioramaStyle.add_box(
		dressing, Vector3(1.2, 1.0, 1.2), Vector3(1.4, 0.5, -0.8), forge_mat, "Forge"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(0.5, 1.8, 0.5), Vector3(1.4, 1.4, -0.8), mats.wall, "Chimney"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(0.7, 0.35, 0.5), Vector3(-0.8, 0.55, -0.6), mats.accent, "Anvil"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(2.0, 0.85, 0.75), Vector3(-1.2, 0.42, -1.2), mats.wood, "Workbench"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(0.25, 0.9, 0.25), Vector3(-2.0, 0.45, -1.0), mats.accent, "ToolRack"
	)

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

	_add_ridge_sign(visuals, "Blacksmith", wall_height + roof_peak, mats.accent)
	_position_door_interact(building, depth, entrance_width, yaw)


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

	for i in 5:
		var stripe_mat: Material = mats.accent if i % 2 == 0 else mats.floor
		PixelDioramaStyle.add_box(
			dressing,
			Vector3(0.85, 0.1, 0.18),
			Vector3(-1.8 + i * 0.9, 2.15, half_d - 0.12),
			stripe_mat,
			"Awning%d" % i
		)
	PixelDioramaStyle.add_box(
		dressing, Vector3(3.2, 0.95, 0.65), Vector3(0.0, 0.48, -0.8), mats.wood, "Counter"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(0.65, 0.65, 0.65), Vector3(-1.3, 0.32, -1.4), mats.accent, "CrateA"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(0.65, 0.65, 0.65), Vector3(1.3, 0.32, -1.5), mats.accent, "CrateB"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(2.4, 1.4, 0.3), Vector3(-1.8, 1.05, -1.0), mats.wood, "ShelfL"
	)
	PixelDioramaStyle.add_box(
		dressing, Vector3(2.4, 1.4, 0.3), Vector3(1.8, 1.05, -1.0), mats.wood, "ShelfR"
	)

	var lantern := OmniLight3D.new()
	lantern.name = "LanternLight"
	lantern.light_color = Color(1.0, 0.82, 0.55)
	lantern.light_energy = 0.7
	lantern.omni_range = 3.8
	lantern.position = Vector3(0.0, 2.0, half_d - 0.5)
	dressing.add_child(lantern)

	_add_ridge_sign(visuals, "Merchant", wall_height + roof_peak, mats.accent)
	_position_door_interact(building, depth, entrance_width, yaw)


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

	PixelDioramaStyle.add_box(
		dressing, Vector3(3.4, 1.8, 0.35), Vector3(0.0, 0.9, -1.4), mats.wood, "ShelfBack"
	)
	for i in 3:
		PixelDioramaStyle.add_box(
			dressing,
			Vector3(0.85, 0.5, 0.5),
			Vector3(-1.1 + i * 1.1, 1.2, -1.2),
			mats.accent,
			"Crate%d" % i
		)
	PixelDioramaStyle.add_cylinder(
		dressing, 0.4, 0.4, 1.0, Vector3(-1.8, 0.5, -1.0), mats.wood, "BarrelA"
	)
	PixelDioramaStyle.add_cylinder(
		dressing, 0.4, 0.4, 1.0, Vector3(1.8, 0.5, -1.0), mats.wood, "BarrelB"
	)

	var lamp := OmniLight3D.new()
	lamp.name = "StorageLight"
	# Warm, like every other light in the plaza. This was a cold blue lamp, which read as deliberate
	# contrast back when the hub was lit by a 1.7-energy orange sun — against the dusk ambient it
	# now sits in, it just made the crates and barrels under it look like blue plastic.
	lamp.light_color = Color(1.0, 0.80, 0.48)
	lamp.light_energy = 0.55
	lamp.omni_range = 3.5
	lamp.position = Vector3(0.0, 2.2, -0.6)
	dressing.add_child(lamp)

	_add_ridge_sign(visuals, "Storage", wall_height + roof_peak, mats.accent)
	_position_door_interact(
		building, depth, entrance_width, yaw, Vector3(entrance_width + 1.0, 3.0, 3.0)
	)


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

	PixelDioramaStyle.add_box(
		dressing, Vector3(2.8, 1.8, 0.16), Vector3(0.0, 1.35, half_d - 0.25), mats.accent, "Board"
	)
	for i in 4:
		PixelDioramaStyle.add_box(
			dressing,
			Vector3(0.5, 0.65, 0.04),
			Vector3(-0.9 + i * 0.6, 1.25 + (i % 2) * 0.22, half_d - 0.12),
			mats.paper,
			"Notice%d" % i
		)
	PixelDioramaStyle.add_box(
		dressing, Vector3(0.45, 0.45, 0.45), Vector3(1.3, 0.22, -0.4), mats.wood, "BenchCrate"
	)

	var paper_light := OmniLight3D.new()
	paper_light.name = "QuestLight"
	paper_light.light_color = Color(0.95, 0.88, 0.72)
	paper_light.light_energy = 0.5
	paper_light.omni_range = 3.2
	paper_light.position = Vector3(0.0, 1.8, half_d - 0.4)
	dressing.add_child(paper_light)

	_add_ridge_sign(visuals, "Quests", wall_height + roof_peak, mats.accent)
	_position_door_interact(board, depth, entrance_width, yaw)


static func _add_ridge_sign(
	visuals: Node3D, label_text: String, ridge_y: float, mat: Material
) -> void:
	var sign_root := Node3D.new()
	sign_root.name = "RidgeSign"
	sign_root.position = Vector3(0.0, ridge_y + 0.72, 0.0)
	visuals.add_child(sign_root)
	PixelDioramaStyle.add_box(
		sign_root, Vector3(1.6, 0.35, 0.12), Vector3(0.0, 0.25, 0.08), mat, "SignBacking"
	)
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


static func _wire_interact_feedback(hub: Node3D) -> void:
	var service_map := {
		"Blacksmith": "DioramaVisuals/RidgeSign",
		"Merchant": "DioramaVisuals/RidgeSign",
		"Storage": "DioramaVisuals/RidgeSign",
		"QuestBoard": "DioramaVisuals/RidgeSign",
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
		"SkiesPortal",
		"CathedralPortal",
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


## Hub NPCs get the same voxel character rig the player and the enemies use.
##
## They used to be three boxes — a torso, a head cube and a slab for feet — in a game whose player
## is a fully sculpted voxel warden, so every shopkeeper in the hub read as a placeholder someone
## forgot to replace. Each one now carries an `appearance` block in `content/npcs/*.json`: rig,
## skin, hair, face and the class garment whose colours suit the job they do, so the blacksmith is a
## heavy ruddy figure in berserker leathers and the lector a lean pale one in a scholar's hood.
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
		# Freed rather than queued: `_dress_npcs` can run again on the same node, and a queued node
		# is still a child when the replacement is added — `NpcBase._resolve_visual` binds to the
		# first "Diorama*" child it meets, which could be the one on its way out.
		existing.free()

	# The name matters: `NpcBase._resolve_visual` binds to the first child called "Diorama*" and
	# drives the idle bob and the look-at from it.
	var visuals := Node3D.new()
	visuals.name = "DioramaBody"
	npc.add_child(visuals)
	DioramaCharacterSkin.build_preview_body(visuals, _npc_appearance(npc_id))


## The authored appearance, or the neutral default if the catalogue entry has none, so an NPC added
## without an `appearance` block still gets a real body rather than three boxes.
static func _npc_appearance(npc_id: String) -> Dictionary:
	var authored: Variant = NpcCatalog.get_definition(npc_id).get("appearance", null)
	if authored is Dictionary and not (authored as Dictionary).is_empty():
		_warn_unknown_appearance(npc_id, authored as Dictionary)
		return authored as Dictionary
	return CharacterAppearance.default_profile()


## `CharacterAppearance.sanitize` drops a value it does not recognise and substitutes the default
## without a word, so a typo in a content file costs an NPC its face and nothing says so. Five were
## wrong on the first pass here — "calm" for a face, "raven" for a hair colour — and looked fine.
static func _warn_unknown_appearance(npc_id: String, authored: Dictionary) -> void:
	var clean := CharacterAppearance.sanitize(authored)
	for key: String in authored:
		if not clean.has(key):
			continue
		# Only the catalogue-matched fields. `theme` and `trim` are numbers that get clamped, and
		# JSON hands them back as floats, so comparing them as text reported every NPC as broken for
		# turning 0.0 into 0.
		if not (authored[key] is String):
			continue
		if str(clean[key]) != str(authored[key]):
			push_warning(
				"HubDiorama: npc %s appearance.%s = %s is not a known value, using %s"
				% [npc_id, key, authored[key], clean[key]]
			)
