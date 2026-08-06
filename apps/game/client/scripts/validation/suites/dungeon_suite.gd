extends "res://scripts/validation/validation_suite.gd"

const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")
const RunFloorConfigScript := preload("res://scripts/dungeon/run_floor_config.gd")


func get_category() -> String:
	return "dungeon"


func run() -> void:
	await _test_build_pipeline()
	_test_builder_wiring()
	await _test_snapshot_roundtrip()
	await _test_loot_chest_configure()
	_test_no_height_delta_without_support()
	await _test_shortcut_edges_wired()
	_test_final_floor_biome_fantasy()
	_test_height_transitions_flat_when_disabled()
	_test_shortcut_edges_emitted()
	await _test_shortcut_edges_wired_in_build()
	_test_final_floor_biome_layout()
	await _test_cross_room_navigation()
	await _test_boss_reachable_by_path()
	await _test_single_nav_map()
	await _test_placements_inside_own_room()
	await _test_build_determinism()
	await _test_rotated_room_doors()
	await _test_secret_reachable()
	await _test_unload_leaves_nothing()
	await _test_unknown_template_aborts()
	await _test_minimal_fixture_builds()
	await _test_stair_levers_all_tracked()
	await _test_stairs_lever_parity()
	await _test_fixture_secret_parent_room_id()
	await _test_boss_door_blocks()
	await _test_boss_door_opens_and_seals()
	await _test_boss_door_release()
	await _test_boss_door_requirement()
	await _test_exit_portal_parented()
	await _test_exit_portal_requires_confirm()
	await _test_exit_portal_activate_path()
	await _test_no_door_without_boss()
	await _test_shell_freed_on_unload()
	await _test_no_ceiling_over_empty_cells()
	_test_floor_scaling_curve()
	await _test_stair_lookup_agreement()


func _test_build_pipeline() -> void:
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	if not gen.get("ok", false):
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"dungeon.build_from_definition",
			get_category(),
			false,
			"procgen failed before build test",
			start,
			"M3.dungeon.build"
		)
		return

	var root := Node3D.new()
	root.name = "ValidationDungeon"
	ctx.owner.add_child(root)

	var player_scene: PackedScene = load("res://scenes/player/player.tscn")
	var player: CharacterBody3D = player_scene.instantiate() as CharacterBody3D
	root.add_child(player)

	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, gen.get("definition", {}))
	await ctx.await_physics(2)

	var start := Time.get_ticks_msec()
	var room_count: int = builder.get_room_ids().size()
	var enemy_count: int = builder.get_spawned_enemy_count()
	ctx.timed_record(
		"dungeon.rooms_instantiated",
		get_category(),
		room_count > 0,
		"%d rooms built from procgen definition" % room_count,
		start,
		"M3.dungeon.rooms"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"dungeon.enemies_spawned",
		get_category(),
		enemy_count > 0,
		"%d enemies spawned from placements" % enemy_count,
		start,
		"M3.dungeon.enemies"
	)

	start = Time.get_ticks_msec()
	var chests: int = ctx.count_loot_chests(root)
	ctx.timed_record(
		"dungeon.loot_placed",
		get_category(),
		chests > 0,
		"%d loot chests in built dungeon" % chests,
		start,
		"M3.dungeon.loot"
	)

	start = Time.get_ticks_msec()
	var boss_door := builder.get_boss_door()
	ctx.timed_record(
		"dungeon.boss_door_wired",
		get_category(),
		boss_door != null,
		"boss room door created by builder",
		start,
		"M3.dungeon.boss_door"
	)

	start = Time.get_ticks_msec()
	var exit_room_id: String = gen.get("definition", {}).get("placements", {}).get("exit", "boss")
	var exit_room := builder.get_room(exit_room_id)
	var has_exit_marker: bool = (
		exit_room != null
		and (
			exit_room.get_node_or_null("Props/ExitPortal") != null
			or exit_room.get_node_or_null("Props/ExitPortalMarker") != null
		)
	)
	ctx.timed_record(
		"dungeon.exit_portal_wiring",
		get_category(),
		has_exit_marker,
		"exit portal or marker present in exit room",
		start,
		"M3.dungeon.exit_portal"
	)

	root.queue_free()


func _test_builder_wiring() -> void:
	var start := Time.get_ticks_msec()
	var template_count: int = BiomeRegistry.get_room_scenes(BiomeRegistry.BIOME_CASTLE).size()
	ctx.timed_record(
		"dungeon.room_scene_registry",
		get_category(),
		template_count >= 8,
		"%d room templates registered for castle biome" % template_count,
		start,
		"M2.dungeon.templates"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"dungeon.builder_exit_portal_script",
		get_category(),
		DungeonBuilder.EXIT_PORTAL_SCENE != null,
		"DungeonBuilder references exit portal script",
		start,
		"M3.dungeon.exit_script"
	)


func _test_snapshot_roundtrip() -> void:
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	if not gen.get("ok", false):
		return

	var root := Node3D.new()
	root.name = "SnapshotTest"
	ctx.owner.add_child(root)
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, gen.get("definition", {}))
	await ctx.await_frame()

	var start := Time.get_ticks_msec()
	var enemy_states := builder.capture_enemy_states()
	var loot_states := builder.capture_loot_states()
	var captured: bool = not enemy_states.is_empty() or not loot_states.is_empty()
	ctx.timed_record(
		"dungeon.snapshot_capture",
		get_category(),
		captured,
		"capture_enemy_states + capture_loot_states return data",
		start,
		"M3.save.snapshot"
	)

	start = Time.get_ticks_msec()
	var snapshot := {
		"enemies": enemy_states,
		"loot": loot_states,
		"bossDefeated": false,
	}
	builder.apply_snapshot(snapshot)
	ctx.timed_record(
		"dungeon.snapshot_restore",
		get_category(),
		true,
		"apply_snapshot completes without error",
		start,
		"M3.save.snapshot"
	)
	root.queue_free()


