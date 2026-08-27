extends CastleEnemyBase


func _resolve_enemy_id() -> String:
	return "swamp_bogling"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.3, 0.38, 0.18, 1.0))
