extends "res://scripts/validation/validation_suite.gd"

const CastleRunScript := preload("res://scripts/dungeon/castle_run.gd")


func get_category() -> String:
	return "flow"


func run() -> void:
	_test_run_flow_scene_paths()
	_test_run_flow_offline_procgen()
	_test_debug_overlay_seed()
	_test_results_screen()
	_test_run_outcome_flow()
	_test_run_lifecycle_results()
	await _test_floor_transition_failure()
	await _test_floor_transition_stair_spawn()
	_test_floor_cache_eviction()
	_test_dungeon_builder_static_cache_bounded()
	_test_cleared_floors_bounded()
	_test_loot_history_bounded()
	_test_run_meta_cleared_on_return()
	_test_portal_completes_run()


func _test_portal_completes_run() -> void:
	var start := Time.get_ticks_msec()
	var ok: bool = (
		ctx.file_contains("res://scripts/dungeon/exit_portal.gd", "RunFlow.complete_run_via_portal")
		and RunFlow.has_method("complete_run_via_portal")
	)
	ctx.timed_record(
		"flow.portal_completes_run",
		get_category(),
		ok,
		"portal confirmation path calls complete_run_via_portal",
		start,
		"BDP-02"
	)


func _test_run_outcome_flow() -> void:
	var start := Time.get_ticks_msec()
	var has_death := RunFlow.has_method("on_player_died")
	var has_escape_rules: bool = ctx.script_has_method("res://scripts/app/run_flow.gd", "_escape_rules_summary")
	ctx.timed_record(
		"flow.death_escape_api",
		get_category(),
		has_death and has_escape_rules,
		"RunFlow documents escape/death economy",
		start,
		"M4.flow.economy"
	)

	start = Time.get_ticks_msec()
	var results_has_xp: bool = ctx.script_has_property("res://scripts/ui/results_screen.gd", "xp_gained")
	ctx.timed_record(
		"flow.results_outcome_ui",
		get_category(),
		results_has_xp,
		"results screen shows XP outcome",
		start,
		"M4.flow.economy"
	)


func _test_run_flow_scene_paths() -> void:
	var paths := {
		"flow.hub_scene": RunFlow.HUB_SCENE,
		"flow.castle_scene": RunFlow.CASTLE_RUN_SCENE,
		"flow.arena_scene": RunFlow.ARENA_SCENE,
		"flow.results_scene": RunFlow.RESULTS_SCENE,
	}
	for test_id in paths:
		var start := Time.get_ticks_msec()
		var path: String = paths[test_id]
		ctx.timed_record(
			test_id,
			get_category(),
			ResourceLoader.exists(path),
			"RunFlow scene path exists: %s" % path,
			start,
			"M3.flow.scenes"
		)


func _test_run_flow_offline_procgen() -> void:
	var start := Time.get_ticks_msec()
	var uses_local: bool = ctx.file_contains(
		"res://scripts/app/run_flow.gd", "LocalProcgen.generate"
	)
	ctx.timed_record(
		"flow.offline_procgen",
		get_category(),
		uses_local,
		"RunFlow uses LocalProcgen for dungeon creation",
		start,
		"M3.flow.offline"
	)

	start = Time.get_ticks_msec()
	var has_continue := RunFlow.has_method("continue_castle_run")
	var has_hub_return := RunFlow.has_method("return_to_hub")
	ctx.timed_record(
		"flow.continue_and_hub_api",
		get_category(),
		has_continue and has_hub_return,
		"RunFlow exposes continue_castle_run() and return_to_hub()",
		start,
		"M3.flow.continue"
	)

	start = Time.get_ticks_msec()
	var has_portal_complete := RunFlow.has_method("complete_run_via_portal")
	ctx.timed_record(
		"flow.portal_complete_api",
		get_category(),
		has_portal_complete,
		"RunFlow exposes complete_run_via_portal()",
		start,
		"M3.flow.results"
	)

	start = Time.get_ticks_msec()
	var has_loot_claim_api: bool = ctx.file_contains(
		"res://scripts/app/run_flow.gd", "lootClaimedInstanceIds"
	)
	var has_cloud_finalize: bool = ctx.script_has_method("res://scripts/app/run_flow.gd", "_cloud_finalize_run")
	ctx.timed_record(
		"flow.complete_run_loot_ids",
		get_category(),
		has_loot_claim_api and has_cloud_finalize,
		"RunFlow tracks lootClaimedInstanceIds and calls complete_run",
		start,
		"M4.flow.complete"
	)

	start = Time.get_ticks_msec()
	var hub_cloud_sync: bool = ctx.file_contains("res://scripts/hub/hub.gd", "sync_from_cloud")
	ctx.timed_record(
		"flow.hub_cloud_sync",
		get_category(),
		hub_cloud_sync,
		"hub boot pulls cloud save when API available",
		start,
		"M4.flow.cloud"
	)


