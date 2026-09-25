extends Node


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

const SFX_PROFILES := {
	"hit": {"path": "res://assets/audio/sfx/hit.ogg", "bus": &"SFX"},
	"hit_armor": {"path": "res://assets/audio/sfx/hit_armor.ogg", "bus": &"SFX"},
	"block": {"path": "res://assets/audio/sfx/block.ogg", "bus": &"SFX"},
	"parry": {"path": "res://assets/audio/sfx/parry.ogg", "bus": &"SFX"},
	"swing": {"path": "res://assets/audio/sfx/swing_01.ogg", "bus": &"SFX"},
	"death": {"path": "res://assets/audio/sfx/death_01.ogg", "bus": &"SFX"},
	"footstep": {"path": "res://assets/audio/sfx/step_stone_01.ogg", "bus": &"SFX"},
	"footstep_stone": {"path": "res://assets/audio/sfx/step_stone_01.ogg", "bus": &"SFX"},
	"footstep_wood": {"path": "res://assets/audio/sfx/step_wood_01.ogg", "bus": &"SFX"},
	"footstep_water": {"path": "res://assets/audio/sfx/step_water_01.ogg", "bus": &"SFX"},
	"footstep_snow": {"path": "res://assets/audio/sfx/step_snow_01.ogg", "bus": &"SFX"},
	"windup": {"path": "res://assets/audio/sfx/windup_01.ogg", "bus": &"SFX"},
	"impact_heavy": {"path": "res://assets/audio/sfx/hit_armor.ogg", "bus": &"SFX"},
	"heal_raise": {"path": "res://assets/audio/sfx/heal_raise.ogg", "bus": &"SFX"},
	"heal_gulp": {"path": "res://assets/audio/sfx/heal_gulp.ogg", "bus": &"SFX"},
	"heal_commit": {"path": "res://assets/audio/sfx/heal_commit.ogg", "bus": &"SFX"},
	"lever_pull": {"path": "res://assets/audio/sfx/lever_pull.ogg", "bus": &"SFX"},
	"lever_unlock": {"path": "res://assets/audio/sfx/lever_unlock.ogg", "bus": &"SFX"},
	"ui": {"path": "res://assets/audio/sfx/ui_click_01.ogg", "bus": &"UI"},
	"door_open": {"path": "res://assets/audio/sfx/door_open.ogg", "bus": &"SFX"},
	"door_seal": {"path": "res://assets/audio/sfx/door_seal.ogg", "bus": &"SFX"},
	"door_release": {"path": "res://assets/audio/sfx/door_release.ogg", "bus": &"SFX"},
	"portal_open": {"path": "res://assets/audio/sfx/portal_open.ogg", "bus": &"SFX"},
	"portal_enter": {"path": "res://assets/audio/sfx/portal_enter.ogg", "bus": &"UI"},
	"loot_drop_common": {"path": "res://assets/audio/sfx/loot_drop_common.ogg", "bus": &"SFX"},
	"loot_drop_magic": {"path": "res://assets/audio/sfx/loot_drop_magic.ogg", "bus": &"SFX"},
	"loot_drop_rare": {"path": "res://assets/audio/sfx/loot_drop_rare.ogg", "bus": &"SFX"},
	"loot_drop_epic": {"path": "res://assets/audio/sfx/loot_drop_epic.ogg", "bus": &"SFX"},
	"loot_drop_legendary": {"path": "res://assets/audio/sfx/loot_drop_legendary.ogg", "bus": &"SFX"},
	"loot_drop_aumbral": {"path": "res://assets/audio/sfx/loot_drop_aumbral.ogg", "bus": &"SFX"},
	"dodge_perfect": {"path": "res://assets/audio/sfx/dodge_perfect.ogg", "bus": &"SFX"},
	"exhausted": {"path": "res://assets/audio/sfx/exhausted.ogg", "bus": &"SFX"},
	"resource_denied": {"path": "res://assets/audio/sfx/resource_denied.ogg", "bus": &"UI"},
	"guard_break": {"path": "res://assets/audio/sfx/guard_break.ogg", "bus": &"SFX"},
	"boss_reveal": {"path": "res://assets/audio/shared/sting_boss.ogg", "bus": &"Music"},
}

