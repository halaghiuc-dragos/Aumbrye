extends Node


const MIX_RATE := 44100.0
const DEFAULT_CROSSFADE := 0.8
const SFX_POOL_SIZE := 10
const SFX_3D_POOL_SIZE := 20
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

const CRITICAL_SFX := [
	"parry", "guard_break", "boss_reveal", "resource_denied", "windup_unblockable", "windup_grab",
]
const THREAT_SFX := ["windup", "swing", "door_seal", "portal_open"]
const IMPACT_SFX := ["hit", "hit_armor", "hit_poise_break", "block", "death"]
const DEFAULT_SPATIAL_POLICY := {"unit_size": 8.0, "max_distance": 28.0, "occlusion": true}
const THREAT_SPATIAL_POLICY := {"unit_size": 13.0, "max_distance": 46.0, "occlusion": true}

const LAYER_AMBIENCE := "ambience"
const LAYER_EXPLORE := "explore"
const LAYER_COMBAT := "combat"
const LAYER_BOSS := "boss"
const LAYER_KEYS: Array[String] = [LAYER_AMBIENCE, LAYER_EXPLORE, LAYER_COMBAT, LAYER_BOSS]

const LAYER_SILENCE_DB := -60.0
const LAYER_MAX_DB := 6.0

const LAYER_GAIN_CURVE := {
	LAYER_AMBIENCE: [[0.0, 1.0], [0.55, 0.8], [1.0, 0.5]],
	LAYER_EXPLORE: [[0.0, 1.0], [0.35, 0.55], [0.7, 0.0], [1.0, 0.0]],
	LAYER_COMBAT: [[0.0, 0.0], [0.2, 0.5], [0.6, 1.0], [0.85, 0.9], [1.0, 0.45]],
	LAYER_BOSS: [[0.0, 0.0], [0.78, 0.0], [1.0, 1.0]],
}

const INTENSITY_PER_ENGAGEMENT := 0.26
const INTENSITY_COMBAT_CAP := 0.72
const INTENSITY_LOW_VITALITY_BONUS := 0.18
const LOW_VITALITY_THRESHOLD := 0.35
const LOW_HP_CUTOFF_HZ := 1400.0
const OPEN_CUTOFF_HZ := 20500.0
const INTENSITY_EPSILON := 0.005
const COMBAT_RELEASE_HYSTERESIS := 2.0

var _ambience: AudioStreamPlayer
const MENU_THEME_PATH := "res://assets/audio/shared/title_theme.ogg"
const HUB_THEME_PATH := "res://assets/audio/shared/hub_theme.ogg"
const DEFAULT_STINGER_PATHS := {
	"boss_reveal": "res://assets/audio/shared/sting_boss.ogg",
	"floor_clear": "res://assets/audio/shared/sting_clear.ogg",
	"secret_found": "res://assets/audio/shared/sting_secret.ogg",
	"key_taken": "res://assets/audio/shared/sting_key.ogg",
	"lock_opened": "res://assets/audio/shared/sting_lock.ogg",
	"shortcut_opened": "res://assets/audio/shared/sting_shortcut.ogg",
	"rare_drop": "res://assets/audio/shared/sting_rare_drop.ogg",
	"personal_best": "res://assets/audio/shared/sting_personal_best.ogg",
	"hit_poise_break": "res://assets/audio/shared/sting_poise_break.ogg",
}

var _music: AudioStreamPlayer
var _explore: AudioStreamPlayer
var _combat_layer: AudioStreamPlayer
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
var _lowpass_cutoff := OPEN_CUTOFF_HZ
var _lowpass_tween: Tween
var _heartbeat_running := false
var _ambience_duck_idx := -1
var _sfx_bank: Dictionary = {}
var _sfx_streams: Dictionary = {}
var _sfx_surface_streams: Dictionary = {}
var _sfx_shuffle_bags: Dictionary = {}
var _sfx_last_played_ms: Dictionary = {}
var _sfx_active_counts: Dictionary = {}
var _missing_sfx_warned: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _layer_base_db: Dictionary = {}
var _intensity := 0.0
var _boss_active := false
var _player_vitality := 1.0
var _combat_release_pending := false
var _combat_release_token := 0
var _door_acoustic_state := false


func _exit_tree() -> void:
	var players: Array[Node] = [_music, _explore, _combat_layer, _ambience]
	players.append_array(_sfx_pool)
	players.append_array(_sfx_3d_pool)
	for node in players:
		if not is_instance_valid(node):
			continue
		if node.has_method("stop"):
			node.call("stop")
		node.set("stream", null)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	set_process(true)
	_rng.randomize()
	AudioSettings.load_from_save()
	_setup_bus_effects()
	_load_sfx_bank()
	_ambience = _create_player("AmbiencePlayer", &"Ambience")
	_music = _create_player("MusicPlayer", &"Music")
	_explore = _create_player("ExplorePlayer", &"Music")
	_combat_layer = _create_player("CombatPlayer", &"Music")
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
	for i in SFX_3D_POOL_SIZE:
		var player3d := AudioStreamPlayer3D.new()
		player3d.name = "Sfx3dPlayer%d" % i
		player3d.bus = &"SFX"
		player3d.max_distance = 24.0
		add_child(player3d)
		_sfx_3d_pool.append(player3d)