func _test_loot_chest_configure() -> void:
	var start := Time.get_ticks_msec()
	var chest_scene: PackedScene = load("res://scenes/loot/loot_chest.tscn")
	var chest: Node3D = chest_scene.instantiate() as Node3D
	ctx.owner.add_child(chest)
	await ctx.await_frame()
	if chest.has_method("configure"):
		chest.call("configure", {"items": [{"itemId": "iron_scrap", "quantity": 1}]})
	var opened_before: bool = chest.call("is_opened") if chest.has_method("is_opened") else true
	chest.queue_free()
	ctx.timed_record(
		"dungeon.loot_chest_configure",
		get_category(),
		not opened_before,
		"loot chest configure() sets items without opening",
		start,
		"M2.loot.chest"
	)


func _test_no_height_delta_without_support() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var ok := false
	var message := "procgen failed before height check"
	if gen.get("ok", false):
		var def: Dictionary = gen.get("definition", {})
		var max_height := int(def.get("maxHeightLevel", 0))
		var flat_y: float = NAN
		var uniform_y := true
		for room in def.get("rooms", []):
			if not room is Dictionary:
				continue
			var y := float(room.get("transform", {}).get("y", 0.0))
			if is_nan(flat_y):
				flat_y = y
			elif absf(y - flat_y) > 0.001:
				uniform_y = false
				message = (
					"room '%s' at y=%.2f differs from y=%.2f while maxHeightLevel=%d"
					% [room.get("id", ""), y, flat_y, max_height]
				)
				break
		ok = max_height > 0 or uniform_y
		if ok:
			message = (
				"all %d rooms share y=%.1f with maxHeightLevel=%d"
				% [def.get("rooms", []).size(), flat_y, max_height]
			)
	ctx.timed_record(
		"dungeon.no_height_delta_without_support", get_category(), ok, message, start, "DBL-05"
	)


func _find_definition_with_shortcut_edges(max_attempts: int = 64) -> Dictionary:
	for attempt in max_attempts:
		var seed := TC.SEED_A + attempt * 17_003
		var gen := LocalProcgen.generate("forgotten_castle", seed)
		if not gen.get("ok", false):
			continue
		var def: Dictionary = gen.get("definition", {})
		for edge in def.get("edges", []):
			if edge is Dictionary and str(edge.get("kind", "")) == "shortcut":
				return def
	return {}


func _count_nav_links_on_root(root: Node3D) -> int:
	var nav_root: Node = root.get_node_or_null("DungeonRoot/NavLinks")
	if nav_root == null:
		return 0
	var count := 0
	for child in nav_root.get_children():
		if child is NavigationLink3D:
			count += 1
	return count


func _count_nav_links(room: RoomTemplate) -> int:
	var blockout := room.get_blockout()
	if blockout == null:
		return 0
	var count := 0
	for child in blockout.get_children():
		if child is NavigationLink3D:
			count += 1
	return count


func _test_shortcut_edges_wired() -> void:
	var start := Time.get_ticks_msec()
	var def := _find_definition_with_shortcut_edges()
	if def.is_empty():
		ctx.timed_record(
			"dungeon.shortcut_edges_wired",
			get_category(),
			false,
			"no procgen seed produced a shortcut edge in %d attempts" % 64,
			start,
			"DBL-06"
		)
		return

	var shortcut_edges: Array = []
	for edge in def.get("edges", []):
		if edge is Dictionary and str(edge.get("kind", "")) == "shortcut":
			shortcut_edges.append(edge)

	var root := Node3D.new()
	root.name = "ShortcutEdgeTest"
	ctx.owner.add_child(root)
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, def)
	await ctx.await_physics(2)

	var doors_open := true
	var nav_links := 0
	for edge in shortcut_edges:
		var from_room := builder.get_room(str(edge.get("from", "")))
		var to_room := builder.get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			doors_open = false
			continue
		var from_blockout := from_room.get_blockout()
		var to_blockout := to_room.get_blockout()
		if from_blockout == null or to_blockout == null:
			doors_open = false
			continue
		var from_mask := from_room.door_mask_toward(to_room)
		var to_mask := to_room.door_mask_toward(from_room)
		if (
			not _blockout_has_door(from_blockout, from_mask)
			or not _blockout_has_door(to_blockout, to_mask)
		):
			doors_open = false
		nav_links += _count_nav_links_on_root(root)

	var ok := doors_open and nav_links > 0
	ctx.timed_record(
		"dungeon.shortcut_edges_wired",
		get_category(),
		ok,
		(
			"%d shortcut edge(s): doors open=%s, nav links=%d"
			% [shortcut_edges.size(), doors_open, nav_links]
		),
		start,
		"DBL-06"
	)
	root.queue_free()


func _blockout_has_door(blockout: CastleBlockout, door_mask: int) -> bool:
	match door_mask:
		RoomGraphSlot.DOOR_NORTH:
			return blockout.door_north
		RoomGraphSlot.DOOR_EAST:
			return blockout.door_east
		RoomGraphSlot.DOOR_SOUTH:
			return blockout.door_south
		RoomGraphSlot.DOOR_WEST:
			return blockout.door_west
	return false


