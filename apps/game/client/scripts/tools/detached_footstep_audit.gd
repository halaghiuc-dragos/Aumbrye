extends Node

const LocomotionScript := preload("res://scripts/player/locomotion.gd")


func _ready() -> void:
	var player := CharacterBody3D.new()
	player.set_script(LocomotionScript)
	player.play_footstep_effects()
	player.free()
	print("DETACHED FOOTSTEP RESULT 0 failures")
	get_tree().quit(0)
