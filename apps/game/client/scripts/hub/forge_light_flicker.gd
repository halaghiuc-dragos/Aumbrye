extends Node

## Subtle forge OmniLight + emissive pulse for hub blacksmith (one intentional motion cue).

const EMISSION_PARAM := "emission_energy"

var _light: OmniLight3D
var _shader_mat: ShaderMaterial
var _standard_mat: StandardMaterial3D
var _base_energy: float = 1.0
var _base_emission: float = 1.0
var _t: float = 0.0


func setup(light: OmniLight3D, emissive_mesh: MeshInstance3D = null) -> void:
	_light = light
	if light:
		_base_energy = light.light_energy
	if emissive_mesh == null:
		return
	var source := emissive_mesh.material_override
	if source is ShaderMaterial:
		_shader_mat = (source as ShaderMaterial).duplicate() as ShaderMaterial
		emissive_mesh.material_override = _shader_mat
		var value: Variant = _shader_mat.get_shader_parameter(EMISSION_PARAM)
		_base_emission = float(value) if value != null else 1.0
	elif source is StandardMaterial3D:
		_standard_mat = (source as StandardMaterial3D).duplicate() as StandardMaterial3D
		emissive_mesh.material_override = _standard_mat
		_base_emission = _standard_mat.emission_energy_multiplier


func _process(delta: float) -> void:
	_t += delta
	var flick: float = 0.88 + sin(_t * 8.0) * 0.06 + sin(_t * 13.0) * 0.04
	if _light:
		_light.light_energy = _base_energy * flick
	if _shader_mat:
		_shader_mat.set_shader_parameter(EMISSION_PARAM, _base_emission * flick)
	elif _standard_mat:
		_standard_mat.emission_energy_multiplier = _base_emission * flick
