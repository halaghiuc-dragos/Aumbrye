extends Node

## A footstep animation event can arrive while the character is being detached for a scene change.
## The handler must do nothing then: no surface probe, no effects, no errors.

const LocomotionScript := preload("res://scripts/player/locomotion.gd")


func _ready() -> void:
	var failures := 0
	var player := CharacterBody3D.new()
	player.set_script(LocomotionScript)
	player.set("_surface_probe_timer", 5.0)
	player.play_footstep_effects()
	if not is_equal_approx(float(player.get("_surface_probe_timer")), 5.0):
		failures += 1
		push_error("a detached character still ran the footstep handler")
	player.free()
	print("DETACHED FOOTSTEP RESULT %d failures" % failures)
	get_tree().quit(0 if failures == 0 else 1)
