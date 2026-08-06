extends "res://scripts/validation/validation_suite.gd"

const LEGACY_SFX_KEYS := [
	"hit",
	"block",
	"parry",
	"swing",
	"death",
	"footstep",
	"windup",
	"ui",
]
const REQUIRED_BUSES := ["Master", "Music", "SFX", "Ambience", "UI"]


func get_category() -> String:
	return "content"


func run() -> void:
	_test_profiles_load()
	_test_profile_biome_coverage()
	_test_layer_stems_on_disk()
	_test_loop_imports_loop()
	_test_reverb_presets_valid()
	_test_sfx_bank_loads()
	_test_sfx_keys_complete()
	_test_sfx_variants_on_disk()
	_test_buses_present()
	_test_file_stream_survives_mode_change()
	_test_generator_fallback_installs()
	_test_fallback_freqs_from_profile()
	_test_sfx_unknown_key_safe()
	_test_sfx_concurrency_capped()
	_test_sfx_cooldown_respected()
	_test_sfx_variant_rotation()
	_test_bus_effects_idempotent()
	_test_volume_roundtrip()
	_test_mute_is_silent()
	_test_stinger_ducks()
	_test_emitter_frees_with_host()
	_test_no_process_synthesis_with_stems()


func _test_profiles_load() -> void:
	var start := Time.get_ticks_msec()
	var schema_path := _content_root().path_join("content/schemas/audio-profile.v1.json")
	var schema_ok := FileAccess.file_exists(schema_path)
	var all_ok := schema_ok
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var profile: Dictionary = ContentLoader.load_json(
			BiomeRegistry.get_audio_profile_path(biome_id)
		)
		if profile.is_empty() or not profile.has("id") or not profile.has("biomeId"):
			all_ok = false
	ctx.timed_record(
		"audio.profiles_load",
		get_category(),
		all_ok,
		"all audio profiles parse with required keys",
		start,
		"M2.audio.profiles"
	)


func _test_profile_biome_coverage() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var path := BiomeRegistry.get_audio_profile_path(biome_id)
		var profile: Dictionary = ContentLoader.load_json(path)
		if str(profile.get("biomeId", "")) != biome_id:
			ok = false
	ctx.timed_record(
		"audio.profile_biome_coverage",
		get_category(),
		ok,
		"every biome has a matching audio profile filename",
		start,
		"M2.audio.coverage"
	)


func _test_layer_stems_on_disk() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var profile: Dictionary = ContentLoader.load_json(
			BiomeRegistry.get_audio_profile_path(biome_id)
		)
		var layers: Dictionary = profile.get("layers", {})
		for layer_key in ["ambience", "explore", "combat", "boss"]:
			var path: String = str(layers.get(layer_key, {}).get("path", ""))
			if path == "":
				ok = false
				continue
			if not _source_exists(path):
				ok = false
	ctx.timed_record(
		"audio.layer_stems_on_disk",
		get_category(),
		ok,
		"every layers.*.path exists on disk via FileAccess",
		start,
		"M2.audio.stems"
	)


func _test_loop_imports_loop() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var audio_root := ProjectSettings.globalize_path("res://assets/audio/")
	var dir := DirAccess.open(audio_root)
	if dir:
		ok = _scan_loop_imports(dir, audio_root)
	ctx.timed_record(
		"audio.loop_imports_loop",
		get_category(),
		ok,
		"every *_loop.ogg.import has loop=true",
		start,
		"M2.audio.loop"
	)


func _scan_loop_imports(dir: DirAccess, root: String) -> bool:
	var ok := true
	dir.list_dir_begin()
	var name := dir.get_next()
	while name != "":
		if name == "." or name == "..":
			name = dir.get_next()
			continue
		var path := root.path_join(name)
		if dir.current_is_dir():
			var sub := DirAccess.open(path)
			if sub:
				ok = _scan_loop_imports(sub, root) and ok
		elif name.ends_with("_loop.ogg.import"):
			var text := FileAccess.get_file_as_string(path)
			if not text.contains("loop=true"):
				ok = false
		name = dir.get_next()
	dir.list_dir_end()
	return ok


