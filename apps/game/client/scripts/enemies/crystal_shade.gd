extends "res://scripts/enemies/castle_archer.gd"


func _resolve_enemy_id() -> String:
	return "crystal_shade"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.65, 0.45, 0.95, 1.0))
