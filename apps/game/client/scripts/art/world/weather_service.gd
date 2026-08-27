extends Node


const PARAM_RAIN := &"rain_amount"

signal rain_changed(amount: float)

const DRY_MIN := 240.0
const DRY_MAX := 600.0
const RAIN_MIN := 200.0
const RAIN_MAX := 420.0
const BUILD_SECONDS := 14.0
const EASE_SECONDS := 22.0
const DRY_OUT_SECONDS := 95.0

enum Phase { DRY, BUILDING, POURING, EASING }

var _phase: Phase = Phase.DRY
var _timer := 0.0
var _rain := 0.0
var _wetness := 0.0
var _outdoors := false
var _rng := RandomNumberGenerator.new()
var _wind_player: AudioStreamPlayer
var _rain_player: AudioStreamPlayer

const WIND_DB_MIN := -34.0
const WIND_DB_MAX := -13.0
const RAIN_DB_MIN := -40.0
const RAIN_DB_MAX := -8.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_rng.randomize()
	_timer = _rng.randf_range(DRY_MIN * 0.2, DRY_MAX * 0.5)
	_build_ambience()
	_publish()


func _build_ambience() -> void:
	_wind_player = _make_loop_player("WeatherWind", "res://assets/audio/sfx/weather_wind_loop.ogg")
	_rain_player = _make_loop_player("WeatherRain", "res://assets/audio/sfx/weather_rain_loop.ogg")


func _make_loop_player(node_name: String, path: String) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = node_name
	player.bus = &"Ambience"
	player.volume_db = -80.0
	if ResourceLoader.exists(path):
		var stream := load(path) as AudioStream
		if stream is AudioStreamOggVorbis:
			(stream as AudioStreamOggVorbis).loop = true
		player.stream = stream
	add_child(player)
	if player.stream != null:
		player.play()
	return player


func set_outdoors(value: bool) -> void:
	if _outdoors == value:
		return
	_outdoors = value
	if not value:
		_phase = Phase.DRY
		_rain = 0.0
		_wetness = 0.0
		_timer = _rng.randf_range(DRY_MIN, DRY_MAX)
		_silence_ambience()
		_publish()


func rain_amount() -> float:
	return _rain


func _process(delta: float) -> void:
	if not _outdoors:
		if _wetness > 0.0:
			_wetness = maxf(0.0, _wetness - delta / DRY_OUT_SECONDS)
			_publish()
		return
	_advance_phase(delta)
	_wetness = (
		maxf(_wetness, _rain)
		if _rain > _wetness
		else maxf(_rain, _wetness - delta / DRY_OUT_SECONDS)
	)
	_update_ambience()
	_publish()


func _advance_phase(delta: float) -> void:
	match _phase:
		Phase.DRY:
			_rain = 0.0
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.BUILDING
				_timer = _rng.randf_range(RAIN_MIN, RAIN_MAX)
		Phase.BUILDING:
			_rain = minf(1.0, _rain + delta / BUILD_SECONDS)
			if _rain >= 1.0:
				_phase = Phase.POURING
		Phase.POURING:
			_rain = 0.78 + sin(Time.get_ticks_msec() * 0.00021) * 0.22
			_timer -= delta
			if _timer <= 0.0:
				_phase = Phase.EASING
		Phase.EASING:
			_rain = maxf(0.0, _rain - delta / EASE_SECONDS)
			if _rain <= 0.0:
				_phase = Phase.DRY
				_timer = _rng.randf_range(DRY_MIN, DRY_MAX)


func _update_ambience() -> void:
	if _wind_player != null and is_instance_valid(_wind_player):
		var wind := WindService.strength() if WindService else 0.0
		_wind_player.volume_db = lerpf(WIND_DB_MIN, WIND_DB_MAX, clampf(wind, 0.0, 1.0))
	if _rain_player != null and is_instance_valid(_rain_player):
		_rain_player.volume_db = (
			lerpf(RAIN_DB_MIN, RAIN_DB_MAX, _rain) if _rain > 0.01 else -80.0
		)


func _silence_ambience() -> void:
	for player in [_wind_player, _rain_player]:
		if player != null and is_instance_valid(player):
			player.volume_db = -80.0


const RAIN_SIGNAL_EPSILON := 0.004

var _last_signalled_rain := -1.0


func _publish() -> void:
	RenderingServer.global_shader_parameter_set(PARAM_RAIN, _wetness)
	if absf(_rain - _last_signalled_rain) < RAIN_SIGNAL_EPSILON:
		return
	_last_signalled_rain = _rain
	rain_changed.emit(_rain)
