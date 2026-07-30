extends "res://scripts/enemies/castle_archer.gd"

## Arcane crystal shade — ranged arcane damage (THEME-5.2).


func get_enemy_id() -> String:
	return "crystal_shade"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.65, 0.45, 0.95, 1.0))
	if _telegraph and _telegraph.get_surface_override_material_count() > 0:
		var mat := _telegraph.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat = mat.duplicate()
			mat.albedo_color = Color(0.6, 0.3, 1.0, 0.85)
			mat.emission = Color(0.5, 0.2, 0.9, 1.0)
			_telegraph.set_surface_override_material(0, mat)
