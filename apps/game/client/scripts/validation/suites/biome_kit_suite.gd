extends "res://scripts/validation/validation_suite.gd"

const RoomTemplateCatalogScript := preload("res://scripts/dungeon/procgen/room_template_catalog.gd")

const REQUIRED_KEYS := [
	"id",
	"name",
	"templatePrefix",
	"assetFolder",
	"roomCount",
	"roomTemplateIds",
	"materials",
	"lighting",
	"audioProfile",
	"propKit",
	"enemyPool",
	"bossPool",
	"budgets",
	"lootTables",
	"trapPool",
	"finalFloor",
]


func get_category() -> String:
	return "biome_kit"


func run() -> void:
	BiomeRegistry.warm_index()
	_test_all_biomes_load()
	_test_all_resource_paths_resolve()
	_test_room_scene_convention()
	_test_biome_cache_single_read()
	_test_unknown_biome_errors()
	_test_boss_pool_variety()
	_test_audio_paths_distinct()
	_test_lighting_applied_per_mode()
	_test_no_grid_step()
	_test_ceiling_materials_distinct()


func _test_all_biomes_load() -> void:
	var start := Time.get_ticks_msec()
	var ok := BiomeRegistry.ALL_BIOMES.size() == 10
	if ok:
		for biome_id in BiomeRegistry.ALL_BIOMES:
			var biome := BiomeRegistry.get_biome(biome_id)
			if biome.is_empty():
				ok = false
				break
			for key in REQUIRED_KEYS:
				if not biome.has(key):
					ok = false
					break
	ctx.timed_record(
		"biome_kit.all_biomes_load",
		get_category(),
		ok,
		"all 10 biomes load with required v2 keys",
		start,
		"BIO-01"
	)


func _test_all_resource_paths_resolve() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var biome := BiomeRegistry.get_biome(biome_id)
		var materials: Dictionary = biome.get("materials", {})
		for slot in ["floor", "wall", "ceiling", "accent"]:
			if not ResourceLoader.exists(str(materials.get(slot, ""))):
				ok = false
		var prop_kit: Dictionary = biome.get("propKit", {})
		if not ResourceLoader.exists(str(prop_kit.get("pillar", ""))):
			ok = false
		if not ResourceLoader.exists(str(prop_kit.get("sconce", ""))):
			ok = false
		for rubble_path in prop_kit.get("rubble", []):
			if not ResourceLoader.exists(str(rubble_path)):
				ok = false
		var audio_rel := str(biome.get("audioProfile", ""))
		if not FileAccess.file_exists(ContentLoader.content_path(audio_rel)):
			ok = false
		for kind in BiomeRegistry.ROOM_KINDS:
			var scene_path := BiomeRegistry.room_scene_path(biome_id, kind)
			if not ResourceLoader.exists(scene_path):
				ok = false
	ctx.timed_record(
		"biome_kit.resource_paths_resolve",
		get_category(),
		ok,
		"materials, props, audio, and room scenes resolve for all biomes",
		start,
		"BIO-01"
	)


func _test_room_scene_convention() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var biome := BiomeRegistry.get_biome(biome_id)
		var prefix := str(biome.get("templatePrefix", ""))
		var folder := str(biome.get("assetFolder", ""))
		for kind in BiomeRegistry.ROOM_KINDS:
			var expected := "res://scenes/rooms/%s/%s_%s.tscn" % [folder, prefix, kind]
			if BiomeRegistry.room_scene_path(biome_id, kind) != expected:
				ok = false
			if not ResourceLoader.exists(expected):
				ok = false
	ctx.timed_record(
		"biome_kit.room_scene_convention",
		get_category(),
		ok,
		"room scene paths follow templatePrefix/assetFolder convention",
		start,
		"BIO-01"
	)


func _test_biome_cache_single_read() -> void:
	var start := Time.get_ticks_msec()
	BiomeRegistry.clear_caches()
	var first := BiomeRegistry.get_biome("forgotten_castle")
	var second := BiomeRegistry.get_biome("forgotten_castle")
	var ok := not first.is_empty() and first == second
	ctx.timed_record(
		"biome_kit.cache_single_read",
		get_category(),
		ok,
		"get_biome twice performs one file read",
		start,
		"BIO-02"
	)