func set_biome(biome_id: String) -> void:
	var next_profile := ContentLoader.load_json(BiomeRegistry.get_audio_profile_path(biome_id))
	if next_profile.is_empty():
		next_profile = {
			"ambienceFreq": 110.0,
			"bossFreq": 196.0,
			"crossfadeSeconds": DEFAULT_CROSSFADE,
		}
	var next_streams := _resolve_profile_streams(next_profile)
	_current_biome = biome_id
	_profile = next_profile
	_crossfade = float(_profile.get("crossfadeSeconds", DEFAULT_CROSSFADE))
	_ambience.stream = next_streams[LAYER_AMBIENCE]
	_bind_music_stems(next_streams[LAYER_EXPLORE], next_streams[LAYER_COMBAT])
	_music.stream = next_streams[LAYER_BOSS]
	_load_layer_mix_metadata()
	var reverb_preset: String = str(_profile.get("reverbPreset", BIOME_REVERB_PRESETS.get(biome_id, "indoor_castle")))
	_apply_reverb_preset(reverb_preset)


func _load_layer_mix_metadata() -> void:
	_layer_base_db.clear()
	var layers: Dictionary = _profile.get("layers", {})
	for layer in LAYER_KEYS:
		var player := _player_for_layer(layer)
		if player == null:
			continue
		var entry: Dictionary = layers.get(layer, {})
		_layer_base_db[layer] = float(entry.get("volume_db", 0.0))


func _resolve_profile_streams(profile: Dictionary) -> Dictionary:
	var layers: Dictionary = profile.get("layers", {})
	var paths := {
		LAYER_AMBIENCE: str(profile.get("ambiencePath", "")),
		LAYER_EXPLORE: str((layers.get(LAYER_EXPLORE, {}) as Dictionary).get("path", "")),
		LAYER_COMBAT: str((layers.get(LAYER_COMBAT, {}) as Dictionary).get("path", "")),
		LAYER_BOSS: str(profile.get("bossPath", "")),
	}
	var resolved := {}
	for layer in LAYER_KEYS:
		var stream := _load_audio_stream(paths[layer]) if paths[layer] != "" else null
		if stream == null and paths[layer] != "":
			push_warning("AudioDirector: missing audio file '%s' for the %s layer" % [paths[layer], layer])
		resolved[layer] = stream
	return resolved


const STEM_INDEX := {LAYER_EXPLORE: 0, LAYER_COMBAT: 1}

var _stem_sync: AudioStreamSynchronized
var _stem_db: Dictionary = {}
var _stem_tweens: Dictionary = {}


## Explore and combat are two recordings of one piece. On separate players each starts whenever it
## becomes audible and they drift apart; inside one synchronized stream they share a clock and only
## their volumes move. The explore player carries both; the combat player stays empty.
func _bind_music_stems(explore_stream: AudioStream, combat_stream: AudioStream) -> void:
	_stem_sync = null
	if (
		explore_stream == null
		or combat_stream == null
	):
		_explore.stream = explore_stream
		_combat_layer.stream = combat_stream
		return
	var sync := AudioStreamSynchronized.new()
	sync.stream_count = 2
	sync.set_sync_stream(STEM_INDEX[LAYER_EXPLORE], explore_stream)
	sync.set_sync_stream(STEM_INDEX[LAYER_COMBAT], combat_stream)
	_stem_sync = sync
	_explore.stream = sync
	_combat_layer.stream = null
	_reset_stems()


func _reset_stems() -> void:
	for layer: String in STEM_INDEX:
		if _stem_tweens.has(layer):
			var tween: Tween = _stem_tweens[layer]
			if tween and tween.is_valid():
				tween.kill()
			_stem_tweens.erase(layer)
		_set_stem_db(layer, LAYER_SILENCE_DB)


func _set_stem_db(layer: String, db: float) -> void:
	_stem_db[layer] = db
	if _stem_sync != null:
		_stem_sync.set_sync_stream_volume(int(STEM_INDEX[layer]), db)


func _tween_stem(layer: String, gain: float, duration: float) -> void:
	var target_db := LAYER_SILENCE_DB
	if gain > 0.001:
		var base_db := float(_layer_base_db.get(layer, 0.0))
		target_db = clampf(base_db + linear_to_db(gain), LAYER_SILENCE_DB, LAYER_MAX_DB)
	if not _explore.playing:
		_kill_tween(_explore)
		_reset_stems()
		_explore.volume_db = 0.0
		_explore.stream_paused = false
		_explore.play()
	if _stem_tweens.has(layer):
		var previous: Tween = _stem_tweens[layer]
		if previous and previous.is_valid():
			previous.kill()
	var tween := create_tween()
	_stem_tweens[layer] = tween
	tween.tween_method(
		func(db: float) -> void: _set_stem_db(layer, db),
		float(_stem_db.get(layer, LAYER_SILENCE_DB)),
		target_db,
		maxf(0.05, duration)
	)


func _player_for_layer(layer: String) -> AudioStreamPlayer:
	if layer == LAYER_AMBIENCE:
		return _ambience
	if layer == LAYER_EXPLORE:
		return _explore
	if layer == LAYER_COMBAT:
		return _combat_layer
	if layer == LAYER_BOSS:
		return _music
	return null


func _sample_curve(points: Array, x: float) -> float:
	if points.is_empty():
		return 0.0
	var first: Array = points[0]
	if x <= float(first[0]):
		return float(first[1])
	for i in range(1, points.size()):
		var prev: Array = points[i - 1]
		var next: Array = points[i]
		var x0 := float(prev[0])
		var x1 := float(next[0])
		if x > x1:
			continue
		if x1 - x0 <= 0.0001:
			return float(next[1])
		var t := (x - x0) / (x1 - x0)
		return lerpf(float(prev[1]), float(next[1]), t)
	var last: Array = points[points.size() - 1]
	return float(last[1])


