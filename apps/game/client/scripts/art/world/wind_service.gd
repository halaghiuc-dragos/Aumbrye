extends Node


const PARAM_VECTOR := &"wind_vector"
const PARAM_TIME := &"wind_time"
const PARAM_GUST := &"wind_gust"
const PARAM_DRIFT := &"wind_drift"

const BASE_STRENGTH := 0.34
const GUST_STRENGTH := 0.62
const GUST_INTERVAL_MIN := 6.0
const GUST_INTERVAL_MAX := 17.0
const GUST_RISE := 1.1
const GUST_HOLD := 1.4
const GUST_FALL := 2.6
const DIRECTION_DRIFT := 0.045

var _phase := 0.0
var _direction := 0.7
var _drift := Vector3.ZERO
var _fixed_direction := NAN
var _gust := 0.0
var _gust_timer := 4.0
var _gust_elapsed := -1.0
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_gust_timer = _rng.randf_range(GUST_INTERVAL_MIN, GUST_INTERVAL_MAX)
	_publish()


func _process(delta: float) -> void:
	if is_nan(_fixed_direction):
		_direction += DIRECTION_DRIFT * delta
	else:
		_direction = _fixed_direction
	_advance_gust(delta)
	_phase += delta * (0.6 + strength() * 1.4)
	_drift += wind_vector() * delta
	_publish()


func _advance_gust(delta: float) -> void:
	if _gust_elapsed < 0.0:
		_gust_timer -= delta
		if _gust_timer <= 0.0:
			_gust_elapsed = 0.0
		_gust = 0.0
		return
	_gust_elapsed += delta
	var total := GUST_RISE + GUST_HOLD + GUST_FALL
	if _gust_elapsed >= total:
		_gust_elapsed = -1.0
		_gust = 0.0
		_gust_timer = _rng.randf_range(GUST_INTERVAL_MIN, GUST_INTERVAL_MAX)
		return
	if _gust_elapsed < GUST_RISE:
		_gust = _ease(_gust_elapsed / GUST_RISE)
	elif _gust_elapsed < GUST_RISE + GUST_HOLD:
		_gust = 0.9 + sin(_gust_elapsed * 5.0) * 0.1
	else:
		_gust = _ease(1.0 - (_gust_elapsed - GUST_RISE - GUST_HOLD) / GUST_FALL)


static func _ease(t: float) -> float:
	var x := clampf(t, 0.0, 1.0)
	return x * x * (3.0 - 2.0 * x)


func strength() -> float:
	return clampf(BASE_STRENGTH + _gust * GUST_STRENGTH, 0.0, 1.0)


func gust() -> float:
	return _gust


func set_fixed_direction(dir: Vector3) -> void:
	var flat := Vector3(dir.x, 0.0, dir.z)
	if flat.length_squared() < 0.0001:
		clear_fixed_direction()
		return
	flat = flat.normalized()
	_fixed_direction = atan2(flat.z, flat.x)
	_direction = _fixed_direction


func clear_fixed_direction() -> void:
	_fixed_direction = NAN


func direction() -> Vector3:
	return Vector3(cos(_direction), 0.0, sin(_direction))


func drift() -> Vector3:
	return _drift


func wind_vector() -> Vector3:
	return direction() * strength()


func _publish() -> void:
	RenderingServer.global_shader_parameter_set(PARAM_VECTOR, wind_vector())
	RenderingServer.global_shader_parameter_set(PARAM_TIME, _phase)
	RenderingServer.global_shader_parameter_set(PARAM_GUST, _gust)
	RenderingServer.global_shader_parameter_set(PARAM_DRIFT, _drift)
	LightEmbers.drive_wind(wind_vector())
