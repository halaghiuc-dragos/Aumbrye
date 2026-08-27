class_name VisualLighting
extends RefCounted


const LightFlickerScript := preload("res://scripts/art/lighting/light_flicker.gd")
const BiomeAtmosphereFollowScript := preload(
	"res://scripts/art/lighting/biome_atmosphere_follow.gd"
)

const SOFT_OMNI_ATTENUATION := 1.48
const TORCH_OMNI_RANGE := 13.5
const TORCH_OMNI_ENERGY := 0.92
const WALL_TORCH_ENERGY := 0.78
const WALL_TORCH_RANGE := 10.0
const ROOM_FILL_ENERGY := 0.88
const SHELL_TORCH_SPACING := 16.0

const SKY_SHADER_PATH := "res://assets/shared/pixel_sky.gdshader"
const SKY_BIRDS_SCRIPT := "res://scripts/art/world/sky_birds.gd"
const SKY_BIRDS_NAME := "SkyBirds"

const GATE_ROW_WIND := Vector3(0.0, 0.0, 1.0)

const SKYLINE_SCRIPT := "res://scripts/art/world/distant_skyline.gd"
const SKYLINE_NAME := "DistantSkyline"

const REFLECTION_PROBE_NAME := "LevelReflectionProbe"
const HUB_PROBE_EXTENTS := Vector3(26.0, 12.0, 22.0)
const HUB_PROBE_ORIGIN := Vector3(0.0, 6.0, 0.0)
const ARENA_PROBE_EXTENTS := Vector3(17.0, 9.0, 17.0)
const ARENA_PROBE_ORIGIN := Vector3(0.0, 4.5, 0.0)
const LIGHTING_DATA_PATH := "content/art/lighting.json"

const SKY_UNIFORM_NAMES: PackedStringArray = [
	"zenith_color",
	"horizon_color",
	"ground_color",
	"apex_color",
	"bands",
	"band_softness",
	"horizon_falloff",
	"sun_color",
	"sun_size",
	"sun_glow",
	"cloud_amount",
	"cloud_color",
	"cloud_shadow_color",
	"cloud_drift",
	"cloud_ceiling",
]

static var _data_cache: Dictionary = {}
static var _atmosphere_root: WeakRef
static var _atmosphere_profile_id: String = ""
static var _atmosphere_follow: WeakRef


static func apply_hub(root: Node3D) -> void:
	apply_profile(root, "hub")
	attach_atmosphere(root, "hub")
	attach_sky_birds(root)
	attach_reflection_probe(root, HUB_PROBE_EXTENTS, HUB_PROBE_ORIGIN)
	attach_distant_skyline(root, "hub")
	WindService.set_fixed_direction(GATE_ROW_WIND)


static func apply_arena(root: Node3D) -> void:
	apply_profile(root, "hub")
	attach_atmosphere(root, "arena")
	attach_sky_birds(root)
	attach_reflection_probe(root, ARENA_PROBE_EXTENTS, ARENA_PROBE_ORIGIN)
	attach_distant_skyline(root, "hub")
	WindService.set_fixed_direction(GATE_ROW_WIND)


static func attach_distant_skyline(root: Node3D, profile_id: String) -> void:
	if root == null or root.get_node_or_null(SKYLINE_NAME) != null:
		return
	var sky: Dictionary = get_profile(profile_id).get("sky", {})
	var skyline := Node3D.new()
	skyline.name = SKYLINE_NAME
	skyline.set_script(load(SKYLINE_SCRIPT))
	root.add_child(skyline)
	skyline.call("build", _parse_color(sky.get("horizon", "#b4653c")))


static func attach_reflection_probe(root: Node3D, extents: Vector3, origin: Vector3) -> void:
	if root == null or root.get_node_or_null(REFLECTION_PROBE_NAME) != null:
		return
	var probe := ReflectionProbe.new()
	probe.name = REFLECTION_PROBE_NAME
	probe.size = extents * 2.0
	probe.origin_offset = Vector3.ZERO
	probe.position = origin
	probe.update_mode = ReflectionProbe.UPDATE_ONCE
	probe.interior = false
	probe.max_distance = 90.0
	probe.ambient_mode = ReflectionProbe.AMBIENT_ENVIRONMENT
	root.add_child(probe)


