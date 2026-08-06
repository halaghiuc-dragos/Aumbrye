extends "res://scripts/validation/validation_suite.gd"

const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

const BIOME_IDS := [
	"forgotten_castle",
	"crystal_caverns",
	"poison_swamp",
	"frozen_fortress",
	"dark_cathedral",
	"iron_vault",
	"prism_depths",
	"venom_mire",
	"glacial_hollow",
	"umbral_chapel",
]

const SOCKET_DIRECTIONS := [
	CastleRoomConstants.Direction.NORTH,
	CastleRoomConstants.Direction.EAST,
	CastleRoomConstants.Direction.SOUTH,
	CastleRoomConstants.Direction.WEST,
]


func get_category() -> String:
	return "room_kit"


func run() -> void:
	_test_all_templates_instantiate()
	_test_blockout_matches_kind_specs()
	_test_four_sockets_per_room()
	_test_socket_on_wall_face()
	_test_required_markers_present()
	await _test_socket_toward_after_rotation()
	_test_required_kind_substitution()


func _test_all_templates_instantiate() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		var scenes: Dictionary = BiomeRegistry.get_room_scenes(biome_id)
		if scenes.size() != 10:
			ok = false
			break
		for template_id in scenes:
			var packed: PackedScene = scenes[template_id]
			var room := packed.instantiate()
			if not room is RoomTemplate:
				ok = false
				break
			room.free()
		if not ok:
			break
	ctx.timed_record(
		"room_kit.all_templates_instantiate",
		get_category(),
		ok,
		"Each biome exposes 10 room scenes that instantiate as RoomTemplate",
		start,
		"RTP-08"
	)


func _test_blockout_matches_kind_specs() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		for template_id in BiomeRegistry.get_room_scenes(biome_id):
			var room: RoomTemplate = BiomeRegistry.get_room_scene(biome_id, template_id).instantiate()
			room.template_id = str(template_id)
			if room is CastleRoomScene:
				(room as CastleRoomScene).sync_kit_contract()
			else:
				room._ready()
			var blockout := room.get_blockout()
			var spec := RoomTemplateCatalogScript.get_spec(str(template_id))
			if blockout == null:
				ok = false
			elif (
				not is_equal_approx(blockout.room_width, float(spec.get("width", -1)))
				or not is_equal_approx(blockout.room_depth, float(spec.get("depth", -1)))
			):
				ok = false
			room.free()
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"room_kit.blockout_matches_kind_specs",
		get_category(),
		ok,
		"CastleBlockout dimensions match KIND_SPECS for all templates",
		start,
		"RTP-01"
	)


func _test_four_sockets_per_room() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		for template_id in BiomeRegistry.get_room_scenes(biome_id):
			var room: RoomTemplate = BiomeRegistry.get_room_scene(biome_id, template_id).instantiate()
			room.template_id = str(template_id)
			if room is CastleRoomScene:
				(room as CastleRoomScene).sync_kit_contract()
			else:
				room._ready()
			var seen := {}
			for socket in room.get_sockets():
				seen[socket.direction] = true
			if seen.size() != 4:
				ok = false
			room.free()
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"room_kit.four_sockets_per_room",
		get_category(),
		ok,
		"Every room scene has four distinct DoorwaySocket directions",
		start,
		"RTP-06"
	)


func _test_socket_on_wall_face() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		for template_id in BiomeRegistry.get_room_scenes(biome_id):
			var room: RoomTemplate = BiomeRegistry.get_room_scene(biome_id, template_id).instantiate()
			room.template_id = str(template_id)
			if room is CastleRoomScene:
				(room as CastleRoomScene).sync_kit_contract()
			else:
				room._ready()
			var blockout := room.get_blockout()
			if blockout == null:
				ok = false
				break
			var half_w := blockout.room_width * 0.5
			var half_d := blockout.room_depth * 0.5
			for socket in room.get_sockets():
				var expected := RoomTemplateCatalogScript.socket_wall_position(
					socket.direction, half_w, half_d
				)
				if socket.position.distance_to(expected) > 0.01:
					ok = false
					break
			room.free()
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"room_kit.socket_on_wall_face",
		get_category(),
		ok,
		"DoorwaySocket local positions sit on the wall face implied by kind",
		start,
		"RTP-01"
	)