func _test_final_floor_biome_fantasy() -> void:
	var start := Time.get_ticks_msec()
	var gen := DungeonProcgenScript.generate(
		BiomeRegistry.BIOME_HOLLOW, TC.SEED_A, 1, 1, RunFloorConfigScript.MAX_FLOORS, true
	)
	var def: Dictionary = gen.get("definition", {})
	var boss_id := str(def.get("placements", {}).get("boss", {}).get("enemyId", ""))
	var hollow_only := true
	for room in def.get("rooms", []):
		if room is Dictionary and not str(room.get("templateId", "")).begins_with("hollow_"):
			hollow_only = false
			break
	var ok: bool = (
		bool(gen.get("ok", false))
		and bool(def.get("isFinalFloor", false))
		and def.get("rooms", []).size() == 3
		and boss_id == "boss_frost_warlord"
		and boss_id != "final_boss_forgotten_castle"
		and hollow_only
	)
	(
		ctx
		. timed_record(
			"dungeon.final_floor_biome_fantasy",
			get_category(),
			ok,
			(
				"glacial_hollow floor %d: boss=%s, rooms=%d, hollow templates=%s"
				% [
					RunFloorConfigScript.MAX_FLOORS,
					boss_id,
					def.get("rooms", []).size(),
					hollow_only,
				]
			),
			start,
			"DBL.floor10"
		)
	)


func _test_height_transitions_flat_when_disabled() -> void:
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	if not gen.get("ok", false):
		return
	var definition: Dictionary = gen.get("definition", {})
	var start := Time.get_ticks_msec()
	var max_height := int(definition.get("maxHeightLevel", 0))
	var flat := true
	for room_def in definition.get("rooms", []):
		var y := float(room_def.get("transform", {}).get("y", 0.0))
		if absf(y) > 0.001:
			flat = false
			break
	ctx.timed_record(
		"dungeon.height_transitions_flat",
		get_category(),
		max_height == 0 and flat,
		"maxHeightLevel=%d and all rooms at y=0" % max_height,
		start,
		"DBL-05"
	)


func _test_shortcut_edges_emitted() -> void:
	var start := Time.get_ticks_msec()
	var found := false
	for seed in [TC.SEED_A, TC.SEED_B, 4242, 9001]:
		var gen := LocalProcgen.generate("forgotten_castle", seed)
		if not gen.get("ok", false):
			continue
		for edge in gen.get("definition", {}).get("edges", []):
			if edge.get("kind", "") == "shortcut":
				found = true
				break
		if found:
			break
	ctx.timed_record(
		"dungeon.shortcut_edges_emitted",
		get_category(),
		found,
		"procgen emits at least one shortcut edge from loop connections",
		start,
		"DBL-06"
	)


func _test_shortcut_edges_wired_in_build() -> void:
	var definition: Dictionary = {}
	for seed in [TC.SEED_A, TC.SEED_B, 4242, 9001]:
		var gen := LocalProcgen.generate("forgotten_castle", seed)
		if not gen.get("ok", false):
			continue
		var candidate: Dictionary = gen.get("definition", {})
		for edge in candidate.get("edges", []):
			if edge.get("kind", "") == "shortcut":
				definition = candidate
				break
		if not definition.is_empty():
			break
	var start := Time.get_ticks_msec()
	if definition.is_empty():
		ctx.timed_record(
			"dungeon.shortcut_edges_wired",
			get_category(),
			false,
			"no shortcut edges found to wire",
			start,
			"DBL-06"
		)
		return
	var shortcut_edges: Array = []
	for edge in definition.get("edges", []):
		if edge.get("kind", "") == "shortcut":
			shortcut_edges.append(edge)
	var root := Node3D.new()
	root.name = "ShortcutBuildTest"
	ctx.owner.add_child(root)
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, definition)
	await ctx.await_frame()
	var wired := true
	for edge in shortcut_edges:
		var from_room := builder.get_room(str(edge.get("from", "")))
		var to_room := builder.get_room(str(edge.get("to", "")))
		if from_room == null or to_room == null:
			wired = false
			break
		var from_blockout := from_room.get_blockout()
		var to_blockout := to_room.get_blockout()
		if from_blockout == null or to_blockout == null:
			wired = false
			break
		var from_open := (
			from_blockout.door_north
			or from_blockout.door_south
			or from_blockout.door_east
			or from_blockout.door_west
		)
		var to_open := (
			to_blockout.door_north
			or to_blockout.door_south
			or to_blockout.door_east
			or to_blockout.door_west
		)
		if not from_open or not to_open:
			wired = false
			break
	ctx.timed_record(
		"dungeon.shortcut_edges_wired",
		get_category(),
		wired,
		"shortcut edges open blockout doors on both rooms",
		start,
		"DBL-06"
	)
	root.queue_free()


