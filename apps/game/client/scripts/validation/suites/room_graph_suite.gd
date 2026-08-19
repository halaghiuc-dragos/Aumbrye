extends "res://scripts/validation/validation_suite.gd"

const RoomGraphGeneratorScript := preload("res://scripts/dungeon/procgen/room_graph_generator.gd")
const RoomGraphConfigScript := preload("res://scripts/dungeon/procgen/room_graph_config.gd")
const RoomGraphDebugScript := preload("res://scripts/dungeon/procgen/room_graph_debug.gd")
const RoomGraphPathsScript := preload("res://scripts/dungeon/procgen/room_graph_paths.gd")
const RoomGraphAssignerScript := preload("res://scripts/dungeon/procgen/room_graph_assigner.gd")
const RoomGraphGeometryScript := preload("res://scripts/dungeon/procgen/room_graph_geometry.gd")
const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")
const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const MinimapScript := preload("res://scripts/ui/minimap.gd")
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


func get_category() -> String:
	return "room_graph"


func run() -> void:
	_test_phase1_deterministic()
	_test_phase1_ascii()
	_test_phase1_validation_fields()
	_test_phase1_variation()
	_test_no_fallback_needed()
	_test_no_sealed_rooms()
	_test_special_roles_distinct()
	_test_treasure_always_present()
	_test_door_reachability()
	_test_graph_distance_is_door_distance()
	_test_height_levels_step_by_one()
	_test_assigner_varies_with_rng()
	_test_room_bounds_do_not_overlap()
	_test_full_pipeline()
	_test_shortcut_edge_emission()
	_test_map_edge_fog()
	_test_map_neighbour_promotion()
	_test_map_player_marker_bound()
	_test_map_uniform_scale()
	_test_map_integral_coords()
	_test_map_bounds_no_origin_bias()
	_test_map_has_graph_false_when_unconfigured()
	_test_map_icon_cells_present()
	_test_map_kind_fallback()
	_test_map_center_cache()
	_test_map_action_registered()


func _test_phase1_deterministic() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var a := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var b := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph_a: RoomGraph = a.get("graph")
	var graph_b: RoomGraph = b.get("graph")
	var ok: bool = (
		a.get("ok", false)
		and b.get("ok", false)
		and graph_a.occupied_ids().size() == graph_b.occupied_ids().size()
		and graph_a.boss_id == graph_b.boss_id
	)
	ctx.timed_record(
		"room_graph.phase1_deterministic",
		get_category(),
		ok,
		"Phase 1 graph is deterministic for seed %d" % TC.SEED_A,
		start,
		"M8.room_graph.determinism"
	)


func _test_phase1_ascii() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result := RoomGraphGeneratorScript.generate(config, TC.SEED_B)
	var graph: RoomGraph = result.get("graph")
	var ascii := RoomGraphDebugScript.render_ascii(graph)
	var ok: bool = ascii.contains("Start=") and ascii.contains("Boss=")
	ctx.timed_record(
		"room_graph.phase1_ascii",
		get_category(),
		ok,
		"ASCII debug renderer includes start/boss markers",
		start,
		"M8.room_graph.ascii"
	)


func _test_phase1_validation_fields() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = result.get("graph")
	var ok: bool = (
		result.get("ok", false)
		and graph.start_id != ""
		and graph.boss_id != ""
		and graph.stairs_id != ""
		and graph.treasure_id != ""
		and graph.main_slot_count() >= config.min_rooms
	)
	ctx.timed_record(
		"room_graph.phase1_validated",
		get_category(),
		ok,
		"Phase 1 graph has start/boss/stairs/treasure and >= min rooms",
		start,
		"M8.room_graph.validation"
	)


func _test_phase1_variation() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result_a := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var result_b := RoomGraphGeneratorScript.generate(config, TC.SEED_B)
	var graph_a: RoomGraph = result_a.get("graph")
	var graph_b: RoomGraph = result_b.get("graph")
	var sig_a := "|".join(graph_a.occupied_ids())
	var sig_b := "|".join(graph_b.occupied_ids())
	var ok: bool = result_a.get("ok", false) and result_b.get("ok", false) and sig_a != sig_b
	ctx.timed_record(
		"room_graph.phase1_variation",
		get_category(),
		ok,
		"Different seeds produce different layout signatures",
		start,
		"M8.room_graph.variation"
	)


