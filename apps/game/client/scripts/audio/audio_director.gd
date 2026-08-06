extends Node

## Autoload — per-biome ambience/boss music, SFX pool, and bus routing.

const MIX_RATE := 44100.0
const GENERATOR_BUFFER_SEC := 0.25
const DEFAULT_CROSSFADE := 0.8
const SFX_POOL_SIZE := 8
const SFX_BANK_PATH := "content/audio/sfx.json"

const REVERB_PRESETS := {
	"indoor_castle": {"wet": 0.22, "room_size": 0.55, "damping": 0.48, "spread": 0.35},
	"cathedral": {"wet": 0.34, "room_size": 0.82, "damping": 0.38, "spread": 0.42},
	"cave": {"wet": 0.28, "room_size": 0.72, "damping": 0.62, "spread": 0.28},
	"swamp": {"wet": 0.14, "room_size": 0.38, "damping": 0.72, "spread": 0.22},
	"frozen": {"wet": 0.18, "room_size": 0.5, "damping": 0.58, "spread": 0.3},
	"vault": {"wet": 0.24, "room_size": 0.46, "damping": 0.55, "spread": 0.25},
	"umbral": {"wet": 0.3, "room_size": 0.66, "damping": 0.42, "spread": 0.38},
	"outdoor": {"wet": 0.08, "room_size": 0.32, "damping": 0.75, "spread": 0.2},
}

const BIOME_REVERB_PRESETS := {
	"forgotten_castle": "indoor_castle",
	"dark_cathedral": "cathedral",
	"crystal_caverns": "cave",
	"poison_swamp": "swamp",
	"prism_depths": "cave",
	"glacial_hollow": "frozen",
	"venom_mire": "swamp",
	"frozen_fortress": "frozen",
	"umbral_chapel": "umbral",
	"iron_vault": "vault",
}

## Primary path for each SFX key. Bank variants in `content/audio/sfx.json` take precedence.
const SFX_PROFILES := {
	"hit": {"path": "res://assets/audio/sfx/hit.ogg", "bus": &"SFX"},
	"hit_armor": {"path": "res://assets/audio/sfx/hit_armor.ogg", "bus": &"SFX"},
	"block": {"path": "res://assets/audio/sfx/block.ogg", "bus": &"SFX"},
	"parry": {"path": "res://assets/audio/sfx/parry.ogg", "bus": &"SFX"},
	"swing": {"path": "res://assets/audio/sfx/swing_01.ogg", "bus": &"SFX"},
	"death": {"path": "res://assets/audio/sfx/death_01.ogg", "bus": &"SFX"},
	"footstep": {"path": "res://assets/audio/sfx/step_stone_01.ogg", "bus": &"SFX"},
	"footstep_stone": {"freq": 80.0, "duration": 0.05, "bus": &"SFX"},
	"footstep_wood": {"freq": 120.0, "duration": 0.05, "bus": &"SFX"},
	"footstep_water": {"freq": 200.0, "duration": 0.09, "bus": &"SFX"},
	"footstep_snow": {"freq": 60.0, "duration": 0.07, "bus": &"SFX"},
	"windup": {"path": "res://assets/audio/sfx/windup_01.ogg", "bus": &"SFX"},
	"heal_raise": {"path": "res://assets/audio/sfx/heal_raise.ogg", "bus": &"SFX"},
	"heal_gulp": {"path": "res://assets/audio/sfx/heal_gulp.ogg", "bus": &"SFX"},
	"heal_commit": {"path": "res://assets/audio/sfx/heal_commit.ogg", "bus": &"SFX"},
	"lever_pull": {"path": "res://assets/audio/sfx/ui_click_01.ogg", "bus": &"SFX"},
	"lever_unlock": {"path": "res://assets/audio/sfx/heal_commit.ogg", "bus": &"SFX"},
	"ui": {"path": "res://assets/audio/sfx/ui_click_01.ogg", "bus": &"UI"},
	"door_open": {"path": "res://assets/audio/sfx/swing_01.ogg", "bus": &"SFX"},
	"door_seal": {"path": "res://assets/audio/sfx/block_01.ogg", "bus": &"SFX"},
	"door_release": {"path": "res://assets/audio/sfx/heal_raise.ogg", "bus": &"SFX"},
	"portal_open": {"path": "res://assets/audio/sfx/heal_commit.ogg", "bus": &"SFX"},
	"portal_enter": {"path": "res://assets/audio/sfx/ui_click_01.ogg", "bus": &"UI"},
	"boss_reveal": {"path": "res://assets/audio/shared/sting_boss.ogg", "bus": &"Music"},
}

