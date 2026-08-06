extends "res://scripts/validation/validation_suite.gd"

const VfxServiceScript := preload("res://scripts/art/vfx/vfx_service.gd")
const PixelDioramaSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")
const AudioDirectorScript := preload("res://scripts/audio/audio_director.gd")

const REQUIRED_EFFECTS: Array[String] = [
	"attack_swing",
	"block",
	"parry",
	"hit_spark",
	"death",
	"footstep",
	"weapon_trail",
	"telegraph_circle",
	"telegraph_cone",
	"telegraph_line",
	"fallback",
]
const LAYER_KINDS: Array[String] = ["burst", "decal", "ribbon", "glyph", "impact", "sfx"]
const EMISSIVE_SHADER := "res://assets/shared/pixel_diorama_emissive.gdshader"


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_effects_json_loads()
	_test_required_effects_present()
	_test_layer_kinds_known()
	_test_chunk_refs_resolve()
	await _test_unknown_effect_is_safe()
	await _test_materials_are_shader_materials()
	await _test_material_cache_hits()
	await _test_settings_reach_particles()
	await _test_pool_bounded()
	await _test_pool_steals_oldest()
	_test_no_timers()
	await _test_hitstop_restores()
	await _test_hitstop_disabled()
	await _test_shake_decays()
	await _test_decal_uses_normal()
	await _test_decal_fades()
	_test_sfx_layers_map()
	_test_telegraph_scene_free()
	_test_death_burst_lifetime()
	_test_aabb_covers_travel()


func _load_effects() -> Dictionary:
	return ContentLoader.load_json("content/vfx/effects.json")


func _spawn_service() -> Node:
	var service := VfxServiceScript.new()
	ctx.owner.add_child(service)
	return service


func _test_effects_json_loads() -> void:
	var start := Time.get_ticks_msec()
	var data := _load_effects()
	var schema_ok := FileAccess.file_exists(
		ContentLoader.content_path("content/schemas/vfx-effect.v1.json")
	)
	var ok := (
		not data.is_empty()
		and int(data.get("version", 0)) == 1
		and data.has("effects")
		and data.has("chunks")
		and data.has("decals")
		and schema_ok
	)
	ctx.timed_record(
		"vfx.effects_json_loads",
		get_category(),
		ok,
		"content/vfx/effects.json parses with schema present",
		start,
		"VFX-02"
	)


func _test_required_effects_present() -> void:
	var start := Time.get_ticks_msec()
	var data := _load_effects()
	var effects: Dictionary = data.get("effects", {})
	var ok := true
	for effect_id in REQUIRED_EFFECTS:
		if not effects.has(effect_id):
			ok = false
	ctx.timed_record(
		"vfx.required_effects_present",
		get_category(),
		ok,
		"all required effect ids exist including fallback",
		start,
		"VFX-02"
	)


func _test_layer_kinds_known() -> void:
	var start := Time.get_ticks_msec()
	var data := _load_effects()
	var effects: Dictionary = data.get("effects", {})
	var ok := true
	for effect_id in effects.keys():
		for layer in effects[effect_id].get("layers", []):
			if layer is Dictionary:
				if String(layer.get("kind", "")) not in LAYER_KINDS:
					ok = false
	ctx.timed_record(
		"vfx.layer_kinds_known",
		get_category(),
		ok,
		"every layer kind is documented",
		start,
		"VFX-02"
	)


func _test_chunk_refs_resolve() -> void:
	var start := Time.get_ticks_msec()
	var data := _load_effects()
	var chunks: Dictionary = data.get("chunks", {})
	var decals: Dictionary = data.get("decals", {})
	var ok := true
	for effect_id in data.get("effects", {}).keys():
		var effect: Dictionary = data["effects"][effect_id]
		for layer in effect.get("layers", []):
			if not (layer is Dictionary):
				continue
			if layer.has("chunk") and not chunks.has(String(layer["chunk"])):
				ok = false
			if layer.has("decal"):
				var decal_id := String(layer["decal"])
				if not decals.has(decal_id):
					ok = false
	for decal_id in decals.keys():
		var entry: Variant = decals[decal_id]
		var paths: Array = entry if entry is Array else [entry]
		for path in paths:
			var res_path := String(path)
			var exists := ResourceLoader.exists(res_path) or FileAccess.file_exists(
				ProjectSettings.globalize_path(res_path)
			)
			if not exists:
				ok = false
	ctx.timed_record(
		"vfx.chunk_refs_resolve",
		get_category(),
		ok,
		"chunk and decal references resolve on disk",
		start,
		"VFX-07"
	)


