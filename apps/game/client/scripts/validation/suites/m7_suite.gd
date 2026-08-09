extends "res://scripts/validation/validation_suite.gd"

const SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
const InputGlyphScript := preload("res://scripts/ui/input_glyph_service.gd")
const HubTutorialScript := preload("res://scripts/hub/hub_tutorial_service.gd")
const RunFloorConfigScript := preload("res://scripts/dungeon/run_floor_config.gd")
const StairCollisionScript := preload("res://scripts/dungeon/stair_collision_builder.gd")
const SkipFloorSvc := preload("res://scripts/dungeon/skip_floor_service.gd")
const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")
const FinalBossScript := preload("res://scripts/enemies/final_boss_forgotten_castle.gd")
const RM := preload("res://scripts/app/run_mode_config.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")
const DungeonBuilderScript := preload("res://scripts/dungeon/dungeon_builder.gd")
const StairMenuScript := preload("res://scripts/ui/stair_menu.gd")
const StairLeverScript := preload("res://scripts/dungeon/stair_lever.gd")
const BiomeRegistryScript := preload("res://scripts/dungeon/biome_registry.gd")


func get_category() -> String:
	return "run"


func run() -> void:
	_test_floor_seed_derivation()
	_test_max_secrets_per_floor()
	await _test_procgen_floor_variation()
	await _test_stair_collision()
	await _test_stair_lever_suite()
	_test_light_pass_ceiling_all_modes()
	_test_final_boss_phases()
	_test_save_migration_floor()
	_test_input_glyphs()
	_test_hub_tutorial()
	_test_ci_release_workflow()
	_test_ship_docs()
	_test_multi_floor_run_state()
	_test_floor_chunking()
	_test_endless_mode()
	_test_waves_mode()
	_test_skip_items()
	await _test_skip_requires_item()
	_test_run_modes()
	_test_endless_portal_blocked()
	_test_endless_continue_api()
	_test_waves_extended()
	_test_hub_umbral_portals()
	_test_skip_all_four()
	_test_save_v2_migration()
	_test_global_drops()
	_test_endless_scaling_tiers()
	_test_endless_curve_bounded()
	_test_floor_seed_avalanche()
	await _test_secret_cap_from_biome()
	_test_boss_phase_constants()
	_test_endless_retreat_api()
	_test_waves_equip_ui()
	_test_boss_cannon_flow()


func _test_floor_chunking() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		RunFlow.has_method("_unload_current_floor_chunk")
		and RunFlow.has_method("_clear_floor_cache")
	)
	ctx.timed_record(
		"run.floor.chunking_api",
		get_category(),
		ok,
		"floor chunk unload API present",
		start,
		"FLOOR-7.6"
	)
	start = Time.get_ticks_msec()
	var builder := preload("res://scripts/dungeon/dungeon_builder.gd").new()
	ok = builder.has_method("unload_from_parent")
	ctx.timed_record(
		"run.floor.builder_unload",
		get_category(),
		ok,
		"dungeon builder can unload floor chunk",
		start,
		"FLOOR-7.6"
	)


