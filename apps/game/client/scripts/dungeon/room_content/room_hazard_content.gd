extends "res://scripts/dungeon/room_content/room_content_base.gd"

const POISON_POOL := preload("res://scenes/traps/poison_pool.tscn")


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	var hazard: Node3D = POISON_POOL.instantiate() as Node3D
	hazard.position = Vector3(-2.0, 0.0, -2.0)
	hazard.set_meta("biome_id", get_meta("biome_id", ""))
	_content_root().add_child(hazard)
