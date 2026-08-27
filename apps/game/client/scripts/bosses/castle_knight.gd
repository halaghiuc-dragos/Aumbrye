extends "res://scripts/bosses/arena_boss.gd"


func _resolve_enemy_id() -> String:
	return "castle_knight"


func get_hp_bar_height() -> float:
	return 2.8


func get_lock_aim_point() -> Vector3:
	return global_position + Vector3(0.0, 1.9, 0.0)