static func attach_sky_birds(root: Node3D) -> void:
	if root == null or root.get_node_or_null(SKY_BIRDS_NAME) != null:
		return
	var birds := Node3D.new()
	birds.name = SKY_BIRDS_NAME
	birds.set_script(load(SKY_BIRDS_SCRIPT))
	root.add_child(birds)


static func apply_waves_outdoors(root: Node3D) -> void:
	apply_profile(root, "hub")
	attach_atmosphere(root, "hub")
	attach_sky_birds(root)
	attach_distant_skyline(root, "hub")


static func profile_for_biome(biome_id: String) -> String:
	var data := _load_data()
	var mapped: Variant = data.get("biome_profile_map", {}).get(biome_id, "")
	if str(mapped) != "":
		return str(mapped)
	if data.get("profiles", {}).has(biome_id):
		return biome_id
	push_warning("VisualLighting: unknown biome '%s', falling back to hub" % biome_id)
	return "hub"


static func get_profile(profile_id: String) -> Dictionary:
	var profiles: Dictionary = _load_data().get("profiles", {})
	if profiles.has(profile_id):
		return (profiles[profile_id] as Dictionary).duplicate(true)
	push_warning("VisualLighting: unknown profile '%s', falling back to hub" % profile_id)
	return (profiles.get("hub", {}) as Dictionary).duplicate(true)


static func get_torch_config(profile_id: String) -> Dictionary:
	var torch: Dictionary = get_profile(profile_id).get("torch", {})
	return {
		"color": _parse_color(torch.get("color", "#ffb45a")),
		"energy": float(torch.get("energy", TORCH_OMNI_ENERGY)),
		"range": float(torch.get("range", TORCH_OMNI_RANGE)),
		"flicker": float(torch.get("flicker", 0.12)),
		"flicker_hz": float(torch.get("flicker_hz", 7.5)),
		"max_shadow_omnis": int(torch.get("max_shadow_omnis", 2)),
	}


static func get_torch_config_for_biome(biome_id: String) -> Dictionary:
	return get_torch_config(profile_for_biome(biome_id))


static func apply_profile(root: Node3D, profile_id: String) -> void:
	if root == null:
		return
	var profile := get_profile(profile_id)
	if profile.is_empty():
		return
	var has_sky := profile.has("sky")
	_apply_environment(root, profile, has_sky)
	_apply_sun(root, profile.get("sun", {}), has_sky)
	_apply_fill(root, profile.get("fill", {}))
	_apply_key_light(root, profile.get("key_light", {}))
	if not has_sky:
		_remove_node(root, "FillLight")
	if has_sky:
		NightLights.bind(root)
	else:
		NightLights.clear()
	if has_sky:
		DayNightService.register_level(
			_environment_of(root),
			root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D,
			root.get_node_or_null("FillLight") as DirectionalLight3D,
			profile_id
		)
	else:
		DayNightService.clear_level()


static func configure_soft_omni(
	light: OmniLight3D,
	color: Color,
	energy: float,
	light_range: float,
	cast_shadows: bool = false
) -> void:
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = SOFT_OMNI_ATTENUATION
	light.shadow_enabled = false
	if cast_shadows and PixelDioramaSettings.shadow_quality > 0:
		light.shadow_enabled = true
		light.shadow_bias = 0.03
		light.shadow_normal_bias = 1.4
		light.shadow_opacity = 0.85
		light.distance_fade_enabled = true
		light.distance_fade_begin = 18.0


static func attach_flicker(
	light: OmniLight3D, amount: float, hz: float, phase: float = -1.0
) -> void:
	if light == null or not PixelDioramaSettings.light_animation:
		return
	if amount <= 0.0:
		return
	if light.get_node_or_null("LightFlicker") != null:
		return
	var flicker := LightFlickerScript.new()
	flicker.name = "LightFlicker"
	light.add_child(flicker)
	var use_phase := phase if phase >= 0.0 else flicker_phase_for_position(light.global_position)
	flicker.setup(light, amount, hz, use_phase)


static func flicker_phase_for_position(pos: Vector3) -> float:
	return fposmod(pos.x * 12.9898 + pos.z * 78.233, TAU)