func _test_debug_overlay_seed() -> void:
	var start := Time.get_ticks_msec()
	var has_seed_display: bool = ctx.file_contains(
		"res://scripts/debug/debug_overlay.gd", "run_seed"
	)
	ctx.timed_record(
		"flow.debug_overlay_seed",
		get_category(),
		has_seed_display,
		"debug overlay displays entered run seed",
		start,
		"M3.debug.seed"
	)


func _test_results_screen() -> void:
	var start := Time.get_ticks_msec()
	var results_script_ok := FileAccess.file_exists("res://scripts/ui/results_screen.gd")
	ctx.timed_record(
		"flow.results_screen_script",
		get_category(),
		results_script_ok,
		"results screen script exists",
		start,
		"M3.flow.results"
	)

	start = Time.get_ticks_msec()
	var waves_outcomes: bool = (
		ctx.file_contains("res://scripts/ui/results_screen.gd", "OUTCOME_WAVES_FAILED")
		and ctx.file_contains("res://scripts/ui/results_screen.gd", "OUTCOME_WAVES_COMPLETE")
	)
	ctx.timed_record(
		"flow.results_waves_outcomes",
		get_category(),
		waves_outcomes,
		"results screen branches on waves_complete and waves_failed",
		start,
		"M4.flow.results"
	)


