extends Node

const PixelStyleSuite := preload("res://scripts/validation/suites/pixel_style_suite.gd")
const PixelPipelineSuite := preload("res://scripts/validation/suites/pixel_pipeline_suite.gd")
const TestContext := preload("res://scripts/validation/test_context.gd")


func _ready() -> void:
	var ctx := TestContext.new(self)
	await _run_suite(ctx, PixelStyleSuite)
	await _run_suite(ctx, PixelPipelineSuite)
	var failed := ctx.failed
	print("pixel_style suites: passed=%d failed=%d" % [ctx.passed, failed])
	for record in ctx.records:
		if not bool(record.get("ok", false)):
			print("FAIL: %s — %s" % [record.get("id", ""), record.get("message", "")])
	get_tree().quit(1 if failed > 0 else 0)


func _run_suite(ctx: RefCounted, suite_script: Script) -> void:
	var suite: RefCounted = suite_script.new(ctx)
	if suite.has_method("run"):
		await suite.run()
