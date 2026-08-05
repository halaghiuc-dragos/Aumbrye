extends RefCounted
class_name PixelDioramaSettings

## User-configurable pixel-diorama visual settings (persisted in LocalSave meta).
##
## Single source of truth for every tunable that shapes the pixel look: internal
## render resolution, surface shader uniforms, shading bands, and the screen-space
## finish pass. Art modules read from here rather than defining their own defaults.

const SAVE_KEY := "pixel_diorama"

const SURFACE_SHADER_SUFFIX := "pixel_diorama_surface.gdshader"
const EMISSIVE_SHADER_SUFFIX := "pixel_diorama_emissive.gdshader"
const LEGACY_SHADER_SUFFIX := "pixel_diorama.gdshader"
const SCREEN_FINISH_SHADER_PATH := "res://assets/shared/pixel_screen_finish.gdshader"

const DEFAULT_PIXEL_SCALE := 8.0
const DEFAULT_COLOR_LEVELS := 6.0
const DEFAULT_EDGE_STRENGTH := 0.24
const DEFAULT_STITCH_STRENGTH := 0.16
const DEFAULT_PATTERN_STRENGTH := 0.5
const DEFAULT_SHADE_BANDS := 4.0
const DEFAULT_SHADE_DITHER := 0.55
const DEFAULT_LIGHT_WRAP := 0.16
const DEFAULT_AMBIENT_OCCLUSION := true
const DEFAULT_RIM_STRENGTH := 0.08
const DEFAULT_LINEAR_TONEMAP := true
const DEFAULT_GLOW_ENABLED := true
const DEFAULT_NEAREST_TEXTURE_FILTER := true
const DEFAULT_ANTI_ALIASING_OFF := true
const DEFAULT_LOW_RES_VIEWPORT := true
const DEFAULT_VIEWPORT_WIDTH := 480
const DEFAULT_VIEWPORT_HEIGHT := 270
const DEFAULT_CAMERA_SNAP := false
const DEFAULT_SCREEN_FINISH := true
const DEFAULT_CONTRAST := 1.08
const DEFAULT_SATURATION := 1.06
const DEFAULT_VIGNETTE := 0.18
const DEFAULT_POSTERIZE_LEVELS := 0.0
const DEFAULT_SHADOW_QUALITY := 1
const DEFAULT_PARTICLE_QUALITY := 1

const QUALITY_LABELS: Array[String] = ["Low", "Medium", "High"]

## Internal render resolutions offered in Settings. All are 16:9 so the
## nearest-neighbour upscale stays square-pixel at common window sizes.
const RESOLUTION_PRESETS: Array = [
	{"label": "320 x 180 (chunky)", "width": 320, "height": 180},
	{"label": "480 x 270 (default)", "width": 480, "height": 270},
	{"label": "640 x 360 (fine)", "width": 640, "height": 360},
	{"label": "854 x 480 (soft)", "width": 854, "height": 480},
	{
		"label": "1280 x 720 (HD)",
		"width": 1280,
		"height": 720,
		"native": true,
		"pixel_scale": 3.0,
		"color_levels": 12.0,
		"shade_bands": 6.0,
		"edge_strength": 0.14,
		"pattern_strength": 0.28,
		"shade_dither": 0.35,
	},
	{
		"label": "1920 x 1080 (Full HD)",
		"width": 1920,
		"height": 1080,
		"native": true,
		"pixel_scale": 2.0,
		"color_levels": 16.0,
		"shade_bands": 8.0,
		"edge_strength": 0.1,
		"pattern_strength": 0.2,
		"shade_dither": 0.25,
	},
]