const COMBAT_SFX_KEYS: Array[String] = [
	"hit", "hit_armor", "block", "parry", "swing", "death", "footstep", "windup",
]

var _ambience: AudioStreamPlayer
var _music: AudioStreamPlayer
var _explore: AudioStreamPlayer
var _combat_layer: AudioStreamPlayer
var _ambience_freq := 110.0
var _music_freq := 196.0
var _explore_freq := 110.0
var _combat_freq := 130.0
var _ambience_phase := 0.0
var _music_phase := 0.0
var _explore_phase := 0.0
var _combat_phase := 0.0
var _current_mode := "none"
var _current_biome := ""
var _crossfade := DEFAULT_CROSSFADE
var _profile: Dictionary = {}
var _sfx_pool: Array[AudioStreamPlayer] = []
var _sfx_3d_pool: Array[AudioStreamPlayer3D] = []
var _active_tweens: Dictionary = {}
var _combat_engagements := 0
var _ambience_reverb_idx := -1
var _sfx_reverb_idx := -1
var _ambience_duck_idx := -1
var _sfx_bank: Dictionary = {}
var _sfx_streams: Dictionary = {}
var _sfx_last_played_ms: Dictionary = {}
var _sfx_active_counts: Dictionary = {}
var _rng := RandomNumberGenerator.new()


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_rng.randomize()
	AudioSettings.load_from_save()
	_setup_bus_effects()
	_load_sfx_bank()
	_ambience = _create_player("AmbiencePlayer", _ambience_freq, &"Ambience")
	_music = _create_player("MusicPlayer", _music_freq, &"Music")
	_explore = _create_player("ExplorePlayer", _explore_freq, &"Music")
	_combat_layer = _create_player("CombatPlayer", _combat_freq, &"Music")
	add_child(_ambience)
	add_child(_music)
	add_child(_explore)
	add_child(_combat_layer)
	for i in SFX_POOL_SIZE:
		var player := AudioStreamPlayer.new()
		player.name = "SfxPlayer%d" % i
		player.bus = &"SFX"
		add_child(player)
		_sfx_pool.append(player)
	for i in 4:
		var player3d := AudioStreamPlayer3D.new()
		player3d.name = "Sfx3dPlayer%d" % i
		player3d.bus = &"SFX"
		player3d.max_distance = 24.0
		add_child(player3d)
		_sfx_3d_pool.append(player3d)


func _process(_delta: float) -> void:
	if _ambience.playing and _ambience.stream is AudioStreamGenerator:
		_ambience_phase = _fill_generator_for_mode(_ambience, _ambience_freq, _ambience_phase, _current_mode)
	if _music.playing and _music.stream is AudioStreamGenerator:
		_music_phase = _fill_generator_for_mode(_music, _music_freq, _music_phase, _current_mode)
	if _explore.playing and _explore.stream is AudioStreamGenerator:
		_explore_phase = _fill_generator_for_mode(_explore, _explore_freq, _explore_phase, _current_mode)
	if _combat_layer.playing and _combat_layer.stream is AudioStreamGenerator:
		_combat_phase = _fill_generator_for_mode(_combat_layer, _combat_freq, _combat_phase, _current_mode)


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
	_explore_freq = float(_profile.get("exploreFreq", _ambience_freq))
	_combat_freq = float(_profile.get("combatFreq", _music_freq))
	_music_freq = float(_profile.get("bossFreq", 196.0))
	_crossfade = float(_profile.get("crossfadeSeconds", DEFAULT_CROSSFADE))
	_ambience.set_meta(&"freq", _ambience_freq)
	_explore.set_meta(&"freq", _explore_freq)
	_combat_layer.set_meta(&"freq", _combat_freq)
	_music.set_meta(&"freq", _music_freq)
	var ambience_path: String = _profile.get("ambiencePath", "")
	var boss_path: String = _profile.get("bossPath", "")
	if ambience_path != "":
		_try_load_file_stream(_ambience, ambience_path)
	if boss_path != "":
		_try_load_file_stream(_music, boss_path)
	var reverb_preset: String = str(_profile.get("reverbPreset", BIOME_REVERB_PRESETS.get(biome_id, "indoor_castle")))
	_apply_reverb_preset(reverb_preset)