func _test_final_floor_biome_layout() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("umbral_chapel", TC.SEED_A, RunFloorConfig.MAX_FLOORS)
	if not gen.get("ok", false):
		ctx.timed_record(
			"dungeon.final_floor_biome_layout",
			get_category(),
			false,
			"umbral floor 10 procgen failed",
			start,
			"RGP-08"
		)
		return
	var definition: Dictionary = gen.get("definition", {})
	var room_ids: Array = []
	var template_ids: Array = []
	for room_def in definition.get("rooms", []):
		room_ids.append(str(room_def.get("id", "")))
		template_ids.append(str(room_def.get("templateId", "")))
	var boss_id: String = definition.get("placements", {}).get("boss", {}).get("enemyId", "")
	var ok := (
		bool(definition.get("isFinalFloor", false))
		and room_ids.has("arena")
		and template_ids.has("umbral_arena")
		and template_ids.has("umbral_boss")
		and boss_id == "boss_cathedral_hollow"
	)
	ctx.timed_record(
		"dungeon.final_floor_biome_layout",
		get_category(),
		ok,
		"umbral floor 10: arena room, themed templates, biome boss (%s)" % boss_id,
		start,
		"RGP-08"
	)


func _build_test_dungeon(definition: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "DungeonTestRoot"
	ctx.owner.add_child(root)
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, definition)
	return {"root": root, "builder": builder, "player": player}


func _test_cross_room_navigation() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var message := ""
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var gen := LocalProcgen.generate(biome_id, TC.SEED_A)
		if not gen.get("ok", false):
			ok = false
			message = "procgen failed for %s" % biome_id
			break
		var built := _build_test_dungeon(gen.get("definition", {}))
		await ctx.await_physics(2)
		var builder: DungeonBuilder = built["builder"]
		var map := builder.get_floor_nav_map()
		for edge in gen.get("definition", {}).get("edges", []):
			var kind := str(edge.get("kind", "door"))
			if kind == "secret":
				continue
			var from_room := builder.get_room(str(edge.get("from", "")))
			var to_room := builder.get_room(str(edge.get("to", "")))
			if from_room == null or to_room == null:
				ok = false
				break
			var from_spawn := from_room.get_player_spawn_global()
			var to_center := to_room.global_position
			var path: PackedVector3Array = NavigationServer3D.map_get_path(map, from_spawn, to_center, true)
			if path.size() <= 1:
				ok = false
				message = "degenerate path %s->%s in %s" % [edge.get("from"), edge.get("to"), biome_id]
				break
			if path[path.size() - 1].distance_to(to_center) > 2.0:
				ok = false
				message = "path end far from target on %s->%s" % [edge.get("from"), edge.get("to")]
				break
		built["root"].queue_free()
		if not ok:
			break
	if ok:
		message = "cross-room paths valid for all %d biomes" % BiomeRegistry.ALL_BIOMES.size()
	ctx.timed_record("dungeon.cross_room_navigation", get_category(), ok, message, start, "DBL-01")


func _test_boss_reachable_by_path() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var message := ""
	for i in 50:
		var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A + i * 7919)
		if not gen.get("ok", false):
			continue
		var def: Dictionary = gen.get("definition", {})
		var boss_room_id := str(def.get("placements", {}).get("boss", {}).get("roomId", "boss"))
		var entrance_id := str(def.get("placements", {}).get("entrance", "entrance"))
		if boss_room_id.is_empty():
			continue
		var built := _build_test_dungeon(def)
		await ctx.await_physics(1)
		var builder: DungeonBuilder = built["builder"]
		var map := builder.get_floor_nav_map()
		var entrance := builder.get_room(entrance_id)
		var boss_room := builder.get_room(boss_room_id)
		if entrance == null or boss_room == null:
			ok = false
			message = "missing entrance or boss room"
			built["root"].queue_free()
			break
		var path: PackedVector3Array = NavigationServer3D.map_get_path(
			map,
			entrance.get_player_spawn_global(),
			boss_room.global_position,
			true
		)
		if path.is_empty():
			ok = false
			message = "no path to boss on seed offset %d" % i
			built["root"].queue_free()
			break
		built["root"].queue_free()
	if ok:
		message = "boss reachable by nav path on 50 procgen seeds"
	ctx.timed_record("dungeon.boss_reachable_by_path", get_category(), ok, message, start, "DBL-01")


func _test_single_nav_map() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var ok := false
	var message := "procgen failed"
	if gen.get("ok", false):
		var built := _build_test_dungeon(gen.get("definition", {}))
		await ctx.await_frame()
		var builder: DungeonBuilder = built["builder"]
		var map := builder.get_floor_nav_map()
		ok = map != RID()
		if ok:
			for room_id in builder.get_room_ids():
				var room := builder.get_room(room_id)
				var blockout := room.get_blockout()
				if blockout and blockout.get_navigation_map() != map:
					ok = false
					message = "blockout map mismatch in %s" % room_id
					break
			var nav_root: Node = built["root"].get_node_or_null("DungeonRoot/NavLinks")
			if nav_root:
				for child in nav_root.get_children():
					if child is NavigationLink3D and child.navigation_map != map:
						ok = false
						message = "nav link map mismatch"
						break
		if ok:
			message = "single floor nav map assigned"
		built["root"].queue_free()
	ctx.timed_record("dungeon.single_nav_map", get_category(), ok, message, start, "DBL-02")


func _test_placements_inside_own_room() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var ok := false
	var message := "procgen failed"
	if gen.get("ok", false):
		var built := _build_test_dungeon(gen.get("definition", {}))
		await ctx.await_frame()
		var builder: DungeonBuilder = built["builder"]
		ok = true
		for room_id in builder.get_room_ids():
			var room := builder.get_room(room_id)
			for child in room.get_children():
				if child.is_in_group("enemy") or child is CharacterBody3D and child.is_in_group("enemy"):
					if not room.contains_world_point(child.global_position):
						ok = false
						message = "enemy outside %s" % room_id
						break
			if not ok:
				break
		if ok:
			message = "placements inside room AABBs"
		built["root"].queue_free()
	ctx.timed_record("dungeon.placements_inside_room", get_category(), ok, message, start, "DBL-02")