func _is_layered_mode() -> bool:
	return _current_mode == "dungeon" or _current_mode == "boss"


func _recompute_intensity(duration: float) -> void:
	var target := 0.0
	if _boss_active:
		target = 1.0
	elif _combat_engagements > 0 or _combat_release_pending:
		target = minf(float(_combat_engagements) * INTENSITY_PER_ENGAGEMENT, INTENSITY_COMBAT_CAP)
		if _player_vitality <= LOW_VITALITY_THRESHOLD:
			target = minf(INTENSITY_COMBAT_CAP, target + INTENSITY_LOW_VITALITY_BONUS)
	if absf(target - _intensity) < INTENSITY_EPSILON:
		return
	_intensity = target
	_apply_layer_mix(duration)


func _apply_layer_mix(duration: float) -> void:
	if not _is_layered_mode():
		return
	for layer in LAYER_KEYS:
		var player := _player_for_layer(layer)
		if player == null:
			continue
		_tween_layer(player, layer, _sample_curve(LAYER_GAIN_CURVE[layer], _intensity), duration)


func _tween_layer(
	player: AudioStreamPlayer, layer: String, gain: float, duration: float
) -> void:
	if _stem_sync != null and STEM_INDEX.has(layer):
		_tween_stem(layer, gain, duration)
		return
	if player.stream == null:
		return
	var audible := gain > 0.001
	var target_db := LAYER_SILENCE_DB
	if audible:
		var base_db := float(_layer_base_db.get(layer, 0.0))
		target_db = clampf(base_db + linear_to_db(gain), LAYER_SILENCE_DB, LAYER_MAX_DB)
	_kill_tween(player)
	if not player.playing:
		player.volume_db = LAYER_SILENCE_DB
		player.stream_paused = false
		player.play()
	var tween := create_tween()
	_active_tweens[player] = tween
	tween.tween_property(player, "volume_db", target_db, maxf(0.05, duration))


func notify_player_vitality(ratio: float) -> void:
	var clamped := clampf(ratio, 0.0, 1.0)
	if absf(clamped - _player_vitality) < 0.01:
		return
	var was_low := _player_vitality <= LOW_VITALITY_THRESHOLD
	_player_vitality = clamped
	if was_low != (clamped <= LOW_VITALITY_THRESHOLD):
		_recompute_intensity(_crossfade * 1.5)
	_apply_vitality_dsp()


## Near death the world goes muffled and a heartbeat takes over: the music and ambience lose their
## top end in proportion to how little health is left, and a pulse quickens as it falls.
func _apply_vitality_dsp() -> void:
	var fight_on := _current_mode in ["dungeon", "boss"]
	var low := fight_on and _player_vitality <= LOW_VITALITY_THRESHOLD
	var depth := clampf(1.0 - _player_vitality / LOW_VITALITY_THRESHOLD, 0.0, 1.0) if low else 0.0
	var target_cutoff := exp(lerpf(log(OPEN_CUTOFF_HZ), log(LOW_HP_CUTOFF_HZ), depth))
	if _lowpass_tween != null and _lowpass_tween.is_valid():
		_lowpass_tween.kill()
	_lowpass_tween = create_tween()
	_lowpass_tween.tween_method(_set_lowpass_cutoff, _lowpass_cutoff, target_cutoff, 0.6)
	if low and not _heartbeat_running:
		_heartbeat_running = true
		_heartbeat_tick()
	elif not low:
		_heartbeat_running = false


func _set_lowpass_cutoff(cutoff: float) -> void:
	_lowpass_cutoff = cutoff
	for bus_name: StringName in [&"Music", &"Ambience"]:
		var bus_idx := AudioServer.get_bus_index(bus_name)
		if bus_idx < 0:
			continue
		for i in AudioServer.get_bus_effect_count(bus_idx):
			var effect := AudioServer.get_bus_effect(bus_idx, i) as AudioEffectLowPassFilter
			if effect != null:
				effect.cutoff_hz = cutoff


func _heartbeat_tick() -> void:
	if not _heartbeat_running:
		return
	play_sfx("heartbeat")
	var depth := clampf(1.0 - _player_vitality / LOW_VITALITY_THRESHOLD, 0.0, 1.0)
	get_tree().create_timer(lerpf(1.15, 0.7, depth), true).timeout.connect(_heartbeat_tick)


func play_dungeon_ambience() -> void:
	_current_mode = "dungeon"
	_combat_engagements = 0
	_boss_active = false
	_player_vitality = 1.0
	_apply_vitality_dsp()
	_intensity = 0.0
	_apply_layer_mix(_crossfade)


func play_menu_music() -> void:
	_current_mode = "menu"
	_combat_engagements = 0
	_boss_active = false
	_intensity = 0.0
	_layer_base_db.clear()
	# Keep an already-playing title stream intact. Forcing a generator swap here created orphaned
	# Ogg playback sequences every time the menu was reopened.
	_try_load_file_stream(_music, MENU_THEME_PATH)
	_apply_reverb_preset("cathedral")
	_fade_out_player(_combat_layer, _crossfade)
	_fade_out_player(_ambience, _crossfade)
	_fade_out_player(_explore, _crossfade)
	_fade_in_player(_music)