func _test_run_lifecycle_results() -> void:
	var start := Time.get_ticks_msec()
	var xp := {"gained": 10, "levels_gained": 0}
	var base_extra := {
		"run_mode": "castle",
		"floor_reached": 1,
		"boss_defeated": false,
		"loot_kept": true,
		"run_relics_lost": false,
		"loot_lost": [],
	}
	var outcomes: Array[String] = [
		RunLifecycle.OUTCOME_ESCAPED,
		RunLifecycle.OUTCOME_DIED,
		RunLifecycle.OUTCOME_RESPAWNED,
		RunLifecycle.OUTCOME_RETREATED,
		RunLifecycle.OUTCOME_ABANDONED,
		RunLifecycle.OUTCOME_WAVES_COMPLETE,
		RunLifecycle.OUTCOME_WAVES_FAILED,
	]
	var reference_keys: Array = []
	var parity_ok := true
	for outcome in outcomes:
		var built: Dictionary = RunLifecycle.build_results(
			outcome, 1.0, 0, [], xp, 10, "rules", base_extra
		)
		if reference_keys.is_empty():
			reference_keys = built.keys()
		else:
			var keys_a: Array = reference_keys.duplicate()
			var keys_b: Array = built.keys()
			keys_a.sort()
			keys_b.sort()
			if keys_a != keys_b:
				parity_ok = false
				break
	ctx.timed_record(
		"flow.results.key_parity",
		get_category(),
		parity_ok,
		"all seven outcomes share identical results keys",
		start,
		"RFL.results"
	)

	start = Time.get_ticks_msec()
	var level_before := ProgressionService.level
	var xp_before := ProgressionService.xp
	var xp_result := ProgressionService.grant_xp(
		ProgressionService.xp_to_next_level() + 1, "validation"
	)
	var waves_results: Dictionary = RunLifecycle.build_results(
		RunLifecycle.OUTCOME_WAVES_COMPLETE,
		1.0,
		0,
		[],
		xp_result,
		RunFlow.WAVES_COMPLETION_XP,
		"waves",
		base_extra
	)
	var levels_honest := int(waves_results.get("levels_gained", 0)) >= 1
	ctx.timed_record(
		"flow.results.waves_levels_honest",
		get_category(),
		levels_honest,
		"waves completion reports grant_xp levels_gained",
		start,
		"WAV-01"
	)
	ProgressionService.level = level_before
	ProgressionService.xp = xp_before

	start = Time.get_ticks_msec()
	var failed_results: Dictionary = RunLifecycle.build_results(
		RunLifecycle.OUTCOME_WAVES_FAILED,
		1.0,
		0,
		[],
		{"gained": 0, "levels_gained": 0},
		0,
		"waves failed",
		base_extra
	)
	var failed_keys_ok := failed_results.has("run_relics_lost")
	ctx.timed_record(
		"wav.results.failed_keys",
		get_category(),
		failed_keys_ok,
		"waves failed results include run_relics_lost",
		start,
		"WAV-02"
	)

	start = Time.get_ticks_msec()
	var inv_backup = InventoryService.inventory
	InventoryService.inventory = GridInventory.new()
	InventoryService.add_item("iron_scrap", 1)
	InventoryService.add_item("castle_sword", 1)
	var loot_lost: Array[String] = ["iron_scrap", "castle_sword"]
	InventoryService.remove_run_loot(loot_lost)
	var missing: Array[String] = []
	for item_id in loot_lost:
		var found := false
		for slot in InventoryService.inventory.slots:
			if slot.get("itemId", "") == item_id:
				found = true
				break
		if not found:
			missing.append(item_id)
	var death_results: Dictionary = RunLifecycle.build_results(
		RunLifecycle.OUTCOME_DIED,
		1.0,
		0,
		[],
		xp,
		20,
		"death",
		{"loot_lost": loot_lost, "loot_kept": false, "run_relics_lost": true}
	)
	var loot_diff_ok: bool = (
		death_results.get("loot_lost", []) == loot_lost and missing.size() == loot_lost.size()
	)
	InventoryService.inventory = inv_backup
	ctx.timed_record(
		"flow.results.loot_lost_diff",
		get_category(),
		loot_diff_ok,
		"loot_lost matches inventory removal",
		start,
		"RFL.results"
	)


func _test_floor_transition_failure() -> void:
	var start := Time.get_ticks_msec()
	var warned := false
	var warn_cb := func(_msg: String) -> void: warned = true
	if RunFlow.run_warning.is_connected(warn_cb):
		RunFlow.run_warning.disconnect(warn_cb)
	RunFlow.run_warning.connect(warn_cb)
	var prev_def := {"seed": 42, "rooms": []}
	var prev_floor := 2
	RunFlow._run_active = true
	RunFlow.current_floor = 3
	RunFlow.current_dungeon_definition = prev_def.duplicate(true)
	RunFlow._test_resolve_floor_override = false
	await RunFlow._transition_floor(true)
	var floor_ok := RunFlow.current_floor == prev_floor
	var def_ok := RunFlow.current_dungeon_definition == prev_def
	RunFlow.run_warning.disconnect(warn_cb)
	ctx.timed_record(
		"flow.transition.generation_failure_restores",
		get_category(),
		floor_ok and def_ok and warned,
		"failed floor generation restores floor and definition",
		start,
		"RFL.transition"
	)