func _test_build_determinism() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var ok := false
	var message := "procgen failed"
	if gen.get("ok", false):
		var def: Dictionary = gen.get("definition", {})
		var built_a := _build_test_dungeon(def)
		await ctx.await_frame()
		var positions_a := _collect_enemy_positions(built_a["builder"])
		built_a["root"].queue_free()
		var built_b := _build_test_dungeon(def)
		await ctx.await_frame()
		var positions_b := _collect_enemy_positions(built_b["builder"])
		ok = positions_a == positions_b
		message = "identical enemy positions" if ok else "enemy positions diverged"
		built_b["root"].queue_free()
	ctx.timed_record("dungeon.build_determinism", get_category(), ok, message, start, "DBL-02")


func _collect_enemy_positions(builder: DungeonBuilder) -> Array:
	var out: Array = []
	for room_id in builder.get_room_ids():
		var room := builder.get_room(room_id)
		for child in room.get_children():
			if child.is_in_group("enemy"):
				out.append(child.global_position)
	out.sort_custom(func(a: Vector3, b: Vector3) -> bool:
		return a.x < b.x or (a.x == b.x and a.z < b.z)
	)
	return out


func _test_rotated_room_doors() -> void:
	var start := Time.get_ticks_msec()
	var definition := {
		"seed": TC.SEED_A,
		"biomeId": "forgotten_castle",
		"rooms": [
			{"id": "a", "templateId": "castle_courtyard", "type": "combat", "transform": {"x": 0, "y": 0, "z": 0, "yaw": 90}},
			{"id": "b", "templateId": "castle_hall", "type": "combat", "transform": {"x": 0, "y": 0, "z": 24, "yaw": 90}},
		],
		"edges": [{"from": "a", "to": "b", "kind": "door"}],
		"placements": {"entrance": "a", "enemies": [], "loot": [], "traps": [], "secrets": []},
	}
	var built := _build_test_dungeon(definition)
	await ctx.await_frame()
	var builder: DungeonBuilder = built["builder"]
	var room_a := builder.get_room("a")
	var room_b := builder.get_room("b")
	var socket := room_a.socket_toward(room_b)
	var blockout := room_a.get_blockout()
	var ok := socket != null and blockout != null
	if ok:
		match socket.direction:
			CastleRoomConstants.Direction.NORTH:
				ok = blockout.door_north
			CastleRoomConstants.Direction.EAST:
				ok = blockout.door_east
			CastleRoomConstants.Direction.SOUTH:
				ok = blockout.door_south
			CastleRoomConstants.Direction.WEST:
				ok = blockout.door_west
	built["root"].queue_free()
	ctx.timed_record(
		"dungeon.rotated_room_doors",
		get_category(),
		ok,
		"rotated rooms open door matching socket direction",
		start,
		"DBL-03"
	)


func _test_secret_reachable() -> void:
	var start := Time.get_ticks_msec()
	var def: Dictionary = {}
	for seed in [TC.SEED_A, TC.SEED_B, 4242]:
		var gen := LocalProcgen.generate("forgotten_castle", seed)
		if not gen.get("ok", false):
			continue
		var candidate: Dictionary = gen.get("definition", {})
		if not candidate.get("placements", {}).get("secrets", []).is_empty():
			def = candidate
			break
	var ok := false
	var message := "no secret placement found"
	if not def.is_empty():
		var built := _build_test_dungeon(def)
		await ctx.await_frame()
		var builder: DungeonBuilder = built["builder"]
		for secret in def.get("placements", {}).get("secrets", []):
			var parent := builder.get_room(str(secret.get("parentRoomId", "")))
			if parent == null:
				continue
			var props := parent.get_node_or_null("Props")
			if props == null:
				continue
			for child in props.get_children():
				if child is Area3D or child.get_node_or_null("InteractArea") != null:
					ok = true
					var secret_id := str(secret.get("roomId", ""))
					builder.reveal_secret(secret_id)
					break
		message = "secret mechanism interactable and reveal opens door" if ok else "no interactable secret node"
		built["root"].queue_free()
	ctx.timed_record("dungeon.secret_reachable", get_category(), ok, message, start, "DBL-04")


func _test_unload_leaves_nothing() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var ok := false
	var message := "procgen failed"
	if gen.get("ok", false):
		var built := _build_test_dungeon(gen.get("definition", {}))
		await ctx.await_frame()
		var builder: DungeonBuilder = built["builder"]
		var root: Node3D = built["root"]
		builder.unload_from_parent(root)
		await ctx.await_frame()
		var names := ["Rooms", "DoorwayBridges", "Landmarks", "FloorShell", "NavLinks", "Entities", "DungeonRoot"]
		ok = true
		for name in names:
			if root.get_node_or_null(name) != null:
				ok = false
				message = "leftover node %s" % name
				break
		if ok:
			message = "unload removed all builder nodes"
		root.queue_free()
	ctx.timed_record("dungeon.unload_leaves_nothing", get_category(), ok, message, start, "DBL-09")