func _test_no_fallback_needed() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var fail_detail := ""
	for biome_id in BIOME_IDS:
		var biome := BiomeRegistry.get_biome(biome_id)
		var config := RoomGraphConfigScript.from_biome(biome)
		for i in 500:
			var seed := TC.SEED_A + i * 1_003
			var result := RoomGraphGeneratorScript.generate(config, seed)
			if not result.get("ok", false):
				ok = false
				fail_detail = "biome=%s seed=%d reason=%s" % [
					biome_id, seed, result.get("reason", "?")
				]
				break
		if not ok:
			break
	ctx.timed_record(
		"room_graph.no_fallback_needed",
		get_category(),
		ok,
		"generate() succeeds without fallback (500 seeds x 10 biomes)" if ok else fail_detail,
		start,
		"RGP-10"
	)


func _test_no_sealed_rooms() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BIOME_IDS:
		var biome := BiomeRegistry.get_biome(biome_id)
		var config := RoomGraphConfigScript.from_biome(biome)
		for i in 200:
			var seed := TC.SEED_A + i * 7919
			var result := RoomGraphGeneratorScript.generate(config, seed)
			if not result.get("ok", false):
				ok = false
				break
			var graph: RoomGraph = result.get("graph")
			for cell in graph.slots:
				var slot: RoomGraphSlot = graph.slots[cell]
				if slot.connection_count() < 1:
					ok = false
					break
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"room_graph.no_sealed_rooms",
		get_category(),
		ok,
		"Every slot has at least one door (200 seeds x 10 biomes)",
		start,
		"RGP-04"
	)


func _test_special_roles_distinct() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var ok := true
	for i in 100:
		var result := RoomGraphGeneratorScript.generate(config, TC.SEED_A + i * 13)
		if not result.get("ok", false):
			ok = false
			break
		var graph: RoomGraph = result.get("graph")
		if (
			graph.boss_id == ""
			or graph.stairs_id == ""
			or graph.treasure_id == ""
			or graph.boss_id == graph.stairs_id
			or graph.boss_id == graph.treasure_id
			or graph.stairs_id == graph.treasure_id
		):
			ok = false
			break
	ctx.timed_record(
		"room_graph.special_roles_distinct",
		get_category(),
		ok,
		"boss, stairs, and treasure are distinct non-empty slot ids",
		start,
		"RGP-03"
	)


func _test_treasure_always_present() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var ok := true
	for i in 100:
		var result := RoomGraphGeneratorScript.generate(config, TC.SEED_B + i * 17)
		if not result.get("ok", false):
			ok = false
			break
		var graph: RoomGraph = result.get("graph")
		var treasure := graph.get_slot(graph.treasure_id)
		if treasure == null or treasure.slot_type != RoomGraphSlot.SlotType.TREASURE:
			ok = false
			break
	ctx.timed_record(
		"room_graph.treasure_always_present",
		get_category(),
		ok,
		"treasure_id is set and slot type is TREASURE",
		start,
		"RGP-02"
	)


func _test_door_reachability() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var ok := true
	for i in 100:
		var result := RoomGraphGeneratorScript.generate(config, 4242 + i)
		if not result.get("ok", false):
			ok = false
			break
		var graph: RoomGraph = result.get("graph")
		var component := RoomGraphPathsScript.connected_component(graph, graph.start_id)
		if component.size() != graph.main_slot_count():
			ok = false
			break
	ctx.timed_record(
		"room_graph.door_reachability",
		get_category(),
		ok,
		"Door-connected component covers all non-secret slots",
		start,
		"RGP-06"
	)


func _test_graph_distance_is_door_distance() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var ok := true
	for i in 20:
		var result := RoomGraphGeneratorScript.generate(config, TC.SEED_A + i * 503)
		if not result.get("ok", false):
			ok = false
			break
		var graph: RoomGraph = result.get("graph")
		var distances := RoomGraphPathsScript.bfs_distances(graph, graph.start_id)
		for cell in graph.slots:
			var slot: RoomGraphSlot = graph.slots[cell]
			if slot.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			if slot.graph_distance != int(distances.get(slot.slot_id, -1)):
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"room_graph.graph_distance_is_door_distance",
		get_category(),
		ok,
		"slot.graph_distance matches door BFS for 20 seeds",
		start,
		"RGP-06"
	)