func play_hub_ambience() -> void:
	_current_mode = "hub"
	_combat_engagements = 0
	_boss_active = false
	_intensity = 0.0
	_layer_base_db.clear()
	# The hub's sound is its theme, the weather and the props' own loops; the ambience and combat
	# layers stay empty rather than fall back to a synthesised drone.
	for layer in [_ambience, _explore, _combat_layer]:
		layer.stop()
		layer.stream = null
	_try_load_file_stream(_music, HUB_THEME_PATH)
	_apply_reverb_preset("umbral")
	_fade_out_player(_combat_layer, _crossfade)
	_fade_out_player(_explore, _crossfade)
	_fade_in_player(_ambience)
	_fade_in_player(_music)


func play_boss_music() -> void:
	_current_mode = "boss"
	_combat_engagements = 0
	_boss_active = true
	_intensity = 1.0
	_apply_layer_mix(_crossfade)


func set_boss_phase(phase_index: int, music_path: String = "") -> void:
	if not _boss_active:
		return
	if music_path != "":
		_try_load_file_stream(_music, music_path)
		_fade_in_player(_music)
	if phase_index > 0:
		play_sfx("boss_reveal")


func end_boss_music() -> void:
	if not _boss_active:
		return
	_boss_active = false
	_current_mode = "dungeon"
	_intensity = -1.0
	var boss_path: String = _profile.get("bossPath", "")
	if boss_path != "":
		_try_load_file_stream(_music, boss_path)
	_recompute_intensity(_crossfade * 1.5)


func register_combat_engagement() -> void:
	if _current_mode != "dungeon":
		return
	_combat_engagements += 1
	_cancel_combat_release()
	_recompute_intensity(_crossfade)


func unregister_combat_engagement() -> void:
	if _current_mode != "dungeon":
		return
	_combat_engagements = maxi(0, _combat_engagements - 1)
	if _combat_engagements == 0:
		_start_combat_release()
	else:
		_recompute_intensity(_crossfade * 1.5)


## The combat layer lets go a moment after the last engagement ends. This is a tree timer and not
## a countdown in `_process`: that stops the moment no generator stream is playing.
func _start_combat_release() -> void:
	_combat_release_pending = true
	_combat_release_token += 1
	get_tree().create_timer(COMBAT_RELEASE_HYSTERESIS).timeout.connect(
		_finish_combat_release.bind(_combat_release_token)
	)


func _cancel_combat_release() -> void:
	_combat_release_pending = false
	_combat_release_token += 1


func _finish_combat_release(token: int) -> void:
	if token != _combat_release_token:
		return
	_combat_release_pending = false
	_recompute_intensity(_crossfade * 1.5)


func stop_all(fade: float = 0.3) -> void:
	_current_mode = "none"
	_combat_engagements = 0
	_cancel_combat_release()
	_boss_active = false
	_intensity = 0.0
	_player_vitality = 1.0
	_apply_vitality_dsp()
	_fade_out_player(_ambience, fade)
	_fade_out_player(_music, fade)
	_fade_out_player(_explore, fade)
	_fade_out_player(_combat_layer, fade)


func set_door_acoustic_state(closed: bool) -> void:
	if _door_acoustic_state == closed:
		return
	_door_acoustic_state = closed
	var preset_id := str(_profile.get("reverbPreset", BIOME_REVERB_PRESETS.get(_current_biome, "indoor_castle")))
	var preset: Dictionary = REVERB_PRESETS.get(preset_id, REVERB_PRESETS["indoor_castle"]).duplicate()
	if closed:
		preset["wet"] = float(preset.get("wet", 0.2)) * 0.72
		preset["damping"] = minf(0.9, float(preset.get("damping", 0.5)) + 0.2)
	_apply_reverb_preset_values(preset)


func play_combat_sfx(kind: String, world_pos: Variant = null, surface: String = "stone") -> void:
	play_sfx(kind, world_pos, surface)


func play_sfx(kind: String, world_pos: Variant = null, surface: String = "stone") -> void:
	var entry: Dictionary = _sfx_bank.get(kind, {})
	if not _can_play_sfx(kind, entry):
		return
	var streams: Array = _sfx_streams.get(kind, [])
	if streams.is_empty():
		_warn_missing_sfx(kind)
		_mark_sfx_played(kind)
		_duck_for_threat(kind, entry)
		return
	var stream: AudioStream = _pick_sfx_stream(kind, entry, surface)
	if stream == null:
		_warn_missing_sfx(kind)
		_mark_sfx_played(kind)
		_duck_for_threat(kind, entry)
		return
	_play_stream(stream, world_pos, entry, kind, 0.0, _pitch_variant(kind, entry))
	_mark_sfx_played(kind)
	_play_supporting_layers(entry, world_pos, surface)
	_duck_for_threat(kind, entry)


func play_ui_sfx() -> void:
	play_sfx("ui")


