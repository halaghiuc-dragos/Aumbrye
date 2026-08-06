class_name VisualLighting
extends RefCounted

## Single entry point for every light and environment decision in the game.
##
## Profiles live in `content/art/lighting.json`. Outdoor scenes use sky + sun + fill;
## dungeon interiors use key light + torch omnis. Shadow and tonemap tuning defer to
## PixelDioramaSettings so the pixel look stays consistent across scene types.

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
const LIGHTING_DATA_PATH := "content/art/lighting.json"

const SKY_UNIFORM_NAMES: PackedStringArray = [
	"zenith_color",
	"horizon_color",
	"ground_color",
	"bands",
	"horizon_falloff",
	"sun_color",
	"sun_size",
	"sun_glow",
	"cloud_amount",
	"cloud_color",
]

static var _data_cache: Dictionary = {}
static var _atmosphere_root: WeakRef
static var _atmosphere_profile_id: String = ""
static var _atmosphere_follow: WeakRef


static func apply_hub(root: Node3D) -> void:
	apply_profile(root, "hub")


static func apply_arena(root: Node3D) -> void:
	apply_profile(root, "arena")


static func apply_waves_outdoors(root: Node3D) -> void:
	apply_profile(root, "waves_outdoors")


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


static func profile_summary(profile_id: String) -> Dictionary:
	var profile := get_profile(profile_id)
	if profile.is_empty():
		return {}
	var ambient: Dictionary = profile.get("ambient", {})
	var fog: Dictionary = profile.get("fog", {})
	var torch: Dictionary = profile.get("torch", {})
	return {
		"ambient_color": _parse_color(ambient.get("color", "#9e8f85")),
		"ambient_energy": float(ambient.get("energy", 0.5)),
		"fog_enabled": bool(fog.get("enabled", false)),
		"fog_color": _parse_color(fog.get("color", "#332e38")),
		"fog_density": float(fog.get("density", 0.01)),
		"torch_color": _parse_color(torch.get("color", ambient.get("color", "#ffb45a"))),
		"torch_energy": float(torch.get("energy", TORCH_OMNI_ENERGY)),
	}


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


static func apply_indoor_environment(environment: Environment, lighting_profile: Dictionary) -> void:
	if environment == null:
		return
	var base_ambient: Color = lighting_profile.get("ambient_color", Color(0.58, 0.5, 0.44))
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = base_ambient.lerp(Color(0.1, 0.09, 0.12), 0.68)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = base_ambient.lerp(Color(0.78, 0.68, 0.55), 0.42)
	environment.ambient_light_energy = float(lighting_profile.get("ambient_energy", 0.5))
	var fog_enabled := bool(lighting_profile.get("fog_enabled", false))
	environment.fog_enabled = fog_enabled
	if fog_enabled:
		environment.fog_light_color = lighting_profile.get("fog_color", Color(0.35, 0.32, 0.38))
		environment.fog_density = float(lighting_profile.get("fog_density", 0.004))
		environment.fog_sky_affect = 0.0
	PixelDioramaSettings.configure_environment(environment)


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


static func apply_biome_atmosphere(root: Node3D, biome_id: String, follow: Node3D = null) -> void:
	attach_atmosphere(root, profile_for_biome(biome_id), follow)


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


static func sky_uniforms_for_profile(profile_id: String) -> Dictionary:
	var sky: Dictionary = get_profile(profile_id).get("sky", {})
	if sky.is_empty():
		return {}
	var ambient: Dictionary = get_profile(profile_id).get("ambient", {})
	var sun: Dictionary = get_profile(profile_id).get("sun", {})
	return {
		"zenith_color": _parse_color(sky.get("zenith", "#4a6bad")),
		"horizon_color": _parse_color(sky.get("horizon", "#edb875")),
		"ground_color": _parse_color(sky.get("ground", "#3d3130")),
		"bands": float(sky.get("bands", 8.0)),
		"horizon_falloff": float(sky.get("horizon_falloff", 2.4)),
		"sun_color": _parse_color(sun.get("color", ambient.get("color", "#ffe0a8"))),
		"sun_size": float(sky.get("sun_size", 0.045)),
		"sun_glow": float(sky.get("sun_glow", 0.4)),
		"cloud_amount": float(sky.get("cloud_amount", 0.0)),
		"cloud_color": _parse_color(sky.get("cloud_color", "#fae0c2")),
	}


static func tonemap_white_for_profile(profile_id: String) -> float:
	var grade: Dictionary = get_profile(profile_id).get("grade", {})
	if grade.has("white"):
		return float(grade.get("white", 1.2))
	return 1.2 if PixelDioramaSettings.linear_tonemap else 1.0


static func _load_data() -> Dictionary:
	if _data_cache.is_empty():
		_data_cache = ContentLoader.load_json(LIGHTING_DATA_PATH)
	return _data_cache


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
		"bands": float(sky.get("bands", 8.0)),
		"horizon_falloff": float(sky.get("horizon_falloff", 2.4)),
		"sun_color": _parse_color(sun.get("color", ambient.get("color", "#ffe0a8"))),
		"sun_size": float(sky.get("sun_size", 0.045)),
		"sun_glow": float(sky.get("sun_glow", 0.4)),
		"cloud_amount": float(sky.get("cloud_amount", 0.0)),
		"cloud_color": _parse_color(sky.get("cloud_color", "#fae0c2")),
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
	if bool(fog.get("enabled", false)) and bool(fog_volume.get("enabled", true)):
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
