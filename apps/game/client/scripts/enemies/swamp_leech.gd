extends CastleEnemyBase

## Swamp leech — fast melee with poison on hit (THEME-5.3).


func _resolve_enemy_id() -> String:
	return "swamp_leech"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.25, 0.45, 0.2, 1.0))
	scale = Vector3(0.75, 0.6, 0.75)
