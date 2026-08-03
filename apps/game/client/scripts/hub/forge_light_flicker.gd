extends Node

## Subtle forge OmniLight + emissive pulse for hub blacksmith (one intentional motion cue).

var _light: OmniLight3D
var _emissive_mat: StandardMaterial3D
var _base_energy: float = 1.0
var _base_emission: float = 1.0
var _t: float = 0.0


func setup(light: OmniLight3D, emissive_mesh: MeshInstance3D = null) -> void:
	_light = light
	if light:
		_base_energy = light.light_energy
	if emissive_mesh and emissive_mesh.material_override is StandardMaterial3D:
		_emissive_mat = (emissive_mesh.material_override as StandardMaterial3D).duplicate()
		emissive_mesh.material_override = _emissive_mat
		_base_emission = _emissive_mat.emission_energy_multiplier


func _process(delta: float) -> void:
	_t += delta
	var flick: float = 0.88 + sin(_t * 8.0) * 0.06 + sin(_t * 13.0) * 0.04
	if _light:
		_light.light_energy = _base_energy * flick
	if _emissive_mat:
		_emissive_mat.emission_energy_multiplier = _base_emission * flick
