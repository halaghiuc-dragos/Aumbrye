extends "res://scripts/validation/validation_suite.gd"

const LightFlickerScript := preload("res://scripts/art/lighting/light_flicker.gd")
const DioramaRoomDressingScript := preload("res://scripts/dungeon/diorama_room_dressing.gd")

const LIGHTING_JSON := "content/art/lighting.json"
const LIGHTING_SCHEMA := "content/schemas/lighting-profile.v1.json"
const SKY_SHADER_PATH := "res://assets/shared/pixel_sky.gdshader"
const VISUAL_LIGHTING_PATH := "res://scripts/art/lighting/visual_lighting.gd"
const HEX_COLOR_RE := "^#[0-9a-fA-F]{6}$"


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_lighting_json_loads()
	_test_biome_map_total()
	_test_scene_profiles_present()
	_test_colors_well_formed()
	_test_profiles_distinct()
	_test_apply_creates_nodes()
	_test_apply_is_idempotent()
	_test_interior_has_key_light()
	_test_sky_uniform_coverage()
	_test_shadow_budget()
	_test_flicker_phase_differs()
	_test_flicker_bounded()
	_test_flicker_disabled()
	await _test_atmosphere_follows()
	await _test_atmosphere_respects_quality()
	_test_grade_consistent()
	_test_no_unused_constants()


func _lighting_data() -> Dictionary:
	return ContentLoader.load_json(LIGHTING_JSON)


func _shader_uniform_names() -> PackedStringArray:
	var text := FileAccess.get_file_as_string(SKY_SHADER_PATH)
	var names: PackedStringArray = []
	for line in text.split("\n"):
		var stripped := line.strip_edges()
		if not stripped.begins_with("uniform "):
			continue
		var decl := stripped.split(":")[0]
		var tokens := decl.split(" ", false)
		if tokens.size() >= 3:
			names.append(tokens[2])
	return names


func _spawn_root() -> Node3D:
	var root := Node3D.new()
	root.name = "LightingFixture"
	ctx.owner.add_child(root)
	return root


func _test_lighting_json_loads() -> void:
	var start := Time.get_ticks_msec()
	var data := _lighting_data()
	var ok := (
		not data.is_empty()
		and int(data.get("version", 0)) == 1
		and data.has("profiles")
		and data.has("biome_profile_map")
		and FileAccess.file_exists(ContentLoader.content_path(LIGHTING_SCHEMA))
	)
	ctx.timed_record(
		"lighting.json_loads",
		get_category(),
		ok,
		"%s parses with schema file present" % LIGHTING_JSON,
		start,
		"LIT-04"
	)


func _test_biome_map_total() -> void:
	var start := Time.get_ticks_msec()
	BiomeRegistry.warm_index()
	var map: Dictionary = _lighting_data().get("biome_profile_map", {})
	var profiles: Dictionary = _lighting_data().get("profiles", {})
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		if not map.has(biome_id):
			ok = false
			continue
		if not profiles.has(str(map[biome_id])):
			ok = false
	ctx.timed_record(
		"lighting.biome_map_total",
		get_category(),
		ok,
		"every BiomeRegistry.ALL_BIOMES id maps to a declared profile",
		start,
		"LIT-02"
	)


func _test_scene_profiles_present() -> void:
	var start := Time.get_ticks_msec()
	var profiles: Dictionary = _lighting_data().get("profiles", {})
	var required := [
		"hub",
		"arena",
		"waves_outdoors",
		"waves_arena",
		"castle_interior",
		"umbral_chapel",
	]
	var ok := true
	for profile_id in required:
		if not profiles.has(profile_id):
			ok = false
	ctx.timed_record(
		"lighting.scene_profiles_present",
		get_category(),
		ok,
		"hub/arena/waves/castle_interior/umbral profiles exist",
		start,
		"LIT-02"
	)


func _test_colors_well_formed() -> void:
	var start := Time.get_ticks_msec()
	var profiles: Dictionary = _lighting_data().get("profiles", {})
	var color_re := RegEx.new()
	color_re.compile(HEX_COLOR_RE)
	var ok := true
	for profile_id in profiles:
		var profile: Dictionary = profiles[profile_id]
		var ambient: Dictionary = profile.get("ambient", {})
		if not color_re.search(str(ambient.get("color", ""))):
			ok = false
		var energy := float(ambient.get("energy", -1.0))
		if energy < 0.0 or energy > 8.0:
			ok = false
	ctx.timed_record(
		"lighting.colors_well_formed",
		get_category(),
		ok,
		"profile ambient colors are #RRGGBB and energy in [0,8]",
		start,
		"LIT-04"
	)