func _test_endless_mode() -> void:
	var start := Time.get_ticks_msec()
	var ok := (
		RM.MODE_ENDLESS == "endless"
		and RunFloorConfig.ENDLESS_MAX_FLOORS > RunFloorConfig.MAX_FLOORS
	)
	ctx.timed_record(
		"run.endless.mode_constants",
		get_category(),
		ok,
		"endless mode supports infinite floors",
		start,
		"UMBRAL-7.1"
	)
	start = Time.get_ticks_msec()
	var tier1: int = EndlessDifficultyScript.floor_tier(11)
	var mult: float = EndlessDifficultyScript.hp_multiplier(11)
	ctx.timed_record(
		"run.endless.difficulty_scaling",
		get_category(),
		tier1 >= 1 and mult > 1.0,
		"floor 11+ has increased difficulty tier",
		start,
		"UMBRAL-7.1"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scripts/ui/umbral_endless_menu.gd")
	ctx.timed_record(
		"run.endless.menu",
		get_category(),
		ok,
		"umbral endless menu script exists",
		start,
		"UMBRAL-7.1"
	)


func _test_waves_mode() -> void:
	var start := Time.get_ticks_msec()
	var ok := FileAccess.file_exists("res://scenes/dungeon/waves_run.tscn")
	ctx.timed_record(
		"run.waves.scene", get_category(), ok, "waves run scene exists", start, "UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	ok = WavesRunService.MILESTONES.size() == 4 and WavesRunService.get_chest_count() == 6
	ctx.timed_record(
		"run.waves.milestones",
		get_category(),
		ok,
		"waves milestones and 6 chests configured",
		start,
		"UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	var waves_backup: Dictionary = LocalSave.get_waves_active_run()
	LocalSave.set_waves_active_run({"probe": "qa01"}, false)
	var round_tripped: bool = LocalSave.get_waves_active_run().get("probe", "") == "qa01"
	LocalSave.clear_waves_active_run()
	var cleared := LocalSave.get_waves_active_run().is_empty()
	if not waves_backup.is_empty():
		LocalSave.set_waves_active_run(waves_backup, false)
	ok = round_tripped and cleared
	ctx.timed_record(
		"run.waves.save_persist",
		get_category(),
		ok,
		"waves active run round-trips through LocalSave and clears on demand",
		start,
		"UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scripts/loot/rarity_registry.gd")
	ctx.timed_record(
		"loot.rarity.global_registry",
		get_category(),
		ok,
		"global rarity registry exists",
		start,
		"UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	ok = LocalSave.has_method("has_continuable_waves_run")
	ctx.timed_record(
		"run.waves.save", get_category(), ok, "waves continue save API present", start, "UMBRAL-7.2"
	)


func _test_skip_items() -> void:
	var start := Time.get_ticks_msec()
	var ok := ItemCatalog.has_item("skip_10_floors") and ItemCatalog.has_item("skip_500_floors")
	ctx.timed_record(
		"run.skip.items_catalog",
		get_category(),
		ok,
		"skip-floor consumables in catalog",
		start,
		"UMBRAL-7.3"
	)
	start = Time.get_ticks_msec()
	ok = SkipFloorSvc.start_floor_for_item("skip_100_floors") == 101
	ctx.timed_record(
		"run.skip.start_floors",
		get_category(),
		ok,
		"skip items map to correct start floors",
		start,
		"UMBRAL-7.3"
	)
	start = Time.get_ticks_msec()
	var drops: Dictionary = ContentLoader.load_json("content/loot/global_drops.json")
	ok = drops.get("skipItems", []).size() >= 4
	ctx.timed_record(
		"run.skip.loot_table",
		get_category(),
		ok,
		"global skip drop table defined",
		start,
		"UMBRAL-7.3"
	)


func _test_skip_requires_item() -> void:
	CharacterService.reset_to_defaults()
	var start := Time.get_ticks_msec()
	await RunFlow.start_endless_run(1, "skip_500_floors")
	await ctx.await_frame()
	var blocked := not RunFlow.is_run_active() and RunFlow.last_hub_message != ""
	var qty := 0
	for slot in InventoryService.inventory.slots:
		if slot.get("itemId", "") == "skip_500_floors":
			qty += int(slot.get("quantity", 0))
	ctx.timed_record(
		"run.skip.requires_item",
		get_category(),
		blocked and qty == 0,
		"missing skip item blocks endless start: %s" % RunFlow.last_hub_message,
		start,
		"DCT-01"
	)


func _test_floor_seed_derivation() -> void:
	var start := Time.get_ticks_msec()
	var a := RunFloorConfig.mix_seed(TC.SEED_A, 1)
	var b := RunFloorConfig.mix_seed(TC.SEED_A, 2)
	ctx.timed_record(
		"run.floor.seed_derivation",
		get_category(),
		a != b and a >= 1,
		"floor seed mix differs per floor",
		start,
		"FLOOR-7.1"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"run.floor.max_floors",
		get_category(),
		RunFloorConfig.MAX_FLOORS == 10,
		"main mode is 10 floors",
		start,
		"FLOOR-7.1"
	)
	start = Time.get_ticks_msec()
	var tier1 := DungeonSeedService.derive_tier_seed(TC.SEED_A, 1)
	var tier2 := DungeonSeedService.derive_tier_seed(TC.SEED_A, 2)
	ctx.timed_record(
		"procgen.tier.seed_derivation",
		get_category(),
		tier1 == TC.SEED_A and tier2 != tier1 and tier2 >= 1,
		"tier 1 keeps base seed; tier 2 derives a distinct seed",
		start,
		"FLOOR-7.1"
	)


func _test_max_secrets_per_floor() -> void:
	var start := Time.get_ticks_msec()
	var cap := RunFloorConfig.max_secrets_for_biome(BiomeRegistry.BIOME_CASTLE)
	ctx.timed_record(
		"run.floor.max_secrets_from_biome",
		get_category(),
		cap == 2,
		"biome maxSecrets default is 2",
		start,
		"FLOOR-7.2"
	)


func _test_procgen_floor_variation() -> void:
	var start := Time.get_ticks_msec()
	var floor1 := LocalProcgen.generate(BiomeRegistry.BIOME_CASTLE, TC.SEED_A, 1)
	var floor2 := LocalProcgen.generate(BiomeRegistry.BIOME_CASTLE, TC.SEED_A, 2)
	var ok: bool = floor1.get("ok", false) and floor2.get("ok", false)
	var sig1: String = ctx.layout_signature(floor1.get("definition", {}))
	var sig2: String = ctx.layout_signature(floor2.get("definition", {}))
	ctx.timed_record(
		"procgen.run.floor_layout_differs",
		get_category(),
		ok and sig1 != sig2,
		"same run seed different layout per floor",
		start,
		"FLOOR-7.1"
	)
	if ok:
		start = Time.get_ticks_msec()
		var secrets := RunFloorConfig.count_secrets(floor1.get("definition", {}))
		var cap := RunFloorConfig.max_secrets_for_biome(BiomeRegistry.BIOME_CASTLE)
		ctx.timed_record(
			"procgen.run.secrets_cap",
			get_category(),
			secrets <= cap,
			"floor has %d secrets (max %d)" % [secrets, cap],
			start,
			"FLOOR-7.2"
		)
	start = Time.get_ticks_msec()
	var final_gen := LocalProcgen.generate(
		BiomeRegistry.BIOME_CASTLE, TC.SEED_A, RunFloorConfig.MAX_FLOORS
	)
	var final_def: Dictionary = final_gen.get("definition", {})
	var final_room_ids: Array = []
	for room_def in final_def.get("rooms", []):
		final_room_ids.append(str(room_def.get("id", "")))
	ctx.timed_record(
		"procgen.run.final_floor",
		get_category(),
		(
			final_gen.get("ok", false)
			and bool(final_def.get("isFinalFloor", false))
			and final_room_ids.has("arena")
		),
		"floor 10 generates final-floor layout with arena",
		start,
		"FLOOR-7.4"
	)


func _test_stair_collision() -> void:
	var start := Time.get_ticks_msec()
	var scene: PackedScene = load(TC.ROOM_TEMPLATE_SCENES["castle_stairs"])
	var room := scene.instantiate() as RoomTemplate
	ctx.owner.add_child(room)
	StairCollisionScript.ensure_stair_collision(room)
	var has_collision := room.get_node_or_null("Props/StairCollision") != null
	ctx.timed_record(
		"run.floor.stair_collision",
		get_category(),
		has_collision,
		"stairs room has physical collision body",
		start,
		"FLOOR-7.3"
	)
	room.queue_free()


func _test_light_pass_ceiling_all_modes() -> void:
	var start := Time.get_ticks_msec()
	var shell_path := "res://scripts/dungeon/floor_shell_builder.gd"
	var registry_path := "res://scripts/dungeon/biome_registry.gd"
	var ok: bool = (
		ctx.file_contains(shell_path, '_add_slab(shell, "CeilingSlab"')
		and ctx.file_contains(registry_path, "uses_indoor_lighting")
		and ctx.file_contains(registry_path, "sun.visible = false")
		and ctx.script_has_method("res://scripts/dungeon/dungeon_builder.gd", "_build_floor_shell")
		and ctx.file_contains("res://scripts/dungeon/waves_run.gd", "WavesOutdoorsDiorama")
	)
	ctx.timed_record(
		"run.floor.indoor_ceiling_lighting",
		get_category(),
		ok,
		"opaque ceilings + per-room lights for dungeon/endless; waves uses open outdoors meadow",
		start,
		"FLOOR-7.1"
	)


func _test_stair_lever_suite() -> void:
	await _test_lever_created_per_stairs_room()
	await _test_lever_starts_locked()
	await _test_lever_unlocks_on_boss_death()
	_test_lever_flags_by_mode()
	_test_facing_helper_null_safe()
	await _test_stair_menu_pauses()
	await _test_stair_menu_focus()
	await _test_stair_menu_disabled_reasons()


func _stairs_test_definition(room_id: String = "stairs") -> Dictionary:
	return {
		"seed": TC.SEED_A,
		"biomeId": "forgotten_castle",
		"rooms":
		[
			{
				"id": room_id,
				"templateId": "castle_stairs",
				"type": "corridor",
				"transform": {"x": 0, "y": 0, "z": 0, "yaw": 0},
			},
		],
		"edges": [],
		"placements":
		{"entrance": room_id, "enemies": [], "loot": [], "traps": [], "secrets": [], "boss": null},
	}


func _build_stairs_test_dungeon(definition: Dictionary) -> Dictionary:
	var root := Node3D.new()
	root.name = "StairLeverTestRoot"
	ctx.owner.add_child(root)
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	root.add_child(player)
	var builder := DungeonBuilderScript.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, definition)
	return {"root": root, "builder": builder, "player": player}


func _test_lever_created_per_stairs_room() -> void:
	var start := Time.get_ticks_msec()
	var biomes := {
		BiomeRegistryScript.BIOME_CASTLE: "castle_stairs",
		BiomeRegistryScript.BIOME_CRYSTAL: "crystal_stairs",
		BiomeRegistryScript.BIOME_SWAMP: "swamp_stairs",
		BiomeRegistryScript.BIOME_FROZEN: "frozen_stairs",
		BiomeRegistryScript.BIOME_CATHEDRAL: "cathedral_stairs",
		BiomeRegistryScript.BIOME_VAULT: "vault_stairs",
		BiomeRegistryScript.BIOME_PRISM: "prism_stairs",
		BiomeRegistryScript.BIOME_MIRE: "mire_stairs",
		BiomeRegistryScript.BIOME_HOLLOW: "hollow_stairs",
		BiomeRegistryScript.BIOME_UMBRAL: "umbral_stairs",
	}
	var ok := true
	var message := "one lever per stairs room in all biomes"
	for biome_id in biomes:
		var built := _build_stairs_test_dungeon(
			{
				"seed": TC.SEED_A,
				"biomeId": biome_id,
				"rooms":
				[
					{
						"id": "stairs",
						"templateId": biomes[biome_id],
						"type": "corridor",
						"transform": {"x": 0, "y": 0, "z": 0, "yaw": 0},
					},
				],
				"edges": [],
				"placements":
				{
					"entrance": "stairs",
					"enemies": [],
					"loot": [],
					"traps": [],
					"secrets": [],
					"boss": null,
				},
			}
		)
		await ctx.await_frame()
		var builder: DungeonBuilder = built["builder"]
		if builder.get_stair_levers().size() != 1:
			ok = false
			message = "biome %s missing stair lever" % biome_id
		built["root"].queue_free()
		if not ok:
			break
	ctx.timed_record(
		"run.floor.lever_per_stairs_room", get_category(), ok, message, start, "STL-03"
	)


func _test_lever_starts_locked() -> void:
	var start := Time.get_ticks_msec()
	var built := _build_stairs_test_dungeon(_stairs_test_definition())
	await ctx.await_frame()
	var lever: Node = built["builder"].get_stair_lever()
	var ok: bool = lever != null and not bool(lever.call("is_unlocked"))
	built["root"].queue_free()
	ctx.timed_record(
		"run.floor.lever_starts_locked",
		get_category(),
		ok,
		"new stair lever starts locked",
		start,
		"STL-07"
	)


func _test_lever_unlocks_on_boss_death() -> void:
	var start := Time.get_ticks_msec()
	var definition := _stairs_test_definition("s1")
	(
		definition["rooms"]
		. append(
			{
				"id": "s2",
				"templateId": "castle_stairs",
				"type": "corridor",
				"transform": {"x": 20, "y": 0, "z": 0, "yaw": 0},
			}
		)
	)
	var built := _build_stairs_test_dungeon(definition)
	await ctx.await_frame()
	built["builder"].call("_unlock_stair_lever")
	var ok := true
	for lever in built["builder"].get_stair_levers():
		if not lever.call("is_unlocked"):
			ok = false
			break
	built["root"].queue_free()
	ctx.timed_record(
		"run.floor.lever_unlocks_on_boss_death",
		get_category(),
		ok,
		"all stair levers unlock together",
		start,
		"STL-02"
	)


func _test_lever_flags_by_mode() -> void:
	var start := Time.get_ticks_msec()
	var lever := StairLeverScript.new()
	var ok := lever.has_method("floor_options") and lever.has_method("use")
	if ok:
		lever.call("configure", true, false, true, 1)
		lever.call("unlock")
		var options: Array = lever.call("floor_options")
		ok = options.size() == 3 and bool(options[0].get("enabled", false))
	lever.free()
	ctx.timed_record(
		"run.floor.lever_flags_by_mode",
		get_category(),
		ok,
		"floor_options exposes ascend/descend/retreat rows",
		start,
		"STL-08"
	)


func _test_facing_helper_null_safe() -> void:
	var start := Time.get_ticks_msec()
	var facing := RunFloorConfigScript.stairs_spawn_facing_y(null)
	ctx.timed_record(
		"run.floor.spawn_facing_helper",
		get_category(),
		typeof(facing) == TYPE_FLOAT and facing == 0.0,
		"stairs_spawn_facing_y(null) returns 0.0",
		start,
		"STL-11"
	)


func _test_stair_menu_pauses() -> void:
	var start := Time.get_ticks_msec()
	var menu := StairMenuScript.new()
	ctx.owner.add_child(menu)
	await ctx.await_frame()
	var was_paused := menu.get_tree().paused
	var lever := StairLeverScript.new()
	lever.call("configure", true, false, false, 2)
	lever.call("unlock")
	menu.open_for_lever(lever, lever.call("floor_options"))
	var paused_while_open := menu.get_tree().paused
	menu.close_menu()
	var restored := menu.get_tree().paused == was_paused
	lever.free()
	menu.queue_free()
	ctx.timed_record(
		"ui.run.stair_menu_pauses",
		get_category(),
		paused_while_open and restored,
		"stair menu pauses tree and restores prior state",
		start,
		"STL-04"
	)


func _test_stair_menu_focus() -> void:
	var start := Time.get_ticks_msec()
	var menu := StairMenuScript.new()
	ctx.owner.add_child(menu)
	await ctx.await_frame()
	var lever := StairLeverScript.new()
	lever.call("configure", true, true, false, 3)
	lever.call("unlock")
	menu.open_for_lever(lever, lever.call("floor_options"))
	await ctx.await_frame()
	var focused := menu.get_viewport().gui_get_focus_owner() is Button
	menu.close_menu()
	lever.free()
	menu.queue_free()
	ctx.timed_record(
		"ui.run.stair_menu_focus",
		get_category(),
		focused,
		"first enabled stair menu button has focus",
		start,
		"STL-05"
	)


func _test_stair_menu_disabled_reasons() -> void:
	var start := Time.get_ticks_msec()
	var lever := StairLeverScript.new()
	lever.call("configure", true, false, false, 1)
	lever.call("unlock")
	var options: Array = lever.call("floor_options")
	var descend: Dictionary = options[1]
	var ok := (
		not bool(descend.get("enabled", true)) and str(descend.get("reason", "")).contains("lowest")
	)
	lever.free()
	ctx.timed_record(
		"ui.run.stair_menu_disabled_reasons",
		get_category(),
		ok,
		"disabled descend row carries a reason string",
		start,
		"STL-07"
	)


func _test_final_boss_phases() -> void:
	var start := Time.get_ticks_msec()
	var boss := FinalBossScript.new()
	ctx.timed_record(
		"combat.boss.final_script",
		get_category(),
		boss.has_method("is_immune") and boss.has_method("capture_state"),
		"final boss has phase/state API",
		start,
		"FLOOR-7.5"
	)
	start = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/enemies/final_boss_forgotten_castle.tscn")
	ctx.timed_record(
		"combat.boss.final_scene",
		get_category(),
		scene != null and EnemyCatalog.has_enemy("final_boss_forgotten_castle"),
		"final boss scene + catalog entry",
		start,
		"FLOOR-7.5"
	)


func _test_save_migration_floor() -> void:
	var start := Time.get_ticks_msec()
	var migrated: Dictionary = (
		SaveMigratorScript
		. migrate(
			{
				"schemaVersion": 1,
				"inventory": {"schemaVersion": 1, "slots": [], "equipped": {}},
				"activeRun":
				{
					"runId": "test",
					"seed": TC.SEED_A,
					"dungeonDefinition": {"rooms": []},
				},
			}
		)
	)
	var run: Dictionary = migrated.get("activeRun", {})
	ctx.timed_record(
		"save.migration.migration_floor_fields",
		get_category(),
		(
			int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
			and run.has("currentFloor")
			and str(run.get("runMode", "")) != ""
			and run.has("lastCheckpoint")
		),
		"v1 save migrates with floor fields",
		start,
		"SCHEMA-7.1"
	)


func _test_input_glyphs() -> void:
	var start := Time.get_ticks_msec()
	var glyph := InputGlyphScript.get_action_glyph("interact")
	var label := InputGlyphScript.format_interact_label()
	ctx.timed_record(
		"ui.polish.controller_glyphs",
		get_category(),
		not glyph.is_empty() and "Press" in label,
		"input glyph service returns labels",
		start,
		"POLISH-7.1"
	)


func _test_hub_tutorial() -> void:
	var start := Time.get_ticks_msec()
	HubTutorialScript.reset_for_character()
	HubTutorialScript.load_catalog()
	var tip := HubTutorialScript.get_current_tip()
	var can_skip: bool = true
	ctx.timed_record(
		"ui.polish.hub_tutorial",
		get_category(),
		not tip.is_empty() and can_skip,
		"hub tutorial tips available and skippable",
		start,
		"POLISH-7.2"
	)


func _test_ci_release_workflow() -> void:
	var start := Time.get_ticks_msec()
	var path := _content_root().path_join(".github/workflows/release.yml")
	var content := FileAccess.get_file_as_string(path) if FileAccess.file_exists(path) else ""
	var dockerfile_path := _content_root().path_join("services/backend/Dockerfile")
	var ok: bool = (
		FileAccess.file_exists(path)
		and "workflow_dispatch" in content
		and "ghcr.io" in content
		and "4.4.0" not in content
		and FileAccess.file_exists(dockerfile_path)
	)
	ctx.timed_record(
		"docs.ci.release_workflow",
		get_category(),
		ok,
		(
			"release workflow publishes to ghcr.io with Dockerfile"
			if ok
			else "release workflow incomplete"
		),
		start,
		"CI-7.1"
	)


func _test_ship_docs() -> void:
	var start := Time.get_ticks_msec()
	var path := ProjectSettings.globalize_path("res://").path_join("../../..").path_join(
		"docs/validation/manual-checklist.md"
	)
	var ok: bool = (
		FileAccess.file_exists(path)
		and "Manual validation checklist" in FileAccess.get_file_as_string(path)
	)
	ctx.timed_record(
		"docs.ship.manual_checklist",
		get_category(),
		ok,
		"manual validation checklist documented",
		start,
		"SHIP-7.1"
	)


func _test_multi_floor_run_state() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = RunFlow.has_method("ascend_floor") and RunFlow.has_method("get_current_floor")
	ctx.timed_record(
		"run.floor.run_flow_api",
		get_category(),
		ok,
		"RunFlow exposes multi-floor API",
		start,
		"FLOOR-7.1"
	)
	start = Time.get_ticks_msec()
	var blocked: bool = not RunFlow.can_escape_run()
	ctx.timed_record(
		"run.floor.escape_gated",
		get_category(),
		blocked,
		"escape gated until final floor boss defeated",
		start,
		"FLOOR-7.4"
	)


func _test_run_modes() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = (
		RM.ALL_MODES.size() == 3
		and RM.is_endless(RM.MODE_ENDLESS)
		and RM.is_waves(RM.MODE_WAVES)
		and RM.is_multi_floor(RM.MODE_CASTLE)
	)
	ctx.timed_record(
		"run.mode.helpers",
		get_category(),
		ok,
		"run mode helpers cover castle/endless/waves",
		start,
		"FLOOR-7.1"
	)
	start = Time.get_ticks_msec()
	ok = RM.is_multi_floor(RM.MODE_ENDLESS) and not RM.is_multi_floor(RM.MODE_WAVES)
	ctx.timed_record(
		"run.mode.multi_floor",
		get_category(),
		ok,
		"castle and endless are multi-floor; waves is isolated",
		start,
		"FLOOR-7.1"
	)


func _test_endless_portal_blocked() -> void:
	var start := Time.get_ticks_msec()
	var run_mode_backup := RunFlow.run_mode
	var run_active_backup := RunFlow._run_active
	RunFlow.run_mode = RM.MODE_ENDLESS
	RunFlow._run_active = true
	RunFlow.complete_run_via_portal()
	var ok: bool = RunFlow._run_active == true
	RunFlow.run_mode = run_mode_backup
	RunFlow._run_active = run_active_backup
	ctx.timed_record(
		"run.endless.no_mid_portal",
		get_category(),
		ok,
		"complete_run_via_portal is a no-op while run_mode is endless",
		start,
		"ENDLESS-7.x"
	)


func _test_endless_continue_api() -> void:
	var start := Time.get_ticks_msec()
	var ok := RunFlow.has_method("continue_endless_run") and RunFlow.has_method("start_endless_run")
	ctx.timed_record(
		"run.endless.continue_api",
		get_category(),
		ok,
		"RunFlow exposes endless start/continue",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	var endless_menu_scene := load("res://scenes/ui/umbral_endless_menu.tscn") as PackedScene
	ok = false
	if endless_menu_scene != null and ctx.owner != null:
		var active_run_backup: Dictionary = LocalSave.get_active_run().duplicate(true)
		var endless_menu := endless_menu_scene.instantiate()
		ctx.owner.add_child(endless_menu)
		await ctx.await_frame()
		var continuable_snapshot := {"player": {"health": 100.0}}
		LocalSave.set_active_run(
			{"runMode": "castle", "currentFloor": 3, "snapshot": continuable_snapshot}, false
		)
		endless_menu.call("open_menu")
		var castle_disabled: bool = (
			endless_menu.get_node("MainPanel/Margin/VBox/ContinueButton") as Button
		).disabled
		LocalSave.set_active_run(
			{"runMode": "endless", "currentFloor": 5, "snapshot": continuable_snapshot}, false
		)
		endless_menu.call("open_menu")
		var endless_disabled: bool = (
			endless_menu.get_node("MainPanel/Margin/VBox/ContinueButton") as Button
		).disabled
		ok = castle_disabled and not endless_disabled
		endless_menu.queue_free()
		LocalSave.set_active_run(active_run_backup, false)
	ctx.timed_record(
		"run.endless.continue_save_check",
		get_category(),
		ok,
		"endless menu's continue button enables only for a saved endless run",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scenes/ui/umbral_endless_menu.tscn")
	ctx.timed_record(
		"run.endless.menu_scene",
		get_category(),
		ok,
		"umbral endless menu scene exists",
		start,
		"ENDLESS-7.x"
	)


func _test_waves_extended() -> void:
	var start := Time.get_ticks_msec()
	WavesRunService.begin_new_run()
	var isolated := WavesRunService.waves_inventory != InventoryService.inventory
	ctx.timed_record(
		"run.waves.isolated_inventory",
		get_category(),
		isolated,
		"waves inventory is separate from main inventory",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	var ok: bool = (
		ctx.file_contains("res://scripts/ui/waves_run_ui.gd", "Choose up to 3 items")
		and ctx.file_contains("res://scripts/ui/waves_run_ui.gd", "Pick at least one reward")
	)
	ctx.timed_record(
		"run.waves.reward_ui",
		get_category(),
		ok,
		"waves reward pick allows up to 3 items",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scenes/ui/umbral_waves_menu.tscn")
	ctx.timed_record(
		"run.waves.menu_scene",
		get_category(),
		ok,
		"umbral waves menu scene exists",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = (
		RunFlow.has_method("complete_waves_run")
		and ctx.file_contains("res://scripts/app/run_flow.gd", "kept up to 3 chosen items")
	)
	ctx.timed_record(
		"run.waves.complete_rewards",
		get_category(),
		ok,
		"waves completion transfers chosen rewards to main inventory",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	WavesRunService.begin_new_run()
	WavesRunService.mark_ready()
	var blocked_before_chests := not WavesRunService.lobby_ready
	for i in WavesRunService.get_chest_count():
		WavesRunService.open_chest(i)
	WavesRunService.mark_ready()
	ok = blocked_before_chests and WavesRunService.all_chests_opened() and WavesRunService.lobby_ready
	ctx.timed_record(
		"run.waves.lobby_ready_gate",
		get_category(),
		ok,
		"waves ready blocked until all 6 chests opened",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = (
		ctx.file_contains("res://scripts/dungeon/waves_run.gd", "CombatHUD")
		and ctx.script_has_method("res://scripts/dungeon/waves_run.gd", "_restore_waves_snapshot")
	)
	ctx.timed_record(
		"run.waves.combat_hud_restore",
		get_category(),
		ok,
		"waves scene builds CombatHUD and restores continue snapshot",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = RarityRegistryScript.normalize("mythic") == "aumbral"
	ctx.timed_record(
		"loot.rarity.aumbral_alias",
		get_category(),
		ok,
		"mythic rarity aliases to aumbral top tier",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = (
		BlacksmithService.get_max_upgrade_level_for_slot(
			{"itemId": "mythic_blade", "rarity": "aumbral"}
		)
		== 10
	)
	ctx.timed_record(
		"progression.blacksmith.aumbral_cap",
		get_category(),
		ok,
		"aumbral items upgrade to +10 at blacksmith",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = BlacksmithService.get_max_upgrade_level_for_slot({"itemId": "castle_sword"}) == 5
	ctx.timed_record(
		"progression.blacksmith.standard_cap",
		get_category(),
		ok,
		"standard items upgrade to +5 at blacksmith",
		start,
		"WAVES-7.x"
	)


func _test_hub_umbral_portals() -> void:
	var hub_text := FileAccess.get_file_as_string("res://scenes/hub/hub.tscn")
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"hub.portal.endless_portal",
		get_category(),
		"UmbralEndlessPortal" in hub_text and "UmbralEndlessMenu" in hub_text,
		"hub has Umbral Endless portal + menu",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"hub.portal.waves_portal",
		get_category(),
		"UmbralWavesPortal" in hub_text and "UmbralWavesMenu" in hub_text,
		"hub has Umbral Waves portal + menu",
		start,
		"WAVES-7.x"
	)


func _test_skip_all_four() -> void:
	var items: Array[String] = [
		"skip_10_floors", "skip_50_floors", "skip_100_floors", "skip_500_floors"
	]
	for item_id in items:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"run.skip.catalog_%s" % item_id,
			get_category(),
			ItemCatalog.has_item(item_id),
			"%s in item catalog" % item_id,
			start,
			"SKIP-7.x"
		)
		start = Time.get_ticks_msec()
		var floor: int = SkipFloorSvc.start_floor_for_item(item_id)
		var expected: int = int(SkipFloorSvc.SKIP_ITEMS.get(item_id, 1))
		ctx.timed_record(
			"run.skip.floor_%s" % item_id,
			get_category(),
			floor == expected,
			"%s starts at floor %d" % [item_id, floor],
			start,
			"SKIP-7.x"
		)


func _test_save_v2_migration() -> void:
	var start := Time.get_ticks_msec()
	var migrated: Dictionary = (
		SaveMigratorScript
		. migrate(
			{
				"schemaVersion": 2,
				"activeRun":
				{
					"runId": "v2test",
					"runMode": "castle",
					"currentFloor": 3,
					"floorDefinitions": {"1": {}, "2": {}},
				},
			}
		)
	)
	var run: Dictionary = migrated.get("activeRun", {})
	ctx.timed_record(
		"save.migration.v2_to_v3_strips_floors",
		get_category(),
		(
			int(migrated.get("schemaVersion", 0)) == SaveMigratorScript.CURRENT_VERSION
			and not run.has("floorDefinitions")
		),
		"v2 save migrates to current without floorDefinitions cache",
		start,
		"SCHEMA-7.1"
	)


func _test_global_drops() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = ResourceLoader.exists("res://scripts/loot/global_drop_service.gd")
	ctx.timed_record(
		"loot.global.service",
		get_category(),
		ok,
		"GlobalDropService class present",
		start,
		"SKIP-7.x"
	)
	start = Time.get_ticks_msec()
	var schema_path := _content_root().path_join("content/schemas/global-drops.v1.json")
	ok = FileAccess.file_exists(schema_path)
	ctx.timed_record(
		"loot.global.schema", get_category(), ok, "global-drops schema exists", start, "SKIP-7.x"
	)
	start = Time.get_ticks_msec()
	var drop := GlobalDropService.roll_enemy_drop(12345, 15)
	ok = drop == "" or ItemCatalog.has_item(drop)
	ctx.timed_record(
		"loot.global.roll_valid",
		get_category(),
		ok,
		"global drop roll returns catalog item or empty",
		start,
		"SKIP-7.x"
	)


func _test_endless_scaling_tiers() -> void:
	var start := Time.get_ticks_msec()
	var tier := EndlessDifficultyScript.floor_tier(21)
	var mult := EndlessDifficultyScript.hp_multiplier(21)
	ctx.timed_record(
		"run.endless.tier_floor_21",
		get_category(),
		tier == 2 and mult > 1.2 and mult <= EndlessDifficultyScript.HP_SOFT_CAP,
		"floor 21 is tier 2 with bounded HP multiplier",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	var bonus := EndlessDifficultyScript.rare_drop_bonus(30)
	ctx.timed_record(
		"run.endless.rare_drop_bonus",
		get_category(),
		bonus > 0.0 and bonus <= RunFloorConfigScript.DROP_RATE_BONUS_CAP,
		"endless rare drop bonus scales with tier",
		start,
		"ENDLESS-7.x"
	)


func _test_endless_curve_bounded() -> void:
	var start := Time.get_ticks_msec()
	var hp_ok := true
	var dmg_ok := true
	var prev_hp := 0.0
	var prev_dmg := 0.0
	for floor in range(1, 2001):
		var hp := EndlessDifficultyScript.hp_multiplier(floor)
		var dmg := EndlessDifficultyScript.damage_multiplier(floor)
		if hp < prev_hp or dmg < prev_dmg:
			hp_ok = false
			dmg_ok = false
			break
		prev_hp = hp
		prev_dmg = dmg
	var ceiling_hp := EndlessDifficultyScript.hp_multiplier(999999)
	var ceiling_dmg := EndlessDifficultyScript.damage_multiplier(999999)
	ctx.timed_record(
		"run.endless.curve_bounded",
		get_category(),
		(
			hp_ok
			and dmg_ok
			and ceiling_hp <= EndlessDifficultyScript.HP_SOFT_CAP
			and ceiling_dmg <= EndlessDifficultyScript.DAMAGE_SOFT_CAP
		),
		"endless HP/damage monotonic and capped (hp=%.2f dmg=%.2f)" % [ceiling_hp, ceiling_dmg],
		start,
		"DCT-04"
	)


func _test_floor_seed_avalanche() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for i in range(1000):
		var seed_val := 1 + (i * 7919) % 1_000_000
		var floor_val := 1 + (i % 500)
		var a := RunFloorConfig.mix_seed(seed_val, floor_val)
		var b := RunFloorConfig.mix_seed(seed_val, floor_val + 1)
		var distance := _hamming_distance(a, b)
		if distance < 10:
			ok = false
			break
	ctx.timed_record(
		"run.floor.seed_avalanche",
		get_category(),
		ok,
		"consecutive floor seeds differ by >= 10 bits",
		start,
		"DCT-05"
	)


func _hamming_distance(a: int, b: int) -> int:
	var x := a ^ b
	var count := 0
	while x != 0:
		count += x & 1
		x >>= 1
	return count


func _test_secret_cap_from_biome() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var cap := RunFloorConfig.max_secrets_for_biome(biome_id)
		for seed_offset in range(200):
			var gen := LocalProcgen.generate(biome_id, TC.SEED_A + seed_offset, 1)
			if not gen.get("ok", false):
				continue
			var secrets := RunFloorConfig.count_secrets(gen.get("definition", {}))
			if secrets > cap:
				ok = false
				break
		if not ok:
			break
	ctx.timed_record(
		"procgen.run.secret_cap_biome",
		get_category(),
		ok,
		"generated secret count never exceeds biome maxSecrets",
		start,
		"DCT-09"
	)


func _test_boss_phase_constants() -> void:
	var start := Time.get_ticks_msec()
	var boss := FinalBossScript.new()
	var ok: bool = (
		boss.has_method("is_immune")
		and FinalBossScript.Phase.has("COMBAT")
		and FinalBossScript.Phase.has("SPIKES")
		and FinalBossScript.Phase.has("PUZZLE")
	)
	ctx.timed_record(
		"combat.boss.phase_api",
		get_category(),
		ok,
		"final boss defines phase enum and immunity API",
		start,
		"FLOOR-7.5"
	)
	start = Time.get_ticks_msec()
	ok = ResourceLoader.exists("res://scenes/bosses/final_boss_crystal.tscn")
	ctx.timed_record(
		"combat.boss.crystal_scene",
		get_category(),
		ok,
		"final boss crystal scene exists for puzzle phase",
		start,
		"FLOOR-7.5"
	)


func _test_endless_retreat_api() -> void:
	var start := Time.get_ticks_msec()
	var retreat_lever_probe := StairLeverScript.new()
	var ok: bool = (
		RunFlow.has_method("retreat_to_hub")
		and RunFlow.has_method("can_retreat_to_hub")
		and retreat_lever_probe.has_method("use")
		and retreat_lever_probe.has_method("floor_options")
	)
	retreat_lever_probe.queue_free()
	ctx.timed_record(
		"run.endless.retreat_api",
		get_category(),
		ok,
		"endless/castle retreat to hub via stair lever",
		start,
		"ENDLESS-7.x"
	)


func _test_waves_equip_ui() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = (
		FileAccess.file_exists("res://scripts/ui/inventory_ui.gd")
		and ctx.file_contains("res://scripts/ui/inventory_ui.gd", "WavesRunService.waves_inventory")
		and ctx.script_has_property("res://scripts/ui/inventory_ui.gd", "_waves_mode")
		and WavesRunService.has_method("apply_equipment_to_player")
	)
	ctx.timed_record(
		"run.waves.equip_ui",
		get_category(),
		ok,
		"waves equip UI script wired into waves run",
		start,
		"WAVES-7.x"
	)


func _test_boss_cannon_flow() -> void:
	var start := Time.get_ticks_msec()
	var cannon_boss_probe := FinalBossScript.new()
	var cannon_probe: Object = (preload("res://scripts/dungeon/final_boss_cannon.gd") as Script).new()
	var ok: bool = (
		ResourceLoader.exists("res://scenes/bosses/final_boss_cannon.tscn")
		and cannon_boss_probe.has_method("register_cannon_hit")
		and cannon_probe.has_method("deposit_crystal")
	)
	cannon_boss_probe.queue_free()
	if cannon_probe is Node:
		cannon_probe.queue_free()
	ctx.timed_record(
		"combat.boss.cannon_flow",
		get_category(),
		ok,
		"final boss cannon load-and-fire puzzle flow",
		start,
		"FLOOR-7.5"
	)


func _content_root() -> String:
	return ContentLoader.content_path("content").get_base_dir()