static func attach_atmosphere(root: Node3D, profile_id: String, follow: Node3D = null) -> void:
	if root == null:
		return
	_atmosphere_profile_id = profile_id
	_atmosphere_follow = weakref(follow) if follow != null else null
	if PixelDioramaSettings.particle_quality <= 0:
		_free_atmosphere(root)
		return
	var holder := root.get_node_or_null("BiomeAtmosphere") as Node3D
	if holder == null:
		holder = Node3D.new()
		holder.name = "BiomeAtmosphere"
		root.add_child(holder)
	_atmosphere_root = weakref(holder)
	_rebuild_atmosphere(holder, profile_id, follow)


static func refresh_atmosphere() -> void:
	var root_ref := _atmosphere_root
	if root_ref == null:
		return
	var holder := root_ref.get_ref() as Node3D
	if holder == null:
		return
	var scene_root := holder.get_parent() as Node3D
	if scene_root == null:
		return
	if PixelDioramaSettings.particle_quality <= 0:
		_free_atmosphere(scene_root)
		return
	var follow: Node3D = null
	if _atmosphere_follow != null:
		follow = _atmosphere_follow.get_ref() as Node3D
	attach_atmosphere(scene_root, _atmosphere_profile_id, follow)


static func _load_data() -> Dictionary:
	if _data_cache.is_empty():
		_data_cache = ContentLoader.load_json(LIGHTING_DATA_PATH)
	return _data_cache


static func _environment_of(root: Node3D) -> Environment:
	var node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	return node.environment if node else null


static func day_night_block() -> Dictionary:
	return _load_data().get("day_night", {})


static func _apply_environment(root: Node3D, profile: Dictionary, has_sky: bool) -> void:
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		root.add_child(env_node)
	var env := env_node.environment
	if env == null:
		env = Environment.new()
		env_node.environment = env
	var ambient: Dictionary = profile.get("ambient", {})
	var fog: Dictionary = profile.get("fog", {})
	if has_sky:
		env.background_mode = Environment.BG_SKY
		if env.sky == null:
			env.sky = Sky.new()
			env.sky.process_mode = Sky.PROCESS_MODE_AUTOMATIC
			env.sky.radiance_size = Sky.RADIANCE_SIZE_32
		_update_sky(env.sky, profile)
	else:
		env.background_mode = Environment.BG_COLOR
		var base := _parse_color(ambient.get("color", "#9e8f85"))
		env.background_color = base.lerp(Color(0.1, 0.09, 0.12), 0.68)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	if has_sky:
		env.ambient_light_color = _parse_color(ambient.get("color", "#9e8f85"))
	else:
		var base_ambient := _parse_color(ambient.get("color", "#9e8f85"))
		env.ambient_light_color = base_ambient.lerp(Color(0.78, 0.68, 0.55), 0.42)
	env.ambient_light_energy = float(ambient.get("energy", 0.5))
	env.fog_enabled = bool(fog.get("enabled", false))
	if env.fog_enabled:
		env.fog_light_color = _parse_color(fog.get("color", "#6b7699"))
		env.fog_density = float(fog.get("density", 0.003))
		env.fog_aerial_perspective = float(fog.get("aerial", 0.25))
		env.fog_sky_affect = float(fog.get("sky_affect", 0.0))
	PixelDioramaSettings.configure_environment(env)


static func _update_sky(sky: Sky, profile: Dictionary) -> void:
	var uniforms := sky_uniforms_for_profile_from_raw(profile)
	var mat: ShaderMaterial
	if sky.sky_material is ShaderMaterial:
		mat = sky.sky_material as ShaderMaterial
	else:
		mat = ShaderMaterial.new()
		mat.shader = load(SKY_SHADER_PATH) as Shader
		sky.sky_material = mat
	for key in uniforms:
		mat.set_shader_parameter(key, uniforms[key])