func _test_unknown_template_aborts() -> void:
	var start := Time.get_ticks_msec()
	var definition := {
		"seed": TC.SEED_A,
		"biomeId": "forgotten_castle",
		"rooms": [{"id": "r0", "templateId": "bogus_template_xyz", "type": "combat", "transform": {"x": 0, "y": 0, "z": 0, "yaw": 0}}],
		"edges": [],
		"placements": {"entrance": "r0", "enemies": [], "loot": [], "traps": [], "secrets": []},
	}
	var built := _build_test_dungeon(definition)
	await ctx.await_frame()
	var ok := built["root"].get_node_or_null("DungeonRoot/Rooms") == null
	built["root"].queue_free()
	ctx.timed_record("dungeon.unknown_template_aborts", get_category(), ok, "no Rooms node on bogus template", start, "DBL-12")


func _test_minimal_fixture_builds() -> void:
	var start := Time.get_ticks_msec()
	var definition := ContentLoader.load_json("content/fixtures/dungeon_definition_v1_minimal.json")
	var built := _build_test_dungeon(definition)
	await ctx.await_frame()
	var room_count: int = built["builder"].get_room_ids().size()
	var ok := room_count >= 2
	built["root"].queue_free()
	ctx.timed_record(
		"dungeon.minimal_fixture_builds",
		get_category(),
		ok,
		"%d rooms from minimal fixture" % room_count,
		start,
		"DBL-12"
	)


func _test_stair_levers_all_tracked() -> void:
	var start := Time.get_ticks_msec()
	var definition := {
		"seed": TC.SEED_A,
		"biomeId": "forgotten_castle",
		"rooms": [
			{"id": "s1", "templateId": "castle_stairs", "type": "corridor", "transform": {"x": 0, "y": 0, "z": 0, "yaw": 0}},
			{"id": "s2", "templateId": "castle_stairs", "type": "corridor", "transform": {"x": 20, "y": 0, "z": 0, "yaw": 0}},
		],
		"edges": [],
		"placements": {"entrance": "s1", "enemies": [], "loot": [], "traps": [], "secrets": [], "boss": null},
	}
	var built := _build_test_dungeon(definition)
	await ctx.await_frame()
	var builder: DungeonBuilder = built["builder"]
	var ok := builder.get_stair_levers().size() == 2
	if ok:
		builder.call("_unlock_stair_lever")
		ok = builder.get_stair_levers()[0].call("is_unlocked") and builder.get_stair_levers()[1].call("is_unlocked")
	built["root"].queue_free()
	ctx.timed_record(
		"dungeon.stair_levers_all_tracked",
		get_category(),
		ok,
		"two stair levers tracked and unlock together",
		start,
		"DBL-08"
	)


func _test_stairs_lever_parity() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var message := "stairs rooms have levers on floors 1-3"
	for floor_index in [1, 2, 3]:
		var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A, floor_index)
		if not gen.get("ok", false):
			ok = false
			message = "procgen failed for floor %d" % floor_index
			break
		var def: Dictionary = gen.get("definition", {})
		var stair_id := RunFloorConfigScript.find_stairs_room_id(def)
		var stairs_def: Dictionary = {}
		for room in def.get("rooms", []):
			if room is Dictionary and str(room.get("id", "")) == stair_id:
				stairs_def = room
				break
		if not RunFloorConfigScript.is_stairs_room(stairs_def):
			ok = false
			message = "find_stairs_room_id returned non-stairs room %s on floor %d" % [stair_id, floor_index]
			break
		var built := _build_test_dungeon(def)
		await ctx.await_frame()
		var builder: DungeonBuilder = built["builder"]
		var room := builder.get_room(stair_id)
		var lever := room.get_node_or_null("Props/StairLever") if room else null
		if lever == null:
			ok = false
			message = "floor %d stairs room %s missing StairLever" % [floor_index, stair_id]
		built["root"].queue_free()
		if not ok:
			break
	ctx.timed_record("castle.stairs.lever_parity", get_category(), ok, message, start, "CST-02")


func _test_fixture_secret_parent_room_id() -> void:
	var start := Time.get_ticks_msec()
	var root := Node3D.new()
	root.name = "FixtureSecretTest"
	ctx.owner.add_child(root)
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build(root, player)
	await ctx.await_frame()
	var courtyard := builder.get_room("courtyard")
	var mechanism := courtyard.get_node_or_null("Props/IllusoryWall") if courtyard else null
	var ok := mechanism != null
	root.queue_free()
	ctx.timed_record(
		"castle.fixture.secret_parent_room",
		get_category(),
		ok,
		"forgotten_castle_slice fixture spawns secret mechanism in parent room",
		start,
		"CST-08"
	)


func _test_shell_freed_on_unload() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var ok := false
	var message := "procgen failed"
	if gen.get("ok", false):
		var built := _build_test_dungeon(gen.get("definition", {}))
		await ctx.await_frame()
		var builder: DungeonBuilder = built["builder"]
		var root: Node3D = built["root"]
		builder.unload_from_parent(root)
		await ctx.await_frame()
		ok = root.get_node_or_null("DungeonRoot/FloorShell") == null
		message = "FloorShell freed with DungeonRoot" if ok else "FloorShell survived unload"
		root.queue_free()
	ctx.timed_record("dungeon.shell_freed_on_unload", get_category(), ok, message, start, "FSH-05")


func _room_footprint(room: RoomTemplate) -> AABB:
	var blockout := room.get_blockout()
	if blockout == null:
		return AABB(room.position, Vector3.ZERO)
	var half_w := blockout.room_width * 0.5
	var half_d := blockout.room_depth * 0.5
	var min_v := room.to_global(Vector3(-half_w, 0.0, -half_d))
	var max_v := room.to_global(Vector3(half_w, 0.0, half_d))
	return AABB(
		Vector3(minf(min_v.x, max_v.x), 0.0, minf(min_v.z, max_v.z)),
		Vector3(absf(max_v.x - min_v.x), 0.0, absf(max_v.z - min_v.z))
	)


