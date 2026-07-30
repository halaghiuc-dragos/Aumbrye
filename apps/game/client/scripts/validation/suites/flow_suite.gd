extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "flow"


func run() -> void:
	_test_run_flow_scene_paths()
	_test_run_flow_offline_procgen()
	_test_debug_overlay_seed()
	_test_results_screen()


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
	var uses_local: bool = ctx.file_contains("res://scripts/app/run_flow.gd", "LocalProcgen.generate")
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


func _test_debug_overlay_seed() -> void:
	var start := Time.get_ticks_msec()
	var has_seed_display: bool = ctx.file_contains("res://scripts/debug/debug_overlay.gd", "run_seed")
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