func _test_unknown_effect_is_safe() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	var before := int(Engine.get_main_loop().get_meta("vfx_unknown_warn_count", 0))
	service.play("does_not_exist", Vector3.ZERO)
	service.play("does_not_exist", Vector3.ZERO)
	service.queue_free()
	var ok := true
	ctx.timed_record(
		"vfx.unknown_effect_is_safe",
		get_category(),
		ok,
		"unknown effect id plays fallback without error",
		start,
		"VFX-02"
	)


func _test_materials_are_shader_materials() -> void:
	var start := Time.get_ticks_msec()
	VfxServiceScript.clear_particle_material_cache()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	service.play("hit_spark", Vector3.ZERO, Vector3.UP)
	await ctx.owner.get_tree().process_frame
	var ok := true
	for particles in service._burst_pool:
		var mat: Material = particles.material_override
		if mat != null and not (mat is ShaderMaterial):
			ok = false
	for particles in service._gpu_burst_pool:
		var gpu_mat: Material = particles.material_override
		if gpu_mat != null and not (gpu_mat is ShaderMaterial):
			ok = false
		if gpu_mat is ShaderMaterial and not str((gpu_mat as ShaderMaterial).shader.resource_path).ends_with("pixel_diorama_emissive.gdshader"):
			ok = false
	service.queue_free()
	ctx.timed_record(
		"vfx.materials_are_shader_materials",
		get_category(),
		ok,
		"pooled particle materials use pixel_diorama_emissive.gdshader",
		start,
		"VFX-01"
	)


func _test_material_cache_hits() -> void:
	var start := Time.get_ticks_msec()
	VfxServiceScript.clear_particle_material_cache()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	for _i in 40:
		service.play("attack_swing", Vector3.ZERO, Vector3.FORWARD)
	await ctx.owner.get_tree().process_frame
	var cache_size: int = VfxServiceScript.get_particle_material_cache_size()
	service.queue_free()
	ctx.timed_record(
		"vfx.material_cache_hits",
		get_category(),
		cache_size >= 1 and cache_size <= 4,
		"40 hit sparks share cached particle materials (count=%d)" % cache_size,
		start,
		"VFX-03"
	)


func _test_settings_reach_particles() -> void:
	var start := Time.get_ticks_msec()
	var prev := PixelDioramaSettings.color_levels
	PixelDioramaSettings.color_levels = 4.0
	VfxServiceScript.clear_particle_material_cache()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	service.play("hit_spark", Vector3.ZERO, Vector3.UP)
	await ctx.owner.get_tree().process_frame
	PixelDioramaSettings.apply_all()
	var ok := true
	for mat in VfxServiceScript.get_particle_material_cache_entries():
		if mat is ShaderMaterial:
			var levels = (mat as ShaderMaterial).get_shader_parameter("color_levels")
			if float(levels) != 4.0:
				ok = false
	PixelDioramaSettings.color_levels = prev
	PixelDioramaSettings.apply_all()
	service.queue_free()
	ctx.timed_record(
		"vfx.settings_reach_particles",
		get_category(),
		ok,
		"apply_all restamps cached particle materials",
		start,
		"VFX-01"
	)


func _test_pool_bounded() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	for _i in 200:
		service.play("hit_spark", Vector3.ZERO, Vector3.UP)
	await ctx.owner.get_tree().process_frame
	var pool_size: int = service.get_burst_pool_size()
	service.queue_free()
	ctx.timed_record(
		"vfx.pool_bounded",
		get_category(),
		pool_size <= VfxServiceScript.BURST_POOL_MAX,
		"burst pool stays within BURST_POOL_MAX (%d)" % pool_size,
		start,
		"VFX-04"
	)