static var pixel_scale: float = DEFAULT_PIXEL_SCALE
static var color_levels: float = DEFAULT_COLOR_LEVELS
static var edge_strength: float = DEFAULT_EDGE_STRENGTH
static var stitch_strength: float = DEFAULT_STITCH_STRENGTH
static var pattern_strength: float = DEFAULT_PATTERN_STRENGTH
static var shade_bands: float = DEFAULT_SHADE_BANDS
static var shade_dither: float = DEFAULT_SHADE_DITHER
static var light_wrap: float = DEFAULT_LIGHT_WRAP
static var rim_strength: float = DEFAULT_RIM_STRENGTH
static var linear_tonemap: bool = DEFAULT_LINEAR_TONEMAP
static var glow_enabled: bool = DEFAULT_GLOW_ENABLED
static var ambient_occlusion_enabled: bool = DEFAULT_AMBIENT_OCCLUSION
static var nearest_texture_filter: bool = DEFAULT_NEAREST_TEXTURE_FILTER
static var anti_aliasing_off: bool = DEFAULT_ANTI_ALIASING_OFF
static var low_res_viewport_enabled: bool = false
static var viewport_width: int = DEFAULT_VIEWPORT_WIDTH
static var viewport_height: int = DEFAULT_VIEWPORT_HEIGHT
static var camera_snap_enabled: bool = DEFAULT_CAMERA_SNAP
static var screen_finish_enabled: bool = DEFAULT_SCREEN_FINISH
static var screen_contrast: float = DEFAULT_CONTRAST
static var screen_saturation: float = DEFAULT_SATURATION
static var vignette_strength: float = DEFAULT_VIGNETTE
static var posterize_levels: float = DEFAULT_POSTERIZE_LEVELS
static var shadow_quality: int = DEFAULT_SHADOW_QUALITY
static var particle_quality: int = DEFAULT_PARTICLE_QUALITY

## Height the SubViewport actually renders at, which is the requested preset
## rounded to an integer divisor of the window. Set by PixelDioramaViewport.
static var active_render_height: int = DEFAULT_VIEWPORT_HEIGHT


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	pixel_scale = float(data.get("pixel_scale", DEFAULT_PIXEL_SCALE))
	color_levels = float(data.get("color_levels", DEFAULT_COLOR_LEVELS))
	edge_strength = float(data.get("edge_strength", DEFAULT_EDGE_STRENGTH))
	stitch_strength = float(data.get("stitch_strength", DEFAULT_STITCH_STRENGTH))
	pattern_strength = float(data.get("pattern_strength", DEFAULT_PATTERN_STRENGTH))
	shade_bands = float(data.get("shade_bands", DEFAULT_SHADE_BANDS))
	shade_dither = float(data.get("shade_dither", DEFAULT_SHADE_DITHER))
	light_wrap = float(data.get("light_wrap", DEFAULT_LIGHT_WRAP))
	rim_strength = float(data.get("rim_strength", DEFAULT_RIM_STRENGTH))
	linear_tonemap = bool(data.get("linear_tonemap", DEFAULT_LINEAR_TONEMAP))
	glow_enabled = bool(data.get("glow_enabled", DEFAULT_GLOW_ENABLED))
	ambient_occlusion_enabled = bool(
		data.get("ambient_occlusion_enabled", DEFAULT_AMBIENT_OCCLUSION)
	)
	nearest_texture_filter = bool(data.get("nearest_texture_filter", DEFAULT_NEAREST_TEXTURE_FILTER))
	anti_aliasing_off = bool(data.get("anti_aliasing_off", DEFAULT_ANTI_ALIASING_OFF))
	low_res_viewport_enabled = bool(data.get("low_res_viewport_enabled", DEFAULT_LOW_RES_VIEWPORT))
	viewport_width = int(data.get("viewport_width", DEFAULT_VIEWPORT_WIDTH))
	viewport_height = int(data.get("viewport_height", DEFAULT_VIEWPORT_HEIGHT))
	camera_snap_enabled = bool(data.get("camera_snap_enabled", DEFAULT_CAMERA_SNAP))
	screen_finish_enabled = bool(data.get("screen_finish_enabled", DEFAULT_SCREEN_FINISH))
	screen_contrast = float(data.get("screen_contrast", DEFAULT_CONTRAST))
	screen_saturation = float(data.get("screen_saturation", DEFAULT_SATURATION))
	vignette_strength = float(data.get("vignette_strength", DEFAULT_VIGNETTE))
	posterize_levels = float(data.get("posterize_levels", DEFAULT_POSTERIZE_LEVELS))
	shadow_quality = int(data.get("shadow_quality", DEFAULT_SHADOW_QUALITY))
	particle_quality = int(data.get("particle_quality", DEFAULT_PARTICLE_QUALITY))
	var preset := _preset_for_size(viewport_width, viewport_height)
	if bool(preset.get("native", false)):
		_apply_native_hd_shader_tuning(preset)


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"pixel_scale": pixel_scale,
		"color_levels": color_levels,
		"edge_strength": edge_strength,
		"stitch_strength": stitch_strength,
		"pattern_strength": pattern_strength,
		"shade_bands": shade_bands,
		"shade_dither": shade_dither,
		"light_wrap": light_wrap,
		"rim_strength": rim_strength,
		"linear_tonemap": linear_tonemap,
		"glow_enabled": glow_enabled,
		"ambient_occlusion_enabled": ambient_occlusion_enabled,
		"nearest_texture_filter": nearest_texture_filter,
		"anti_aliasing_off": anti_aliasing_off,
		"low_res_viewport_enabled": low_res_viewport_enabled,
		"viewport_width": viewport_width,
		"viewport_height": viewport_height,
		"camera_snap_enabled": camera_snap_enabled,
		"screen_finish_enabled": screen_finish_enabled,
		"screen_contrast": screen_contrast,
		"screen_saturation": screen_saturation,
		"vignette_strength": vignette_strength,
		"posterize_levels": posterize_levels,
		"shadow_quality": shadow_quality,
		"particle_quality": particle_quality,
	}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()


