class_name VisualLighting
extends RefCounted

## Single entry point for every light and environment decision in the game.
##
## Outdoor scenes (hub, arena, waves) use the named presets; dungeon interiors use
## apply_indoor_environment() plus configure_soft_omni() for torches and fills.
## Shadow and tonemap tuning always defers to PixelDioramaSettings so the pixel
## look stays consistent across scene types.

## Indoor tuning. Shadowless, wide-attenuation omnis keep chunky geometry readable
## without spraying noisy shadow edges across a 480x270 frame.
const SOFT_OMNI_ATTENUATION := 1.48
const TORCH_OMNI_RANGE := 13.5
const TORCH_OMNI_ENERGY := 0.92
const WALL_TORCH_ENERGY := 0.78
const WALL_TORCH_RANGE := 10.0
const ROOM_FILL_ENERGY := 0.88
const SHELL_TORCH_ENERGY := 0.72
const SHELL_TORCH_SPACING := 16.0

const SKY_SHADER_PATH := "res://assets/shared/pixel_sky.gdshader"

## Fog is kept deliberately thin. At 480x270 a dense fog flattens every distant
## silhouette into the background colour, which is the opposite of the crisp
## read the diorama style depends on; depth comes from the banded sky instead.
const OUTDOOR_PRESETS := {
	"hub": {
		"sky_zenith": Color(0.29, 0.42, 0.68),
		"sky_horizon": Color(0.93, 0.72, 0.46),
		"sky_ground": Color(0.24, 0.19, 0.18),
		"sky_bands": 8.0,
		"cloud_amount": 0.5,
		"cloud_color": Color(0.98, 0.88, 0.76),
		"ambient": Color(0.62, 0.56, 0.52),
		"ambient_energy": 0.03,
		"fog_color": Color(0.82, 0.66, 0.5),
		"fog_density": 0.0032,
		"fog_aerial": 0.22,
		"sun_color": Color(1.0, 0.88, 0.66),
		"sun_energy": 1.7,
		"sun_rotation": Vector3(-0.5, 1.7, 0.0),
		"fill_color": Color(0.5, 0.62, 0.9),
		"fill_energy": 0.0,
		"fill_rotation": Vector3(-0.25, -2.1, 0.0),
	},
	"arena": {
		"sky_zenith": Color(0.16, 0.22, 0.42),
		"sky_horizon": Color(0.56, 0.56, 0.72),
		"sky_ground": Color(0.14, 0.14, 0.2),
		"sky_bands": 7.0,
		"cloud_amount": 0.25,
		"cloud_color": Color(0.78, 0.78, 0.88),
		"ambient": Color(0.56, 0.56, 0.7),
		"ambient_energy": 0.44,
		"fog_color": Color(0.42, 0.46, 0.6),
		"fog_density": 0.0026,
		"fog_aerial": 0.25,
		"sun_color": Color(0.98, 0.92, 0.82),
		"sun_energy": 1.8,
		"sun_rotation": Vector3(-0.92, 0.65, 0.0),
		"fill_color": Color(0.62, 0.7, 0.96),
		"fill_energy": 0.3,
		"fill_rotation": Vector3(-0.2, -1.35, 0.0),
	},
	"waves_outdoors": {
		"sky_zenith": Color(0.3, 0.52, 0.86),
		"sky_horizon": Color(0.82, 0.9, 0.96),
		"sky_ground": Color(0.2, 0.28, 0.2),
		"sky_bands": 9.0,
		"cloud_amount": 0.65,
		"cloud_color": Color(1.0, 1.0, 0.98),
		"ambient": Color(0.68, 0.76, 0.7),
		"ambient_energy": 0.5,
		"fog_color": Color(0.74, 0.84, 0.92),
		"fog_density": 0.0018,
		"fog_aerial": 0.32,
		"sun_color": Color(1.0, 0.94, 0.76),
		"sun_energy": 1.85,
		"sun_rotation": Vector3(-0.88, 0.3, 0.0),
		"fill_color": Color(0.5, 0.68, 0.95),
		"fill_energy": 0.28,
		"fill_rotation": Vector3(-0.18, -1.8, 0.0),
	},
}


static func apply_hub(root: Node3D) -> void:
	apply_outdoor(root, "hub")


static func apply_arena(root: Node3D) -> void:
	apply_outdoor(root, "arena")


static func apply_waves_outdoors(root: Node3D) -> void:
	apply_outdoor(root, "waves_outdoors")


static func apply_outdoor(root: Node3D, preset_id: String) -> void:
	if root == null:
		return
	var preset: Dictionary = OUTDOOR_PRESETS.get(preset_id, OUTDOOR_PRESETS["hub"])
	_apply_environment(root, preset)
	_apply_sun(root, preset)
	_apply_fill(root, preset)


