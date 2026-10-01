extends RefCounted
class_name DioramaRoomDressing


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

const BiomeAmbienceEmitterScript := preload("res://scripts/audio/biome_ambience_emitter.gd")
const BiomeRoomAtmosphereScript := preload("res://scripts/art/vfx/biome_room_atmosphere.gd")

## The corner pillar's procedural fallback height, matched to the authored propKit pillar
## mesh (`scenes/props/<biome>/pillar.tscn`, a 3.0m-tall CylinderMesh). Callers ask for pillars of
## varying height (2.2-3.2m across room kinds); when a real propKit pillar is instanced instead of
## the procedural box, it is Y-scaled by `height / PROP_KIT_PILLAR_HEIGHT` so that variance survives.
const PROP_KIT_PILLAR_HEIGHT := 3.0

static var _shadow_omni_budget: int = 0
static var _max_shadow_omnis: int = 2
static var _torch_flicker: Dictionary = {}

## `propKit` scene content, resolved once per biome and cached for the life of the process
## (this is a hot path -- every prop placement in every room of every floor would otherwise re-load
## and re-inspect the same handful of .tscn files). Keyed by biome_id -> {"pillar": PackedScene|null,
## "sconce": PackedScene|null, "rubble": Array[PackedScene]}. A `null` entry means the kit slot is
## either unset or still the 3-line placeholder scene ("existence is not content" -- `ResourceLoader
## .exists()` is true for the stub too, so the check loads the scene and requires more than just its
## root node).
static var _prop_kit_cache: Dictionary = {}

const PROP_KIT_FALLBACK_DIR := "res://scenes/props/castle"
const PROP_KIT_KINDS: Array[String] = ["pillar", "sconce", "statue", "altar", "banner", "debris_pile"]


static func _get_prop_kit(biome_id: String) -> Dictionary:
	if _prop_kit_cache.has(biome_id):
		return _prop_kit_cache[biome_id]
	var kit_paths: Dictionary = BiomeRegistry.get_biome(biome_id).get("propKit", {})
	var kit_dir := str(kit_paths.get("pillar", PROP_KIT_FALLBACK_DIR + "/pillar.tscn")).get_base_dir()
	var resolved := {}
	for kind in PROP_KIT_KINDS:
		resolved[kind] = _resolve_prop_kit_scene("%s/%s.tscn" % [kit_dir, kind])
	resolved["rubble"] = [
		_resolve_prop_kit_scene("%s/rubble_a.tscn" % kit_dir),
		_resolve_prop_kit_scene("%s/rubble_b.tscn" % kit_dir),
	]
	_prop_kit_cache[biome_id] = resolved
	return resolved


## True content check: a scene with only its root node (the "[gd_scene]/blank/[node]" placeholder
## every propKit path pointed at) reports `get_node_count() == 1` without needing a
## full instantiate.
static func _resolve_prop_kit_scene(path: String) -> PackedScene:
	if path == "" or not ResourceLoader.exists(path):
		return null
	var packed := load(path) as PackedScene
	if packed == null:
		return null
	var state := packed.get_state()
	if state == null or state.get_node_count() <= 1:
		return null
	return packed


static func _instance_prop_kit_scene(
	scene: PackedScene, pos: Vector3, yaw: float, node_name: String, height_scale: float = 1.0
) -> Node3D:
	var inst := scene.instantiate() as Node3D
	if inst == null:
		return null
	inst.name = node_name
	inst.position = pos
	inst.rotation.y = yaw
	if not is_equal_approx(height_scale, 1.0):
		inst.scale.y = height_scale
	return inst


static func apply_to_room(room: RoomTemplate, biome_id: String, _room_seed: int = 0) -> void:
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
	if room.room_type == "obstacle":
		_spawn_obstacle_course(dressing, half_w, half_d, floor_mat, wall_mat, accent_mat, biome_id)
		return
	match suffix:
		"entrance":
			_spawn_entrance(dressing, half_w, half_d, biome_id)
		"boss":
			_spawn_boss(dressing, half_w, half_d, biome_id)
		"courtyard":
			_spawn_courtyard(dressing, half_w, half_d, biome_id)
		"hall":
			_spawn_hall(dressing, half_w, half_d, biome_id)
		"treasure":
			_spawn_treasure(dressing, biome_id)
		"secret":
			_spawn_secret(dressing, half_w, biome_id)
		"stairs":
			_spawn_stairs(dressing, half_w, biome_id)
		"arena":
			_spawn_arena(dressing, half_w, half_d, biome_id)
		"puzzle":
			_spawn_puzzle(dressing, biome_id)
		_:
			_spawn_generic_corners(dressing, half_w, half_d, biome_id)
	_spawn_family_dressing(dressing, room, half_w, half_d, biome_id)
	_spawn_variant_props(dressing, room, biome_id)
	var landmark_rng := RandomNumberGenerator.new()
	landmark_rng.seed = absi(("%s:%s" % [biome_id, room.room_id]).hash())
	_spawn_biome_landmark(dressing, room, half_w, half_d, biome_id, landmark_rng)
	var density_rng := RandomNumberGenerator.new()
	density_rng.seed = absi(("%s:%s:density" % [biome_id, room.room_id]).hash())
	_spawn_density_props(dressing, room, half_w, half_d, blockout, biome_id, density_rng)
	PropMerger.merge_static(dressing)
	BiomeRoomAtmosphereScript.attach(dressing, biome_id, half_w, half_d)