func play_dungeon_ambience() -> void:
	_current_mode = "dungeon"
	_combat_engagements = 0
	_restore_generator_streams()
	_crossfade_to(_ambience, _music)
	_crossfade_to(_explore, _combat_layer)


func play_menu_music() -> void:
	_current_mode = "menu"
	_combat_engagements = 0
	_ambience_freq = 98.0
	_music_freq = 392.0
	_explore_freq = 523.0
	_combat_freq = 294.0
	_ambience.set_meta(&"freq", _ambience_freq)
	_music.set_meta(&"freq", _music_freq)
	_explore.set_meta(&"freq", _explore_freq)
	_combat_layer.set_meta(&"freq", _combat_freq)
	_restore_generator_streams()
	_apply_reverb_preset("cathedral")
	_fade_out_player(_combat_layer, _crossfade)
	_fade_out_player(_ambience, _crossfade)
	_fade_in_player(_music)
	_fade_in_player(_explore)


func play_hub_ambience() -> void:
	_current_mode = "hub"
	_combat_engagements = 0
	_ambience_freq = 110.0
	_music_freq = 220.0
	_explore_freq = 165.0
	_combat_freq = 87.5
	_ambience.set_meta(&"freq", _ambience_freq)
	_music.set_meta(&"freq", _music_freq)
	_explore.set_meta(&"freq", _explore_freq)
	_combat_layer.set_meta(&"freq", _combat_freq)
	_restore_generator_streams()
	_apply_reverb_preset("umbral")
	_fade_out_player(_combat_layer, _crossfade)
	_fade_out_player(_explore, _crossfade)
	_fade_out_player(_music, _crossfade)
	_fade_in_player(_ambience)
	_fade_in_player(_music)


func play_boss_music() -> void:
	_current_mode = "boss"
	_combat_engagements = 0
	_fade_out_player(_combat_layer, _crossfade)
	_crossfade_to(_music, _ambience)
	_fade_out_player(_explore, _crossfade)


func register_combat_engagement() -> void:
	if _current_mode != "dungeon":
		return
	_combat_engagements += 1
	if _combat_engagements == 1:
		_crossfade_to(_combat_layer, _explore)


func unregister_combat_engagement() -> void:
	if _current_mode != "dungeon":
		return
	_combat_engagements = maxi(0, _combat_engagements - 1)
	if _combat_engagements == 0:
		_crossfade_to(_explore, _combat_layer)


func stop_all(fade: float = 0.3) -> void:
	_current_mode = "none"
	_combat_engagements = 0
	_fade_out_player(_ambience, fade)
	_fade_out_player(_music, fade)
	_fade_out_player(_explore, fade)
	_fade_out_player(_combat_layer, fade)


func play_combat_sfx(kind: String, world_pos: Variant = null, surface: String = "stone") -> void:
	play_sfx(kind, world_pos, surface)


func play_sfx(kind: String, world_pos: Variant = null, surface: String = "stone") -> void:
	var entry: Dictionary = _sfx_bank.get(kind, {})
	var streams: Array = _sfx_streams.get(kind, [])
	if streams.is_empty():
		_warn_missing_sfx(kind)
		_play_fallback_tone(kind, world_pos, entry)
		return
	if not _can_play_sfx(kind, entry):
		return
	var stream: AudioStream = _pick_sfx_stream(kind, entry, surface)
	if stream == null:
		_warn_missing_sfx(kind)
		_play_fallback_tone(kind, world_pos, entry)
		return
	_play_stream(stream, world_pos, entry, kind)
	_mark_sfx_played(kind)


func play_ui_sfx() -> void:
	play_sfx("ui")


func play_cue(cue_name: StringName, world_pos: Variant = null) -> void:
	play_sfx(String(cue_name), world_pos)


