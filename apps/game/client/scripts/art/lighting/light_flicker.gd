class_name LightFlicker
extends Node

## Deterministic two-octave flicker for torch omnis. Disabled when culled or when
## PixelDioramaSettings.light_animation is false.

var _light: OmniLight3D
var _base_energy: float = 1.0
var _amount: float = 0.12
var _hz: float = 7.5
var _phase: float = 0.0
var _time: float = 0.0
var _cull_timer: float = 0.0


func setup(light: OmniLight3D, amount: float, hz: float, phase: float) -> void:
	_light = light
	_base_energy = light.light_energy
	_amount = amount
	_hz = hz
	_phase = phase
	process_mode = Node.PROCESS_MODE_PAUSABLE
	set_process(true)


func _process(delta: float) -> void:
	if _light == null or not is_instance_valid(_light):
		queue_free()
		return
	if not PixelDioramaSettings.light_animation:
		_light.light_energy = _base_energy
		return
	_cull_timer += delta
	if _cull_timer >= 0.25:
		_cull_timer = 0.0
		var visible := _light.is_visible_in_tree()
		set_process(visible)
		if not visible:
			_light.light_energy = _base_energy
			return
	_time += delta
	var swing := (
		sin(_time * _hz * TAU + _phase) * 0.6
		+ sin(_time * _hz * 2.7 * TAU + _phase * 1.7) * 0.4
	) * 0.5
	var energy := _base_energy * (1.0 + _amount * swing)
	_light.light_energy = maxf(energy, 0.0)


static func compute_energy_at(
	base_energy: float, amount: float, hz: float, phase: float, time: float
) -> float:
	var swing := (
		sin(time * hz * TAU + phase) * 0.6 + sin(time * hz * 2.7 * TAU + phase * 1.7) * 0.4
	) * 0.5
	return maxf(base_energy * (1.0 + amount * swing), 0.0)