func preview_bus(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		play_ui_sfx()
		return
	# A click is the preview: it is routed through the bus being adjusted by the cue's own bus.
	play_ui_sfx()


func play_cue(cue_name: StringName, world_pos: Variant = null) -> void:
	play_sfx(String(cue_name), world_pos)


func play_stinger(stinger_id: String) -> void:
	var stingers: Dictionary = _profile.get("stingers", {})
	var path := str(stingers.get(stinger_id, DEFAULT_STINGER_PATHS.get(stinger_id, "")))
	var stream: AudioStream = _load_audio_stream(path) if path != "" else null
	if stream != null:
		_play_stream_2d(stream, &"Music", 0.0, 1.0)
	else:
		play_sfx(stinger_id)
		# Only a stinger with no authored file borrows a chord; stacking one on a real file
		# muddies it.
	var duck_players: Array[AudioStreamPlayer] = []
	for layer in [LAYER_EXPLORE, LAYER_COMBAT, LAYER_BOSS]:
		var player := _player_for_layer(layer)
		if player != null and player.playing:
			duck_players.append(player)
	for player in duck_players:
		_kill_tween(player)
		var baseline := _layer_target_db(_layer_for_player(player))
		var duck := create_tween()
		_active_tweens[player] = duck
		duck.tween_property(player, "volume_db", baseline - 8.0, 0.08)
		duck.tween_property(player, "volume_db", baseline, 1.2)


func _layer_for_player(player: AudioStreamPlayer) -> String:
	for layer in LAYER_KEYS:
		if _player_for_layer(layer) == player:
			return layer
	return LAYER_BOSS


func _layer_target_db(layer: String) -> float:
	if _stem_sync != null and STEM_INDEX.has(layer):
		return 0.0
	var points: Array = LAYER_GAIN_CURVE.get(layer, [])
	var gain := _sample_curve(points, _intensity)
	if gain <= 0.001:
		return LAYER_SILENCE_DB
	var base_db := float(_layer_base_db.get(layer, 0.0))
	return clampf(base_db + linear_to_db(gain), LAYER_SILENCE_DB, LAYER_MAX_DB)


func _pitch_variant(_kind: String, entry: Dictionary) -> float:
	var variants: Variant = entry.get("pitch_variants", [])
	if not variants is Array or (variants as Array).is_empty():
		return 1.0
	var values: Array = variants
	# `pitch_variants` are semitone offsets; fractions stay subtle enough for foley.
	var semitones := float(values[_rng.randi_range(0, values.size() - 1)])
	return pow(2.0, semitones / 12.0)


func _play_supporting_layers(entry: Dictionary, world_pos: Variant, surface: String) -> void:
	var layers: Variant = entry.get("layers", [])
	if not layers is Array:
		return
	for raw_layer in layers:
		if not raw_layer is Dictionary:
			continue
		var layer: Dictionary = raw_layer
		if _rng.randf() > float(layer.get("chance", 1.0)):
			continue
		var key := str(layer.get("key", ""))
		if key.is_empty():
			continue
		var support_entry: Dictionary = _sfx_bank.get(key, {})
		if not _can_play_sfx(key, support_entry):
			continue
		var support_stream := _pick_sfx_stream(key, support_entry, surface)
		if support_stream == null:
			continue
		_play_stream(
			support_stream,
			world_pos,
			support_entry,
			key,
			float(layer.get("volume_db", -12.0)),
			float(layer.get("pitch", 1.0)) * _pitch_variant(key, support_entry)
		)
		_mark_sfx_played(key)


func play_biome_accent(biome_id: String, world_pos: Vector3) -> void:
	var profile := _biome_accent_profile(biome_id)
	var stream := _make_biome_accent_stream(profile)
	_play_stream(stream, world_pos, {"bus": "Ambience", "volume_db": -18.0, "max_concurrent": 2}, "biome_accent")


func _biome_accent_profile(biome_id: String) -> Dictionary:
	match biome_id:
		"crystal_caverns", "prism_depths":
			return {"freq": 620.0, "duration": 0.72, "shimmer": 1.0, "noise": 0.04}
		"poison_swamp", "venom_mire":
			return {"freq": 92.0, "duration": 0.9, "shimmer": 0.15, "noise": 0.24}
		"frozen_fortress", "glacial_hollow":
			return {"freq": 148.0, "duration": 1.0, "shimmer": 0.45, "noise": 0.18}
		"iron_vault":
			return {"freq": 118.0, "duration": 0.64, "shimmer": 0.68, "noise": 0.08}
		"dark_cathedral", "umbral_chapel":
			return {"freq": 174.0, "duration": 0.88, "shimmer": 0.52, "noise": 0.05}
		_:
			return {"freq": 126.0, "duration": 0.72, "shimmer": 0.28, "noise": 0.12}


func _make_biome_accent_stream(profile: Dictionary) -> AudioStreamWAV:
	var seconds := float(profile.get("duration", 0.7))
	var frames := maxi(1, int(MIX_RATE * seconds))
	var freq := float(profile.get("freq", 120.0)) * _rng.randf_range(0.92, 1.08)
	var shimmer := float(profile.get("shimmer", 0.3))
	var noise_amount := float(profile.get("noise", 0.1))
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var progress := float(i) / float(frames)
		var envelope := minf(progress / 0.08, pow(1.0 - progress, 1.35))
		var phase := TAU * freq * float(i) / MIX_RATE
		var sample := sin(phase) * 0.16
		sample += sin(phase * (1.5 + shimmer * 0.5)) * (0.05 + shimmer * 0.04)
		sample += _rng.randf_range(-1.0, 1.0) * noise_amount * 0.045
		data.encode_s16(i * 2, int(clampf(sample * envelope, -1.0, 1.0) * 32767.0))
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = int(MIX_RATE)
	stream.data = data
	return stream


func has_sfx(kind: String) -> bool:
	_cache_sfx_kind(kind)
	return _sfx_streams.has(kind) and not (_sfx_streams[kind] as Array).is_empty()


## Whether `kind` is a declared cue in `sfx.json`, as opposed to `has_sfx()`, which is only true once
## its audio files actually load. Callers building a cue name from content (a per-enemy voice prefix)
## use this to decide whether the specific cue is worth playing.
func has_sfx_entry(kind: String) -> bool:
	return _sfx_bank.has(kind)


func attach_loop_emitter(host: Node3D, key: String, radius: float = 6.0) -> AudioStreamPlayer3D:
	var player := AudioStreamPlayer3D.new()
	player.name = "LoopEmitter_%s" % key
	player.unit_size = radius
	player.max_distance = radius * 3.0
	_cache_sfx_kind(key)
	var entry: Dictionary = _sfx_bank.get(key, {})
	player.bus = StringName(str(entry.get("bus", "Ambience")))
	player.volume_db = float(entry.get("volume_db", 0.0))
	var streams: Array = _sfx_streams.get(key, [])
	if streams.is_empty():
		_warn_missing_sfx(key)
	else:
		var stream := streams[0] as AudioStream
		if stream is AudioStreamWAV:
			var looped := (stream as AudioStreamWAV).duplicate(true) as AudioStreamWAV
			looped.loop_mode = AudioStreamWAV.LOOP_FORWARD
			stream = looped
		player.stream = stream
		player.autoplay = true
	host.add_child(player)
	if player.stream != null and not player.playing:
		player.play()
	return player


func _load_sfx_bank() -> void:
	var bank_data := ContentLoader.load_json(SFX_BANK_PATH)
	_sfx_bank = bank_data.get("sfx", {})
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
	var entry: Dictionary = _sfx_bank.get(kind, {})
	var banks := {}
	for surface in (entry.get("surface_variants", {}) as Dictionary):
		var bank: Array[AudioStream] = []
		for path in entry["surface_variants"][surface]:
			var stream := _load_audio_stream(str(path))
			if stream != null:
				bank.append(stream)
		if not bank.is_empty():
			banks[str(surface)] = bank
	if not banks.is_empty():
		_sfx_surface_streams[kind] = banks


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
	return paths


func _pick_sfx_stream(kind: String, _entry: Dictionary, surface: String) -> AudioStream:
	var streams: Array = _sfx_streams.get(kind, [])
	if streams.is_empty():
		return null
	var bank_key := "%s:%s" % [kind, surface]
	var surface_banks: Dictionary = _sfx_surface_streams.get(kind, {})
	var bank: Array = surface_banks.get(surface, streams)
	if bank.is_empty():
		return null
	var bag: Array = _sfx_shuffle_bags.get(bank_key, [])
	if bag.is_empty():
		bag = bank.duplicate()
		# Fisher-Yates uses this service's seeded runtime RNG and exhausts every variant before reuse.
		for i in range(bag.size() - 1, 0, -1):
			var j := _rng.randi_range(0, i)
			var swap: Variant = bag[i]
			bag[i] = bag[j]
			bag[j] = swap
	_sfx_shuffle_bags[bank_key] = bag
	return (_sfx_shuffle_bags[bank_key] as Array).pop_back() as AudioStream


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


func _cue_priority(kind: String, entry: Dictionary) -> int:
	if entry.has("priority"):
		return int(entry["priority"])
	if kind in CRITICAL_SFX:
		return 3
	if kind in THREAT_SFX:
		return 2
	if kind in IMPACT_SFX or kind.begins_with("hit_"):
		return 1
	return 0


func _prepare_voice(player: Node, kind: String, priority: int) -> void:
	var old_finished_callback: Variant = (
		player.get_meta(&"sfx_finished_callback") if player.has_meta(&"sfx_finished_callback") else null
	)
	if old_finished_callback is Callable and player.finished.is_connected(old_finished_callback):
		player.finished.disconnect(old_finished_callback)
	# Release clears its metadata, including the callback. Disconnect first so a pooled voice cannot
	# accumulate one one-shot listener per reuse and then report an already-connected error.
	_release_voice_owner(player)
	var generation := int(player.get_meta(&"sfx_generation", 0)) + 1
	player.set_meta(&"sfx_generation", generation)
	player.set_meta(&"sfx_kind", kind)
	player.set_meta(&"sfx_priority", priority)
	player.set_meta(&"sfx_started_ms", Time.get_ticks_msec())
	_sfx_active_counts[kind] = int(_sfx_active_counts.get(kind, 0)) + 1
	var finished_callback := _on_voice_finished_generation.bind(player, generation)
	player.set_meta(&"sfx_finished_callback", finished_callback)
	player.finished.connect(finished_callback, CONNECT_ONE_SHOT)


func _release_voice_owner(player: Node) -> void:
	var old_kind := str(player.get_meta(&"sfx_kind", ""))
	if old_kind != "":
		_sfx_active_counts[old_kind] = maxi(0, int(_sfx_active_counts.get(old_kind, 0)) - 1)
	for key in [&"sfx_kind", &"sfx_priority", &"sfx_started_ms", &"sfx_finished_callback"]:
		if player.has_meta(key):
			player.remove_meta(key)


func _on_voice_finished_generation(player: Node, generation: int) -> void:
	if int(player.get_meta(&"sfx_generation", -1)) == generation:
		_release_voice_owner(player)


func _play_stream(
	stream: AudioStream,
	world_pos: Variant,
	entry: Dictionary,
	kind: String,
	volume_offset_db: float = 0.0,
	pitch_multiplier: float = 1.0
) -> void:
	var bus: StringName = &"SFX"
	if entry.has("bus"):
		bus = StringName(str(entry["bus"]))
	bus = _routed_bus(kind, bus)
	var priority := _cue_priority(kind, entry)
	# Critical telegraphs and clean impacts should win the mix, even in a dense room.  The gain is
	# deliberately small: this is clarity, not a permanent loudness war against ambience.
	var clarity_boost := 1.25 if priority >= 3 else (0.65 if priority >= 2 else 0.0)
	var volume_db := float(entry.get("volume_db", 0.0)) + volume_offset_db + clarity_boost
	var pitch_jitter := float(entry.get("pitch_jitter", 0.0))
	var pitch_scale := float(entry.get("pitch", 1.0)) * pitch_multiplier
	if pitch_jitter > 0.0:
		pitch_scale *= 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	if world_pos is Vector3:
		var player3d := _acquire_sfx_3d_player(priority, world_pos)
		if player3d == null:
			_play_stream_2d(stream, bus, volume_db, pitch_scale, kind, entry)
			return
		_prepare_voice(player3d, kind, priority)
		player3d.global_position = world_pos
		player3d.bus = bus
		player3d.volume_db = volume_db + _configure_spatial_voice(player3d, entry, kind, world_pos)
		player3d.pitch_scale = pitch_scale
		player3d.stream = stream
		player3d.play()
	else:
		_play_stream_2d(stream, bus, volume_db, pitch_scale, kind, entry)


func _configure_spatial_voice(
	player: AudioStreamPlayer3D, entry: Dictionary, kind: String, world_pos: Vector3
) -> float:
	var policy: Dictionary = THREAT_SPATIAL_POLICY if _cue_priority(kind, entry) >= 2 else DEFAULT_SPATIAL_POLICY
	var authored: Variant = entry.get("spatial", {})
	if authored is Dictionary:
		policy = policy.merged(authored, true)
	player.unit_size = maxf(0.5, float(policy.get("unit_size", 8.0)))
	player.max_distance = maxf(player.unit_size, float(policy.get("max_distance", 28.0)))
	if not bool(policy.get("occlusion", true)) or not _is_occluded(world_pos):
		return 0.0
	return float(policy.get("occluded_volume_db", -9.0))


## Where the player is listening from: the player's own `AudioListener3D`, or the camera when the
## scene has no player.
func _listener_position() -> Variant:
	var listener := get_tree().get_first_node_in_group("audio_listener") as Node3D
	if listener != null and listener.is_inside_tree():
		return listener.global_position
	var camera := PixelDioramaViewport.get_gameplay_camera()
	if camera != null:
		return camera.global_position
	return null


func _is_occluded(world_pos: Vector3) -> bool:
	var origin: Variant = _listener_position()
	if origin == null:
		return false
	var camera := PixelDioramaViewport.get_gameplay_camera()
	if camera == null:
		return false
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(origin as Vector3, world_pos)
	query.collision_mask = CombatLayers.WORLD_OCCLUDERS
	query.collide_with_areas = false
	query.collide_with_bodies = true
	return not space.intersect_ray(query).is_empty()


func _play_stream_2d(
	stream: AudioStream,
	bus: StringName,
	volume_db: float,
	pitch_scale: float,
	kind: String = "",
	entry: Dictionary = {}
) -> void:
	var player := _acquire_sfx_player(_cue_priority(kind, entry))
	if player == null:
		return
	if kind != "":
		_prepare_voice(player, kind, _cue_priority(kind, entry))
	player.bus = bus
	player.volume_db = volume_db
	player.pitch_scale = pitch_scale
	player.stream = stream
	player.play()


func _duck_for_threat(kind: String, entry: Dictionary) -> void:
	if _cue_priority(kind, entry) < 2:
		return
	var attenuation := float(entry.get("duck_music_db", -4.0))
	for layer in [LAYER_EXPLORE, LAYER_COMBAT, LAYER_BOSS]:
		var player := _player_for_layer(layer)
		if player == null or not player.playing:
			continue
		_kill_tween(player)
		var baseline := _layer_target_db(layer)
		var tween := create_tween()
		_active_tweens[player] = tween
		tween.tween_property(player, "volume_db", baseline + attenuation, 0.04)
		tween.tween_property(player, "volume_db", baseline, 0.28)


func _warn_missing_sfx(kind: String) -> void:
	if OS.is_debug_build() and not _missing_sfx_warned.has(kind):
		_missing_sfx_warned[kind] = true
		push_warning("AudioDirector: missing authored SFX for '%s'" % kind)


func _acquire_sfx_player(request_priority: int = 0) -> AudioStreamPlayer:
	for player in _sfx_pool:
		if not player.playing:
			return player
	var candidate: AudioStreamPlayer = null
	for player in _sfx_pool:
		if int(player.get_meta(&"sfx_priority", 0)) > request_priority:
			continue
		if candidate == null or int(player.get_meta(&"sfx_started_ms", 0)) < int(candidate.get_meta(&"sfx_started_ms", 0)):
			candidate = player
	return candidate


func _acquire_sfx_3d_player(
	request_priority: int = 0, world_pos: Vector3 = Vector3.ZERO
) -> AudioStreamPlayer3D:
	for player in _sfx_3d_pool:
		if not player.playing:
			return player
	var candidate: AudioStreamPlayer3D = null
	var candidate_score := INF
	var listener: Variant = _listener_position()
	for player in _sfx_3d_pool:
		var priority := int(player.get_meta(&"sfx_priority", 0))
		if priority > request_priority:
			continue
		var distance := (
			(listener as Vector3).distance_to(player.global_position)
			if listener != null else player.global_position.distance_to(world_pos)
		)
		var age := float(Time.get_ticks_msec() - int(player.get_meta(&"sfx_started_ms", 0))) / 1000.0
		var score := float(priority) * 100.0 - distance - age * 4.0
		if candidate == null or score < candidate_score:
			candidate = player
			candidate_score = score
	return candidate


func _load_audio_stream(path: String) -> AudioStream:
	for candidate in _audio_path_candidates(path):
		if not ResourceLoader.exists(candidate):
			continue
		var loaded: Variant = ResourceLoader.load(candidate)
		if loaded is AudioStream:
			return loaded
	return null


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


func _create_player(player_name: String, bus: StringName) -> AudioStreamPlayer:
	var player := AudioStreamPlayer.new()
	player.name = player_name
	player.bus = bus
	player.volume_db = 0.0
	player.autoplay = false
	return player


func _try_load_file_stream(player: AudioStreamPlayer, path: String) -> void:
	var stream := _load_audio_stream(path)
	if stream == null or player.stream == stream:
		return
	player.stop()
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
	_ensure_sfx_subbuses()
	_ensure_low_pass(&"Music")
	_ensure_low_pass(&"Ambience")
	_ensure_master_limiter()


func _ensure_low_pass(bus_name: StringName) -> void:
	var bus_idx := AudioServer.get_bus_index(bus_name)
	if bus_idx < 0:
		return
	for i in AudioServer.get_bus_effect_count(bus_idx):
		if AudioServer.get_bus_effect(bus_idx, i) is AudioEffectLowPassFilter:
			return
	var filter := AudioEffectLowPassFilter.new()
	filter.cutoff_hz = OPEN_CUTOFF_HZ
	AudioServer.add_bus_effect(bus_idx, filter)


## Twenty spatial voices and the music can stack past full scale in a fight; the limiter holds the
## master under it.
## The player's own sounds, the enemies' and the voices each get a bus under SFX, so a busy fight
## can be balanced by source and the SFX volume setting still moves all of them.
const SFX_SUBBUSES: Array[StringName] = [&"Player", &"Enemies", &"Voice"]
const CUE_SUBBUS_BY_PREFIX := {
	"footstep": &"Player",
	"swing": &"Player",
	"dodge": &"Player",
	"block": &"Player",
	"parry": &"Player",
	"heal": &"Player",
	"guard": &"Player",
	"exhausted": &"Player",
	"windup": &"Enemies",
	"death": &"Enemies",
	"npc_murmur": &"Voice",
}


func _ensure_sfx_subbuses() -> void:
	for bus_name in SFX_SUBBUSES:
		if AudioServer.get_bus_index(bus_name) >= 0:
			continue
		AudioServer.add_bus()
		var idx := AudioServer.get_bus_count() - 1
		AudioServer.set_bus_name(idx, bus_name)
		AudioServer.set_bus_send(idx, &"SFX")


func _routed_bus(kind: String, bus: StringName) -> StringName:
	if bus != &"SFX":
		return bus
	for prefix: String in CUE_SUBBUS_BY_PREFIX:
		if kind.begins_with(prefix):
			var target: StringName = CUE_SUBBUS_BY_PREFIX[prefix]
			return target if AudioServer.get_bus_index(target) >= 0 else bus
	return bus


func _ensure_master_limiter() -> void:
	var master := AudioServer.get_bus_index(&"Master")
	if master < 0:
		return
	for i in AudioServer.get_bus_effect_count(master):
		if AudioServer.get_bus_effect(master, i) is AudioEffectLimiter:
			return
	var limiter := AudioEffectLimiter.new()
	limiter.ceiling_db = -1.0
	limiter.threshold_db = -6.0
	AudioServer.add_bus_effect(master, limiter)


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
	_apply_reverb_preset_values(preset)


func _apply_reverb_preset_values(preset: Dictionary) -> void:
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


var _pause_mix_active := false
var _saved_music_layers: Dictionary = {}
var _saved_bus_mutes: Dictionary = {}


func set_pause_mix(enabled: bool) -> void:
	if enabled == _pause_mix_active:
		return
	_pause_mix_active = enabled
	if enabled:
		_saved_music_layers.clear()
		for layer in [LAYER_EXPLORE, LAYER_COMBAT, LAYER_BOSS]:
			var player := _player_for_layer(layer)
			if player == null or not player.playing:
				continue
			_saved_music_layers[layer] = player.volume_db
			_kill_tween(player)
			player.volume_db -= 6.0
		for bus_name: StringName in [&"Ambience", &"SFX"]:
			var idx := AudioServer.get_bus_index(bus_name)
			if idx >= 0:
				_saved_bus_mutes[bus_name] = AudioServer.is_bus_mute(idx)
				AudioServer.set_bus_mute(idx, true)
		play_sfx("ui")
	else:
		for layer in _saved_music_layers:
			var player := _player_for_layer(layer)
			if player == null:
				continue
			_kill_tween(player)
			player.volume_db = _layer_target_db(layer)
		_saved_music_layers.clear()
		for bus_name: StringName in _saved_bus_mutes:
			var idx := AudioServer.get_bus_index(bus_name)
			if idx >= 0:
				AudioServer.set_bus_mute(idx, bool(_saved_bus_mutes[bus_name]))
		_saved_bus_mutes.clear()