func play_stinger(stinger_id: String) -> void:
	var before_db := _music.volume_db if _music else 0.0
	play_sfx(stinger_id)
	if _music and _music.playing:
		_kill_tween(_music)
		_music.volume_db = before_db - 8.0
		var tween := create_tween()
		_active_tweens[_music] = tween
		tween.tween_property(_music, "volume_db", before_db, 1.2)


func has_combat_sfx(kind: String) -> bool:
	return _sfx_streams.has(kind) and not (_sfx_streams[kind] as Array).is_empty()


func has_sfx(kind: String) -> bool:
	_cache_sfx_kind(kind)
	return _sfx_streams.has(kind) and not (_sfx_streams[kind] as Array).is_empty()


func attach_loop_emitter(host: Node3D, key: String, radius: float = 6.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = "LoopEmitter_%s" % key
	host.add_child(player)
	player.unit_size = radius
	player.max_distance = radius * 3.0
	player.bus = &"SFX"
	_cache_sfx_kind(key)
	var streams: Array = _sfx_streams.get(key, [])
	if streams.is_empty():
		_warn_missing_sfx(key)
	else:
		player.stream = streams[0]
		player.autoplay = true
	return player


func _load_sfx_bank() -> void:
	var bank_data := ContentLoader.load_json(SFX_BANK_PATH)
	_sfx_bank = bank_data.get("sfx", {})
	for kind in SFX_PROFILES:
		_cache_sfx_kind(str(kind))
	for kind in _sfx_bank:
		_cache_sfx_kind(str(kind))


func _cache_sfx_kind(kind: String) -> void:
	if _sfx_streams.has(kind):
		return
	var paths := _resolve_sfx_paths(kind)
	var streams: Array[AudioStream] = []
	for path in paths:
		var stream := _load_audio_stream(path)
		if stream != null:
			streams.append(stream)
	if not streams.is_empty():
		_sfx_streams[kind] = streams


func _resolve_sfx_paths(kind: String) -> Array[String]:
	var paths: Array[String] = []
	if _sfx_bank.has(kind):
		var entry: Dictionary = _sfx_bank[kind]
		for path in entry.get("variants", []):
			paths.append(str(path))
		if paths.is_empty():
			var surface_variants: Dictionary = entry.get("surface_variants", {})
			for surface_paths in surface_variants.values():
				for path in surface_paths:
					paths.append(str(path))
	if paths.is_empty() and SFX_PROFILES.has(kind):
		var profile: Dictionary = SFX_PROFILES[kind]
		if profile.has("path"):
			paths.append(str(profile["path"]))
	return paths


func _pick_sfx_stream(kind: String, entry: Dictionary, surface: String) -> AudioStream:
	var streams: Array = _sfx_streams.get(kind, [])
	if streams.is_empty():
		return null
	if entry.has("surface_variants"):
		var surface_variants: Dictionary = entry["surface_variants"]
		if surface_variants.has(surface):
			var surface_paths: Array = surface_variants[surface]
			var surface_streams: Array[AudioStream] = []
			for path in surface_paths:
				var stream := _load_audio_stream(str(path))
				if stream != null:
					surface_streams.append(stream)
			if not surface_streams.is_empty():
				return surface_streams[_rng.randi_range(0, surface_streams.size() - 1)]
	return streams[_rng.randi_range(0, streams.size() - 1)]


func _can_play_sfx(kind: String, entry: Dictionary) -> bool:
	var cooldown_ms := int(entry.get("cooldown_ms", 0))
	if cooldown_ms > 0 and _sfx_last_played_ms.has(kind):
		if Time.get_ticks_msec() - int(_sfx_last_played_ms[kind]) < cooldown_ms:
			return false
	var max_concurrent := int(entry.get("max_concurrent", 8))
	var active := int(_sfx_active_counts.get(kind, 0))
	return active < max_concurrent


func _mark_sfx_played(kind: String) -> void:
	_sfx_last_played_ms[kind] = Time.get_ticks_msec()
	_sfx_active_counts[kind] = int(_sfx_active_counts.get(kind, 0)) + 1
	var timer := get_tree().create_timer(0.5)
	timer.timeout.connect(func() -> void:
		_sfx_active_counts[kind] = maxi(0, int(_sfx_active_counts.get(kind, 0)) - 1)
	, CONNECT_ONE_SHOT)


func _play_stream(stream: AudioStream, world_pos: Variant, entry: Dictionary, kind: String) -> void:
	var bus: StringName = &"SFX"
	if entry.has("bus"):
		bus = StringName(str(entry["bus"]))
	elif SFX_PROFILES.has(kind):
		bus = SFX_PROFILES[kind].get("bus", &"SFX")
	var volume_db := float(entry.get("volume_db", 0.0))
	var pitch_jitter := float(entry.get("pitch_jitter", 0.0))
	var pitch_scale := 1.0
	if pitch_jitter > 0.0:
		pitch_scale = 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	if world_pos is Vector3:
		var player3d := _acquire_sfx_3d_player()
		if player3d == null:
			_play_stream_2d(stream, bus, volume_db, pitch_scale)
			return
		player3d.global_position = world_pos
		player3d.bus = bus
		player3d.volume_db = volume_db
		player3d.pitch_scale = pitch_scale
		player3d.stream = stream
		player3d.play()
	else:
		_play_stream_2d(stream, bus, volume_db, pitch_scale)


func _play_stream_2d(stream: AudioStream, bus: StringName, volume_db: float, pitch_scale: float) -> void:
	var player := _acquire_sfx_player()
	if player == null:
		return
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.stream = stream
	player.play()


func _play_fallback_tone(kind: String, world_pos: Variant, entry: Dictionary) -> void:
	var profile := _fallback_profile(kind, entry)
	if world_pos is Vector3:
		_play_sfx_3d(profile, world_pos)
	else:
		_play_sfx_2d(profile)


func _fallback_profile(kind: String, entry: Dictionary = {}) -> Dictionary:
	var profile: Dictionary = {}
	if entry.has("fallback_tone"):
		var tone: Dictionary = entry["fallback_tone"]
		profile = {
			"freq": float(tone.get("freq", 220.0)),
			"duration": float(tone.get("duration", 0.08)),
			"bus": StringName(str(entry.get("bus", "SFX"))),
		}
	elif SFX_PROFILES.has(kind):
		var sfx_profile: Dictionary = SFX_PROFILES[kind]
		profile = {
			"bus": sfx_profile.get("bus", &"SFX"),
			"freq": float(sfx_profile.get("freq", 220.0)),
			"duration": float(sfx_profile.get("duration", 0.08)),
		}
	else:
		profile = {"freq": 220.0, "duration": 0.08, "bus": &"SFX"}
	return profile


func _warn_missing_sfx(kind: String) -> void:
	if OS.is_debug_build():
		push_warning("AudioDirector: missing authored SFX for '%s'" % kind)


func _play_sfx_2d(profile: Dictionary) -> void:
	var player := _acquire_sfx_player()
	if player == null:
		return
	_prime_tone_burst(player, profile)


func _play_sfx_3d(profile: Dictionary, world_pos: Vector3) -> void:
	var player := _acquire_sfx_3d_player()
	if player == null:
		_play_sfx_2d(profile)
		return
	player.global_position = world_pos
	_prime_tone_burst(player, profile)


func _acquire_sfx_player() -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	return _sfx_pool[0] if not _sfx_pool.is_empty() else null


func _acquire_sfx_3d_player() -> AudioStreamPlayer3D:
	for player in _sfx_3d_pool:
		if not player.playing:
			return player
	return _sfx_3d_pool[0] if not _sfx_3d_pool.is_empty() else null


func _prime_tone_burst(player: Node, profile: Dictionary) -> void:
	var bus: StringName = profile.get("bus", &"SFX")
	player.bus = bus
	player.volume_db = 0.0
	var freq := float(profile.get("freq", 220.0))
	var duration := float(profile.get("duration", 0.08))
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = maxf(duration, GENERATOR_BUFFER_SEC)
	player.stream = generator
	player.play()
	var playback: AudioStreamPlayback = player.get_stream_playback()
	if playback == null or not playback is AudioStreamGeneratorPlayback:
		return
	var gen_playback := playback as AudioStreamGeneratorPlayback
	var frame_count := int(duration * MIX_RATE)
	var phase := 0.0
	var phase_step := freq * TAU / MIX_RATE
	for i in frame_count:
		var env := 1.0 - float(i) / float(maxi(frame_count, 1))
		var sample := sin(phase) * 0.35 * env
		gen_playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + phase_step, TAU)


