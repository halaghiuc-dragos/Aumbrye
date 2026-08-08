extends CastleEnemyBase

signal phase_changed(phase: int)
signal boss_defeated


func _resolve_enemy_id() -> String:
	return "boss_cathedral_hollow"


func _ready() -> void:
	super._ready()
	boss_phase_entered.connect(_on_boss_phase_entered)


func _on_boss_phase_entered(index: int, _phase: Dictionary) -> void:
	phase_changed.emit(index + 1)


func _on_died() -> void:
	super._on_died()
	boss_defeated.emit()