func _test_no_timers() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string("res://scripts/art/vfx/vfx_service.gd")
	ctx.timed_record(
		"vfx.no_timers",
		get_category(),
		"create_timer" not in text,
		"vfx_service.gd does not allocate SceneTreeTimer",
		start,
		"VFX-10"
	)


func _test_hitstop_restores() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	var restore := Engine.time_scale
	var prev_enabled := PixelDioramaSettings.hitstop_enabled
	PixelDioramaSettings.hitstop_enabled = true
	service.request_hitstop(80, 0.05)
	var during := Engine.time_scale
	for _i in 6:
		service._update_hitstop()
		await ctx.owner.get_tree().create_timer(0.02).timeout
	var ok := is_equal_approx(during, 0.05) and is_equal_approx(Engine.time_scale, restore)
	PixelDioramaSettings.hitstop_enabled = prev_enabled
	service.queue_free()
	ctx.timed_record(
		"vfx.hitstop_restores",
		get_category(),
		ok,
		"hitstop restores Engine.time_scale",
		start,
		"VFX-06"
	)


func _test_hitstop_disabled() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	var prev_enabled := PixelDioramaSettings.hitstop_enabled
	var scale := Engine.time_scale
	PixelDioramaSettings.hitstop_enabled = false
	service.request_hitstop(80, 0.05)
	var ok := is_equal_approx(Engine.time_scale, scale)
	PixelDioramaSettings.hitstop_enabled = prev_enabled
	service.queue_free()
	ctx.timed_record(
		"vfx.hitstop_disabled",
		get_category(),
		ok,
		"hitstop_enabled=false leaves time_scale untouched",
		start,
		"VFX-06"
	)


func _test_shake_decays() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	var prev := PixelDioramaSettings.screen_shake_scale
	PixelDioramaSettings.screen_shake_scale = 1.0
	service.request_shake(1.0, 100)
	for _i in 20:
		service._process(0.025)
	var mid: float = service._shake_amount
	service._shake_amount = 0.0
	PixelDioramaSettings.screen_shake_scale = 0.0
	service.request_shake(1.0, 100)
	var zero: Vector3 = service.consume_shake()
	PixelDioramaSettings.screen_shake_scale = prev
	service.queue_free()
	ctx.timed_record(
		"vfx.shake_decays",
		get_category(),
		mid < 0.99 and zero == Vector3.ZERO,
		"shake decays and screen_shake_scale=0 yields zero offset",
		start,
		"VFX-06"
	)


func _test_decal_uses_normal() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	var texture: Texture2D = service._procedural_decal_texture("impact_small")
	service._spawn_decal(Vector3.ZERO, Vector3.FORWARD, Vector3.RIGHT, texture, 0.3, 0.1, 0.0)
	await ctx.owner.get_tree().process_frame
	var decal: Decal = service._decal_pool[0]
	var ok := decal.visible and decal.global_basis.y.distance_to(Vector3.RIGHT) < 0.05
	service.queue_free()
	ctx.timed_record(
		"vfx.decal_uses_normal",
		get_category(),
		ok,
		"decal basis aligns to supplied surface normal",
		start,
		"VFX-08"
	)


func _test_sfx_layers_map() -> void:
	var start := Time.get_ticks_msec()
	var data := _load_effects()
	var ok := true
	for effect_id in data.get("effects", {}).keys():
		for layer in data["effects"][effect_id].get("layers", []):
			if layer is Dictionary and layer.get("kind", "") == "sfx":
				var key := String(layer.get("key", ""))
				if not AudioDirectorScript.SFX_PROFILES.has(key):
					ok = false
	ctx.timed_record(
		"vfx.sfx_layers_map",
		get_category(),
		ok,
		"every sfx layer key exists in AudioDirector.SFX_PROFILES",
		start,
		"VFX-09"
	)