func _load_audio_stream(path: String) -> AudioStream:
	for candidate in _audio_path_candidates(path):
		if not ResourceLoader.exists(candidate):
			continue
		var loaded: Variant = ResourceLoader.load(candidate)
		if loaded is AudioStream:
			return loaded
	return null


func _crossfade_to(fade_in: AudioStreamPlayer, fade_out: AudioStreamPlayer) -> void:
	_fade_out_player(fade_out, _crossfade)
	call_deferred("_fade_in_player", fade_in)


func _fade_in_player(player: AudioStreamPlayer) -> void:
	if player.stream == null:
		return
	_kill_tween(player)
	player.volume_db = -40.0
	player.stream_paused = false
	if not player.playing:
		player.play()
	var tween := create_tween()
	_active_tweens[player] = tween
	tween.tween_property(player, "volume_db", 0.0, _crossfade)


func _fade_out_player(player: AudioStreamPlayer, fade: float) -> void:
	if not player.playing:
		player.stop()
		return
	_kill_tween(player)
	var tween := create_tween()
	_active_tweens[player] = tween
	tween.tween_property(player, "volume_db", -80.0, fade)
	tween.tween_callback(func() -> void:
		if is_instance_valid(player):
			player.stop()
			player.volume_db = 0.0
	)


func _kill_tween(player: AudioStreamPlayer) -> void:
	if _active_tweens.has(player):
		var tween: Tween = _active_tweens[player]
		if tween and tween.is_valid():
			tween.kill()
		_active_tweens.erase(player)