## The procedural room kit establishes scale; this compact landmark pass gives each biome a local
## silhouette, colour focus and sound source.  It avoids door bands and gameplay anchors by living
## on a back-side third of the room, so visual identity never compromises navigation.
static func _spawn_biome_landmark(
	parent: Node3D,
	room: RoomTemplate,
	half_w: float,
	half_d: float,
	biome_id: String,
	rng: RandomNumberGenerator
) -> void:
	if parent == null or room.room_type == "obstacle":
		return
	var suffix := _room_suffix(room.template_id)
	# One composed biome feature per room makes the palette visible without floor scatter.
	var side := -1.0 if rng.randf() < 0.5 else 1.0
	var pos := Vector3(side * half_w * 0.32, 0.0, -half_d * 0.32)
	var landmark := Node3D.new()
	landmark.name = "BiomeLandmark"
	landmark.position = pos
	parent.add_child(landmark)
	var glow_color := _biome_light_color(biome_id)
	var style := str(PropLibrary.BIOME_STYLES.get(biome_id, "castle"))
	match style:
		"crystal":
			glow_color = glow_color.lerp(Color(0.55, 0.9, 1.0), 0.35)
		"swamp":
			glow_color = glow_color.lerp(Color(0.46, 0.88, 0.48), 0.45)
		"frozen":
			glow_color = glow_color.lerp(Color(0.6, 0.82, 1.0), 0.4)
		"vault":
			glow_color = glow_color.lerp(Color(1.0, 0.62, 0.28), 0.3)
		"cathedral":
			glow_color = glow_color.lerp(Color(0.68, 0.48, 1.0), 0.35)
	PropLibrary.attach(landmark, "landmark_%s" % style, biome_id, {"pulse": glow_color})
	var light := OmniLight3D.new()
	light.name = "LandmarkGlow"
	light.position = Vector3(0.0, 1.1, 0.0)
	VisualLighting.configure_soft_omni(light, glow_color, 0.38, 5.5, false)
	landmark.add_child(light)
	LightEmbers.attach(landmark, Vector3(0.0, 0.75, 0.0), glow_color, 0.42, 0.65)
	if suffix in ["boss", "arena", "treasure", "secret", "puzzle"]:
		var ambience := BiomeAmbienceEmitterScript.new() as Node3D
		ambience.name = "BiomeAmbienceAccent"
		ambience.set("biome_id", biome_id)
		landmark.add_child(ambience)
	_spawn_room_purpose_beacon(parent, suffix, half_w, half_d, side, glow_color)


static func _spawn_room_purpose_beacon(
	parent: Node3D, suffix: String, half_w: float, half_d: float, side: float, color: Color
) -> void:
	if not suffix in ["boss", "arena", "treasure", "secret", "puzzle"]:
		return
	var focus := Node3D.new()
	focus.name = "RoomPurposeBeacon_%s" % suffix
	focus.position = Vector3(-side * half_w * 0.33, 0.0, -half_d * 0.3)
	parent.add_child(focus)
	var beacon_id := "beacon_arena"
	match suffix:
		"treasure":
			beacon_id = "beacon_treasure"
		"secret":
			beacon_id = "beacon_secret"
		"puzzle":
			beacon_id = "beacon_puzzle"
	PropLibrary.attach_themed(focus, beacon_id, PixelDioramaStyle.PaletteTheme.CASTLE, {"pulse": color.lightened(0.2)})
	var light := OmniLight3D.new()
	light.name = "PurposeGlow"
	light.position = Vector3(0.0, 0.8, 0.0)
	VisualLighting.configure_soft_omni(light, color, 0.25, 4.2, false)
	focus.add_child(light)