func _test_floor_transition_stair_spawn() -> void:
	var start := Time.get_ticks_msec()
	var definition := {
		"biomeId": "forgotten_castle",
		"rooms":
		[
			{
				"id": "entrance",
				"templateId": "castle_entrance",
				"type": "hub",
				"transform": {"x": 0, "y": 0, "z": 0, "yaw": 0},
			},
			{
				"id": "stairs",
				"templateId": "castle_stairs",
				"type": "corridor",
				"transform": {"x": 0, "y": 0, "z": 14, "yaw": 0},
			},
		],
		"edges": [{"from": "entrance", "to": "stairs", "kind": "corridor"}],
		"placements":
		{
			"entrance": "entrance",
			"enemies": [],
			"loot": [],
			"traps": [],
			"secrets": [],
			"boss": null,
		},
	}
	var root := Node3D.new()
	root.name = "FloorTransitionTest"
	ctx.owner.add_child(root)
	var player: CharacterBody3D = (
		load("res://scenes/player/player.tscn").instantiate() as CharacterBody3D
	)
	root.add_child(player)
	var builder := DungeonBuilder.new()
	root.add_child(builder)
	builder.build_from_definition(root, player, definition)
	await ctx.await_frame()
	var entrance_pos := player.global_position
	var stair_id := RunFloorConfig.find_stairs_room_id(definition)
	var expected := builder.get_stair_spawn_global(stair_id, true)
	var castle := Node3D.new()
	castle.set_script(CastleRunScript)
	root.add_child(castle)
	castle.set("_player", player)
	castle.set("_builder", builder)
	castle.set("_dungeon_def", definition)
	var snapshot := {
		"floorTransition": true,
		"ascending": true,
	}
	castle.call("_restore_saved_snapshot", snapshot)
	castle.call("_apply_floor_transition_spawn", snapshot)
	var target: Vector3 = expected.get("position", Vector3.ZERO)
	var dist := player.global_position.distance_to(target)
	var moved := entrance_pos.distance_to(player.global_position) > 1.0
	root.queue_free()
	ctx.timed_record(
		"castle.floor_transition.stair_spawn",
		get_category(),
		moved and dist < 3.0,
		"floor transition restore places player at ascending stair spawn",
		start,
		"CST-01"
	)


func _test_floor_cache_eviction() -> void:
	var start := Time.get_ticks_msec()
	DungeonBuilder.clear_floor_cache()
	var backup_floor: int = RunFlow.current_floor
	for floor_index in range(1, DungeonBuilder.MAX_CACHED_FLOORS + 2):
		RunFlow.current_floor = floor_index
		RunFlow._set_current_floor_cache({"floor": floor_index})
	var evicted_one := DungeonBuilder.get_floor_cache(1).is_empty()
	var kept_newest := not DungeonBuilder.get_floor_cache(
		DungeonBuilder.MAX_CACHED_FLOORS + 1
	).is_empty()
	DungeonBuilder.clear_floor_cache()
	RunFlow.current_floor = backup_floor
	ctx.timed_record(
		"flow.cache.evicts_farthest",
		get_category(),
		evicted_one and kept_newest,
		"floor cache (owned by DungeonBuilder) evicts farthest floor from RunFlow's current floor",
		start,
		"RFL.cache"
	)


## BUG-30 regression: DungeonBuilder._floor_definition_cache is a *static* cache with no
## per-run eviction of its own — only clear_floor_cache(), called at run start/end. An endless
## run used to hold every floor definition it had ever generated for the life of the run.
func _test_dungeon_builder_static_cache_bounded() -> void:
	var start := Time.get_ticks_msec()
	DungeonBuilder.clear_floor_cache()
	for floor_index in range(1, DungeonBuilder.MAX_CACHED_FLOORS + 6):
		DungeonBuilder.store_floor_cache(floor_index, {"floor": floor_index})
	var bounded := DungeonBuilder._floor_definition_cache.size() <= DungeonBuilder.MAX_CACHED_FLOORS
	var newest_kept := not (
		DungeonBuilder.get_floor_cache(DungeonBuilder.MAX_CACHED_FLOORS + 5).is_empty()
	)
	var oldest_evicted := DungeonBuilder.get_floor_cache(1).is_empty()
	DungeonBuilder.clear_floor_cache()
	ctx.timed_record(
		"flow.dungeon_builder_static_cache_bounded",
		get_category(),
		bounded and newest_kept and oldest_evicted,
		"DungeonBuilder's static floor cache stays bounded across a long endless run",
		start,
		"BUG-30"
	)