func _test_height_levels_step_by_one() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	config.max_height_level = 2
	var ok := true
	for i in 50:
		var result := RoomGraphGeneratorScript.generate(config, TC.SEED_A + i * 97)
		if not result.get("ok", false):
			continue
		var graph: RoomGraph = result.get("graph")
		for cell in graph.slots:
			var slot: RoomGraphSlot = graph.slots[cell]
			if slot.slot_type == RoomGraphSlot.SlotType.SECRET:
				continue
			for dir in [
				Vector2i(0, -1), Vector2i(1, 0), Vector2i(0, 1), Vector2i(-1, 0)
			]:
				if not (slot.door_mask & _dir_to_door(dir)):
					continue
				var neighbor: RoomGraphSlot = graph.get_slot_at(cell + dir)
				if neighbor == null:
					continue
				if absi(slot.height_level - neighbor.height_level) > 1:
					ok = false
					break
			if not ok:
				break
		if not ok:
			break
	ctx.timed_record(
		"room_graph.height_levels_step_by_one",
		get_category(),
		ok,
		"Door-connected rooms differ by at most one height level",
		start,
		"RGP-09"
	)


func _test_assigner_varies_with_rng() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var graph_result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = graph_result.get("graph")
	var varied := false
	for i in 50:
		var rng_a := RandomNumberGenerator.new()
		rng_a.seed = 111 + i
		var rng_b := RandomNumberGenerator.new()
		rng_b.seed = 999_111 + i
		var assign_a := RoomGraphAssignerScript.assign(biome, graph, rng_a)
		var assign_b := RoomGraphAssignerScript.assign(biome, graph, rng_b)
		for j in assign_a.get("rooms", []).size():
			var room_a: Dictionary = assign_a["rooms"][j]
			var room_b: Dictionary = assign_b["rooms"][j]
			if room_a.get("template_id", "") != room_b.get("template_id", ""):
				varied = true
				break
		if varied:
			break
	ctx.timed_record(
		"room_graph.assigner_varies_with_rng",
		get_category(),
		varied,
		"Different assigner RNG seeds can pick different templates",
		start,
		"RGP-07"
	)


func _test_room_bounds_do_not_overlap() -> void:
	var start := Time.get_ticks_msec()
	var biome := BiomeRegistry.get_biome("forgotten_castle")
	var config := RoomGraphConfigScript.from_biome(biome)
	var result := RoomGraphGeneratorScript.generate(config, TC.SEED_A)
	var graph: RoomGraph = result.get("graph")
	var assign_rng := RandomNumberGenerator.new()
	assign_rng.seed = TC.SEED_A
	var assignment := RoomGraphAssignerScript.assign(biome, graph, assign_rng)
	var rooms := RoomGraphGeometryScript.build_rooms(graph, assignment)
	var ok := true
	for i in rooms.size():
		for j in range(i + 1, rooms.size()):
			if _room_aabbs_overlap(rooms[i], rooms[j]):
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"room_graph.room_bounds_no_overlap",
		get_category(),
		ok,
		"Computed room AABBs do not intersect by more than 0.01",
		start,
		"RGP-14"
	)


func _test_full_pipeline() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var def: Dictionary = gen.get("definition", {})
	var rooms: Array = def.get("rooms", [])
	var ok: bool = gen.get("ok", false) == true and rooms.size() >= 8 and int(def.get("schemaVersion", 0)) == 2
	ctx.timed_record(
		"room_graph.full_pipeline",
		get_category(),
		ok,
		"Phase 1+2 pipeline produces %d rooms with schema v2" % rooms.size(),
		start,
		"M8.room_graph.pipeline"
	)

	start = Time.get_ticks_msec()
	var gen2 := DungeonProcgenScript.generate("forgotten_castle", TC.SEED_A, 1, 1, 1, false, false)
	var sig1: String = ctx.layout_signature(def)
	var sig2: String = ctx.layout_signature(gen2.get("definition", {}))
	ctx.timed_record(
		"room_graph.full_deterministic",
		get_category(),
		sig1 == sig2 and not sig1.is_empty(),
		"Full pipeline is deterministic for seed %d" % TC.SEED_A,
		start,
		"M8.room_graph.full_determinism"
	)


func _test_shortcut_edge_emission() -> void:
	var start := Time.get_ticks_msec()
	var found := false
	var shortcut_count := 0
	for attempt in 64:
		var seed := TC.SEED_A + attempt * 17_003
		var gen := DungeonProcgenScript.generate("forgotten_castle", seed, 1, 1, 1, false, false)
		if not gen.get("ok", false):
			continue
		var count := 0
		for edge in gen.get("definition", {}).get("edges", []):
			if edge is Dictionary and str(edge.get("kind", "")) == "shortcut":
				count += 1
			if edge is Dictionary and str(edge.get("kind", "")) == "one_way":
				count = -1
				break
		if count > 0:
			found = true
			shortcut_count = count
			break
	ctx.timed_record(
		"room_graph.shortcut_edge_emission",
		get_category(),
		found,
		"procgen emits shortcut edges without one_way (found %d)" % shortcut_count,
		start,
		"RGP-12"
	)