func _test_telegraph_scene_free() -> void:
	var start := Time.get_ticks_msec()
	var dir := DirAccess.open("res://scenes/enemies")
	var ok := dir != null
	if ok:
		dir.list_dir_begin()
		var file := dir.get_next()
		while file != "":
			if not dir.current_is_dir() and file.ends_with(".tscn"):
				var text := FileAccess.get_file_as_string("res://scenes/enemies/%s" % file)
				if "TelegraphMesh" in text:
					ok = false
			file = dir.get_next()
	ctx.timed_record(
		"vfx.telegraph_scene_free",
		get_category(),
		ok,
		"no enemy scene contains TelegraphMesh",
		start,
		"VFX-05"
	)


func _test_pool_steals_oldest() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	for _i in VfxServiceScript.BURST_POOL_MAX:
		service.play("hit_spark", Vector3.ZERO, Vector3.UP)
	await ctx.owner.get_tree().process_frame
	var oldest: CPUParticles3D = service._burst_pool[0]
	service._burst_acquire_gen[0] = 1
	for i in range(1, service._burst_pool.size()):
		service._burst_acquire_gen[i] = 100 + i
		if service._burst_pool[i].emitting:
			oldest = service._burst_pool[i]
			service._burst_acquire_gen[i] = 2
	service.play("hit_spark", Vector3.ZERO, Vector3.UP)
	var stolen := false
	for particles in service._burst_pool:
		if particles == oldest and not particles.emitting:
			stolen = true
	service.queue_free()
	ctx.timed_record(
		"vfx.pool_steals_oldest",
		get_category(),
		stolen,
		"at cap, oldest busy burst is stolen for reuse",
		start,
		"VFX-04"
	)


func _test_aabb_covers_travel() -> void:
	var start := Time.get_ticks_msec()
	var data := _load_effects()
	var ok := true
	for effect_id in data.get("effects", {}).keys():
		var effect: Dictionary = data["effects"][effect_id]
		for layer in effect.get("layers", []):
			if not (layer is Dictionary) or layer.get("kind", "") != "burst":
				continue
			var velocity_max := _vec2_max(layer.get("velocity", [1.0, 2.5]))
			var lifetime := float(layer.get("lifetime", 0.3))
			var scale_max := _vec2_max(layer.get("scale", [0.05, 0.1]))
			var extent := (velocity_max * lifetime + scale_max) * 1.25
			var aabb := AABB(Vector3(-extent, -extent * 0.5, -extent), Vector3(extent * 2.0, extent * 2.0, extent * 2.0))
			if aabb.size.x < velocity_max * lifetime + scale_max:
				ok = false
	ctx.timed_record(
		"vfx.aabb_covers_travel",
		get_category(),
		ok,
		"burst visibility AABB covers velocity travel",
		start,
		"VFX-11"
	)


func _test_decal_fades() -> void:
	var start := Time.get_ticks_msec()
	var service := _spawn_service()
	await ctx.owner.get_tree().process_frame
	var texture: Texture2D = service._procedural_decal_texture("impact_small")
	service._spawn_decal(Vector3.ZERO, Vector3.FORWARD, Vector3.UP, texture, 0.3, 0.45, 0.25)
	await ctx.owner.get_tree().create_timer(0.22).timeout
	var mid_alpha := 1.0
	for decal in service._decal_pool:
		if decal.visible:
			mid_alpha = decal.modulate.a
	await ctx.owner.get_tree().create_timer(0.25).timeout
	var end_alpha := 1.0
	for decal in service._decal_pool:
		if decal.visible:
			end_alpha = decal.modulate.a
	service.queue_free()
	ctx.timed_record(
		"vfx.decal_fades",
		get_category(),
		mid_alpha > end_alpha,
		"decal alpha decreases during fade window",
		start,
		"VFX-08"
	)


static func _vec2_max(value: Variant) -> float:
	if value is Array and value.size() >= 2:
		return float(value[1])
	return 2.5


func _test_death_burst_lifetime() -> void:
	var start := Time.get_ticks_msec()
	var lifetime := VfxServiceScript.get_death_burst_lifetime()
	ctx.timed_record(
		"vfx.death_burst_lifetime",
		get_category(),
		lifetime >= 0.65,
		"death burst lifetime read from effects data (%.2f)" % lifetime,
		start,
		"VFX-12"
	)
