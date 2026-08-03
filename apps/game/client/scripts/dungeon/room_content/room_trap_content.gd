extends "res://scripts/dungeon/room_content/room_content_base.gd"

const SPIKE_TRAP := preload("res://scenes/traps/spike_trap.tscn")


func configure(_entry: Dictionary, _definition: Dictionary) -> void:
	var trap: Node3D = SPIKE_TRAP.instantiate() as Node3D
	trap.position = Vector3(0.0, 0.0, 2.0)
	trap.set_meta("biome_id", get_meta("biome_id", ""))
	_content_root().add_child(trap)
