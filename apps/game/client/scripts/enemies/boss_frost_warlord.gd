extends CastleEnemyBase

signal boss_defeated


func _resolve_enemy_id() -> String:
	return "boss_frost_warlord"


func _ready() -> void:
	super._ready()


func _on_died() -> void:
	super._on_died()
	boss_defeated.emit()
