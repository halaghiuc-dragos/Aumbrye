extends Node

## Autoload — ambience and boss music stubs with crossfade hooks (AUDIO-2.1).

const AMBIENCE_PATH := "res://assets/audio/castle/ambience_loop.wav"
const BOSS_MUSIC_PATH := "res://assets/audio/castle/boss_theme.wav"
const MIX_RATE := 44100.0
const GENERATOR_BUFFER_SEC := 0.25

var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _ambience_freq := 110.0
var _music_freq := 196.0
var _ambience_phase := 0.0
var _music_phase := 0.0
var _current_mode := "none"


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	var master_idx := AudioServer.get_bus_index(&"Master")
	if master_idx >= 0:
		AudioServer.set_bus_mute(master_idx, false)
		AudioServer.set_bus_volume_db(master_idx, 0.0)
	_ambience = _create_player("AmbiencePlayer", _ambience_freq)
	_music = _create_player("MusicPlayer", _music_freq)
	add_child(_ambience)
	add_child(_music)
	_try_load_file_stream(_ambience, AMBIENCE_PATH)
	_try_load_file_stream(_music, BOSS_MUSIC_PATH)


func _process(_delta: float) -> void:
	if _ambience.playing and _ambience.stream is AudioStreamGenerator:
		_ambience_phase = _fill_generator(_ambience, _ambience_freq, _ambience_phase)
	if _music.playing and _music.stream is AudioStreamGenerator:
		_music_phase = _fill_generator(_music, _music_freq, _music_phase)


func play_dungeon_ambience() -> void:
	_current_mode = "dungeon"
	_stop_player(_music)
	call_deferred("_start_player", _ambience)


func play_boss_music() -> void:
	_current_mode = "boss"
	_stop_player(_ambience)
	call_deferred("_start_player", _music)


func stop_all(_fade: float = 0.3) -> void:
	_current_mode = "none"
	_stop_player(_ambience)
	_stop_player(_music)


func _create_player(player_name: String, freq: float) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = &"Master"
	player.volume_db = 0.0
	player.autoplay = false
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = GENERATOR_BUFFER_SEC
	player.stream = generator
	player.set_meta(&"freq", freq)
	return player


func _try_load_file_stream(player: AudioStreamPlayer, path: String) -> void:
	if not ResourceLoader.exists(path):
		return
	var loaded: Variant = ResourceLoader.load(path)
	if loaded is AudioStream:
		player.stream = loaded


func _start_player(player: AudioStreamPlayer) -> void:
	if player.stream == null:
		push_error("AudioDirector: no stream on %s" % player.name)
		return
	player.volume_db = 0.0
	player.stream_paused = false
	player.play()


func _stop_player(player: AudioStreamPlayer) -> void:
	player.stop()


func _fill_generator(player: AudioStreamPlayer, freq: float, phase: float) -> float:
	var playback := player.get_stream_playback()
	if playback == null or not playback is AudioStreamGeneratorPlayback:
		return phase
	var gen_playback := playback as AudioStreamGeneratorPlayback
	var frames_available := gen_playback.get_frames_available()
	if frames_available <= 0:
		return phase
	var phase_step := freq * TAU / MIX_RATE
	for _i in frames_available:
		var sample := sin(phase) * 0.22 + sin(phase * 0.5) * 0.08
		gen_playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + phase_step, TAU)
	return phase
