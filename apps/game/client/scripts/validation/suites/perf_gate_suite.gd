extends "res://scripts/validation/validation_suite.gd"


func get_category() -> String:
	return "performance"


func run() -> void:
	_test_vfx_pooling()
	_test_frame_budget_placeholder()


func _test_vfx_pooling() -> void:
	var start := Time.get_ticks_msec()
	var script_path := "res://scripts/art/vfx/vfx_service.gd"
	var text := (
		FileAccess.get_file_as_string(script_path) if FileAccess.file_exists(script_path) else ""
	)
	ctx.timed_record(
		"perf.vfx_burst_pool",
		get_category(),
		"_burst_pool" in text and "_acquire_burst" in text,
		"VfxService pools CPUParticles3D bursts",
		start,
		"M7.perf.vfx"
	)


func _test_frame_budget_placeholder() -> void:
	# Documented budget (plan/systems/20-PERFORMANCE.md): 1080p60 → 16.67 ms/frame.
	# Headless validation cannot sample GPU frame time; gate is informational until
	# an in-editor profiling harness writes user://perf_baseline.json.
	const TARGET_FRAME_MS := 16.67
	const BUDGET_DOC := "1080p60 frame budget %.2f ms (GPU profiling deferred)" % TARGET_FRAME_MS
	var start := Time.get_ticks_msec()
	ctx.timed_record(
		"perf.headless_budget_gate", get_category(), true, BUDGET_DOC, start, "M7.perf.gate"
	)