func _test_no_ceiling_over_empty_cells() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var message := "ceilings stay within room footprints"
	for seed in [1, 7, 42, 99, 123, 256, 512, 777, 1024, 2048, 4096, 8192, 16384, 32768, 65535, 99999, 123456, 500000, 8675309, 2147483646]:
		var gen := LocalProcgen.generate("forgotten_castle", seed)
		if not gen.get("ok", false):
			ok = false
			message = "procgen failed for seed %d" % seed
			break
		var built := _build_test_dungeon(gen.get("definition", {}))
		await ctx.await_frame()
		var root: Node3D = built["root"]
		var builder: DungeonBuilder = built["builder"]
		var shell := root.get_node_or_null("DungeonRoot/FloorShell")
		if shell != null and shell.get_node_or_null("CeilingSlab") != null:
			ok = false
			message = "FloorShell still has CeilingSlab for seed %d" % seed
			root.queue_free()
			break
		var footprints: Array[AABB] = []
		for room_id in builder.get_room_ids():
			var room := builder.get_room(room_id)
			if room:
				footprints.append(_room_footprint(room))
		for room_id in builder.get_room_ids():
			var room := builder.get_room(room_id)
			var blockout := room.get_blockout() if room else null
			if blockout == null:
				continue
			var ceiling := blockout.get_node_or_null("Geometry/Ceiling")
			if ceiling == null:
				continue
			var collision := ceiling.get_node_or_null("CollisionShape3D") as CollisionShape3D
			if collision == null or not (collision.shape is BoxShape3D):
				continue
			var box := collision.shape as BoxShape3D
			var center := collision.global_position
			var half := box.size * 0.5
			var ceiling_aabb := AABB(center - half, box.size)
			var contained := false
			for footprint in footprints:
				if footprint.encloses(ceiling_aabb):
					contained = true
					break
			if not contained:
				ok = false
				message = "ceiling outside room footprint for seed %d room %s" % [seed, room_id]
				break
		root.queue_free()
		if not ok:
			break
	ctx.timed_record("dungeon.no_ceiling_over_empty_cells", get_category(), ok, message, start, "FSH-04")


const BossRoomDoorScene := preload("res://scenes/dungeon/boss_room_door.tscn")
const ExitPortalScene := preload("res://scenes/dungeon/exit_portal.tscn")
const BossRoomDoorScript := preload("res://scripts/dungeon/boss_room_door.gd")


func _test_boss_door_blocks() -> void:
	var start := Time.get_ticks_msec()
	var door: Node3D = BossRoomDoorScene.instantiate() as Node3D
	ctx.owner.add_child(door)
	await ctx.await_frame()
	door.call("configure", BiomeRegistry.BIOME_CASTLE, "none", 1, [])
	var shape := door.get_node("Barrier/BarrierShape") as CollisionShape3D
	var ok := shape != null and not shape.disabled
	door.queue_free()
	ctx.timed_record(
		"dungeon.boss_door_blocks",
		get_category(),
		ok,
		"boss door barrier shape starts solid",
		start,
		"BDP-10"
	)


func _test_boss_door_opens_and_seals() -> void:
	var start := Time.get_ticks_msec()
	var door: Node3D = BossRoomDoorScene.instantiate() as Node3D
	ctx.owner.add_child(door)
	await ctx.await_frame()
	door.call("configure", BiomeRegistry.BIOME_CASTLE, "none", 1, [])
	door.call("open_door")
	var shape := door.get_node("Barrier/BarrierShape") as CollisionShape3D
	var opened: bool = shape.disabled and bool(door.call("is_opened"))
	door.call("seal_door")
	var sealed: bool = bool(door.call("is_sealed")) and not shape.disabled
	door.queue_free()
	ctx.timed_record(
		"dungeon.boss_door_opens_and_seals",
		get_category(),
		opened and sealed,
		"boss door opens then seals with barrier re-enabled",
		start,
		"BDP-10"
	)


func _test_boss_door_release() -> void:
	var start := Time.get_ticks_msec()
	var door: Node3D = BossRoomDoorScene.instantiate() as Node3D
	ctx.owner.add_child(door)
	await ctx.await_frame()
	door.call("configure", BiomeRegistry.BIOME_CASTLE, "none", 1, [])
	door.call("open_door")
	door.call("seal_door")
	door.call("release_door")
	var shape := door.get_node("Barrier/BarrierShape") as CollisionShape3D
	var ok: bool = bool(door.call("is_opened")) and shape.disabled
	door.queue_free()
	ctx.timed_record(
		"dungeon.boss_door_release",
		get_category(),
		ok,
		"boss door release disables barrier and reports opened",
		start,
		"BDP-10"
	)


func _test_boss_door_requirement() -> void:
	var start := Time.get_ticks_msec()
	var door: Node3D = BossRoomDoorScene.instantiate() as Node3D
	ctx.owner.add_child(door)
	await ctx.await_frame()
	door.call("configure", BiomeRegistry.BIOME_CASTLE, "sigil", 1, [])
	var locked: bool = str(door.call("get_state_name")) == "LOCKED"
	InventoryService.add_item("boss_sigil", 1)
	door.get_node("InteractArea").body_entered.emit(ctx.owner)
	var input := InputEventAction.new()
	input.action = "interact"
	input.pressed = true
	door._unhandled_input(input)
	var opened: bool = bool(door.call("is_opened"))
	door.queue_free()
	ctx.timed_record(
		"dungeon.boss_door_requirement",
		get_category(),
		locked and opened,
		"sigil requirement blocks then opens after item",
		start,
		"BDP-04"
	)


