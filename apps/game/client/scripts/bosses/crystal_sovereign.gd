extends "res://scripts/bosses/arena_boss.gd"


func _resolve_enemy_id() -> String:
	return "crystal_sovereign"


func get_hp_bar_height() -> float:
	return 3.0


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 2.2, 0.0)


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.5, 0.75, 1.0, 1.0))
	scale = Vector3(1.3, 1.3, 1.3)