const COMBAT_SFX_KEYS: Array[String] = [
	"hit", "hit_armor", "block", "parry", "swing", "death", "footstep", "windup",
]
const CRITICAL_SFX := ["parry", "guard_break", "boss_reveal", "resource_denied"]
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
const INTENSITY_EPSILON := 0.005
const COMBAT_RELEASE_HYSTERESIS := 2.0

var _ambience: AudioStreamPlayer
const MENU_THEME_PATH := "res://assets/audio/shared/title_theme.ogg"
const HUB_THEME_PATH := "res://assets/audio/shared/hub_theme.ogg"

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
var _sfx_surface_streams: Dictionary = {}
var _sfx_shuffle_bags: Dictionary = {}
var _sfx_last_played_ms: Dictionary = {}
var _sfx_active_counts: Dictionary = {}
var _missing_sfx_warned: Dictionary = {}
var _rng := RandomNumberGenerator.new()
var _generator_active := true
var _layer_base_db: Dictionary = {}
var _intensity := 0.0
var _boss_active := false
var _player_vitality := 1.0
var _combat_release_timer := 0.0
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
	_recompute_generator_active()
	_report_placeholder_sfx()


func _report_placeholder_sfx() -> void:
	if not OS.is_debug_build():
		return
	var pending: Array[String] = []
	for key in SFX_PROFILES:
		var profile: Dictionary = SFX_PROFILES[key]
		if bool(profile.get("placeholder", false)) and not _bank_covers(str(key)):
			pending.append(str(key))
	if pending.is_empty():
		return
	pending.sort()
	print_rich(
		"[color=yellow]AudioDirector: %d placeholder SFX still need real foley — %s[/color]"
		% [pending.size(), ", ".join(pending)]
	)


static func _profile_bank_key(key: String) -> Array:
	if key.begins_with("footstep_"):
		return ["footstep", key.substr("footstep_".length())]
	return [key, ""]


func _bank_covers(key: String) -> bool:
	var resolved: Array = _profile_bank_key(key)
	var bank_key: String = str(resolved[0])
	var surface: String = str(resolved[1])
	if not _sfx_bank.has(bank_key):
		return false
	if surface == "":
		return true
	var entry: Dictionary = _sfx_bank[bank_key]
	var surface_variants: Dictionary = entry.get("surface_variants", {})
	var paths: Array = surface_variants.get(surface, [])
	return not paths.is_empty()


func _recompute_generator_active() -> void:
	_generator_active = (
		_ambience.stream is AudioStreamGenerator
		or _music.stream is AudioStreamGenerator
		or _explore.stream is AudioStreamGenerator
		or _combat_layer.stream is AudioStreamGenerator
	)
	set_process(_generator_active)


func _process(delta: float) -> void:
	if _combat_release_timer > 0.0:
		_combat_release_timer -= delta
		if _combat_release_timer <= 0.0:
			_recompute_intensity(_crossfade * 1.5)
	if _ambience.playing and _ambience.stream is AudioStreamGenerator:
		_ambience_phase = _fill_generator_for_mode(_ambience, _ambience_freq, _ambience_phase, _current_mode)
	if _music.playing and _music.stream is AudioStreamGenerator:
		_music_phase = _fill_generator_for_mode(_music, _music_freq, _music_phase, _current_mode)
	if _explore.playing and _explore.stream is AudioStreamGenerator:
		_explore_phase = _fill_generator_for_mode(_explore, _explore_freq, _explore_phase, _current_mode)
	if _combat_layer.playing and _combat_layer.stream is AudioStreamGenerator:
		_combat_phase = _fill_generator_for_mode(_combat_layer, _combat_freq, _combat_phase, _current_mode)


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
	_ambience_freq = float(_profile.get("ambienceFreq", 110.0))
	_music_freq = float(_profile.get("bossFreq", 196.0))
	_explore_freq = float(_profile.get("exploreFreq", _ambience_freq))
	_combat_freq = float(_profile.get("combatFreq", _music_freq))
	_crossfade = float(_profile.get("crossfadeSeconds", DEFAULT_CROSSFADE))
	_ambience.set_meta(&"freq", _ambience_freq)
	_explore.set_meta(&"freq", _explore_freq)
	_combat_layer.set_meta(&"freq", _combat_freq)
	_music.set_meta(&"freq", _music_freq)
	_ambience.stream = next_streams[LAYER_AMBIENCE]
	_explore.stream = next_streams[LAYER_EXPLORE]
	_combat_layer.stream = next_streams[LAYER_COMBAT]
	_music.stream = next_streams[LAYER_BOSS]
	_load_layer_mix_metadata()
	_recompute_generator_active()
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
	var frequencies := {
		LAYER_AMBIENCE: float(profile.get("ambienceFreq", 110.0)),
		LAYER_EXPLORE: float((layers.get(LAYER_EXPLORE, {}) as Dictionary).get("fallback_freq", profile.get("exploreFreq", 110.0))),
		LAYER_COMBAT: float((layers.get(LAYER_COMBAT, {}) as Dictionary).get("fallback_freq", profile.get("combatFreq", 130.0))),
		LAYER_BOSS: float(profile.get("bossFreq", 196.0)),
	}
	var resolved := {}
	for layer in LAYER_KEYS:
		var stream := _load_audio_stream(paths[layer]) if paths[layer] != "" else null
		resolved[layer] = stream if stream != null else _new_generator(float(frequencies[layer]))
	return resolved


