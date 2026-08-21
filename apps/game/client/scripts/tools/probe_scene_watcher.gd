extends Node

## Reports which scene the game settles on, from the tree root so it survives scene changes.

var _elapsed := 0.0


func _process(delta: float) -> void:
	_elapsed += delta
	var current := get_tree().current_scene
	var path := str(current.scene_file_path) if current else ""
	if path.ends_with("hub.tscn"):
		print("LANDED: hub.tscn  (class_id='%s')" % CharacterService.class_id)
		get_tree().quit(0)
	elif path.ends_with("main_menu.tscn"):
		print("LANDED: main_menu.tscn  <-- the reported bug")
		get_tree().quit(2)
	elif _elapsed > 25.0:
		print("TIMEOUT on '%s'" % path)
		get_tree().quit(3)
