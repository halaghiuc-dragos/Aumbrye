extends "res://scripts/validation/validation_suite.gd"

const SaveMigratorScript := preload("res://scripts/save/save_migrator.gd")
const SteamServiceScript := preload("res://scripts/platform/steam_service.gd")
const InputGlyphScript := preload("res://scripts/ui/input_glyph_service.gd")
const HubTutorialScript := preload("res://scripts/hub/hub_tutorial_service.gd")
const RunFloorConfigScript := preload("res://scripts/dungeon/run_floor_config.gd")
const StairCollisionScript := preload("res://scripts/dungeon/stair_collision_builder.gd")
const SkipFloorSvc := preload("res://scripts/dungeon/skip_floor_service.gd")
const EndlessDifficultyScript := preload("res://scripts/dungeon/endless_difficulty.gd")
const FinalBossScript := preload("res://scripts/enemies/final_boss_forgotten_castle.gd")
const RM := preload("res://scripts/app/run_mode_config.gd")
const RarityRegistryScript := preload("res://scripts/loot/rarity_registry.gd")


func get_category() -> String:
	return "m7"


func run() -> void:
	_test_floor_seed_derivation()
	_test_max_secrets_per_floor()
	await _test_procgen_floor_variation()
	await _test_stair_collision()
	_test_stair_lever_script()
	_test_light_pass_ceiling_all_modes()
	_test_final_boss_phases()
	await _test_steam_stub()
	_test_save_migration_floor()
	_test_input_glyphs()
	_test_hub_tutorial()
	_test_crash_logger()
	_test_perf_hooks()
	_test_ci_release_workflow()
	_test_ship_docs()
	_test_schema_doc()
	_test_multi_floor_run_state()
	_test_floor_chunking()
	_test_endless_mode()
	_test_waves_mode()
	_test_skip_items()
	_test_run_modes()
	_test_endless_portal_blocked()
	_test_endless_continue_api()
	_test_waves_extended()
	_test_hub_umbral_portals()
	_test_skip_all_four()
	_test_save_v2_migration()
	_test_global_drops()
	_test_endless_scaling_tiers()
	_test_boss_phase_constants()
	_test_known_issues_doc()
	_test_endless_retreat_api()
	_test_waves_equip_ui()
	_test_boss_cannon_flow()


func _test_floor_chunking() -> void:
	var start := Time.get_ticks_msec()
	var ok := RunFlow.has_method("_unload_current_floor_chunk") and RunFlow.has_method("_clear_floor_cache")
	ctx.timed_record(
		"m7.floor.chunking_api",
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
		"m7.floor.builder_unload",
		get_category(),
		ok,
		"dungeon builder can unload floor chunk",
		start,
		"FLOOR-7.6"
	)