func _new_generator(_frequency: float) -> AudioStreamGenerator:
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = GENERATOR_BUFFER_SEC
	return generator


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
	elif _combat_engagements > 0 or _combat_release_timer > 0.0:
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


func play_dungeon_ambience() -> void:
	_current_mode = "dungeon"
	_combat_engagements = 0
	_boss_active = false
	_player_vitality = 1.0
	_intensity = 0.0
	_restore_generator_streams()
	_apply_layer_mix(_crossfade)


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
	_boss_active = false
	_intensity = 0.0
	_layer_base_db.clear()
	# Keep an already-playing title stream intact. Forcing a generator swap here created orphaned
	# Ogg playback sequences every time the menu was reopened.
	_restore_generator_streams()
	_try_load_file_stream(_music, MENU_THEME_PATH)
	_apply_reverb_preset("cathedral")
	_fade_out_player(_combat_layer, _crossfade)
	_fade_out_player(_ambience, _crossfade)
	_fade_out_player(_explore, _crossfade)
	_fade_in_player(_music)


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
	_boss_active = false
	_intensity = 0.0
	_layer_base_db.clear()
	_restore_generator_streams(true)
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
	elif _music.stream is AudioStreamGenerator:
		_music_freq = float(_profile.get("bossFreq", 196.0)) * pow(1.5, float(maxi(0, phase_index)))
		_music.set_meta(&"freq", _music_freq)
	if phase_index > 0:
		play_sfx("boss_reveal")


func end_boss_music() -> void:
	if not _boss_active:
		return
	_boss_active = false
	_current_mode = "dungeon"
	_intensity = -1.0
	_music_freq = float(_profile.get("bossFreq", 196.0))
	_music.set_meta(&"freq", _music_freq)
	var boss_path: String = _profile.get("bossPath", "")
	if boss_path != "":
		_try_load_file_stream(_music, boss_path)
	_recompute_intensity(_crossfade * 1.5)


func register_combat_engagement() -> void:
	if _current_mode != "dungeon":
		return
	_combat_engagements += 1
	_combat_release_timer = 0.0
	_recompute_intensity(_crossfade)


func unregister_combat_engagement() -> void:
	if _current_mode != "dungeon":
		return
	_combat_engagements = maxi(0, _combat_engagements - 1)
	if _combat_engagements == 0:
		_combat_release_timer = COMBAT_RELEASE_HYSTERESIS
	else:
		_recompute_intensity(_crossfade * 1.5)


func stop_all(fade: float = 0.3) -> void:
	_current_mode = "none"
	_combat_engagements = 0
	_boss_active = false
	_intensity = 0.0
	_player_vitality = 1.0
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
		_play_fallback_tone(kind, world_pos, entry)
		_mark_sfx_played(kind)
		_duck_for_threat(kind, entry)
		return
	var stream: AudioStream = _pick_sfx_stream(kind, entry, surface)
	if stream == null:
		_warn_missing_sfx(kind)
		_play_fallback_tone(kind, world_pos, entry)
		_mark_sfx_played(kind)
		_duck_for_threat(kind, entry)
		return
	_play_stream(stream, world_pos, entry, kind)
	_mark_sfx_played(kind)
	_duck_for_threat(kind, entry)