func _create_player(player_name: String, freq: float, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus
	player.volume_db = 0.0
	player.autoplay = false
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = GENERATOR_BUFFER_SEC
	player.stream = generator
	player.set_meta(&"freq", freq)
	return player


func _try_load_file_stream(player: AudioStreamPlayer, path: String) -> void:
	var stream := _load_audio_stream(path)
	if stream != null:
		player.stream = stream


func _audio_path_candidates(path: String) -> Array[String]:
	if path == "":
		return []
	var candidates: Array[String] = [path]
	if path.ends_with(".wav"):
		candidates.append(path.substr(0, path.length() - 4) + ".ogg")
	elif path.ends_with(".ogg"):
		candidates.append(path.substr(0, path.length() - 4) + ".wav")
	return candidates


func _setup_bus_effects() -> void:
	_ambience_reverb_idx = _ensure_reverb_on_bus(&"Ambience")
	_sfx_reverb_idx = _ensure_reverb_on_bus(&"SFX")
	_ambience_duck_idx = _ensure_sidechain_compressor(&"Ambience", &"Music")


func _ensure_reverb_on_bus(bus_name: StringName) -> int:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectReverb:
			return i
	var reverb := AudioEffectReverb.new()
	reverb.dry = 1.0
	reverb.wet = 0.2
	reverb.room_size = 0.55
	AudioServer.add_bus_effect(bus_idx, reverb)
	return AudioServer.get_bus_effect_count(bus_idx) - 1


func _ensure_sidechain_compressor(bus_name: StringName, sidechain_bus: StringName) -> int:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return -1
	for i in AudioServer.get_bus_effect_count(bus_idx):
		var effect: AudioEffect = AudioServer.get_bus_effect(bus_idx, i)
		if effect is AudioEffectCompressor:
			var existing := effect as AudioEffectCompressor
			if existing.sidechain == sidechain_bus:
				return i
	var compressor := AudioEffectCompressor.new()
	compressor.sidechain = sidechain_bus
	compressor.threshold = -20.0
	compressor.ratio = 5.0
	compressor.attack_us = 120000.0
	compressor.release_ms = 750.0
	compressor.gain = 0.0
	compressor.mix = 1.0
	AudioServer.add_bus_effect(bus_idx, compressor)
	return AudioServer.get_bus_effect_count(bus_idx) - 1


func _apply_reverb_preset(preset_id: String) -> void:
	var preset: Dictionary = REVERB_PRESETS.get(preset_id, REVERB_PRESETS["indoor_castle"])
	_apply_reverb_to_bus(&"Ambience", preset, 1.0)
	_apply_reverb_to_bus(&"SFX", preset, 0.55)


func _apply_reverb_to_bus(bus_name: StringName, preset: Dictionary, wet_scale: float) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	var effect_idx := _ambience_reverb_idx if bus_name == &"Ambience" else _sfx_reverb_idx
	if effect_idx < 0 or effect_idx >= AudioServer.get_bus_effect_count(bus_idx):
		return
	var effect: AudioEffect = AudioServer.get_bus_effect(bus_idx, effect_idx)
	if not effect is AudioEffectReverb:
		return
	var reverb := effect as AudioEffectReverb
	reverb.wet = float(preset.get("wet", 0.2)) * wet_scale
	reverb.room_size = float(preset.get("room_size", 0.55))
	reverb.damping = float(preset.get("damping", 0.5))
	reverb.spread = float(preset.get("spread", 0.3))


func _fill_generator(player: AudioStreamPlayer, freq: float, phase: float) -> float:
	return _fill_generator_for_mode(player, freq, phase, _current_mode)


func _fill_generator_for_mode(
	player: AudioStreamPlayer,
	freq: float,
	phase: float,
	mode: String
) -> float:
	var playback: AudioStreamPlayback = player.get_stream_playback()
	if playback == null or not playback is AudioStreamGeneratorPlayback:
		return phase
	var gen_playback := playback as AudioStreamGeneratorPlayback
	var frames_available := gen_playback.get_frames_available()
	if frames_available <= 0:
		return phase
	var phase_step := freq * TAU / MIX_RATE
	for _i in frames_available:
		var sample := sin(phase) * 0.22 + sin(phase * 0.5) * 0.08
		if mode == "menu":
			var layer := player.name
			if layer == "MusicPlayer":
				sample = sin(phase) * 0.26 + sin(phase * 2.0) * 0.06
			elif layer == "ExplorePlayer":
				sample = sin(phase) * 0.18 + sin(phase * 1.5) * 0.1
			else:
				sample = sin(phase) * 0.14 + sin(phase * 0.5) * 0.06
		elif mode == "hub":
			var hub_layer := player.name
			if hub_layer == "AmbiencePlayer":
				sample = sin(phase) * 0.16 + sin(phase * 0.33) * 0.05
			elif hub_layer == "MusicPlayer":
				sample = sin(phase) * 0.2 + sin(phase * 0.66) * 0.08
			else:
				sample = sin(phase) * 0.12
		gen_playback.push_frame(Vector2(sample, sample))
		phase = fmod(phase + phase_step, TAU)
	return phase


var _pause_mix_active := false
var _saved_music_db := 0.0
var _saved_bus_mutes: Dictionary = {}


func set_pause_mix(enabled: bool) -> void:
	if enabled == _pause_mix_active:
		return
	_pause_mix_active = enabled
	if enabled:
		_saved_music_db = _music.volume_db if _music else 0.0
		if _music:
			_music.volume_db = _saved_music_db - 6.0
		for bus_name: StringName in [&"Ambience", &"SFX"]:
			var idx := AudioServer.get_bus_index(bus_name)
			if idx >= 0:
				_saved_bus_mutes[bus_name] = AudioServer.is_bus_mute(idx)
				AudioServer.set_bus_mute(idx, true)
		play_sfx("ui")
	else:
		if _music:
			_music.volume_db = _saved_music_db
		for bus_name: StringName in _saved_bus_mutes:
			var idx := AudioServer.get_bus_index(bus_name)
			if idx >= 0:
				AudioServer.set_bus_mute(idx, bool(_saved_bus_mutes[bus_name]))
		_saved_bus_mutes.clear()


func _restore_generator_streams() -> void:
	for player in [_explore, _combat_layer]:
		_assign_generator_stream(player)
	for player in [_ambience, _music]:
		if player.stream == null or player.stream is AudioStreamGenerator:
			_assign_generator_stream(player)


func _assign_generator_stream(player: AudioStreamPlayer) -> void:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = GENERATOR_BUFFER_SEC
	player.stream = generator