static func _spawn_family_dressing(
	parent: Node3D, room: RoomTemplate, half_w: float, half_d: float, biome_id: String
) -> void:
	for tag in room.room_tags:
		match str(tag):
			"family_defended_bridge":
				_spawn_corner_pillar(parent, Vector3(-half_w * 0.45, 0.0, 0.0), 3.4, biome_id)
				_spawn_corner_pillar(parent, Vector3(half_w * 0.45, 0.0, 0.0), 3.4, biome_id)
			"family_overlook":
				_spawn_brazier(parent, Vector3(0.0, 0.0, -half_d * 0.4), biome_id, 0.9)
			"family_flooded_bypass":
				_spawn_kit_rubble(parent, 0, Vector3(-half_w * 0.28, 0.0, 0.0), 0.3, biome_id)
				_spawn_kit_rubble(parent, 1, Vector3(half_w * 0.28, 0.0, 0.0), -0.3, biome_id)
			"family_broken_chapel":
				_spawn_wall_midpoint_torches(parent, room.get_blockout(), half_w, half_d, biome_id)
			"family_vertical_return_loop":
				_spawn_brazier(parent, Vector3(0.0, 0.0, half_d * 0.35), biome_id, 1.0)
			"family_ambush_courtyard":
				_spawn_room_center_fill(parent, half_w, half_d, biome_id)


## Places whatever `props` list the room's biome-specific layout variant authored
## (`content/rooms/<biome>.json`), on top of whatever the kind's own built-in dressing already
## placed. Optional -- a variant with no `props` key, or a room on its baseline variant 0, adds
## nothing here.
static func _spawn_variant_props(
	dressing: Node3D, room: RoomTemplate, biome_id: String
) -> void:
	var variant := RoomLayoutCatalog.variant_for_room(
		biome_id, RunFlow.current_seed, room.room_id, room.template_id
	)
	if variant <= 0:
		return
	var props := RoomLayoutCatalog.props_for(biome_id, room.template_id, variant)
	for entry in props:
		if not entry is Dictionary:
			continue
		var record: Dictionary = entry
		var at: Variant = record.get("at", [])
		if not at is Array or (at as Array).size() < 3:
			continue
		var pos := Vector3(float(at[0]), float(at[1]), float(at[2]))
		var yaw := deg_to_rad(float(record.get("yaw", 0.0)))
		_spawn_layout_prop(dressing, str(record.get("kind", "")), pos, yaw, biome_id)


static func _spawn_layout_prop(
	parent: Node3D, kind: String, pos: Vector3, yaw: float, biome_id: String
) -> void:
	match kind:
		"pillar":
			_spawn_corner_pillar(parent, pos, 3.2, biome_id)
		"brazier":
			_spawn_brazier(parent, pos, biome_id)
		"rubble", "rubble_a":
			_spawn_kit_rubble(parent, 0, pos + Vector3(0.0, 0.3, 0.0), yaw, biome_id)
		"rubble_b":
			_spawn_kit_rubble(parent, 1, pos + Vector3(0.0, 0.22, 0.0), yaw, biome_id)
		"sconce":
			_spawn_wall_sconce(parent, pos, biome_id)
		"debris_pile", "statue", "altar":
			_spawn_kit_piece(parent, kind, pos, yaw, biome_id)


## Room area on its own decided almost nothing before this -- a 24x24 arena and an 8x8
## secret got dressed from the same four-prop kit, which is why a big room read as "60% of the
## frame is one flat tile pattern". `props = clampi(area/26, 3, 14)`
## scales the count with the room instead.
## `"sconce"` was here and is not any more: `_spawn_density_props()` below places every kind on the
## open floor (a pillar gets its own +1.6m lift, a statue +1.4m, and so on, all inside
## `_batch_density_box()`), but a sconce is a wall fixture -- `_spawn_wall_sconce()` was handed a
## floor-level point picked anywhere in the room's interior and never snapped it to a wall, so it
## planted a torch (with its own `OmniLight3D`) floating at ground height in open space. Every room
## kind that wants sconces already places them correctly along its own walls (e.g. `_spawn_hall()`'s
## `y = 1.4` pass); this random-floor path had no such placement to fall back on.
const DENSITY_PROP_KINDS := [
	"pillar", "rubble_a", "rubble_b", "banner", "statue", "altar", "debris_pile"
]
const DENSITY_MIN_SPACING := 1.8
const DENSITY_DOORWAY_CLEARANCE := 1.8
const DENSITY_ANCHOR_CLEARANCE := 1.5