static func apply_indoor_environment(environment: Environment, lighting_profile: Dictionary) -> void:
	if environment == null:
		return
	var base_ambient: Color = lighting_profile.get("ambient_color", Color(0.58, 0.5, 0.44))
	environment.background_color = base_ambient.lerp(Color(0.1, 0.09, 0.12), 0.68)
	environment.ambient_light_color = base_ambient.lerp(Color(0.78, 0.68, 0.55), 0.42)
	environment.ambient_light_energy = maxf(float(lighting_profile.get("ambient_energy", 0.5)) * 0.82, 0.5)
	environment.fog_enabled = false
	PixelDioramaSettings.configure_environment(environment)
	if PixelDioramaSettings.linear_tonemap:
		environment.tonemap_exposure = 1.0
		environment.tonemap_white = 1.2
	else:
		environment.tonemap_exposure = 1.02
		environment.tonemap_white = 1.42


static func configure_soft_omni(light: OmniLight3D, color: Color, energy: float, light_range: float) -> void:
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = SOFT_OMNI_ATTENUATION
	light.shadow_enabled = false


static func _apply_environment(root: Node3D, preset: Dictionary) -> void:
	var env_node := root.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		env_node = WorldEnvironment.new()
		env_node.name = "WorldEnvironment"
		root.add_child(env_node)

	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	env.sky = _make_sky(preset)
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = preset.get("ambient", Color(0.6, 0.58, 0.55))
	env.ambient_light_energy = float(preset.get("ambient_energy", 0.5))
	env.fog_enabled = true
	env.fog_light_color = preset.get("fog_color", Color(0.55, 0.55, 0.6))
	env.fog_density = float(preset.get("fog_density", 0.003))
	env.fog_aerial_perspective = float(preset.get("fog_aerial", 0.25))
	# Fog must not touch the sky, or the banded gradient washes into one colour.
	env.fog_sky_affect = 0.0
	# configure_environment owns tonemap and glow; the user's glow choice wins.
	PixelDioramaSettings.configure_environment(env)
	env_node.environment = env


static func _make_sky(preset: Dictionary) -> Sky:
	var mat := ShaderMaterial.new()
	mat.shader = load(SKY_SHADER_PATH) as Shader
	mat.set_shader_parameter("zenith_color", preset.get("sky_zenith", Color(0.26, 0.36, 0.58)))
	mat.set_shader_parameter("horizon_color", preset.get("sky_horizon", Color(0.76, 0.7, 0.6)))
	mat.set_shader_parameter("ground_color", preset.get("sky_ground", Color(0.18, 0.16, 0.18)))
	mat.set_shader_parameter("bands", float(preset.get("sky_bands", 8.0)))
	mat.set_shader_parameter("sun_color", preset.get("sun_color", Color(1.0, 0.94, 0.76)))
	mat.set_shader_parameter("cloud_amount", float(preset.get("cloud_amount", 0.0)))
	mat.set_shader_parameter("cloud_color", preset.get("cloud_color", Color(0.95, 0.93, 0.9)))
	var sky := Sky.new()
	sky.sky_material = mat
	# The sky is flat colour bands; a big radiance cubemap would cost more than
	# it contributes, since ambient comes from an explicit colour.
	sky.radiance_size = Sky.RADIANCE_SIZE_32
	sky.process_mode = Sky.PROCESS_MODE_REALTIME
	return sky


static func _apply_sun(root: Node3D, preset: Dictionary) -> void:
	var sun := root.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun == null:
		sun = DirectionalLight3D.new()
		sun.name = "DirectionalLight3D"
		root.add_child(sun)
	sun.light_color = preset.get("sun_color", Color.WHITE)
	sun.light_energy = float(preset.get("sun_energy", 1.3))
	sun.rotation = preset.get("sun_rotation", Vector3(-0.45, 0.35, 0.0))
	PixelDioramaSettings.configure_directional_shadow(sun)


static func _apply_fill(root: Node3D, preset: Dictionary) -> void:
	var fill := root.get_node_or_null("FillLight") as DirectionalLight3D
	if fill == null:
		fill = DirectionalLight3D.new()
		fill.name = "FillLight"
		root.add_child(fill)
	fill.light_color = preset.get("fill_color", Color(0.65, 0.72, 0.9))
	fill.light_energy = float(preset.get("fill_energy", 0.22))
	fill.shadow_enabled = false
	fill.rotation = preset.get("fill_rotation", Vector3(-0.25, -2.0, 0.0))