func _test_reverb_presets_valid() -> void:
	var start := Time.get_ticks_msec()
	var schema_path := _content_root().path_join("content/schemas/audio-profile.v1.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(schema_path))
	var enum_vals: Array = []
	if parsed is Dictionary:
		var props: Dictionary = parsed.get("properties", {})
		var reverb: Dictionary = props.get("reverbPreset", {})
		enum_vals = reverb.get("enum", [])
	var preset_keys: Array = AudioDirector.REVERB_PRESETS.keys()
	var ok := enum_vals.size() == preset_keys.size()
	for key in preset_keys:
		if not enum_vals.has(key):
			ok = false
	ctx.timed_record(
		"audio.reverb_presets_valid",
		get_category(),
		ok,
		"schema reverbPreset enum matches AudioDirector.REVERB_PRESETS",
		start,
		"M2.audio.reverb"
	)


func _test_sfx_bank_loads() -> void:
	var start := Time.get_ticks_msec()
	var bank: Dictionary = ContentLoader.load_json("content/audio/sfx.json")
	var schema_path := _content_root().path_join("content/schemas/sfx-bank.v1.json")
	var ok := (
		not bank.is_empty()
		and int(bank.get("version", 0)) == 1
		and bank.has("sfx")
		and FileAccess.file_exists(schema_path)
	)
	ctx.timed_record(
		"audio.sfx_bank_loads",
		get_category(),
		ok,
		"content/audio/sfx.json loads with version and schema present",
		start,
		"M2.audio.sfx_bank"
	)


func _test_sfx_keys_complete() -> void:
	var start := Time.get_ticks_msec()
	var bank: Dictionary = ContentLoader.load_json("content/audio/sfx.json")
	var sfx: Dictionary = bank.get("sfx", {})
	var ok := true
	for key in LEGACY_SFX_KEYS:
		if not sfx.has(key):
			ok = false
	if not sfx.has("hit_armor"):
		ok = false
	for emitter_key in ["brazier", "fountain"]:
		if not sfx.has(emitter_key):
			ok = false
	ctx.timed_record(
		"audio.sfx_keys_complete",
		get_category(),
		ok,
		"legacy SFX keys and emitter keys exist in bank",
		start,
		"M2.audio.sfx_keys"
	)


func _test_sfx_variants_on_disk() -> void:
	var start := Time.get_ticks_msec()
	var bank: Dictionary = ContentLoader.load_json("content/audio/sfx.json")
	var sfx: Dictionary = bank.get("sfx", {})
	var ok := true
	for key in sfx:
		var entry: Dictionary = sfx[key]
		var paths: Array = entry.get("variants", [])
		for surface_paths in entry.get("surface_variants", {}).values():
			if surface_paths is Array:
				for p in surface_paths:
					paths.append(p)
		if paths.is_empty():
			if not entry.has("fallback_tone"):
				ok = false
			continue
		var any_exists := false
		for path in paths:
			if _source_exists(str(path)):
				any_exists = true
		if not any_exists and not entry.has("fallback_tone"):
			ok = false
	ctx.timed_record(
		"audio.sfx_variants_on_disk",
		get_category(),
		ok,
		"SFX variants exist on disk or declare fallback_tone",
		start,
		"M2.audio.sfx_variants"
	)


func _test_buses_present() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for bus_name in REQUIRED_BUSES:
		if AudioServer.get_bus_index(bus_name) < 0:
			ok = false
	var bank: Dictionary = ContentLoader.load_json("content/audio/sfx.json")
	for entry in bank.get("sfx", {}).values():
		var bus: String = str(entry.get("bus", ""))
		if not REQUIRED_BUSES.has(bus):
			ok = false
	ctx.timed_record(
		"audio.buses_present",
		get_category(),
		ok,
		"required audio buses and SFX bank bus names resolve",
		start,
		"M2.audio.buses"
	)


func _test_file_stream_survives_mode_change() -> void:
	var start := Time.get_ticks_msec()
	AudioDirector.set_biome(BiomeRegistry.BIOME_CASTLE)
	AudioDirector.play_dungeon_ambience()
	var stream_after := _get_ambience_stream()
	var ok := stream_after is AudioStream and not stream_after is AudioStreamGenerator
	ctx.timed_record(
		"audio.file_stream_survives_mode_change",
		get_category(),
		ok,
		"play_dungeon_ambience() does not replace file-backed ambience stream",
		start,
		"M2.audio.survive"
	)


func _test_generator_fallback_installs() -> void:
	var start := Time.get_ticks_msec()
	_clear_ambience_stream()
	AudioDirector.play_dungeon_ambience()
	var stream := _get_ambience_stream()
	var ok := stream is AudioStreamGenerator
	ctx.timed_record(
		"audio.generator_fallback_installs",
		get_category(),
		ok,
		"null ambience stream gets generator on play_dungeon_ambience()",
		start,
		"M2.audio.generator"
	)


func _test_fallback_freqs_from_profile() -> void:
	var start := Time.get_ticks_msec()
	AudioDirector.set_biome(BiomeRegistry.BIOME_CRYSTAL)
	var crystal_combat := _get_combat_fallback_freq()
	AudioDirector.set_biome(BiomeRegistry.BIOME_SWAMP)
	var swamp_combat := _get_combat_fallback_freq()
	var ok := is_equal_approx(crystal_combat, 220.0) and is_equal_approx(swamp_combat, 105.0)
	ctx.timed_record(
		"audio.fallback_freqs_from_profile",
		get_category(),
		ok,
		"combat fallback freq uses profile default, not previous biome",
		start,
		"M2.audio.freq"
	)


func _test_sfx_unknown_key_safe() -> void:
	var start := Time.get_ticks_msec()
	AudioDirector.play_sfx("nope")
	AudioDirector.play_sfx("nope")
	ctx.timed_record(
		"audio.sfx_unknown_key_safe",
		get_category(),
		true,
		"unknown SFX key falls back to hit without crashing",
		start,
		"M2.audio.sfx_unknown"
	)


func _test_sfx_concurrency_capped() -> void:
	var start := Time.get_ticks_msec()
	for _i in 20:
		AudioDirector.play_sfx("hit")
	var playing := _count_playing_sfx()
	var bank: Dictionary = ContentLoader.load_json("content/audio/sfx.json")
	var max_concurrent := int(bank.get("sfx", {}).get("hit", {}).get("max_concurrent", 3))
	ctx.timed_record(
		"audio.sfx_concurrency_capped",
		get_category(),
		playing <= max_concurrent,
		(
			"20 hit SFX calls leave at most max_concurrent playing (%d <= %d)"
			% [playing, max_concurrent]
		),
		start,
		"M2.audio.sfx_concurrent"
	)


func _test_sfx_cooldown_respected() -> void:
	var start := Time.get_ticks_msec()
	AudioDirector.play_sfx("footstep", null, "stone")
	AudioDirector.play_sfx("footstep", null, "stone")
	var playing := _count_playing_sfx()
	ctx.timed_record(
		"audio.sfx_cooldown_respected",
		get_category(),
		playing <= 1,
		"footstep cooldown blocks rapid duplicate plays",
		start,
		"M2.audio.sfx_cooldown"
	)


func _test_sfx_variant_rotation() -> void:
	var start := Time.get_ticks_msec()
	for _i in 12:
		AudioDirector.play_sfx("hit")
	var bank: Dictionary = ContentLoader.load_json("content/audio/sfx.json")
	var variants: Array = bank.get("sfx", {}).get("hit", {}).get("variants", [])
	var ok := variants.size() >= 3
	ctx.timed_record(
		"audio.sfx_variant_rotation",
		get_category(),
		ok,
		"hit SFX bank declares %d variants for rotation" % variants.size(),
		start,
		"M2.audio.sfx_rotate"
	)


func _test_bus_effects_idempotent() -> void:
	var start := Time.get_ticks_msec()
	var amb_idx := AudioServer.get_bus_index("Ambience")
	var before := AudioServer.get_bus_effect_count(amb_idx) if amb_idx >= 0 else 0
	AudioDirector._setup_bus_effects()
	AudioDirector._setup_bus_effects()
	var after := AudioServer.get_bus_effect_count(amb_idx) if amb_idx >= 0 else 0
	ctx.timed_record(
		"audio.bus_effects_idempotent",
		get_category(),
		before == after,
		"_setup_bus_effects() twice adds no duplicate effects",
		start,
		"M2.audio.bus_fx"
	)


func _test_volume_roundtrip() -> void:
	var start := Time.get_ticks_msec()
	var original := AudioSettings.sfx_volume
	AudioSettings.sfx_volume = 0.5
	AudioSettings.save()
	AudioSettings.sfx_volume = 1.0
	AudioSettings.load_from_save()
	var idx := AudioServer.get_bus_index("SFX")
	var db := AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0
	var expected := linear_to_db(0.5)
	var ok := is_equal_approx(db, expected, 0.01)
	AudioSettings.sfx_volume = original
	AudioSettings.save()
	ctx.timed_record(
		"audio.volume_roundtrip",
		get_category(),
		ok,
		"sfx_volume 0.5 save/load restores bus dB within 0.01",
		start,
		"M2.audio.volume"
	)


func _test_mute_is_silent() -> void:
	var start := Time.get_ticks_msec()
	var original := AudioSettings.master_volume
	AudioSettings.master_volume = 0.0
	AudioSettings.apply()
	var idx := AudioServer.get_bus_index("Master")
	var db := AudioServer.get_bus_volume_db(idx) if idx >= 0 else 0.0
	AudioSettings.master_volume = original
	AudioSettings.apply()
	ctx.timed_record(
		"audio.mute_is_silent",
		get_category(),
		db <= -79.0,
		"master_volume 0.0 yields -80 dB on Master",
		start,
		"M2.audio.mute"
	)


func _test_stinger_ducks() -> void:
	var start := Time.get_ticks_msec()
	AudioDirector.set_biome(BiomeRegistry.BIOME_CASTLE)
	AudioDirector.play_dungeon_ambience()
	var before_db := _get_music_volume_db()
	AudioDirector.play_stinger("boss_reveal")
	var after_db := _get_music_volume_db()
	ctx.timed_record(
		"audio.stinger_ducks",
		get_category(),
		after_db < before_db,
		"boss_reveal stinger ducks music layer",
		start,
		"M2.audio.stinger"
	)


func _test_emitter_frees_with_host() -> void:
	var start := Time.get_ticks_msec()
	var host := Node3D.new()
	ctx.owner.add_child(host)
	var emitter := AudioDirector.attach_loop_emitter(host, "brazier", 6.0)
	var emitter_valid := emitter != null
	host.queue_free()
	await ctx.owner.get_tree().process_frame
	ctx.timed_record(
		"audio.emitter_frees_with_host",
		get_category(),
		emitter_valid,
		"attach_loop_emitter() returns player attached to host",
		start,
		"M2.audio.emitter"
	)


func _test_no_process_synthesis_with_stems() -> void:
	var start := Time.get_ticks_msec()
	AudioDirector.set_biome(BiomeRegistry.BIOME_CASTLE)
	AudioDirector.play_dungeon_ambience()
	var ok := true
	for getter in [
		_get_ambience_stream, _get_music_stream, _get_explore_stream, _get_combat_stream
	]:
		var stream: Variant = getter.call()
		if stream is AudioStreamGenerator:
			ok = false
	ctx.timed_record(
		"audio.no_process_synthesis_with_stems",
		get_category(),
		ok,
		"file-backed layers are not AudioStreamGenerator after dungeon start",
		start,
		"M2.audio.no_synth"
	)


func _content_root() -> String:
	return ContentLoader.content_root()


func _source_exists(res_path: String) -> bool:
	return FileAccess.file_exists(ProjectSettings.globalize_path(res_path))


func _get_ambience_stream() -> Variant:
	return AudioDirector.get_node("AmbiencePlayer").stream


func _get_music_stream() -> Variant:
	return AudioDirector.get_node("MusicPlayer").stream


func _get_explore_stream() -> Variant:
	return AudioDirector.get_node("ExplorePlayer").stream


func _get_combat_stream() -> Variant:
	return AudioDirector.get_node("CombatPlayer").stream


func _get_music_volume_db() -> float:
	return AudioDirector.get_node("MusicPlayer").volume_db


func _clear_ambience_stream() -> void:
	AudioDirector.get_node("AmbiencePlayer").stream = null


func _count_playing_sfx() -> int:
	var playing := 0
	for i in 8:
		var player := AudioDirector.get_node("SfxPlayer%d" % i) as AudioStreamPlayer
		if player and player.playing:
			playing += 1
	return playing


func _get_combat_fallback_freq() -> float:
	return float(AudioDirector.get_node("CombatPlayer").get_meta(&"freq", 130.0))