## Rejection-sampled scatter (a cheap stand-in for a true Poisson-disc one): a random point is
## accepted only if it clears every doorway zone, every existing `PropAnchor_N` marker by
## `DENSITY_ANCHOR_CLEARANCE` (the variant anchors and the built-in corner anchors both use
## that name), and every prop this same pass has already placed by `DENSITY_MIN_SPACING`.
##
## Cover obstacles are placed later by `DungeonBuilder._place_cover()`
## from `definition.placements.cover`, which is not available here -- `apply_to_room()` only ever
## sees a biome id and a seed, not the floor definition. Skipped rather than plumbed through for
## one clearance check; a scatter prop landing near a cover pillar is a visual near-miss, not a
## blocked path (cover placement itself already checks doorway zones and drops rather than nudges).
static func _spawn_density_props(
	dressing: Node3D,
	room: RoomTemplate,
	half_w: float,
	half_d: float,
	blockout: CastleBlockout,
	biome_id: String,
	prop_rng: RandomNumberGenerator
) -> void:
	var area := half_w * 2.0 * (half_d * 2.0)
	var count := clampi(int(area / 26.0), 3, 14)
	var zones := _density_doorway_zones(blockout, half_w, half_d)
	var anchor_points := _density_anchor_points(room)
	var placed: Array[Vector2] = []
	var by_kind: Dictionary = {}
	var margin := 1.2
	var attempts := 0
	var max_attempts := count * 15
	while placed.size() < count and attempts < max_attempts:
		attempts += 1
		var pos := Vector2(
			prop_rng.randf_range(-half_w + margin, half_w - margin),
			prop_rng.randf_range(-half_d + margin, half_d - margin)
		)
		if _density_in_doorway(zones, pos):
			continue
		var too_close := false
		for anchor in anchor_points:
			if anchor.distance_to(pos) < DENSITY_ANCHOR_CLEARANCE:
				too_close = true
				break
		if not too_close:
			for existing in placed:
				if existing.distance_to(pos) < DENSITY_MIN_SPACING:
					too_close = true
					break
		if too_close:
			continue
		placed.append(pos)
		var kind: String = DENSITY_PROP_KINDS[prop_rng.randi_range(0, DENSITY_PROP_KINDS.size() - 1)]
		var yaw := prop_rng.randf_range(0.0, TAU)
		if not by_kind.has(kind):
			by_kind[kind] = [] as Array[Transform3D]
		(by_kind[kind] as Array[Transform3D]).append(
			Transform3D(Basis(Vector3.UP, yaw), Vector3(pos.x, 0.0, pos.y))
		)
	for kind: String in by_kind:
		PropLibrary.scatter(
			dressing,
			PropLibrary.biome_prop_id(biome_id, kind),
			biome_id,
			by_kind[kind] as Array[Transform3D],
			"Density_%s" % kind
		)


static func _density_doorway_zones(blockout: CastleBlockout, half_w: float, half_d: float) -> Array:
	var zones: Array = []
	if blockout.door_north:
		zones.append(
			{
				"along_x": true,
				"offset": blockout.door_north_offset,
				"lo": -half_d,
				"hi": -half_d + DENSITY_DOORWAY_CLEARANCE,
			}
		)
	if blockout.door_south:
		zones.append(
			{
				"along_x": true,
				"offset": blockout.door_south_offset,
				"lo": half_d - DENSITY_DOORWAY_CLEARANCE,
				"hi": half_d,
			}
		)
	if blockout.door_east:
		zones.append(
			{
				"along_x": false,
				"offset": blockout.door_east_offset,
				"lo": half_w - DENSITY_DOORWAY_CLEARANCE,
				"hi": half_w,
			}
		)
	if blockout.door_west:
		zones.append(
			{
				"along_x": false,
				"offset": blockout.door_west_offset,
				"lo": -half_w,
				"hi": -half_w + DENSITY_DOORWAY_CLEARANCE,
			}
		)
	return zones


static func _density_in_doorway(zones: Array, pos: Vector2) -> bool:
	var half_span := CastleRoomConstants.DOOR_WIDTH * 0.5 + 0.4
	for zone in zones:
		var along: float = pos.x if bool(zone["along_x"]) else pos.y
		var across: float = pos.y if bool(zone["along_x"]) else pos.x
		if absf(along - float(zone["offset"])) > half_span:
			continue
		if across >= float(zone["lo"]) and across <= float(zone["hi"]):
			return true
	return false


