extends Node


const PHASE_BUCKETS := 8
const WETNESS_BUCKETS := 4

var _probe: ReflectionProbe
var _last_key := Vector2i(-1, -1)
var _pending_once := false


func configure(probe: ReflectionProbe) -> void:
	_probe = probe


func _process(_delta: float) -> void:
	if _probe == null or not is_instance_valid(_probe):
		return
	if _pending_once:
		_probe.update_mode = ReflectionProbe.UPDATE_ONCE
		_pending_once = false
		return
	var phase_bucket := int(floorf(DayNightService.phase() * PHASE_BUCKETS)) % PHASE_BUCKETS
	var rain := WeatherService.rain_amount() if WeatherService else 0.0
	var wetness_bucket := clampi(int(floorf(rain * WETNESS_BUCKETS)), 0, WETNESS_BUCKETS)
	var key := Vector2i(phase_bucket, wetness_bucket)
	if key == _last_key:
		return
	_last_key = key
	_probe.update_mode = ReflectionProbe.UPDATE_ALWAYS
	_pending_once = true
