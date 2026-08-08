extends CastleEnemyBase

## Poison swamp miniboss shell. Its two phases and move sets are authored in
## `content/enemies/swamp_hag.json`.

signal phase_changed(phase: int)


func _resolve_enemy_id() -> String:
	return "swamp_hag"


func get_hp_bar_height() -> float:
	return 2.5


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.32, 0.28, 0.15, 1.0))
	scale = Vector3(1.15, 1.15, 1.15)
	boss_phase_entered.connect(_on_boss_phase_entered)


func _on_boss_phase_entered(index: int, _phase: Dictionary) -> void:
	phase_changed.emit(index + 1)
