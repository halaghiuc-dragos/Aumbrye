extends Node

## Autoload — per-biome ambience/boss stubs with crossfade (AUDIO-5.1).

const MIX_RATE := 44100.0
const GENERATOR_BUFFER_SEC := 0.25
const DEFAULT_CROSSFADE := 0.8

var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _ambience_freq := 110.0
var _music_freq := 196.0
var _ambience_phase := 0.0
var _music_phase := 0.0
var _current_mode := "none"
var _current_biome := ""
var _crossfade := DEFAULT_CROSSFADE
var _profile: Dictionary = {}


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


func _process(_delta: float) -> void:
	if _ambience.playing and _ambience.stream is AudioStreamGenerator:
		_ambience_phase = _fill_generator(_ambience, _ambience_freq, _ambience_phase)
	if _music.playing and _music.stream is AudioStreamGenerator:
		_music_phase = _fill_generator(_music, _music_freq, _music_phase)


func set_biome(biome_id: String) -> void:
	_current_biome = biome_id
	_profile = ContentLoader.load_json(BiomeRegistry.get_audio_profile_path(biome_id))
	if _profile.is_empty():
		_profile = {
			"ambienceFreq": 110.0,
			"bossFreq": 196.0,
			"crossfadeSeconds": DEFAULT_CROSSFADE,
		}
	_ambience_freq = float(_profile.get("ambienceFreq", 110.0))
	_music_freq = float(_profile.get("bossFreq", 196.0))
	_crossfade = float(_profile.get("crossfadeSeconds", DEFAULT_CROSSFADE))
	_ambience.set_meta(&"freq", _ambience_freq)
	_music.set_meta(&"freq", _music_freq)
	var ambience_path: String = _profile.get("ambiencePath", "")
	var boss_path: String = _profile.get("bossPath", "")
	if ambience_path != "":
		_try_load_file_stream(_ambience, ambience_path)
	if boss_path != "":
		_try_load_file_stream(_music, boss_path)


func play_dungeon_ambience() -> void:
	_current_mode = "dungeon"
	_crossfade_to(_ambience, _music)


func play_boss_music() -> void:
	_current_mode = "boss"
	_crossfade_to(_music, _ambience)


func stop_all(_fade: float = 0.3) -> void:
	_current_mode = "none"
	_stop_player(_ambience)
	_stop_player(_music)


func _crossfade_to(fade_in: AudioStreamPlayer, fade_out: AudioStreamPlayer) -> void:
	_stop_player(fade_out)
	call_deferred("_start_player", fade_in)


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