static func _dir_to_door(dir: Vector2i) -> int:
	if dir == Vector2i(0, -1):
		return RoomGraphSlot.DOOR_NORTH
	if dir == Vector2i(1, 0):
		return RoomGraphSlot.DOOR_EAST
	if dir == Vector2i(0, 1):
		return RoomGraphSlot.DOOR_SOUTH
	return RoomGraphSlot.DOOR_WEST


static func _room_aabbs_overlap(a: Dictionary, b: Dictionary) -> bool:
	var ta: Dictionary = a.get("transform", {})
	var tb: Dictionary = b.get("transform", {})
	var spec_a := RoomTemplateCatalogScript.get_spec(str(a.get("templateId", "")))
	var spec_b := RoomTemplateCatalogScript.get_spec(str(b.get("templateId", "")))
	var yaw_a := deg_to_rad(float(ta.get("yaw", 0.0)))
	var yaw_b := deg_to_rad(float(tb.get("yaw", 0.0)))
	var half_ax := RoomTemplateCatalogScript.half_extent_x(spec_a, yaw_a)
	var half_az := RoomTemplateCatalogScript.half_extent_z(spec_a, yaw_a)
	var half_bx := RoomTemplateCatalogScript.half_extent_x(spec_b, yaw_b)
	var half_bz := RoomTemplateCatalogScript.half_extent_z(spec_b, yaw_b)
	var dx := absf(float(ta.get("x", 0.0)) - float(tb.get("x", 0.0)))
	var dz := absf(float(ta.get("z", 0.0)) - float(tb.get("z", 0.0)))
	return dx < (half_ax + half_bx - 0.01) and dz < (half_az + half_bz - 0.01)


func _chain_definition() -> Dictionary:
	return {
		"rooms":
		[
			{"id": "r1", "transform": {"x": 0.0, "z": 0.0}},
			{"id": "r2", "transform": {"x": 20.0, "z": 0.0}},
			{"id": "r3", "transform": {"x": 40.0, "z": 0.0}},
			{"id": "r4", "transform": {"x": 60.0, "z": 0.0}},
			{"id": "r5", "transform": {"x": 80.0, "z": 0.0}},
		],
		"edges":
		[
			{"from": "r1", "to": "r2"},
			{"from": "r2", "to": "r3"},
			{"from": "r3", "to": "r4"},
			{"from": "r4", "to": "r5"},
		],
		"branchPreviews": [],
	}


func _spawn_minimap() -> Control:
	var minimap: Control = MinimapScript.new()
	ctx.owner.add_child(minimap)
	return minimap


func _test_map_edge_fog() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	minimap.configure(_chain_definition())
	minimap.mark_visited("r1")
	var ok: bool = minimap.count_drawn_edges_for_test() == 1
	ctx.timed_record(
		"map.edge_fog",
		get_category(),
		ok,
		"Only the edge to the SEEN neighbour is drawn after visiting r1",
		start,
		"MAP-01"
	)


func _test_map_neighbour_promotion() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	minimap.configure(_chain_definition())
	minimap.mark_visited("r1")
	var ok: bool = (
		minimap.get_reveal_tier("r2") == MinimapScript.RevealTier.SEEN
		and minimap.get_reveal_tier("r3") == MinimapScript.RevealTier.UNKNOWN
	)
	ctx.timed_record(
		"map.neighbour_promotion",
		get_category(),
		ok,
		"mark_visited promotes graph neighbours to SEEN only",
		start,
		"MAP-01"
	)


func _test_map_player_marker_bound() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	minimap.configure(_chain_definition())
	var player := Node3D.new()
	ctx.owner.add_child(player)
	player.position = Vector3(0.0, 0.0, 0.0)
	minimap.bind_player(player)
	var before: Vector2 = minimap.get_player_map_point()
	player.position = Vector3(5.0, 0.0, 0.0)
	var after: Vector2 = minimap.get_player_map_point()
	var ok: bool = before != after
	ctx.timed_record(
		"map.player_marker_bound",
		get_category(),
		ok,
		"Player movement changes projected map point",
		start,
		"MAP-02"
	)