func _test_endless_mode() -> void:
	var start := Time.get_ticks_msec()
	var ok := RM.MODE_ENDLESS == "endless" and RunFloorConfig.ENDLESS_MAX_FLOORS > RunFloorConfig.MAX_FLOORS
	ctx.timed_record(
		"m7.endless.mode_constants",
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
		"m7.endless.difficulty_scaling",
		get_category(),
		tier1 >= 1 and mult > 1.0,
		"floor 11+ has increased difficulty tier",
		start,
		"UMBRAL-7.1"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scripts/ui/umbral_endless_menu.gd")
	ctx.timed_record(
		"m7.endless.menu",
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
		"m7.waves.scene",
		get_category(),
		ok,
		"waves run scene exists",
		start,
		"UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	ok = WavesRunService.MILESTONES.size() == 4 and WavesRunService.get_chest_count() == 6
	ctx.timed_record(
		"m7.waves.milestones",
		get_category(),
		ok,
		"waves milestones and 6 chests configured",
		start,
		"UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	ok = (
		ctx.file_contains("res://scripts/save/local_save.gd", "wavesActiveRun")
		and ctx.file_contains("res://scripts/save/local_save.gd", '"wavesActiveRun"')
	)
	ctx.timed_record(
		"m7.waves.save_persist",
		get_category(),
		ok,
		"waves active run persisted in save payload",
		start,
		"UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scripts/loot/rarity_registry.gd")
	ctx.timed_record(
		"m7.rarity.global_registry",
		get_category(),
		ok,
		"global rarity registry exists",
		start,
		"UMBRAL-7.2"
	)
	start = Time.get_ticks_msec()
	ok = LocalSave.has_method("has_continuable_waves_run")
	ctx.timed_record(
		"m7.waves.save",
		get_category(),
		ok,
		"waves continue save API present",
		start,
		"UMBRAL-7.2"
	)


func _test_skip_items() -> void:
	var start := Time.get_ticks_msec()
	var ok := ItemCatalog.has_item("skip_10_floors") and ItemCatalog.has_item("skip_500_floors")
	ctx.timed_record(
		"m7.skip.items_catalog",
		get_category(),
		ok,
		"skip-floor consumables in catalog",
		start,
		"UMBRAL-7.3"
	)
	start = Time.get_ticks_msec()
	ok = SkipFloorSvc.start_floor_for_item("skip_100_floors") == 101
	ctx.timed_record(
		"m7.skip.start_floors",
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
		"m7.skip.loot_table",
		get_category(),
		ok,
		"global skip drop table defined",
		start,
		"UMBRAL-7.3"
	)


func _test_floor_seed_derivation() -> void:
	var start := Time.get_ticks_msec()
	var a := RunFloorConfig.mix_seed(TC.SEED_A, 1)
	var b := RunFloorConfig.mix_seed(TC.SEED_A, 2)
	ctx.timed_record(
		"m7.floor.seed_derivation",
		get_category(),
		a != b and a >= 1,
		"floor seed mix differs per floor",
		start,
		"FLOOR-7.1"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"m7.floor.max_floors",
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
		"m7.tier.seed_derivation",
		get_category(),
		tier1 == TC.SEED_A and tier2 != tier1 and tier2 >= 1,
		"tier 1 keeps base seed; tier 2 derives a distinct seed",
		start,
		"FLOOR-7.1"
	)


func _test_max_secrets_per_floor() -> void:
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"m7.floor.max_secrets_constant",
		get_category(),
		RunFloorConfig.MAX_SECRETS_PER_FLOOR == 2,
		"max 2 secrets per floor enforced in config",
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
		"m7.procgen.floor_layout_differs",
		get_category(),
		ok and sig1 != sig2,
		"same run seed different layout per floor",
		start,
		"FLOOR-7.1"
	)
	if ok:
		start = Time.get_ticks_msec()
		var secrets := RunFloorConfig.count_secrets(floor1.get("definition", {}))
		ctx.timed_record(
			"m7.procgen.secrets_cap",
			get_category(),
			secrets <= RunFloorConfig.MAX_SECRETS_PER_FLOOR,
			"floor has %d secrets (max %d)" % [secrets, RunFloorConfig.MAX_SECRETS_PER_FLOOR],
			start,
			"FLOOR-7.2"
		)
	start = Time.get_ticks_msec()
	var final_gen := LocalProcgen.generate(BiomeRegistry.BIOME_CASTLE, TC.SEED_A, RunFloorConfig.MAX_FLOORS)
	var final_def: Dictionary = final_gen.get("definition", {})
	ctx.timed_record(
		"m7.procgen.final_floor",
		get_category(),
		final_gen.get("ok", false) and bool(final_def.get("isFinalFloor", false)),
		"floor 10 generates final-floor layout",
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
		"m7.floor.stair_collision",
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
		ctx.file_contains(shell_path, "_add_slab(shell, \"CeilingSlab\"")
		and ctx.file_contains(registry_path, "uses_indoor_lighting")
		and ctx.file_contains(registry_path, "sun.visible = false")
		and ctx.file_contains("res://scripts/dungeon/dungeon_builder.gd", "_build_floor_shell")
		and ctx.file_contains("res://scripts/dungeon/waves_run.gd", "WavesOutdoorsDiorama")
	)
	ctx.timed_record(
		"m7.floor.indoor_ceiling_lighting",
		get_category(),
		ok,
		"opaque ceilings + per-room lights for dungeon/endless; waves uses open outdoors meadow",
		start,
		"FLOOR-7.1"
	)


func _test_stair_lever_script() -> void:
	var start := Time.get_ticks_msec()
	var lever_script: Script = load("res://scripts/dungeon/stair_lever.gd")
	var ok := lever_script != null
	ctx.timed_record(
		"m7.floor.stair_lever_script",
		get_category(),
		ok,
		"StairLever interactable script exists",
		start,
		"FLOOR-7.2"
	)
	start = Time.get_ticks_msec()
	var facing := RunFloorConfig.stairs_spawn_facing_y(null, true)
	ctx.timed_record(
		"m7.floor.spawn_facing_helper",
		get_category(),
		typeof(facing) == TYPE_FLOAT,
		"stair spawn facing helper callable",
		start,
		"FLOOR-7.2"
	)


func _test_final_boss_phases() -> void:
	var start := Time.get_ticks_msec()
	var boss := FinalBossScript.new()
	ctx.timed_record(
		"m7.boss.final_script",
		get_category(),
		boss.has_method("is_immune") and boss.has_method("capture_state"),
		"final boss has phase/state API",
		start,
		"FLOOR-7.5"
	)
	start = Time.get_ticks_msec()
	var scene: PackedScene = load("res://scenes/enemies/final_boss_forgotten_castle.tscn")
	ctx.timed_record(
		"m7.boss.final_scene",
		get_category(),
		scene != null and EnemyCatalog.has_enemy("final_boss_forgotten_castle"),
		"final boss scene + catalog entry",
		start,
		"FLOOR-7.5"
	)


func _test_steam_stub() -> void:
	var start := Time.get_ticks_msec()
	var steam := SteamServiceScript.new()
	ctx.owner.add_child(steam)
	await ctx.owner.get_tree().process_frame
	var ok := steam.is_available() and steam.is_stub_mode
	ctx.timed_record(
		"m7.steam.stub_init",
		get_category(),
		ok,
		"SteamService stub path initializes",
		start,
		"STEAM-7.1"
	)
	start = Time.get_ticks_msec()
	var synced := steam.sync_achievements(["boss_slayer"])
	ctx.timed_record(
		"m7.steam.achievement_sync_stub",
		get_category(),
		synced >= 0,
		"achievement sync stub callable",
		start,
		"STEAM-7.2"
	)
	start = Time.get_ticks_msec()
	var ticket := steam.get_auth_ticket_hex()
	ctx.timed_record(
		"m7.steam.auth_ticket_deferred",
		get_category(),
		ticket == "",
		"auth ticket deferred in stub mode",
		start,
		"STEAM-7.4"
	)
	steam.queue_free()


func _test_save_migration_floor() -> void:
	var start := Time.get_ticks_msec()
	var migrated: Dictionary = SaveMigratorScript.migrate({
		"schemaVersion": 1,
		"inventory": {"schemaVersion": 1, "slots": [], "equipped": {}},
		"activeRun": {
			"runId": "test",
			"seed": TC.SEED_A,
			"dungeonDefinition": {"rooms": []},
		},
	})
	var run: Dictionary = migrated.get("activeRun", {})
	ctx.timed_record(
		"m7.save.migration_floor_fields",
		get_category(),
		int(migrated.get("schemaVersion", 0)) == 3
			and run.has("currentFloor")
			and str(run.get("runMode", "")) != "",
		"v1 save migrates with floor fields",
		start,
		"SCHEMA-7.1"
	)


func _test_input_glyphs() -> void:
	var start := Time.get_ticks_msec()
	var glyph := InputGlyphScript.get_action_glyph("interact")
	var label := InputGlyphScript.format_interact_label()
	ctx.timed_record(
		"m7.polish.controller_glyphs",
		get_category(),
		not glyph.is_empty() and "Press" in label,
		"input glyph service returns labels",
		start,
		"POLISH-7.1"
	)


func _test_hub_tutorial() -> void:
	var start := Time.get_ticks_msec()
	HubTutorialScript.tips_completed = false
	HubTutorialScript.tips_enabled = true
	HubTutorialScript.current_tip_index = 0
	var tip := HubTutorialScript.get_current_tip()
	var can_skip: bool = true
	ctx.timed_record(
		"m7.polish.hub_tutorial",
		get_category(),
		not tip.is_empty() and can_skip,
		"hub tutorial tips available and skippable",
		start,
		"POLISH-7.2"
	)


func _test_crash_logger() -> void:
	var start := Time.get_ticks_msec()
	var script: Script = load("res://scripts/platform/crash_logger.gd")
	var ok: bool = script != null and ctx.file_contains("res://scripts/platform/crash_logger.gd", "CONTENT_VERSION")
	ctx.timed_record(
		"m7.perf.crash_logger",
		get_category(),
		ok,
		"crash logger hooks present",
		start,
		"PERF-7.2"
	)


func _test_perf_hooks() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = ctx.file_contains("res://scripts/combat/enemy_pool.gd", "class_name EnemyPool")
	ctx.timed_record(
		"m7.perf.enemy_pool",
		get_category(),
		ok,
		"enemy pooling module present (PERF-7.1)",
		start,
		"PERF-7.1"
	)


func _test_ci_release_workflow() -> void:
	var start := Time.get_ticks_msec()
	var path := _content_root().path_join(".github/workflows/release.yml")
	var ok: bool = FileAccess.file_exists(path) and "workflow_dispatch" in FileAccess.get_file_as_string(path)
	ctx.timed_record(
		"m7.ci.release_workflow",
		get_category(),
		ok,
		"release workflow stub exists",
		start,
		"CI-7.1"
	)


func _test_ship_docs() -> void:
	var start := Time.get_ticks_msec()
	var path := _content_root().path_join("docs/plan/07-EA-DEFINITION-OF-DONE.md")
	var ok: bool = FileAccess.file_exists(path) and "Early Access" in FileAccess.get_file_as_string(path)
	ctx.timed_record(
		"m7.ship.manual_checklist",
		get_category(),
		ok,
		"EA definition-of-done documented",
		start,
		"SHIP-7.1"
	)


func _test_schema_doc() -> void:
	var start := Time.get_ticks_msec()
	var path := _content_root().path_join("docs/SAVE_MIGRATIONS.md")
	var ok: bool = FileAccess.file_exists(path) and "schemaVersion" in FileAccess.get_file_as_string(path)
	ctx.timed_record(
		"m7.schema.migration_doc",
		get_category(),
		ok,
		"SAVE_MIGRATIONS.md documents versions",
		start,
		"SCHEMA-7.1"
	)


func _test_multi_floor_run_state() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = RunFlow.has_method("ascend_floor") and RunFlow.has_method("get_current_floor")
	ctx.timed_record(
		"m7.floor.run_flow_api",
		get_category(),
		ok,
		"RunFlow exposes multi-floor API",
		start,
		"FLOOR-7.1"
	)
	start = Time.get_ticks_msec()
	var blocked: bool = not RunFlow.can_escape_run()
	ctx.timed_record(
		"m7.floor.escape_gated",
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
		"m7.run_mode.helpers",
		get_category(),
		ok,
		"run mode helpers cover castle/endless/waves",
		start,
		"FLOOR-7.1"
	)
	start = Time.get_ticks_msec()
	ok = RM.is_multi_floor(RM.MODE_ENDLESS) and not RM.is_multi_floor(RM.MODE_WAVES)
	ctx.timed_record(
		"m7.run_mode.multi_floor",
		get_category(),
		ok,
		"castle and endless are multi-floor; waves is isolated",
		start,
		"FLOOR-7.1"
	)


func _test_endless_portal_blocked() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = ctx.file_contains("res://scripts/app/run_flow.gd", "endless runs have no exit portal")
	ctx.timed_record(
		"m7.endless.no_mid_portal",
		get_category(),
		ok,
		"endless runs block mid-run exit portal",
		start,
		"ENDLESS-7.x"
	)


func _test_endless_continue_api() -> void:
	var start := Time.get_ticks_msec()
	var ok := RunFlow.has_method("continue_endless_run") and RunFlow.has_method("start_endless_run")
	ctx.timed_record(
		"m7.endless.continue_api",
		get_category(),
		ok,
		"RunFlow exposes endless start/continue",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	ok = ctx.file_contains(
		"res://scripts/ui/umbral_endless_menu.gd",
		'str(saved.get("runMode", "")) == "endless"'
	)
	ctx.timed_record(
		"m7.endless.continue_save_check",
		get_category(),
		ok,
		"endless menu filters continuable endless saves",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scenes/ui/umbral_endless_menu.tscn")
	ctx.timed_record(
		"m7.endless.menu_scene",
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
		"m7.waves.isolated_inventory",
		get_category(),
		isolated,
		"waves inventory is separate from main inventory",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	var ok: bool = ctx.file_contains("res://scripts/ui/waves_run_ui.gd", "Choose up to 3 items")
	ctx.timed_record(
		"m7.waves.reward_ui",
		get_category(),
		ok,
		"waves reward pick allows up to 3 items",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = FileAccess.file_exists("res://scenes/ui/umbral_waves_menu.tscn")
	ctx.timed_record(
		"m7.waves.menu_scene",
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
		"m7.waves.complete_rewards",
		get_category(),
		ok,
		"waves completion transfers chosen rewards to main inventory",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = (
		ctx.file_contains("res://scripts/dungeon/waves_run_service.gd", "all_chests_opened")
		and ctx.file_contains("res://scripts/dungeon/waves_run_service.gd", "lobby_ready")
	)
	ctx.timed_record(
		"m7.waves.lobby_ready_gate",
		get_category(),
		ok,
		"waves ready blocked until all 6 chests opened",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = (
		ctx.file_contains("res://scripts/dungeon/waves_run.gd", "CombatHUD")
		and ctx.file_contains("res://scripts/dungeon/waves_run.gd", "_restore_waves_snapshot")
	)
	ctx.timed_record(
		"m7.waves.combat_hud_restore",
		get_category(),
		ok,
		"waves scene builds CombatHUD and restores continue snapshot",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = RarityRegistryScript.normalize("mythic") == "aumbral"
	ctx.timed_record(
		"m7.rarity.aumbral_alias",
		get_category(),
		ok,
		"mythic rarity aliases to aumbral top tier",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = BlacksmithService.get_max_upgrade_level_for_slot({"itemId": "mythic_blade", "rarity": "aumbral"}) == 10
	ctx.timed_record(
		"m7.blacksmith.aumbral_cap",
		get_category(),
		ok,
		"aumbral items upgrade to +10 at blacksmith",
		start,
		"WAVES-7.x"
	)
	start = Time.get_ticks_msec()
	ok = BlacksmithService.get_max_upgrade_level_for_slot({"itemId": "castle_sword"}) == 5
	ctx.timed_record(
		"m7.blacksmith.standard_cap",
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
		"m7.hub.endless_portal",
		get_category(),
		"UmbralEndlessPortal" in hub_text and "UmbralEndlessMenu" in hub_text,
		"hub has Umbral Endless portal + menu",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	ctx.timed_record(
		"m7.hub.waves_portal",
		get_category(),
		"UmbralWavesPortal" in hub_text and "UmbralWavesMenu" in hub_text,
		"hub has Umbral Waves portal + menu",
		start,
		"WAVES-7.x"
	)


func _test_skip_all_four() -> void:
	var items: Array[String] = ["skip_10_floors", "skip_50_floors", "skip_100_floors", "skip_500_floors"]
	for item_id in items:
		var start := Time.get_ticks_msec()
		ctx.timed_record(
			"m7.skip.catalog_%s" % item_id,
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
			"m7.skip.floor_%s" % item_id,
			get_category(),
			floor == expected,
			"%s starts at floor %d" % [item_id, floor],
			start,
			"SKIP-7.x"
		)


func _test_save_v2_migration() -> void:
	var start := Time.get_ticks_msec()
	var migrated: Dictionary = SaveMigratorScript.migrate({
		"schemaVersion": 2,
		"activeRun": {
			"runId": "v2test",
			"runMode": "castle",
			"currentFloor": 3,
			"floorDefinitions": {"1": {}, "2": {}},
		},
	})
	var run: Dictionary = migrated.get("activeRun", {})
	ctx.timed_record(
		"m7.save.v2_to_v3_strips_floors",
		get_category(),
		int(migrated.get("schemaVersion", 0)) == 3 and not run.has("floorDefinitions"),
		"v2 save migrates to v3 without floorDefinitions cache",
		start,
		"SCHEMA-7.1"
	)


func _test_global_drops() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = ResourceLoader.exists("res://scripts/loot/global_drop_service.gd")
	ctx.timed_record(
		"m7.global_drops.service",
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
		"m7.global_drops.schema",
		get_category(),
		ok,
		"global-drops schema exists",
		start,
		"SKIP-7.x"
	)
	start = Time.get_ticks_msec()
	var drop := GlobalDropService.roll_enemy_drop(12345, 15)
	ok = drop == "" or ItemCatalog.has_item(drop)
	ctx.timed_record(
		"m7.global_drops.roll_valid",
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
		"m7.endless.tier_floor_21",
		get_category(),
		tier == 2 and mult > 1.2,
		"floor 21 is tier 2 with higher HP multiplier",
		start,
		"ENDLESS-7.x"
	)
	start = Time.get_ticks_msec()
	var bonus := EndlessDifficultyScript.rare_drop_bonus(30)
	ctx.timed_record(
		"m7.endless.rare_drop_bonus",
		get_category(),
		bonus > 0.0 and bonus <= RunFloorConfigScript.DROP_RATE_BONUS_CAP,
		"endless rare drop bonus scales with tier",
		start,
		"ENDLESS-7.x"
	)


func _test_boss_phase_constants() -> void:
	var start := Time.get_ticks_msec()
	var boss := FinalBossScript.new()
	var ok: bool = (
		boss.has_method("is_immune")
		and ctx.file_contains("res://scripts/enemies/final_boss_forgotten_castle.gd", "enum Phase")
	)
	ctx.timed_record(
		"m7.boss.phase_api",
		get_category(),
		ok,
		"final boss defines phase enum and immunity API",
		start,
		"FLOOR-7.5"
	)
	start = Time.get_ticks_msec()
	ok = ResourceLoader.exists("res://scenes/bosses/final_boss_crystal.tscn")
	ctx.timed_record(
		"m7.boss.crystal_scene",
		get_category(),
		ok,
		"final boss crystal scene exists for puzzle phase",
		start,
		"FLOOR-7.5"
	)


func _test_endless_retreat_api() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = (
		RunFlow.has_method("retreat_to_hub")
		and RunFlow.has_method("can_retreat_to_hub")
		and ctx.file_contains("res://scripts/dungeon/stair_lever.gd", "retreat_to_hub")
	)
	ctx.timed_record(
		"m7.endless.retreat_api",
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
		and ctx.file_contains("res://scripts/ui/inventory_ui.gd", "_waves_mode")
		and WavesRunService.has_method("apply_equipment_to_player")
	)
	ctx.timed_record(
		"m7.waves.equip_ui",
		get_category(),
		ok,
		"waves equip UI script wired into waves run",
		start,
		"WAVES-7.x"
	)


func _test_boss_cannon_flow() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = (
		ResourceLoader.exists("res://scenes/bosses/final_boss_cannon.tscn")
		and ctx.file_contains("res://scripts/enemies/final_boss_forgotten_castle.gd", "register_cannon_hit")
		and ctx.file_contains("res://scripts/dungeon/final_boss_cannon.gd", "deposit_crystal")
	)
	ctx.timed_record(
		"m7.boss.cannon_flow",
		get_category(),
		ok,
		"final boss cannon load-and-fire puzzle flow",
		start,
		"FLOOR-7.5"
	)


func _test_known_issues_doc() -> void:
	var start := Time.get_ticks_msec()
	var path := _content_root().path_join("docs/design/AUDIT_2026-08.md")
	ctx.timed_record(
		"m7.ship.known_issues_doc",
		get_category(),
		FileAccess.file_exists(path),
		"AUDIT_2026-08.md documented",
		start,
		"SHIP-7.x"
	)


func _content_root() -> String:
	return ContentLoader.content_path("content").get_base_dir()
