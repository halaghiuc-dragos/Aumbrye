extends "res://scripts/bosses/arena_hazard.gd"


const CombatLayersScript := preload("res://scripts/combat/combat_layers.gd")
const REFRACTION_COVER_RADIUS := 0.62
const REFRACTION_COVER_HEIGHT := 2.45

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
	_build_refraction_cover()


## These pillars are not merely delayed damage circles. Their solid, world-occluding core gives
## the Sovereign encounter a directional-cover rule: a player can break a long sightline, bait a
## refraction sweep into stone, then choose when to leave the safe side. The same layer is used by
## enemy perception, arrows and audio occlusion, so the cover's visual and combat meaning agree.
func _build_refraction_cover() -> void:
	var cover := StaticBody3D.new()
	cover.name = "RefractionCover"
	cover.collision_layer = CombatLayersScript.WORLD_OCCLUDERS
	cover.collision_mask = 0
	var collision := CollisionShape3D.new()
	collision.name = "CollisionShape3D"
	var shape := CylinderShape3D.new()
	shape.radius = REFRACTION_COVER_RADIUS
	shape.height = REFRACTION_COVER_HEIGHT
	collision.shape = shape
	collision.position = Vector3(0.0, REFRACTION_COVER_HEIGHT * 0.5, 0.0)
	cover.add_child(collision)
	add_child(cover)


## Colourblind mode now remaps this the same way it remaps every other hazard telegraph
## (see `arena_hazard._telegraph_tint()`), rather than keeping a hardcoded blue that never changed.
func _telegraph_tint() -> Color:
	if AccessibilitySettings.colorblind_mode != "default":
		var tint := AccessibilitySettings.get_telegraph_class_color(HAZARD_ATTACK_CLASS)
		tint.a = 0.5
		return tint
	return Color(0.4, 0.7, 1, 0.5)


func _active_tint() -> Color:
	if AccessibilitySettings.colorblind_mode != "default":
		var tint := AccessibilitySettings.get_telegraph_class_color(HAZARD_ATTACK_CLASS)
		tint.a = 0.9
		return tint
	return Color(0.5, 0.85, 1, 0.9)
