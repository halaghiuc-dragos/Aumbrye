extends CastleEnemyBase


func _resolve_enemy_id() -> String:
	return "crystal_slime"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.55, 0.85, 1.0, 1.0))
	configure_physical_size(0.34, 1.45, Vector3(0.85, 0.85, 0.85))
