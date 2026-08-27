extends "res://scripts/enemies/castle_archer.gd"


func _resolve_enemy_id() -> String:
	return "swamp_witch"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.35, 0.5, 0.22, 1.0))
