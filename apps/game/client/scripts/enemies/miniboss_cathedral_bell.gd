extends CastleEnemyBase

signal phase_changed(phase: int)


func _resolve_enemy_id() -> String:
	return "miniboss_cathedral_bell"


func _ready() -> void:
	super._ready()
	boss_phase_entered.connect(_on_boss_phase_entered)


func _on_boss_phase_entered(index: int, _phase: Dictionary) -> void:
	phase_changed.emit(index + 1)