static func sky_uniforms_for_profile_from_raw(profile: Dictionary) -> Dictionary:
	var sky: Dictionary = profile.get("sky", {})
	var ambient: Dictionary = profile.get("ambient", {})
	var sun: Dictionary = profile.get("sun", {})
	return {
		"zenith_color": _parse_color(sky.get("zenith", "#4a6bad")),
		"horizon_color": _parse_color(sky.get("horizon", "#edb875")),
		"ground_color": _parse_color(sky.get("ground", "#3d3130")),
		"apex_color": _parse_color(
			sky.get("apex", "")
		) if str(sky.get("apex", "")) != "" else _parse_color(sky.get("zenith", "#4a6bad")).darkened(0.42),
		"bands": float(sky.get("bands", 8.0)),
		"band_softness": float(sky.get("band_softness", 0.45)),
		"horizon_falloff": float(sky.get("horizon_falloff", 2.4)),
		"sun_color": _parse_color(sun.get("color", ambient.get("color", "#ffe0a8"))),
		"sun_size": float(sky.get("sun_size", 0.045)),
		"sun_glow": float(sky.get("sun_glow", 0.4)),
		"cloud_amount": float(sky.get("cloud_amount", 0.0)),
		"cloud_color": _parse_color(sky.get("cloud_color", "#fae0c2")),
		"cloud_shadow_color": (
			_parse_color(sky.get("cloud_shadow", ""))
			if str(sky.get("cloud_shadow", "")) != ""
			else _parse_color(sky.get("cloud_color", "#fae0c2")).darkened(0.42)
		),
		"cloud_drift": float(sky.get("cloud_drift", 0.02)),
		"cloud_ceiling": float(sky.get("cloud_ceiling", 0.62)),
	}


static func _apply_sun(root: Node3D, sun_block: Dictionary, has_sky: bool) -> void:
	if not has_sky and sun_block.is_empty():
		_remove_node(root, "DirectionalLight3D")
		return
	var energy := float(sun_block.get("energy", 1.3))
	if energy <= 0.0:
		var sun_hide := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
		if sun_hide:
			sun_hide.visible = false
		return
	var sun := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		root.add_child(sun)
	sun.visible = true
	sun.light_color = _parse_color(sun_block.get("color", "#ffffff"))
	sun.light_energy = energy
	sun.rotation = _rotation_from_block(sun_block)
	var cast_shadows := bool(sun_block.get("shadows", true))
	PixelDioramaSettings.configure_directional_shadow(sun, cast_shadows)


static func _apply_fill(root: Node3D, fill_block: Dictionary) -> void:
	if fill_block.is_empty():
		_remove_node(root, "FillLight")
		return
	var energy := float(fill_block.get("energy", 0.0))
	if energy <= 0.0:
		_remove_node(root, "FillLight")
		return
	var fill := root.get_node_or_null("FillLight") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "FillLight"
		root.add_child(fill)
	fill.light_color = _parse_color(fill_block.get("color", "#a6b8e6"))
	fill.light_energy = energy
	fill.shadow_enabled = false
	fill.rotation = _rotation_from_block(fill_block)


static func _apply_key_light(root: Node3D, key_block: Dictionary) -> void:
	if key_block.is_empty():
		_remove_node(root, "KeyLight")
		return
	var energy := float(key_block.get("energy", 0.0))
	if energy <= 0.0:
		_remove_node(root, "KeyLight")
		return
	var key := root.get_node_or_null("KeyLight") as DirectionalLight3D
	if key == null:
		key = DirectionalLight3D.new()
		key.name = "KeyLight"
		root.add_child(key)
	key.visible = true
	key.light_color = _parse_color(key_block.get("color", "#ffffff"))
	key.light_energy = energy
	key.rotation = _rotation_from_block(key_block)
	var cast_shadows := bool(key_block.get("shadows", true))
	PixelDioramaSettings.configure_directional_shadow(key, cast_shadows)


