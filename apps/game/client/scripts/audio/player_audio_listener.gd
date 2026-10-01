extends AudioListener3D

## Hears from the player's head, turned the way the camera faces: sounds pan against what is on
## screen, and a wall between the player and a sound muffles it even when the camera orbits past it.

const HEAD_HEIGHT := 1.4


func _ready() -> void:
	top_level = true
	add_to_group("audio_listener")
	make_current()


func _process(_delta: float) -> void:
	var parent := get_parent() as Node3D
	var camera := get_viewport().get_camera_3d()
	if parent == null or camera == null:
		return
	global_transform = Transform3D(
		camera.global_transform.basis, parent.global_position + Vector3(0.0, HEAD_HEIGHT, 0.0)
	)