func play_ui_sfx() -> void:
	play_sfx("ui")


func preview_bus(bus: StringName) -> void:
	var idx := AudioServer.get_bus_index(bus)
	if idx < 0:
		play_ui_sfx()
		return
	var preview := AudioStreamPlayer.new()
	preview.name = "BusPreview"
	preview.bus = bus
	preview.stream = _preview_tone_for_bus(bus)
	add_child(preview)
	preview.finished.connect(preview.queue_free)
	preview.play()


func _preview_tone_for_bus(bus: StringName) -> AudioStream:
	var freq := 440.0
	match bus:
		&"Music":
			freq = _music_freq * 2.0
		&"Ambience":
			freq = _ambience_freq * 2.0
		&"SFX":
			freq = 330.0
		_:
			freq = 523.25
	return _make_tone_stream(freq, 0.22)


func _make_tone_stream(freq: float, seconds: float) -> AudioStreamWAV:
	var rate := int(MIX_RATE)
	var frames := maxi(1, int(rate * seconds))
	var attack := maxf(1.0, float(frames) * 0.05)
	var release := maxf(1.0, float(frames) * 0.45)
	var data := PackedByteArray()
	data.resize(frames * 2)
	for i in frames:
		var envelope := minf(float(i) / attack, minf(1.0, float(frames - i) / release))
		var sample := sin(TAU * freq * (float(i) / float(rate))) * envelope * 0.35
		var value := int(clampf(sample, -1.0, 1.0) * 32767.0)
		data.encode_s16(i * 2, value)
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = rate
	stream.stereo = false
	stream.data = data
	return stream


func play_cue(cue_name: StringName, world_pos: Variant = null) -> void:
	play_sfx(String(cue_name), world_pos)


func play_stinger(stinger_id: String) -> void:
	var stingers: Dictionary = _profile.get("stingers", {})
	var path := str(stingers.get(stinger_id, ""))
	var stream: AudioStream = _load_audio_stream(path) if path != "" else null
	if stream != null:
		_play_stream_2d(stream, &"SFX", 0.0, 1.0)
	else:
		play_sfx(stinger_id)
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
	var points: Array = LAYER_GAIN_CURVE.get(layer, [])
	var gain := _sample_curve(points, _intensity)
	if gain <= 0.001:
		return LAYER_SILENCE_DB
	var base_db := float(_layer_base_db.get(layer, 0.0))
	return clampf(base_db + linear_to_db(gain), LAYER_SILENCE_DB, LAYER_MAX_DB)


func has_sfx(kind: String) -> bool:
	_cache_sfx_kind(kind)
	return _sfx_streams.has(kind) and not (_sfx_streams[kind] as Array).is_empty()


## `AU-04`: whether `kind` is a declared cue at all (bank entry, even one served only by its
## `fallback_tone`), as opposed to `has_sfx()`, which is only true once real authored audio exists.
## Callers building a cue name from content (e.g. a per-enemy voice prefix) use this to decide
## whether the specific cue they want is worth playing rather than silently degrading to the
## generic 220 Hz beep an unregistered `kind` falls back to.
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
	if paths.is_empty() and SFX_PROFILES.has(kind):
		var profile: Dictionary = SFX_PROFILES[kind]
		if profile.has("path"):
			paths.append(str(profile["path"]))
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


func _play_stream(stream: AudioStream, world_pos: Variant, entry: Dictionary, kind: String) -> void:
	var bus: StringName = &"SFX"
	if entry.has("bus"):
		bus = StringName(str(entry["bus"]))
	elif SFX_PROFILES.has(kind):
		bus = SFX_PROFILES[kind].get("bus", &"SFX")
	var profile: Dictionary = SFX_PROFILES.get(kind, {})
	var volume_db := float(entry.get("volume_db", profile.get("volume_db", 0.0)))
	var pitch_jitter := float(entry.get("pitch_jitter", profile.get("pitch_jitter", 0.0)))
	var pitch_scale := float(entry.get("pitch", profile.get("pitch", 1.0)))
	if pitch_jitter > 0.0:
		pitch_scale *= 1.0 + _rng.randf_range(-pitch_jitter, pitch_jitter)
	if world_pos is Vector3:
		var player3d := _acquire_sfx_3d_player(_cue_priority(kind, entry), world_pos)
		if player3d == null:
			_play_stream_2d(stream, bus, volume_db, pitch_scale, kind, entry)
			return
		_prepare_voice(player3d, kind, _cue_priority(kind, entry))
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


