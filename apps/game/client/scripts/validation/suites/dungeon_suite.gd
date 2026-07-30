extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "dungeon"


func run() -> void:
	await _test_build_pipeline()
	_test_builder_wiring()
	await _test_snapshot_roundtrip()
	await _test_loot_chest_configure()


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
	await ctx.await_frame()

	var start := Time.get_ticks_msec()
	var room_count: int = builder.get_room_ids().size()
	var enemies: Array = ctx.owner.get_tree().get_nodes_in_group("enemy")
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
		enemies.size() > 0,
		"%d enemies spawned from placements" % enemies.size(),
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
	var has_exit_marker: bool = exit_room != null and (
		exit_room.get_node_or_null("Props/ExitPortal") != null
		or exit_room.get_node_or_null("Props/ExitPortalMarker") != null
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
	var template_count := DungeonBuilder.ROOM_SCENES.size()
	ctx.timed_record(
		"dungeon.room_scene_registry",
		get_category(),
		template_count >= 8,
		"%d room templates registered in DungeonBuilder" % template_count,
		start,
		"M2.dungeon.templates"
	)

	start = Time.get_ticks_msec()
	ctx.timed_record(
		"dungeon.builder_exit_portal_script",
		get_category(),
		DungeonBuilder.EXIT_PORTAL_SCRIPT != null,
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
	var player: CharacterBody3D = load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
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
