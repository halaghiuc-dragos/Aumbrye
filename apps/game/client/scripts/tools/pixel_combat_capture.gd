extends Node


func _ready() -> void:
	var scene := load("res://scenes/combat/combat_arena.tscn") as PackedScene
	var arena := scene.instantiate()
	add_child(arena)
	for _frame in 120:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var picture := get_viewport().get_texture().get_image()
	var output_path := "user://pixel_combat_capture.png"
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--output="):
			output_path = argument.trim_prefix("--output=")
	var result := picture.save_png(output_path)
	print("PIXEL CAPTURE RESULT ", result)
	arena.queue_free()
	for _frame in 3:
		await get_tree().process_frame
	get_tree().quit(0 if result == OK else 1)
