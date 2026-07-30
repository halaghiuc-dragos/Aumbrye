extends CastleEnemyBase

## Swamp toad — bulky melee jumper (THEME-5.3).


func get_enemy_id() -> String:
	return "swamp_toad"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.28, 0.42, 0.15, 1.0))
	scale = Vector3(1.15, 0.95, 1.15)


func get_hp_bar_height() -> float:
	return 2.4
