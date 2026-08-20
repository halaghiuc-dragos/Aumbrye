extends CastleEnemyBase

## Crystal caverns miniboss shell. Its two phases and move sets are authored in
## `content/enemies/crystal_guardian.json`.

func _resolve_enemy_id() -> String:
	return "crystal_guardian"


func get_hp_bar_height() -> float:
	return 2.6


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.4, 0.65, 0.9, 1.0))
	scale = Vector3(1.2, 1.2, 1.2)

