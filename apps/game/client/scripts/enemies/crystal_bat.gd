extends "res://scripts/enemies/castle_archer.gd"


func _resolve_enemy_id() -> String:
	return "crystal_bat"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.45, 0.7, 0.95, 1.0))
	configure_physical_size(0.28, 1.2, Vector3(0.7, 0.7, 0.7))
