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
	skip(
		"perf.frame_time_ms",
		"GPU frame time requires an in-editor profiling harness",
		"M7.perf.gate"
	)
