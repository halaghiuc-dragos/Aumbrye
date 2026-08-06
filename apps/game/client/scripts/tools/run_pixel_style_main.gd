extends SceneTree

func _initialize() -> void:
	var host := preload("res://scripts/tools/run_pixel_style_suite.gd").new()
	host.name = "PixelStyleSuiteRunner"
	root.add_child(host)