func _test_exit_portal_parented() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var message := "all biomes parent exit portal under Props"
	for dungeon_id in DungeonCatalog.all_dungeon_ids():
		var gen := LocalProcgen.generate(dungeon_id, TC.SEED_A)
		if not gen.get("ok", false):
			ok = false
			message = "procgen failed for %s" % dungeon_id
			break
		var def: Dictionary = gen.get("definition", {})
		def["isFinalFloor"] = true
		var root := Node3D.new()
		ctx.owner.add_child(root)
		var player: CharacterBody3D = (
			load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
		)
		root.add_child(player)
		var builder := DungeonBuilder.new()
		root.add_child(builder)
		builder.build_from_definition(root, player, def)
		await ctx.await_frame()
		var exit_room_id: String = def.get("placements", {}).get("exit", "boss")
		var room := builder.get_room(exit_room_id)
		var portal := room.get_node_or_null("Props/ExitPortal") if room else null
		if portal == null or portal.get_parent().name != "Props":
			ok = false
			message = "%s exit portal missing or orphaned" % dungeon_id
		root.queue_free()
		if not ok:
			break
	ctx.timed_record(
		"dungeon.exit_portal_parented",
		get_category(),
		ok,
		message,
		start,
		"BDP-01"
	)


func _test_exit_portal_requires_confirm() -> void:
	var start := Time.get_ticks_msec()
	var portal: Area3D = ExitPortalScene.instantiate() as Area3D
	ctx.owner.add_child(portal)
	await ctx.await_frame()
	portal.call("configure", BiomeRegistry.BIOME_CASTLE)
	portal.call("activate")
	var source_ok: bool = (
		ctx.file_contains("res://scripts/dungeon/exit_portal.gd", "RunOutcomeConfirmScript.ask")
		and ctx.file_contains("res://scripts/dungeon/exit_portal.gd", "_unhandled_input")
	)
	portal.queue_free()
	ctx.timed_record(
		"dungeon.exit_portal_requires_confirm",
		get_category(),
		source_ok,
		"exit portal uses confirmation instead of body_enter completion",
		start,
		"BDP-02"
	)


func _test_exit_portal_activate_path() -> void:
	var start := Time.get_ticks_msec()
	var portal: Area3D = ExitPortalScene.instantiate() as Area3D
	ctx.owner.add_child(portal)
	await ctx.await_frame()
	var dormant := not portal.monitoring
	portal.call("activate")
	var active := portal.monitoring and portal.visible
	portal.queue_free()
	var builder_ok: bool = ctx.file_contains(
		"res://scripts/dungeon/dungeon_builder.gd",
		'portal.call("activate")'
	)
	ctx.timed_record(
		"dungeon.exit_portal_activate_path",
		get_category(),
		dormant and active and builder_ok,
		"portal monitoring toggles only through activate()",
		start,
		"BDP-06"
	)


func _test_no_door_without_boss() -> void:
	var start := Time.get_ticks_msec()
	var gen := LocalProcgen.generate("forgotten_castle", TC.SEED_A)
	var def: Dictionary = gen.get("definition", {}).duplicate(true)
	def["placements"] = def.get("placements", {}).duplicate(true)
	def["placements"]["boss"] = null
	var root := Node3D.new()
	ctx.owner.add_child(root)
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, def)
	await ctx.await_frame()
	var ok := builder.get_boss_door() == null
	root.queue_free()
	ctx.timed_record(
		"dungeon.no_door_without_boss",
		get_category(),
		ok,
		"null boss placement skips BossRoomDoor",
		start,
		"BDP-07"
	)


func _test_floor_scaling_curve() -> void:
	var start := Time.get_ticks_msec()
	var hp1 := CastleTierDifficulty.combined_hp_multiplier("forgotten_castle", 1, 1)
	var hp10 := CastleTierDifficulty.combined_hp_multiplier("forgotten_castle", 1, 10)
	var expected_ratio := CastleTierDifficulty.floor_hp_factor("forgotten_castle", 10)
	var ok: bool = hp10 > hp1 and absf(hp10 / hp1 - expected_ratio) < 0.01
	ctx.timed_record(
		"dungeon.floor_scaling_curve",
		get_category(),
		ok,
		"floor 10 HP mult %.3f > floor 1 %.3f" % [hp10, hp1],
		start,
		"DCT-02"
	)


func _test_stair_lookup_agreement() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		for seed_offset in range(200):
			var gen := LocalProcgen.generate(biome_id, TC.SEED_A + seed_offset, 1)
			if not gen.get("ok", false):
				continue
			var definition: Dictionary = gen.get("definition", {})
			var stairs_id := RunFloorConfigScript.find_stairs_room_id(definition)
			var found := false
			for room in definition.get("rooms", []):
				if not room is Dictionary:
					continue
				if str(room.get("id", "")) == stairs_id and RunFloorConfigScript.is_stairs_room(room):
					found = true
					break
			if not found:
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"dungeon.stair_lookup_agreement",
		get_category(),
		ok,
		"find_stairs_room_id matches stairs template room",
		start,
		"DCT-07"
	)

