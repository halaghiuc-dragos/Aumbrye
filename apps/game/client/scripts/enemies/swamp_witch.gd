extends "res://scripts/enemies/castle_archer.gd"

## Swamp witch — poison ranged caster (THEME-5.3).


func _resolve_enemy_id() -> String:
	return "swamp_witch"


func _ready() -> void:
	super._ready()
	_apply_mesh_tint(Color(0.35, 0.5, 0.22, 1.0))
	if _telegraph and _telegraph.get_surface_override_material_count() > 0:
		var mat := _telegraph.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			mat = mat.duplicate()
			mat.albedo_color = Color(0.3, 0.9, 0.2, 0.85)
			mat.emission = Color(0.2, 0.8, 0.15, 1.0)
			_telegraph.set_surface_override_material(0, mat)