func _test_required_markers_present() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		for template_id in BiomeRegistry.get_room_scenes(biome_id):
			var room: RoomTemplate = BiomeRegistry.get_room_scene(biome_id, template_id).instantiate()
			room.template_id = str(template_id)
			if room is CastleRoomScene:
				(room as CastleRoomScene).sync_kit_contract()
			else:
				room._ready()
			if room.get_node_or_null("Props") == null:
				ok = false
			var kind := RoomTemplateCatalogScript.kind_from_template_id(str(template_id))
			if kind == "stairs":
				if room.get_node_or_null("SpawnPoints/LeverSpawn") == null:
					ok = false
				if room.get_node_or_null("Props/StairRamp") == null:
					ok = false
			if kind == "boss":
				if room.get_node_or_null("Props/BossSpawn") == null:
					ok = false
				if room.get_node_or_null("Props/ExitPortalMarker") == null:
					ok = false
				if room.get_node_or_null("Authored") == null or room.get_node("Authored").get_child_count() == 0:
					ok = false
			for index in 4:
				if room.get_node_or_null("Props/PropAnchor_%d" % index) == null:
					ok = false
			room.free()
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"room_kit.required_markers_present",
		get_category(),
		ok,
		"Props, role markers, and PropAnchor nodes exist per kind contract",
		start,
		"RTP-07"
	)


func _test_socket_toward_after_rotation() -> void:
	var start := Time.get_ticks_msec()
	var packed: PackedScene = load("res://scenes/rooms/castle/castle_courtyard.tscn")
	var ok := packed != null
	if ok:
		var root := Node3D.new()
		ctx.owner.add_child(root)
		var offsets := [
			Vector3(0.0, 0.0, -40.0),
			Vector3(40.0, 0.0, 0.0),
			Vector3(0.0, 0.0, 40.0),
			Vector3(-40.0, 0.0, 0.0),
		]
		for yaw in [0.0, PI * 0.5, PI, -PI * 0.5]:
			var room: RoomTemplate = packed.instantiate()
			room.template_id = "castle_courtyard"
			if room is CastleRoomScene:
				(room as CastleRoomScene).sync_kit_contract()
			root.add_child(room)
			room.rotation.y = yaw
			await ctx.await_frame()
			for offset in offsets:
				var probe: RoomTemplate = packed.instantiate()
				probe.template_id = "castle_courtyard"
				root.add_child(probe)
				probe.global_position = room.global_position + offset
				await ctx.await_frame()
				var socket := room.socket_toward(probe)
				if socket == null:
					ok = false
				probe.queue_free()
			room.queue_free()
			if not ok:
				break
		root.queue_free()
	ctx.timed_record(
		"room_kit.socket_toward_after_rotation",
		get_category(),
		ok,
		"socket_toward() resolves correctly on yaw-rotated courtyard rooms",
		start,
		"RTP-03"
	)


func _test_required_kind_substitution() -> void:
	var start := Time.get_ticks_msec()
	var ids: Array = BiomeRegistry.get_biome(BiomeRegistry.BIOME_CASTLE).get("roomTemplateIds", [])
	var doors := RoomGraphSlot.DOOR_NORTH | RoomGraphSlot.DOOR_EAST
	var picked := RoomTemplateCatalogScript.pick_template_for_doors(
		"castle_stairs", doors, ids, null, "stairs"
	)
	var ok := picked == "" or picked.ends_with("_stairs")
	ctx.timed_record(
		"room_kit.required_kind_substitution",
		get_category(),
		ok,
		"pick_template_for_doors with required_kind stairs never returns a non-stairs id",
		start,
		"RTP-02"
	)