static func save_and_apply() -> void:
	save()
	apply_all()


static func apply_all() -> void:
	apply_rendering_project_settings()
	PixelDioramaStyle.clear_material_caches()
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var pixel_viewport := tree.root.get_node_or_null("PixelDioramaViewport")
		if pixel_viewport and pixel_viewport.has_method("apply_settings"):
			pixel_viewport.call("apply_settings")
		if tree.current_scene:
			apply_to_scene(tree.current_scene)


## Restores the tuned "crisp diorama" look, discarding user experimentation.
static func apply_beauty_defaults() -> void:
	pixel_scale = DEFAULT_PIXEL_SCALE
	color_levels = DEFAULT_COLOR_LEVELS
	edge_strength = DEFAULT_EDGE_STRENGTH
	stitch_strength = DEFAULT_STITCH_STRENGTH
	pattern_strength = DEFAULT_PATTERN_STRENGTH
	shade_bands = DEFAULT_SHADE_BANDS
	shade_dither = DEFAULT_SHADE_DITHER
	light_wrap = DEFAULT_LIGHT_WRAP
	rim_strength = DEFAULT_RIM_STRENGTH
	linear_tonemap = DEFAULT_LINEAR_TONEMAP
	glow_enabled = DEFAULT_GLOW_ENABLED
	ambient_occlusion_enabled = DEFAULT_AMBIENT_OCCLUSION
	nearest_texture_filter = true
	anti_aliasing_off = true
	low_res_viewport_enabled = true
	viewport_width = DEFAULT_VIEWPORT_WIDTH
	viewport_height = DEFAULT_VIEWPORT_HEIGHT
	camera_snap_enabled = false
	screen_finish_enabled = true
	screen_contrast = DEFAULT_CONTRAST
	screen_saturation = DEFAULT_SATURATION
	vignette_strength = DEFAULT_VIGNETTE
	posterize_levels = DEFAULT_POSTERIZE_LEVELS
	shadow_quality = DEFAULT_SHADOW_QUALITY
	particle_quality = DEFAULT_PARTICLE_QUALITY
	save_and_apply()


static func particle_amount_scale() -> float:
	match clampi(particle_quality, 0, 2):
		0:
			return 0.45
		2:
			return 1.35
		_:
			return 1.0


static func viewport_internal_size() -> Vector2i:
	return Vector2i(maxi(160, viewport_width), maxi(90, viewport_height))


static func set_resolution_preset(index: int) -> void:
	if index < 0 or index >= RESOLUTION_PRESETS.size():
		return
	var preset: Dictionary = RESOLUTION_PRESETS[index]
	viewport_width = int(preset.get("width", DEFAULT_VIEWPORT_WIDTH))
	viewport_height = int(preset.get("height", DEFAULT_VIEWPORT_HEIGHT))
	if bool(preset.get("native", false)):
		_apply_native_hd_shader_tuning(preset)


static func is_native_hd_preset() -> bool:
	var preset := _preset_for_size(viewport_width, viewport_height)
	return not preset.is_empty() and bool(preset.get("native", false))


static func _preset_for_size(width: int, height: int) -> Dictionary:
	for preset in RESOLUTION_PRESETS:
		if int(preset.get("width", 0)) == width and int(preset.get("height", 0)) == height:
			return preset
	return {}


static func _apply_native_hd_shader_tuning(preset: Dictionary) -> void:
	pixel_scale = float(preset.get("pixel_scale", 2.5))
	color_levels = float(preset.get("color_levels", 14.0))
	shade_bands = float(preset.get("shade_bands", 7.0))
	edge_strength = float(preset.get("edge_strength", 0.12))
	pattern_strength = float(preset.get("pattern_strength", 0.24))
	shade_dither = float(preset.get("shade_dither", 0.3))
	nearest_texture_filter = false
	anti_aliasing_off = false