static func _density_anchor_points(room: Node) -> Array[Vector2]:
	var points: Array[Vector2] = []
	var props := room.get_node_or_null("Props") if room else null
	if props == null:
		return points
	for child in props.get_children():
		var marker := child as Node3D
		if marker == null or not marker.name.begins_with("PropAnchor_"):
			continue
		points.append(Vector2(marker.position.x, marker.position.z))
	return points


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
			_spawn_ceiling_torch(lights, Vector3(x, torch_y, z), biome_id)
			z += spacing
		x += spacing
	_spawn_wall_midpoint_torches(lights, blockout, half_w, half_d, biome_id)
	_spawn_room_center_fill(lights, half_w, half_d, biome_id)


## Half the doorway plus a little margin either side -- the band a torch must clear to never sit in
## the cut opening (embedded in the gap, or hanging in the neighbouring room) rather than on solid
## wall next to it. The lattice seats a door at its wall's dead centre whenever it can, but roughly
## a third of doors measured across sample floors land off-centre anyway -- the cell the centred
## placement wants is often already claimed by another room on a floor this densely packed, and the
## solver slides the door along the wall rather than fail the room. Flanking geometry alone (below)
## assumes the common centred case; this clearance check is what still holds on the slid-door third.
const TORCH_DOOR_CLEARANCE := CastleRoomConstants.DOOR_WIDTH * 0.5 + 0.6

## Where a wall's pair of torches sit, as a fraction of the wall's own half-length out from centre --
## clamped below by `TORCH_DOOR_CLEARANCE` so they never encroach on a centred door regardless of how
## short the wall is, and above by the corner inset so they never crowd past the corner prop on a
## long one.
const TORCH_FLANK_FRACTION := 0.55


## One torch either side of the doorway instead of one in the middle of it. A single midpoint torch
## and a door are both centred on the wall by default, which put the torch in the doorway on sight;
## flanking the door the way sconces flank a real doorway fixes that for the common centred case.
## The wall's actual door state (finalized on the blockout by the time this runs) is still checked
## per torch, because the lattice does slide a meaningful fraction of doors off-centre to resolve
## placement conflicts, and a slid door can still reach a flanking torch's position.
static func _spawn_wall_midpoint_torches(
	parent: Node3D,
	blockout: CastleBlockout,
	half_w: float,
	half_d: float,
	biome_id: String
) -> void:
	var wall_y := CastleRoomConstants.WALL_HEIGHT * 0.5
	var inset := 0.55
	var flank_w := clampf(half_w * TORCH_FLANK_FRACTION, TORCH_DOOR_CLEARANCE, half_w - inset)
	var flank_d := clampf(half_d * TORCH_FLANK_FRACTION, TORCH_DOOR_CLEARANCE, half_d - inset)
	for side: float in [-1.0, 1.0]:
		var x := side * flank_w
		if _clears_door(blockout.door_north, blockout.door_north_offset, x):
			_spawn_wall_torch(parent, Vector3(x, wall_y, -half_d + inset), biome_id)
		if _clears_door(blockout.door_south, blockout.door_south_offset, x):
			_spawn_wall_torch(parent, Vector3(x, wall_y, half_d - inset), biome_id)
		var z := side * flank_d
		if _clears_door(blockout.door_west, blockout.door_west_offset, z):
			_spawn_wall_torch(parent, Vector3(-half_w + inset, wall_y, z), biome_id)
		if _clears_door(blockout.door_east, blockout.door_east_offset, z):
			_spawn_wall_torch(parent, Vector3(half_w - inset, wall_y, z), biome_id)


static func _clears_door(door_open: bool, door_offset: float, lateral: float) -> bool:
	return not door_open or absf(lateral - door_offset) >= TORCH_DOOR_CLEARANCE


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


static func _spawn_entrance(parent: Node3D, half_w: float, half_d: float, biome_id: String) -> void:
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.0, 0.0, -half_d + 1.2), 2.8, biome_id)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.0, 0.0, -half_d + 1.2), 2.8, biome_id)
	_spawn_brazier(parent, Vector3(-half_w + 2.2, 0.0, half_d - 1.5), biome_id)
	_spawn_brazier(parent, Vector3(half_w - 2.2, 0.0, half_d - 1.5), biome_id)


static func _spawn_boss(parent: Node3D, half_w: float, half_d: float, biome_id: String) -> void:
	_place_prop(parent, "dais", Vector3(0.0, 0.0, half_d - 2.5), biome_id, Vector3(half_w * 1.4, 1.0, 1.0), "BossPlatform")
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.2, 0.0, -half_d + 1.2), 3.2, biome_id)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.2, 0.0, -half_d + 1.2), 3.2, biome_id)
	_spawn_brazier(parent, Vector3(-half_w + 2.0, 0.0, half_d - 1.8), biome_id, 0.7)
	_spawn_brazier(parent, Vector3(half_w - 2.0, 0.0, half_d - 1.8), biome_id, 0.7)
	_add_spot(parent, Vector3(0.0, 4.5, half_d - 2.5), biome_id, 1.2)