func _test_profiles_distinct() -> void:
	var start := Time.get_ticks_msec()
	var seen: Dictionary = {}
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var summary := VisualLighting.profile_summary(VisualLighting.profile_for_biome(biome_id))
		var key := "%s:%s" % [summary.get("ambient_color"), summary.get("ambient_energy")]
		if seen.has(key):
			ok = false
		seen[key] = true
	ctx.timed_record(
		"lighting.profiles_distinct",
		get_category(),
		ok,
		"no two biome profiles share ambient color and energy",
		start,
		"LIT-04"
	)


func _test_apply_creates_nodes() -> void:
	var start := Time.get_ticks_msec()
	var root := _spawn_root()
	VisualLighting.apply_profile(root, "hub")
	var ok := (
		root.get_node_or_null("WorldEnvironment") != null
		and root.get_node_or_null("DirectionalLight3D") != null
		and root.get_node_or_null("FillLight") != null
		and root.get_node_or_null("KeyLight") == null
	)
	root.queue_free()
	ctx.timed_record(
		"lighting.apply_creates_nodes",
		get_category(),
		ok,
		"apply_profile(hub) creates WorldEnvironment, sun, fill, no KeyLight",
		start,
		"LIT-02"
	)


func _test_apply_is_idempotent() -> void:
	var start := Time.get_ticks_msec()
	var root := _spawn_root()
	VisualLighting.apply_profile(root, "hub")
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var env_first := env_node.environment
	var child_count := root.get_child_count()
	VisualLighting.apply_profile(root, "hub")
	var ok := root.get_child_count() == child_count and env_node.environment == env_first
	root.queue_free()
	ctx.timed_record(
		"lighting.apply_is_idempotent",
		get_category(),
		ok,
		"second apply_profile reuses Environment instance",
		start,
		"LIT-07"
	)


func _test_interior_has_key_light() -> void:
	var start := Time.get_ticks_msec()
	var prior_shadow := PixelDioramaSettings.shadow_quality
	PixelDioramaSettings.shadow_quality = 2
	var root := _spawn_root()
	VisualLighting.apply_profile(root, "umbral_chapel")
	var key := root.get_node_or_null("KeyLight") as DirectionalLight3D
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	var ok := (
		key != null
		and key.shadow_enabled
		and env_node != null
		and env_node.environment.background_mode == Environment.BG_COLOR
	)
	PixelDioramaSettings.shadow_quality = prior_shadow
	root.queue_free()
	ctx.timed_record(
		"lighting.interior_has_key_light",
		get_category(),
		ok,
		"umbral_chapel profile yields shadowed KeyLight and no sky background",
		start,
		"LIT-01"
	)


func _test_sky_uniform_coverage() -> void:
	var start := Time.get_ticks_msec()
	var declared := _shader_uniform_names()
	var uniforms := VisualLighting.sky_uniforms_for_profile("hub")
	var ok := true
	for uniform_name in declared:
		if not uniforms.has(uniform_name):
			ok = false
	ctx.timed_record(
		"lighting.sky_uniform_coverage",
		get_category(),
		ok,
		"hub sky block writes every pixel_sky.gdshader uniform",
		start,
		"LIT-06"
	)


func _test_shadow_budget() -> void:
	var start := Time.get_ticks_msec()
	var prior_shadow := PixelDioramaSettings.shadow_quality
	PixelDioramaSettings.shadow_quality = 2
	var lights_root := Node3D.new()
	ctx.owner.add_child(lights_root)
	DioramaRoomDressingScript.spawn_hall_torches_fixture(
		lights_root, BiomeRegistry.BIOME_CASTLE, 12.0, 10.0
	)
	var shadow_count := 0
	for node in lights_root.find_children("*", "OmniLight3D"):
		if (node as OmniLight3D).shadow_enabled:
			shadow_count += 1
	var max_allowed := int(
		VisualLighting.get_torch_config_for_biome(BiomeRegistry.BIOME_CASTLE).get(
			"max_shadow_omnis", 2
		)
	)
	PixelDioramaSettings.shadow_quality = prior_shadow
	lights_root.queue_free()
	ctx.timed_record(
		"lighting.shadow_budget",
		get_category(),
		shadow_count <= max_allowed,
		"hall ceiling pass casts at most %d shadow omnis (saw %d)" % [max_allowed, shadow_count],
		start,
		"LIT-01"
	)


func _test_flicker_phase_differs() -> void:
	var start := Time.get_ticks_msec()
	var a := VisualLighting.flicker_phase_for_position(Vector3(0.0, 1.0, 0.0))
	var b := VisualLighting.flicker_phase_for_position(Vector3(2.0, 1.0, 0.0))
	ctx.timed_record(
		"lighting.flicker_phase_differs",
		get_category(),
		absf(a - b) > 0.5,
		"torches 2m apart have phase delta > 0.5 rad",
		start,
		"LIT-03"
	)