func _test_map_uniform_scale() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	minimap.configure(
		{
			"rooms":
			[
				{"id": "a", "transform": {"x": 0.0, "z": 0.0}},
				{"id": "b", "transform": {"x": 60.0, "z": 0.0}},
				{"id": "c", "transform": {"x": 0.0, "z": 20.0}},
			],
			"edges": [],
			"branchPreviews": [],
		}
	)
	var map_rect := Rect2(0.0, 0.0, 120.0, 120.0)
	var origin: Vector2 = minimap.map_point_for_test(Vector2.ZERO, map_rect)
	var along_x: Vector2 = minimap.map_point_for_test(Vector2(1.0, 0.0), map_rect)
	var along_z: Vector2 = minimap.map_point_for_test(Vector2(0.0, 1.0), map_rect)
	var dx := (along_x - origin).length()
	var dz := (along_z - origin).length()
	var ok := is_equal_approx(dx, dz)
	ctx.timed_record(
		"map.uniform_scale",
		get_category(),
		ok,
		"Uniform projection keeps equal metres-per-pixel on both axes",
		start,
		"MAP-06"
	)


func _test_map_integral_coords() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	minimap.configure(_chain_definition())
	var map_rect := Rect2(6.0, 6.0, 128.0, 128.0)
	var ok := true
	for room in _chain_definition()["rooms"]:
		var t: Dictionary = room.get("transform", {})
		var p: Vector2 = minimap.map_point_for_test(
			Vector2(float(t.get("x", 0.0)), float(t.get("z", 0.0))), map_rect
		)
		if not is_equal_approx(p.x, floor(p.x)) or not is_equal_approx(p.y, floor(p.y)):
			ok = false
			break
	ctx.timed_record(
		"map.integral_coords",
		get_category(),
		ok,
		"_map_point returns integral coordinates",
		start,
		"MAP-07"
	)


func _test_map_bounds_no_origin_bias() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	minimap.configure(
		{
			"rooms":
			[
				{"id": "a", "transform": {"x": 100.0, "z": 0.0}},
				{"id": "b", "transform": {"x": 160.0, "z": 0.0}},
			],
			"edges": [],
			"branchPreviews": [],
		}
	)
	var bounds: Rect2 = minimap.get_bounds_for_test()
	var ok := is_equal_approx(bounds.position.x, 100.0)
	ctx.timed_record(
		"map.bounds_no_origin_bias",
		get_category(),
		ok,
		"Bounds seed from first room without forcing world origin",
		start,
		"MAP-08"
	)


func _test_map_has_graph_false_when_unconfigured() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	var ok: bool = not minimap.has_graph()
	ctx.timed_record(
		"map.has_graph_false_when_unconfigured",
		get_category(),
		ok,
		"Fresh minimap reports has_graph() == false",
		start,
		"MAP-05"
	)


func _test_map_icon_cells_present() -> void:
	var start := Time.get_ticks_msec()
	var tex := load("res://assets/ui/minimap_icons.png") as Texture2D
	var ok := tex != null and tex.get_size() == Vector2(32, 16)
	ctx.timed_record(
		"map.icon_cells_present",
		get_category(),
		ok,
		"minimap_icons.png loads at 32x16",
		start,
		"MAP-04"
	)


func _test_map_kind_fallback() -> void:
	var start := Time.get_ticks_msec()
	var minimap := _spawn_minimap()
	var cell: Vector2i = minimap.icon_cell_for_kind("")
	var ok := cell == Vector2i(3, 1)
	ctx.timed_record(
		"map.kind_fallback",
		get_category(),
		ok,
		"Missing kind resolves to unknown icon cell",
		start,
		"MAP-04"
	)


func _test_map_center_cache() -> void:
	var start := Time.get_ticks_msec()
	var source := FileAccess.get_file_as_string("res://scripts/ui/minimap.gd")
	var fn_start := source.find("func _room_center")
	var fn_end := source.find("func _uniform_scale", fn_start)
	var body := source.substr(fn_start, fn_end - fn_start) if fn_end > fn_start else ""
	var ok := fn_start >= 0 and not body.contains("for room_def in _rooms")
	ctx.timed_record(
		"map.center_cache",
		get_category(),
		ok,
		"_room_center uses dictionary lookup, not array scan",
		start,
		"MAP-10"
	)


func _test_map_action_registered() -> void:
	var start := Time.get_ticks_msec()
	var ok := InputMap.has_action("map")
	ctx.timed_record(
		"map.action_registered",
		get_category(),
		ok,
		"map input action is registered in project.godot",
		start,
		"MAP-09"
	)