static func _spawn_courtyard(parent: Node3D, half_w: float, half_d: float, biome_id: String) -> void:
	_spawn_prop_cluster(parent, Vector3(-half_w + 2.0, 0.0, -half_d + 2.0), biome_id, 0)
	_spawn_prop_cluster(parent, Vector3(half_w - 2.0, 0.0, -half_d + 2.0), biome_id, 1)
	_spawn_prop_cluster(parent, Vector3(-half_w + 2.0, 0.0, half_d - 2.0), biome_id, 2)
	_spawn_prop_cluster(parent, Vector3(half_w - 2.0, 0.0, half_d - 2.0), biome_id, 3)
	_place_prop(parent, "plinth", Vector3.ZERO, biome_id, Vector3.ONE, "CenterPlinth")


static func _spawn_hall(parent: Node3D, half_w: float, half_d: float, biome_id: String) -> void:
	var z := -half_d + 2.0
	while z <= half_d - 2.0:
		_spawn_wall_sconce(parent, Vector3(-half_w + 0.5, 1.4, z), biome_id)
		_spawn_wall_sconce(parent, Vector3(half_w - 0.5, 1.4, z), biome_id)
		z += 3.5
	_spawn_corner_pillar(parent, Vector3(-half_w + 0.8, 0.0, 0.0), 2.6, biome_id)
	_spawn_corner_pillar(parent, Vector3(half_w - 0.8, 0.0, 0.0), 2.6, biome_id)


static func _spawn_treasure(parent: Node3D, biome_id: String) -> void:
	_place_prop(parent, "pedestal", Vector3(0.0, 0.0, 1.5), biome_id, Vector3.ONE, "Pedestal")
	_add_spot(parent, Vector3(0.0, 2.5, 1.5), biome_id, 0.65)


static func _spawn_secret(parent: Node3D, half_w: float, biome_id: String) -> void:
	_place_prop(parent, "secret_panel", Vector3(-half_w + 0.6, 0.0, 0.0), biome_id, Vector3.ONE, "SecretPanel", {"pulse": _biome_light_color(biome_id)})
	_add_spot(parent, Vector3(-half_w + 1.0, 2.0, 0.0), biome_id, 0.4)


static func _spawn_stairs(parent: Node3D, half_w: float, biome_id: String) -> void:
	# The exit lever sits on the same floor as every other room. Dress this as a
	# destination with paired wall lights, without suggesting an inaccessible rise.
	_spawn_wall_sconce(parent, Vector3(-half_w + 0.5, 1.6, 0.0), biome_id)
	_spawn_wall_sconce(parent, Vector3(half_w - 0.5, 1.6, 0.0), biome_id)


static func _spawn_arena(parent: Node3D, half_w: float, half_d: float, biome_id: String) -> void:
	_place_prop(
		parent, "arena_ring", Vector3.ZERO, biome_id, Vector3(half_w * 0.6, 1.0, half_d * 0.6), "ArenaRing",
		{"pulse": _biome_light_color(biome_id)}
	)
	_spawn_corner_pillar(parent, Vector3(-half_w + 1.0, 0.0, -half_d + 1.0), 2.2, biome_id)
	_spawn_corner_pillar(parent, Vector3(half_w - 1.0, 0.0, -half_d + 1.0), 2.2, biome_id)
	_spawn_brazier(parent, Vector3(0.0, 0.0, -half_d + 1.5), biome_id, 0.5)


static func _spawn_puzzle(parent: Node3D, biome_id: String) -> void:
	_place_prop(parent, "puzzle_core", Vector3.ZERO, biome_id, Vector3.ONE, "PuzzleCore")
	for i in 4:
		var angle := float(i) / 4.0 * TAU
		_place_prop(
			parent, "puzzle_orb", Vector3(cos(angle) * 2.5, 0.0, sin(angle) * 2.5), biome_id, Vector3.ONE, "PuzzleOrb_%d" % i
		)
	_spawn_brazier(parent, Vector3(0.0, 0.0, 2.8), biome_id, 0.45)


