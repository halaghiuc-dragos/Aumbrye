extends "res://scripts/enemies/castle_archer.gd"

## Crystal bat — fast ranged harass (THEME-5.2).


func get_enemy_id() -> String:
	return "crystal_bat"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.45, 0.7, 0.95, 1.0))
	scale = Vector3(0.7, 0.7, 0.7)