func _is_occluded(world_pos: Vector3) -> bool:
	var camera := get_viewport().get_camera_3d()
	if camera == null:
		return false
	var space: PhysicsDirectSpaceState3D = camera.get_world_3d().direct_space_state
	if space == null:
		return false
	var query := PhysicsRayQueryParameters3D.create(camera.global_position, world_pos)
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
			"kind": kind,
			"priority": _cue_priority(kind, entry),
			"freq": float(tone.get("freq", 220.0)),
			"duration": float(tone.get("duration", 0.08)),
			"bus": StringName(str(entry.get("bus", "SFX"))),
		}
	elif SFX_PROFILES.has(kind):
		var sfx_profile: Dictionary = SFX_PROFILES[kind]
		profile = {
			"kind": kind,
			"priority": _cue_priority(kind, entry),
			"bus": sfx_profile.get("bus", &"SFX"),
			"freq": float(sfx_profile.get("freq", 220.0)),
			"duration": float(sfx_profile.get("duration", 0.08)),
		}
	else:
		profile = {"kind": kind, "priority": 0, "freq": 220.0, "duration": 0.08, "bus": &"SFX"}
	return profile


func _warn_missing_sfx(kind: String) -> void:
	if OS.is_debug_build() and not _missing_sfx_warned.has(kind):
		_missing_sfx_warned[kind] = true
		push_warning("AudioDirector: missing authored SFX for '%s'" % kind)


func _play_sfx_2d(profile: Dictionary) -> void:
	var player := _acquire_sfx_player(int(profile.get("priority", 0)))
	if player == null:
		return
	_prime_tone_burst(player, profile)


func _play_sfx_3d(profile: Dictionary, world_pos: Vector3) -> void:
	var player := _acquire_sfx_3d_player(int(profile.get("priority", 0)), world_pos)
	if player == null:
		_play_sfx_2d(profile)
		return
	player.global_position = world_pos
	_prime_tone_burst(player, profile)


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
	var listener := get_viewport().get_camera_3d()
	for player in _sfx_3d_pool:
		var priority := int(player.get_meta(&"sfx_priority", 0))
		if priority > request_priority:
			continue
		var distance := (
			listener.global_position.distance_to(player.global_position)
			if listener else player.global_position.distance_to(world_pos)
		)
		var age := float(Time.get_ticks_msec() - int(player.get_meta(&"sfx_started_ms", 0))) / 1000.0
		var score := float(priority) * 100.0 - distance - age * 4.0
		if candidate == null or score < candidate_score:
			candidate = player
			candidate_score = score
	return candidate


func _prime_tone_burst(player: Node, profile: Dictionary) -> void:
	var kind := str(profile.get("kind", ""))
	if kind != "":
		_prepare_voice(player, kind, int(profile.get("priority", 0)))
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
	var generation_stream: AudioStream = player.stream
	var stop_timer := get_tree().create_timer(duration + 0.02, true, false, true)
	stop_timer.timeout.connect(func() -> void:
		if is_instance_valid(player) and player.stream == generation_stream:
			player.stop()
	, CONNECT_ONE_SHOT)


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
	_generator_active = true
	return player


func _try_load_file_stream(player: AudioStreamPlayer, path: String) -> void:
	var stream := _load_audio_stream(path)
	if stream == null or player.stream == stream:
		return
	player.stop()
	player.stream = stream
	_recompute_generator_active()


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


func _restore_generator_streams(force: bool = false) -> void:
	for player in [_ambience, _music, _explore, _combat_layer]:
		if force or player.stream == null or player.stream is AudioStreamGenerator:
			_assign_generator_stream(player)


func _assign_generator_stream(player: AudioStreamPlayer) -> void:
	if player.stream is AudioStreamGenerator:
		return
	player.stop()
	var generator := AudioStreamGenerator.new()
	generator.mix_rate = MIX_RATE
	generator.buffer_length = GENERATOR_BUFFER_SEC
	player.stream = generator
	_generator_active = true
	set_process(true)