static func _spawn_obstacle_course(
	parent: Node3D,
	half_w: float,
	half_d: float,
	floor_mat: Material,
	wall_mat: Material,
	accent_mat: Material,
	biome_id: String
) -> void:
	_add_obstacle_block(
		parent, Vector3(-3.5, 0.55, -1.0), Vector3(2.8, 1.1, 2.8), floor_mat, "ObstaclePlatformA", biome_id
	)
	_add_obstacle_block(
		parent, Vector3(3.5, 0.9, 1.5), Vector3(2.4, 1.8, 2.4), floor_mat, "ObstaclePlatformB", biome_id
	)
	_add_obstacle_block(
		parent,
		Vector3(0.0, 0.35, half_d - 3.0),
		Vector3(half_w * 0.55, 0.7, 1.2),
		wall_mat,
		"ObstacleLowWall",
		biome_id
	)
	_add_obstacle_block(
		parent,
		Vector3(-half_w + 2.2, 0.75, 0.0),
		Vector3(1.0, 1.5, half_d * 0.45),
		wall_mat,
		"ObstacleDividerL",
		biome_id
	)
	_add_obstacle_block(
		parent,
		Vector3(half_w - 2.2, 0.75, 0.0),
		Vector3(1.0, 1.5, half_d * 0.45),
		wall_mat,
		"ObstacleDividerR",
		biome_id
	)
	_add_obstacle_block(
		parent,
		Vector3(0.0, 0.25, -half_d + 2.5),
		Vector3(1.6, 0.5, 1.6),
		accent_mat,
		"ObstacleDashPillar",
		biome_id
	)
	_spawn_brazier(parent, Vector3(-half_w + 1.8, 0.0, half_d - 1.8), biome_id, 0.5)
	_spawn_brazier(parent, Vector3(half_w - 1.8, 0.0, half_d - 1.8), biome_id, 0.5)


static func _spawn_generic_corners(
	parent: Node3D,
	half_w: float,
	half_d: float,
	biome_id: String,
	prop_rng: RandomNumberGenerator = null
) -> void:
	var jitter_a := 0.0
	var jitter_b := 0.0
	if prop_rng != null:
		jitter_a = prop_rng.randf_range(-0.8, 0.8)
		jitter_b = prop_rng.randf_range(-0.8, 0.8)
	_spawn_brazier(parent, Vector3(-half_w + 1.5 + jitter_a, 0.0, -half_d + 1.5 + jitter_b), biome_id, 0.4)
	_spawn_brazier(parent, Vector3(half_w - 1.5 - jitter_b, 0.0, half_d - 1.5 - jitter_a), biome_id, 0.4)


static func _spawn_corner_pillar(parent: Node3D, pos: Vector3, height: float, biome_id: String) -> void:
	var kit := _get_prop_kit(biome_id if biome_id != "" else BiomeRegistry.BIOME_CASTLE)
	var pillar_scene: PackedScene = kit.get("pillar")
	if pillar_scene == null:
		return
	var inst := _instance_prop_kit_scene(pillar_scene, pos, 0.0, "Pillar", height / PROP_KIT_PILLAR_HEIGHT)
	if inst != null:
		parent.add_child(inst)


## `rubble_index` 0 -> propKit's rubble_a (or the biome's only rubble entry), 1 -> rubble_b.
## `pos` is already offset to the mesh's resting height by the caller (matching the box fallback's
## own offset), so the propKit scene is instanced at that same position rather than at ground level.
static func _spawn_kit_rubble(
	parent: Node3D, rubble_index: int, pos: Vector3, yaw: float, biome_id: String
) -> void:
	var kit := _get_prop_kit(biome_id if biome_id != "" else BiomeRegistry.BIOME_CASTLE)
	var rubble_scenes: Array = kit.get("rubble", [])
	var scene: PackedScene = rubble_scenes[clampi(rubble_index, 0, rubble_scenes.size() - 1)]
	if scene == null:
		return
	var inst := _instance_prop_kit_scene(scene, pos - Vector3(0.0, pos.y, 0.0), yaw, "Rubble")
	if inst != null:
		parent.add_child(inst)


## A statue, altar or debris pile from the biome's kit, standing on the floor at `pos`.
static func _spawn_kit_piece(parent: Node3D, kind: String, pos: Vector3, yaw: float, biome_id: String) -> void:
	var kit := _get_prop_kit(biome_id if biome_id != "" else BiomeRegistry.BIOME_CASTLE)
	var scene: PackedScene = kit.get(kind)
	if scene == null:
		return
	var inst := _instance_prop_kit_scene(scene, Vector3(pos.x, 0.0, pos.z), yaw, kind.capitalize().replace(" ", ""))
	if inst != null:
		parent.add_child(inst)