static func current_resolution_preset() -> int:
	for i in RESOLUTION_PRESETS.size():
		var preset: Dictionary = RESOLUTION_PRESETS[i]
		if int(preset.get("width", 0)) == viewport_width and int(preset.get("height", 0)) == viewport_height:
			return i
	return -1


## World-space height of one rendered pixel at the given focus distance. Snapping
## the render camera to this grid stops surface patterns from crawling as it moves.
static func camera_snap_step(fov_degrees: float = 75.0, focus_distance: float = 5.0) -> float:
	var half_extent := tan(deg_to_rad(clampf(fov_degrees, 10.0, 170.0)) * 0.5)
	var height := float(maxi(90, active_render_height))
	return maxf(0.001, 2.0 * maxf(0.5, focus_distance) * half_extent / height)


static func apply_rendering_project_settings() -> void:
	if nearest_texture_filter:
		ProjectSettings.set_setting(
			"rendering/textures/default_filters/texture_filter",
			BaseMaterial3D.TEXTURE_FILTER_NEAREST
		)
		ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 0)
		ProjectSettings.set_setting(
			"rendering/textures/canvas_textures/default_texture_filter",
			BaseMaterial3D.TEXTURE_FILTER_NEAREST
		)
	else:
		ProjectSettings.set_setting(
			"rendering/textures/default_filters/texture_filter",
			BaseMaterial3D.TEXTURE_FILTER_LINEAR
		)
		ProjectSettings.set_setting("rendering/textures/default_filters/anisotropic_filtering_level", 2)
		ProjectSettings.set_setting(
			"rendering/textures/canvas_textures/default_texture_filter",
			BaseMaterial3D.TEXTURE_FILTER_LINEAR
		)

	if anti_aliasing_off:
		ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 0)
		ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 0)
	else:
		ProjectSettings.set_setting("rendering/anti_aliasing/quality/msaa_3d", 2)
		ProjectSettings.set_setting("rendering/anti_aliasing/quality/screen_space_aa", 1)


static func configure_environment(environment: Environment) -> void:
	if environment == null:
		return
	if linear_tonemap:
		environment.tonemap_mode = Environment.TONE_MAPPER_LINEAR
		environment.tonemap_white = 1.2
	else:
		environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
		environment.tonemap_white = 1.0
	environment.glow_enabled = glow_enabled
	if glow_enabled:
		# Keep bloom tight so it haloes emissives instead of softening silhouettes.
		environment.glow_intensity = 0.55
		environment.glow_bloom = 0.05
		environment.glow_hdr_threshold = 1.0
		environment.glow_blend_mode = Environment.GLOW_BLEND_MODE_ADDITIVE
	_configure_occlusion(environment)


## Short-radius SSAO. In a diorama the single most important cue is where an
## object touches the ground, and flat banded lighting gives none of it. The
## radius is kept small so it reads as a contact shadow, not a dirt wash.
static func _configure_occlusion(environment: Environment) -> void:
	if not ambient_occlusion_enabled:
		environment.ssao_enabled = false
		return
	environment.ssao_enabled = true
	environment.ssao_radius = 0.85
	environment.ssao_intensity = 2.4
	environment.ssao_power = 1.4
	environment.ssao_detail = 0.0
	environment.ssao_horizon = 0.16
	environment.ssao_sharpness = 1.0
	environment.ssao_light_affect = 0.1
	environment.ssao_ao_channel_affect = 0.0


## Directional shadows tuned for chunky low-poly geometry at low resolution:
## a short range keeps texel density high so shadow edges stay blocky, not noisy.
## Large flat box tops sit near-parallel to the sun and acne badly on the depth
## test alone, so normal bias does the real work here and depth bias stays low
## enough that contact points don't visibly detach.
static func configure_directional_shadow(light: DirectionalLight3D, enable_shadows: bool = true) -> void:
	if light == null:
		return
	var shadows_on := enable_shadows and shadow_quality > 0
	light.shadow_enabled = shadows_on
	if not shadows_on:
		return
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	match clampi(shadow_quality, 0, 2):
		0:
			light.shadow_enabled = false
		2:
			light.directional_shadow_max_distance = 32.0
			light.shadow_bias = 0.008
			light.shadow_normal_bias = 0.18
		_:
			light.directional_shadow_max_distance = 24.0
			light.shadow_bias = 0.01
			light.shadow_normal_bias = 0.2
	light.shadow_opacity = 1.0


