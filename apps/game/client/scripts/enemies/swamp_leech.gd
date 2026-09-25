extends CastleEnemyBase


func _resolve_enemy_id() -> String:
	return "swamp_leech"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.25, 0.45, 0.2, 1.0))
	configure_physical_size(0.3, 0.75, Vector3(0.75, 0.6, 0.75))
