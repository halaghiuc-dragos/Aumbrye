extends CastleEnemyBase

## Crystal golem — high poise, frost-resistant (THEME-5.2).


func _resolve_enemy_id() -> String:
	return "crystal_golem"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.35, 0.55, 0.75, 1.0))
	scale = Vector3(1.35, 1.35, 1.35)


func get_hp_bar_height() -> float:
	return 2.6