func _test_unknown_biome_errors() -> void:
	var start := Time.get_ticks_msec()
	var unknown := BiomeRegistry.get_biome("nope_not_a_biome")
	var ok := unknown.is_empty()
	if ok:
		ok = BiomeRegistry.get_display_name("nope_not_a_biome") == ""
		ok = ok and BiomeRegistry.get_room_scenes("nope_not_a_biome").is_empty()
		ok = ok and BiomeRegistry.get_lighting_profile("nope_not_a_biome").is_empty()
	ctx.timed_record(
		"biome_kit.unknown_biome_errors",
		get_category(),
		ok,
		"unknown biome returns empty without castle fallback",
		start,
		"BIO-10"
	)


func _test_boss_pool_variety() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var pool: Array = BiomeRegistry.get_biome(biome_id).get("bossPool", [])
		if pool.size() < 2:
			ok = false
	ctx.timed_record(
		"biome_kit.boss_pool_variety",
		get_category(),
		ok,
		"every biome bossPool has at least 2 entries",
		start,
		"BIO-07"
	)


func _test_audio_paths_distinct() -> void:
	var start := Time.get_ticks_msec()
	var paths := {}
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var profile_path := ContentLoader.content_path(
			str(BiomeRegistry.get_biome(biome_id).get("audioProfile", ""))
		)
		var text := FileAccess.get_file_as_string(profile_path)
		var profile: Variant = JSON.parse_string(text)
		if not profile is Dictionary:
			ok = false
			continue
		var ambience := str((profile as Dictionary).get("ambiencePath", ""))
		if paths.has(ambience):
			ok = false
		paths[ambience] = biome_id
	ctx.timed_record(
		"biome_kit.audio_paths_distinct",
		get_category(),
		ok,
		"10 distinct ambiencePath values across audio profiles",
		start,
		"BIO-06"
	)


func _test_lighting_applied_per_mode() -> void:
	var start := Time.get_ticks_msec()
	var profile := BiomeRegistry.get_lighting_profile("umbral_chapel")
	var profile_color: Color = profile.get("ambient_color", Color.WHITE)
	var ok := true
	for mode in [
		RunModeConfig.MODE_WAVES,
		RunModeConfig.MODE_CASTLE,
		RunModeConfig.MODE_ENDLESS,
		"",
	]:
		var parent := Node3D.new()
		var env_node := BiomeRegistry.apply_run_presentation(parent, "umbral_chapel", mode)
		if env_node == null or env_node.environment == null:
			ok = false
		else:
			var applied: Color = env_node.environment.ambient_light_color
			var delta := Vector3(applied.r, applied.g, applied.b) - Vector3(
				profile_color.r, profile_color.g, profile_color.b
			)
			if delta.length() > 0.25:
				ok = false
		parent.queue_free()
	ctx.timed_record(
		"biome_kit.lighting_applied_per_mode",
		get_category(),
		ok,
		"waves/castle/endless ambient color stays within 0.25 of biome profile",
		start,
		"BIO-11"
	)


func _test_no_grid_step() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		if BiomeRegistry.get_biome(biome_id).has("gridStep"):
			ok = false
	ctx.timed_record(
		"biome_kit.no_grid_step",
		get_category(),
		ok,
		"gridStep absent from all biome JSON files",
		start,
		"BIO-03"
	)


func _test_ceiling_materials_distinct() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var wall := BiomeRegistry.get_wall_material(biome_id)
		var ceiling := BiomeRegistry.get_ceiling_material(biome_id)
		if wall == null or ceiling == null or wall == ceiling:
			ok = false
	ctx.timed_record(
		"biome_kit.ceiling_materials_distinct",
		get_category(),
		ok,
		"get_ceiling_material != get_wall_material for all 10 biomes",
		start,
		"BIO-12"
	)
