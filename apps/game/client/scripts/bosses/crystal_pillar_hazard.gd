extends "res://scripts/bosses/arena_hazard.gd"


## Matches what `crystal_pillar_hazard.tscn` authors on its DamageArea. The base writes the hazard's
## own values onto that area, so these have to agree or the scene's numbers are silently replaced.
func _ready() -> void:
	damage = 10.0
	poise_damage = 8.0
	telegraph_time = 1.2
	active_time = 3.0
	super._ready()


func _build_visual() -> void:
	DioramaSkin.build_crystal_pillar(self)


func _telegraph_tint() -> Color:
	return Color(0.4, 0.7, 1, 0.5)


func _active_tint() -> Color:
	return Color(0.5, 0.85, 1, 0.9)