static func pixel_scale_for_pattern_type(pattern_type: int) -> float:
	match pattern_type:
		0:
			return pixel_scale * (7.5 / DEFAULT_PIXEL_SCALE)
		1:
			return pixel_scale * (7.0 / DEFAULT_PIXEL_SCALE)
		_:
			return pixel_scale * (8.0 / DEFAULT_PIXEL_SCALE) * 1.05


static func texture_filter_mode() -> BaseMaterial3D.TextureFilter:
	return (
		BaseMaterial3D.TEXTURE_FILTER_NEAREST
		if nearest_texture_filter
		else BaseMaterial3D.TEXTURE_FILTER_LINEAR
	)


static func apply_to_shader_material(mat: ShaderMaterial) -> void:
	if mat == null or mat.shader == null:
		return
	var shader_path := mat.shader.resource_path
	# ShaderMaterial has no texture_filter; nearest filtering is project-wide.
	if shader_path.ends_with(SURFACE_SHADER_SUFFIX):
		mat.set_shader_parameter("pixel_scale", pixel_scale)
		mat.set_shader_parameter("color_levels", color_levels)
		mat.set_shader_parameter("edge_strength", edge_strength)
		mat.set_shader_parameter("stitch_strength", stitch_strength)
		mat.set_shader_parameter("pattern_strength", pattern_strength)
		mat.set_shader_parameter("shade_bands", shade_bands)
		mat.set_shader_parameter("shade_dither", shade_dither)
		mat.set_shader_parameter("light_wrap", light_wrap)
		mat.set_shader_parameter("rim_strength", rim_strength)
	elif shader_path.ends_with(EMISSIVE_SHADER_SUFFIX):
		mat.set_shader_parameter("pixel_scale", pixel_scale)
		mat.set_shader_parameter("color_levels", color_levels)
	elif shader_path.ends_with(LEGACY_SHADER_SUFFIX):
		var pattern_type := int(mat.get_shader_parameter("pattern_type"))
		mat.set_shader_parameter("pixel_scale", pixel_scale_for_pattern_type(pattern_type))
		mat.set_shader_parameter("color_levels", color_levels)
		mat.set_shader_parameter("edge_strength", edge_strength)
		mat.set_shader_parameter("stitch_strength", stitch_strength)
		mat.set_shader_parameter("pattern_strength", pattern_strength)


static func apply_to_standard_material(mat: StandardMaterial3D) -> void:
	if mat == null:
		return
	mat.texture_filter = texture_filter_mode()


static func make_screen_finish_material() -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(SCREEN_FINISH_SHADER_PATH) as Shader
	apply_to_screen_finish(mat)
	return mat


static func apply_to_screen_finish(mat: ShaderMaterial) -> void:
	if mat == null:
		return
	mat.set_shader_parameter("contrast", screen_contrast)
	mat.set_shader_parameter("saturation", screen_saturation)
	mat.set_shader_parameter("vignette_strength", vignette_strength)
	mat.set_shader_parameter("posterize_levels", posterize_levels)
	mat.set_shader_parameter("damage_pulse", 0.0)


static func apply_to_scene(root: Node) -> void:
	if root == null:
		return
	_apply_world_environments(root)
	_apply_materials_recursive(root)


static func _apply_world_environments(root: Node) -> void:
	if root is WorldEnvironment:
		var env_node := root as WorldEnvironment
		if env_node.environment:
			configure_environment(env_node.environment)
	if root is DirectionalLight3D:
		# Only retune lights that already cast; fill lights must stay shadowless.
		var dir_light := root as DirectionalLight3D
		if dir_light.shadow_enabled:
			configure_directional_shadow(dir_light)
	for child in root.get_children():
		_apply_world_environments(child)


static func _apply_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		var override_mat := mesh_inst.material_override
		if override_mat is ShaderMaterial:
			apply_to_shader_material(override_mat as ShaderMaterial)
		elif override_mat is StandardMaterial3D:
			apply_to_standard_material(override_mat as StandardMaterial3D)
		var mesh := mesh_inst.mesh
		if mesh:
			for surface_idx in mesh.get_surface_count():
				var surface_mat := mesh.surface_get_material(surface_idx)
				if surface_mat is ShaderMaterial:
					apply_to_shader_material(surface_mat as ShaderMaterial)
				elif surface_mat is StandardMaterial3D:
					apply_to_standard_material(surface_mat as StandardMaterial3D)
	for child in node.get_children():
		_apply_materials_recursive(child)