static func _spawn_brazier(
	parent: Node3D, pos: Vector3, biome_id: String, energy: float = 0.7
) -> void:
	var brazier := Node3D.new()
	brazier.name = "Brazier"
	brazier.position = pos
	parent.add_child(brazier)
	PropLibrary.attach(brazier, "brazier", biome_id)
	var light := OmniLight3D.new()
	light.name = "BrazierLight"
	light.position = Vector3(0.0, 1.1, 0.0)
	_configure_torch_light(light, _biome_light_color(biome_id), energy, 9.0, brazier)
	AudioDirector.attach_loop_emitter(brazier, "brazier", 6.0)


static func _spawn_wall_sconce(parent: Node3D, pos: Vector3, biome_id: String) -> void:
	_spawn_wall_torch(parent, pos, biome_id if biome_id != "" else BiomeRegistry.BIOME_CASTLE)


static func _spawn_wall_torch(parent: Node3D, pos: Vector3, biome_id: String) -> void:
	# The torch model is the biome kit's sconce (emissive, no light of its own); the real-time
	# OmniLight3D and embers below belong to the room, not to the model.
	var kit := _get_prop_kit(biome_id)
	var sconce_scene: PackedScene = kit.get("sconce")
	if sconce_scene != null:
		var inst := _instance_prop_kit_scene(sconce_scene, pos, 0.0, "WallTorch")
		if inst != null:
			parent.add_child(inst)
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


static func _spawn_ceiling_torch(parent: Node3D, pos: Vector3, biome_id: String) -> void:
	var fixture := Node3D.new()
	fixture.name = "CeilingTorch"
	fixture.position = pos
	parent.add_child(fixture)
	PropLibrary.attach(fixture, "ceiling_torch", biome_id)
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


static func _add_torch_embers(parent: Node3D, pos: Vector3, tint: Color) -> void:
	LightEmbers.attach(parent, pos, tint)


static func _add_obstacle_block(
	parent: Node3D, pos: Vector3, size: Vector3, mat: Material, node_name: String, biome_id: String
) -> StaticBody3D:
	var body := StaticBody3D.new()
	body.name = node_name
	body.collision_layer = 1
	body.collision_mask = 0
	body.set_meta("nav_obstacle", true)
	body.position = pos
	parent.add_child(body)
	var skin := Node3D.new()
	skin.name = "Skin"
	skin.position = Vector3(0.0, -size.y * 0.5, 0.0)
	skin.scale = size
	body.add_child(skin)
	var style := str(PropLibrary.BIOME_STYLES.get(biome_id, "castle"))
	PropLibrary.attach(skin, "walls/block_%s" % style, biome_id, {"materials": {"wall": mat}} if mat != null else {})
	var collision := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	collision.shape = shape
	body.add_child(collision)
	return body


const CLUSTER_PROPS: Array[String] = ["crate", "barrel", "sack", "crate"]


static func _spawn_prop_cluster(parent: Node3D, pos: Vector3, biome_id: String, rng_seed: int) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = hash(biome_id) + rng_seed * 97
	var count := 2 + rng.randi_range(0, 1)
	for i in count:
		var offset := Vector3(rng.randf_range(-0.6, 0.6), 0.0, rng.randf_range(-0.6, 0.6))
		var prop_id: String = CLUSTER_PROPS[rng.randi_range(0, CLUSTER_PROPS.size() - 1)]
		var holder := Node3D.new()
		holder.name = "Cluster_%d" % i
		holder.position = pos + offset
		holder.rotation.y = rng.randf_range(0.0, TAU)
		holder.scale = Vector3.ONE * rng.randf_range(0.7, 1.05)
		parent.add_child(holder)
		PropLibrary.attach(holder, prop_id, biome_id)


static func _add_spot(parent: Node3D, pos: Vector3, biome_id: String, energy: float) -> void:
	var light := OmniLight3D.new()
	light.name = "AccentFill"
	light.position = pos
	VisualLighting.configure_soft_omni(light, _biome_light_color(biome_id), energy * 0.9, 10.0, false)
	parent.add_child(light)


## A Blender prop placed at `pos` (floor level) and scaled, as a named child of `parent`.
static func _place_prop(
	parent: Node3D, id: String, pos: Vector3, biome_id: String, prop_scale: Vector3, node_name: String, options: Dictionary = {}
) -> Node3D:
	var holder := Node3D.new()
	holder.name = node_name
	holder.position = pos
	holder.scale = prop_scale
	parent.add_child(holder)
	PropLibrary.attach(holder, id, biome_id, options)
	return holder


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
