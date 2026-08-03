extends RefCounted
class_name DungeonLighting

## Shared soft indoor lighting tuning for castle + endless dungeon modes.

const SOFT_OMNI_ATTENUATION := 1.48
const TORCH_OMNI_RANGE := 13.5
const TORCH_OMNI_ENERGY := 0.92
const WALL_TORCH_ENERGY := 0.78
const WALL_TORCH_RANGE := 10.0
const ROOM_FILL_ENERGY := 0.88
const SHELL_TORCH_ENERGY := 0.72
const SHELL_TORCH_SPACING := 16.0


static func apply_indoor_environment(environment: Environment, lighting_profile: Dictionary) -> void:
	var base_ambient: Color = lighting_profile.get("ambient_color", Color(0.58, 0.5, 0.44))
	environment.background_color = base_ambient.lerp(Color(0.1, 0.09, 0.12), 0.68)
	environment.ambient_light_color = base_ambient.lerp(Color(0.78, 0.68, 0.55), 0.42)
	environment.ambient_light_energy = maxf(float(lighting_profile.get("ambient_energy", 0.5)) * 0.82, 0.5)
	environment.fog_enabled = false
	PixelDioramaSettings.configure_environment(environment)
	if PixelDioramaSettings.linear_tonemap:
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.tonemap_exposure = 1.0
		environment.tonemap_white = 1.2
	else:
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_exposure = 1.02
		environment.tonemap_white = 1.42


static func configure_soft_omni(light: OmniLight3D, color: Color, energy: float, light_range: float) -> void:
	light.light_color = color
	light.light_energy = energy
	light.omni_range = light_range
	light.omni_attenuation = SOFT_OMNI_ATTENUATION
	light.shadow_enabled = false