static func _rebuild_atmosphere(holder: Node3D, profile_id: String, follow: Node3D) -> void:
	for child in holder.get_children():
		child.queue_free()
	if holder.get_script() == null:
		holder.set_script(BiomeAtmosphereFollowScript)
	holder.call("set_follow", follow)
	var profile := get_profile(profile_id)
	var atmosphere: Dictionary = profile.get("atmosphere", {})
	var motes: Dictionary = atmosphere.get("motes", {})
	if not motes.is_empty():
		var tint := _parse_color(motes.get("tint", "#b8a37a"))
		tint.a = float(motes.get("alpha", 0.28))
		_add_ambient_particles(
			holder,
			tint,
			int(motes.get("amount", 24)),
			float(motes.get("radius", 11.0)),
			float(motes.get("fall_speed", 0.15))
		)
	var fog: Dictionary = profile.get("fog", {})
	var fog_volume: Dictionary = atmosphere.get("fog_volume", {})
	if bool(fog.get("enabled", false)) and bool(fog_volume.get("enabled", false)):
		_enable_volumetric_fog(holder, fog, fog_volume)
		var size_arr: Array = fog_volume.get("size", [48.0, 8.0, 48.0])
		var fog_node := FogVolume.new()
		fog_node.name = "BiomeFogVolume"
		fog_node.size = Vector3(
			float(size_arr[0]), float(size_arr[1]), float(size_arr[2])
		)
		fog_node.position = Vector3(0.0, 3.0, 0.0)
		var fog_mat := FogMaterial.new()
		fog_mat.density = float(fog.get("density", 0.02)) * 0.35
		fog_mat.albedo = _parse_color(fog.get("color", "#1f1a2e"))
		fog_node.material = fog_mat
		holder.add_child(fog_node)


static func _enable_volumetric_fog(
	holder: Node3D, fog: Dictionary, fog_volume: Dictionary
) -> void:
	var scene_root := holder.get_parent()
	if scene_root == null:
		return
	var env_node := scene_root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null or env_node.environment == null:
		return
	var env := env_node.environment
	env.volumetric_fog_enabled = true
	env.volumetric_fog_density = float(fog_volume.get("volumetric_density", 0.012))
	env.volumetric_fog_albedo = _parse_color(fog.get("color", "#6b7699"))
	env.volumetric_fog_emission_energy = float(fog_volume.get("emission", 0.0))
	env.volumetric_fog_gi_inject = 0.0
	env.volumetric_fog_anisotropy = 0.35
	env.volumetric_fog_length = float(fog_volume.get("range", 42.0))
	env.volumetric_fog_detail_spread = 2.0
	env.volumetric_fog_ambient_inject = float(fog_volume.get("ambient_inject", 0.35))


static func _add_ambient_particles(
	parent: Node3D, tint: Color, amount: int, range_size: float, fall_speed: float
) -> void:
	var particles := GPUParticles3D.new()
	particles.name = "AmbientMotes"
	particles.amount = int(amount * PixelDioramaSettings.particle_amount_scale())
	particles.lifetime = 6.0
	particles.visibility_aabb = AABB(
		Vector3(-range_size, -2.0, -range_size), Vector3(range_size * 2.0, 8.0, range_size * 2.0)
	)
	var chunk := BoxMesh.new()
	chunk.size = Vector3(0.08, 0.08, 0.08)
	particles.draw_pass_1 = chunk
	var mat := ParticleProcessMaterial.new()
	mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	mat.emission_box_extents = Vector3(range_size, 3.0, range_size)
	mat.direction = Vector3(0.0, -1.0, 0.0)
	mat.spread = 18.0
	mat.initial_velocity_min = fall_speed * 0.4
	mat.initial_velocity_max = fall_speed
	mat.gravity = Vector3(0.0, -0.35, 0.0)
	mat.scale_min = 0.04
	mat.scale_max = 0.1
	mat.color = tint
	particles.process_material = mat
	parent.add_child(particles)


static func _free_atmosphere(root: Node3D) -> void:
	var holder := root.get_node_or_null("BiomeAtmosphere")
	if holder:
		holder.queue_free()
	_atmosphere_root = null


static func _remove_node(root: Node3D, node_name: String) -> void:
	var node := root.get_node_or_null(node_name)
	if node:
		node.queue_free()


static func _rotation_from_block(block: Dictionary) -> Vector3:
	var deg: Array = block.get("rotation_deg", [-28.6, 97.4, 0.0])
	return Vector3(
		deg_to_rad(float(deg[0])), deg_to_rad(float(deg[1])), deg_to_rad(float(deg[2]))
	)


static func _parse_color(raw: Variant) -> Color:
	if raw is Color:
		return raw
	var text := str(raw).strip_edges()
	if text.begins_with("#") and text.length() >= 7:
		return Color.html(text)
	if raw is Array and (raw as Array).size() >= 3:
		var arr: Array = raw
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color.WHITE