## BUG-30 regression: _cleared_floors used to be a fully unbounded array, duplicate()d into the
## autosave payload on every save.
func _test_cleared_floors_bounded() -> void:
	var start := Time.get_ticks_msec()
	var backup: Array[int] = RunFlow._cleared_floors.duplicate()
	RunFlow._cleared_floors.clear()
	for floor_index in range(1, RunFlow.MAX_CLEARED_FLOORS_TRACKED + 21):
		RunFlow._register_cleared_floor(floor_index)
	var bounded := RunFlow._cleared_floors.size() <= RunFlow.MAX_CLEARED_FLOORS_TRACKED
	var newest_kept := RunFlow._cleared_floors.has(RunFlow.MAX_CLEARED_FLOORS_TRACKED + 20)
	var oldest_evicted := not RunFlow._cleared_floors.has(1)
	RunFlow._cleared_floors = backup
	ctx.timed_record(
		"flow.cleared_floors_bounded",
		get_category(),
		bounded and newest_kept and oldest_evicted,
		"_cleared_floors stays bounded across a long endless run",
		start,
		"BUG-30"
	)


## BUG-30 regression: _loot_claimed_instance_ids grows one entry per unique drop and used to be
## unbounded — realistic over hundreds of endless floors.
func _test_loot_history_bounded() -> void:
	var start := Time.get_ticks_msec()
	var backup_collected: Array[String] = RunFlow._loot_collected.duplicate()
	var backup_claimed: Array[String] = RunFlow._loot_claimed_instance_ids.duplicate()
	RunFlow._loot_collected.clear()
	RunFlow._loot_claimed_instance_ids.clear()
	for i in RunFlow.MAX_LOOT_HISTORY_TRACKED + 20:
		RunFlow.register_loot("castle_sword", "castle_sword#%d" % i)
	var bounded := RunFlow._loot_claimed_instance_ids.size() <= RunFlow.MAX_LOOT_HISTORY_TRACKED
	var newest_kept := RunFlow._loot_claimed_instance_ids.has(
		"castle_sword#%d" % (RunFlow.MAX_LOOT_HISTORY_TRACKED + 19)
	)
	var oldest_evicted := not RunFlow._loot_claimed_instance_ids.has("castle_sword#0")
	RunFlow._loot_collected = backup_collected
	RunFlow._loot_claimed_instance_ids = backup_claimed
	ctx.timed_record(
		"flow.loot_history_bounded",
		get_category(),
		bounded and newest_kept and oldest_evicted,
		"_loot_claimed_instance_ids stays bounded across a long endless run",
		start,
		"BUG-30"
	)


func _test_run_meta_cleared_on_return() -> void:
	var start := Time.get_ticks_msec()
	var root := RunFlow.get_tree().root
	for key in RunFlow.RUN_META_KEYS:
		root.set_meta(key, true)
	root.set_meta("run_respawn_results", true)
	RunFlow._clear_run_meta()
	var cleared := true
	for key in RunFlow.RUN_META_KEYS:
		if root.has_meta(key):
			cleared = false
			break
	if root.has_meta("run_respawn_results"):
		cleared = false
	ctx.timed_record(
		"flow.meta.cleared_on_return",
		get_category(),
		cleared,
		"_clear_run_meta clears RUN_META_KEYS (invoked by return_to_hub)",
		start,
		"RFL.meta"
	)