func _test_flicker_bounded() -> void:
	var start := Time.get_ticks_msec()
	var base := 0.92
	var amount := 0.12
	var ok := true
	for frame in 600:
		var energy := LightFlickerScript.compute_energy_at(base, amount, 7.5, 0.2, frame / 60.0)
		if energy < 0.0 or energy > base * (1.0 + amount) + 0.001:
			ok = false
			break
	ctx.timed_record(
		"lighting.flicker_bounded",
		get_category(),
		ok,
		"600 simulated flicker frames stay within base*(1+-amount)",
		start,
		"LIT-03"
	)


func _test_flicker_disabled() -> void:
	var start := Time.get_ticks_msec()
	var prior := PixelDioramaSettings.light_animation
	PixelDioramaSettings.light_animation = false
	var light := OmniLight3D.new()
	ctx.owner.add_child(light)
	VisualLighting.attach_flicker(light, 0.12, 7.5, 0.0)
	var ok := light.get_node_or_null("LightFlicker") == null
	PixelDioramaSettings.light_animation = prior
	light.queue_free()
	ctx.timed_record(
		"lighting.flicker_disabled",
		get_category(),
		ok,
		"attach_flicker adds no child when light_animation is false",
		start,
		"LIT-03"
	)


func _test_atmosphere_follows() -> void:
	var start := Time.get_ticks_msec()
	var root := _spawn_root()
	var follow := Node3D.new()
	follow.position = Vector3(40.0, 0.0, 0.0)
	root.add_child(follow)
	VisualLighting.attach_atmosphere(root, "umbral_chapel", follow)
	await ctx.idle_frames(2)
	var holder := root.get_node_or_null("BiomeAtmosphere") as Node3D
	var ok := holder != null and holder.global_position.distance_to(follow.global_position) <= 4.0
	root.queue_free()
	ctx.timed_record(
		"lighting.atmosphere_follows",
		get_category(),
		ok,
		"moving follow target 40m snaps BiomeAtmosphere within 4m",
		start,
		"LIT-05"
	)


func _test_atmosphere_respects_quality() -> void:
	var start := Time.get_ticks_msec()
	var prior := PixelDioramaSettings.particle_quality
	var root := _spawn_root()
	PixelDioramaSettings.particle_quality = 2
	VisualLighting.attach_atmosphere(root, "umbral_chapel")
	var had_holder := root.get_node_or_null("BiomeAtmosphere") != null
	PixelDioramaSettings.particle_quality = 0
	PixelDioramaSettings.apply_all()
	await ctx.idle_frames(2)
	var freed := root.get_node_or_null("BiomeAtmosphere") == null
	PixelDioramaSettings.particle_quality = 2
	VisualLighting.attach_atmosphere(root, "umbral_chapel")
	var recreated := root.get_node_or_null("BiomeAtmosphere") != null
	PixelDioramaSettings.particle_quality = prior
	root.queue_free()
	ctx.timed_record(
		"lighting.atmosphere_respects_quality",
		get_category(),
		had_holder and freed and recreated,
		"particle_quality 0 frees holder; restoring quality recreates it",
		start,
		"LIT-05"
	)


func _test_grade_consistent() -> void:
	var start := Time.get_ticks_msec()
	var outdoor := _spawn_root()
	VisualLighting.apply_profile(outdoor, "hub")
	var outdoor_env := (
		outdoor.get_node_or_null("WorldEnvironment") as WorldEnvironment
	).environment
	var indoor := _spawn_root()
	VisualLighting.apply_profile(indoor, "umbral_chapel")
	var indoor_env := (
		indoor.get_node_or_null("WorldEnvironment") as WorldEnvironment
	).environment
	var ok := (
		outdoor_env.tonemap_mode == indoor_env.tonemap_mode
		and is_equal_approx(outdoor_env.tonemap_white, indoor_env.tonemap_white)
	)
	outdoor.queue_free()
	indoor.queue_free()
	ctx.timed_record(
		"lighting.grade_consistent",
		get_category(),
		ok,
		"hub and umbral_chapel share tonemap_mode and tonemap_white",
		start,
		"LIT-08"
	)


func _test_no_unused_constants() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string(VISUAL_LIGHTING_PATH)
	var ok := (
		not ("SHELL_TORCH_ENERGY" in text)
		and not ("OUTDOOR_PRESETS" in text)
		and not ("get_lighting_profile" in text)
	)
	ctx.timed_record(
		"lighting.no_unused_constants",
		get_category(),
		ok,
		"visual_lighting.gd has no OUTDOOR_PRESETS, SHELL_TORCH_ENERGY, or get_lighting_profile",
		start,
		"LIT-10"
	)
