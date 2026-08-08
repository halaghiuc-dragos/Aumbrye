extends RefCounted
class_name PixelDioramaSettings

## User-configurable pixel-diorama visual settings (persisted in LocalSave meta).
##
## Single source of truth for every tunable that shapes the pixel look: internal
## render resolution, surface shader uniforms, shading bands, and the screen-space
## finish pass. Art modules read from here rather than defining their own defaults.

const SAVE_KEY := "pixel_diorama"
const SETTINGS_VERSION := 1
const SAVE_DEBOUNCE_SEC := 0.35

const SURFACE_SHADER_SUFFIX := "pixel_diorama_surface.gdshader"
const EMISSIVE_SHADER_SUFFIX := "pixel_diorama_emissive.gdshader"
const PORTAL_SHADER_SUFFIX := "portal_ellipse.gdshader"
const SCREEN_FINISH_SHADER_PATH := "res://assets/shared/pixel_screen_finish.gdshader"
const VfxServiceScript := preload("res://scripts/art/vfx/vfx_service.gd")
const GameUISkinScript := preload("res://scripts/ui/game_ui_skin.gd")

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
const DEFAULT_ANTI_ALIASING_OFF := false
const DEFAULT_LOW_RES_VIEWPORT := true
const DEFAULT_VIEWPORT_WIDTH := 480
const DEFAULT_VIEWPORT_HEIGHT := 270
const DEFAULT_CAMERA_SNAP := true
const DEFAULT_GAMEPLAY_CAMERA_SNAP := true
const DEFAULT_SCREEN_FINISH := true
const DEFAULT_CONTRAST := 1.08
const DEFAULT_SATURATION := 1.06
const DEFAULT_VIGNETTE := 0.18
const DEFAULT_POSTERIZE_LEVELS := 24.0
const DEFAULT_SHADOW_QUALITY := 1
const DEFAULT_PARTICLE_QUALITY := 1
const DEFAULT_LIGHT_ANIMATION := true
const DEFAULT_HITSTOP_ENABLED := true
const DEFAULT_SCREEN_SHAKE_SCALE := 1.0
const DEFAULT_SCREEN_LIFT := 0.0
const DEFAULT_SHADOW_TINT := Color(0.18, 0.16, 0.26)
const DEFAULT_SHADOW_TINT_AMOUNT := 0.14
const DEFAULT_HIGHLIGHT_TINT := Color(1.0, 0.94, 0.82)
const DEFAULT_HIGHLIGHT_TINT_AMOUNT := 0.1
const DEFAULT_VIGNETTE_SOFTNESS := 0.85
const DEFAULT_PULSE_TINT := Color(0.62, 0.08, 0.08)

const QUALITY_LABELS: Array[String] = ["Low", "Medium", "High"]

## Internal render resolutions offered in Settings. All are 16:9 so the
## nearest-neighbour upscale stays square-pixel at common window sizes.
const RESOLUTION_PRESETS: Array = [
	{"label": "320 x 180 (chunky)", "width": 320, "height": 180},
	{"label": "480 x 270 (chunky, default)", "width": 480, "height": 270, "default": true},
	{"label": "640 x 360 (fine)", "width": 640, "height": 360},
	{"label": "960 x 540 (soft)", "width": 960, "height": 540},
	{
		"label": "1280 x 720 (HD)",
		"width": 1280,
		"height": 720,
		"native": true,
		"tuning": {
			"pixel_scale": 3.0,
			"color_levels": 12.0,
			"shade_bands": 6.0,
			"edge_strength": 0.14,
			"pattern_strength": 0.28,
			"shade_dither": 0.35,
		},
	},
	{
		"label": "1920 x 1080 (Full HD)",
		"width": 1920,
		"height": 1080,
		"native": true,
		"tuning": {
			"pixel_scale": 2.0,
			"color_levels": 16.0,
			"shade_bands": 8.0,
			"edge_strength": 0.1,
			"pattern_strength": 0.2,
			"shade_dither": 0.25,
		},
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
static var low_res_viewport_enabled: bool = DEFAULT_LOW_RES_VIEWPORT
static var viewport_width: int = DEFAULT_VIEWPORT_WIDTH
static var viewport_height: int = DEFAULT_VIEWPORT_HEIGHT
static var camera_snap_enabled: bool = DEFAULT_CAMERA_SNAP
static var gameplay_camera_snap_enabled: bool = DEFAULT_GAMEPLAY_CAMERA_SNAP
static var screen_finish_enabled: bool = DEFAULT_SCREEN_FINISH
static var screen_contrast: float = DEFAULT_CONTRAST
static var screen_saturation: float = DEFAULT_SATURATION
static var vignette_strength: float = DEFAULT_VIGNETTE
static var posterize_levels: float = DEFAULT_POSTERIZE_LEVELS
static var shadow_quality: int = DEFAULT_SHADOW_QUALITY
static var particle_quality: int = DEFAULT_PARTICLE_QUALITY
static var light_animation: bool = DEFAULT_LIGHT_ANIMATION
static var hitstop_enabled: bool = DEFAULT_HITSTOP_ENABLED
static var screen_shake_scale: float = DEFAULT_SCREEN_SHAKE_SCALE
static var tuning_is_preset_default: bool = false
static var screen_lift: float = DEFAULT_SCREEN_LIFT
static var shadow_tint: Color = DEFAULT_SHADOW_TINT
static var shadow_tint_amount: float = DEFAULT_SHADOW_TINT_AMOUNT
static var highlight_tint: Color = DEFAULT_HIGHLIGHT_TINT
static var highlight_tint_amount: float = DEFAULT_HIGHLIGHT_TINT_AMOUNT
static var vignette_softness: float = DEFAULT_VIGNETTE_SOFTNESS
static var pulse_tint: Color = DEFAULT_PULSE_TINT
static var debug_flat_materials: bool = false

static var _debug_flat_cached: bool = false

## Height the SubViewport actually renders at, which is the requested preset
## rounded to an integer divisor of the window. Set by PixelDioramaViewport.
static var active_render_height: int = DEFAULT_VIEWPORT_HEIGHT

## Last source-camera fov mirrored by PixelDioramaViewport / orbit camera snap.
## Runtime-only; not persisted. Used by PixelCameraSnap.rotation_step_radians().
static var snap_fov_hint: float = 75.0

static var _tracked: Array[WeakRef] = []
static var _biome_grade_override: Dictionary = {}
static var _save_timer: SceneTreeTimer = null


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	var version := int(data.get("version", 0))
	if version != SETTINGS_VERSION:
		data = _migrate_settings(data, version)
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
	nearest_texture_filter = bool(
		data.get("nearest_texture_filter", DEFAULT_NEAREST_TEXTURE_FILTER)
	)
	anti_aliasing_off = bool(data.get("anti_aliasing_off", DEFAULT_ANTI_ALIASING_OFF))
	low_res_viewport_enabled = bool(data.get("low_res_viewport_enabled", DEFAULT_LOW_RES_VIEWPORT))
	viewport_width = int(data.get("viewport_width", DEFAULT_VIEWPORT_WIDTH))
	viewport_height = int(data.get("viewport_height", DEFAULT_VIEWPORT_HEIGHT))
	camera_snap_enabled = bool(data.get("camera_snap_enabled", DEFAULT_CAMERA_SNAP))
	gameplay_camera_snap_enabled = bool(
		data.get("gameplayCameraSnap", data.get("gameplay_camera_snap", DEFAULT_GAMEPLAY_CAMERA_SNAP))
	)
	screen_finish_enabled = bool(data.get("screen_finish_enabled", DEFAULT_SCREEN_FINISH))
	screen_contrast = float(data.get("screen_contrast", DEFAULT_CONTRAST))
	screen_saturation = float(data.get("screen_saturation", DEFAULT_SATURATION))
	vignette_strength = float(data.get("vignette_strength", DEFAULT_VIGNETTE))
	posterize_levels = float(data.get("posterize_levels", DEFAULT_POSTERIZE_LEVELS))
	shadow_quality = int(data.get("shadow_quality", DEFAULT_SHADOW_QUALITY))
	particle_quality = int(data.get("particle_quality", DEFAULT_PARTICLE_QUALITY))
	light_animation = bool(data.get("light_animation", DEFAULT_LIGHT_ANIMATION))
	hitstop_enabled = bool(data.get("hitstop_enabled", DEFAULT_HITSTOP_ENABLED))
	screen_shake_scale = float(data.get("screen_shake_scale", DEFAULT_SCREEN_SHAKE_SCALE))
	tuning_is_preset_default = bool(data.get("tuning_is_preset_default", false))
	screen_lift = float(data.get("screen_lift", DEFAULT_SCREEN_LIFT))
	shadow_tint = _color_from_save(data.get("shadow_tint", null), DEFAULT_SHADOW_TINT)
	shadow_tint_amount = float(data.get("shadow_tint_amount", DEFAULT_SHADOW_TINT_AMOUNT))
	highlight_tint = _color_from_save(data.get("highlight_tint", null), DEFAULT_HIGHLIGHT_TINT)
	highlight_tint_amount = float(
		data.get("highlight_tint_amount", DEFAULT_HIGHLIGHT_TINT_AMOUNT)
	)
	vignette_softness = float(data.get("vignette_softness", DEFAULT_VIGNETTE_SOFTNESS))
	if tuning_is_preset_default:
		var preset := _preset_for_size(viewport_width, viewport_height)
		var tuning: Variant = preset.get("tuning", {})
		if tuning is Dictionary and not (tuning as Dictionary).is_empty():
			_apply_preset_tuning(tuning as Dictionary)


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"version": SETTINGS_VERSION,
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
		"gameplayCameraSnap": gameplay_camera_snap_enabled,
		"screen_finish_enabled": screen_finish_enabled,
		"screen_contrast": screen_contrast,
		"screen_saturation": screen_saturation,
		"vignette_strength": vignette_strength,
		"posterize_levels": posterize_levels,
		"shadow_quality": shadow_quality,
		"particle_quality": particle_quality,
		"light_animation": light_animation,
		"hitstop_enabled": hitstop_enabled,
		"screen_shake_scale": screen_shake_scale,
		"tuning_is_preset_default": tuning_is_preset_default,
		"screen_lift": screen_lift,
		"shadow_tint": _color_to_save(shadow_tint),
		"shadow_tint_amount": shadow_tint_amount,
		"highlight_tint": _color_to_save(highlight_tint),
		"highlight_tint_amount": highlight_tint_amount,
		"vignette_softness": vignette_softness,
	}
	LocalSave.set_meta_data(meta)
	LocalSave.autosave()


static func save_and_apply() -> void:
	save()
	apply_all()
	_emit_symbol_preset_invalidated()


static func _emit_symbol_preset_invalidated() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var bus := tree.root.get_node_or_null("/root/UISymbolBus")
	if bus:
		bus.emit_invalidated(&"preset")


static func apply_live() -> void:
	restamp_tracked()
	_notify_viewport()


static func request_save() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		save()
		return
	if _save_timer != null and is_instance_valid(_save_timer):
		_save_timer.time_left = SAVE_DEBOUNCE_SEC
		return
	_save_timer = tree.create_timer(SAVE_DEBOUNCE_SEC)
	_save_timer.timeout.connect(_on_save_debounce_timeout, CONNECT_ONE_SHOT)


static func apply_all() -> void:
	_debug_flat_cached = debug_flat_materials
	VfxServiceScript.clear_particle_material_cache()
	restamp_tracked()
	_notify_viewport()
	_refresh_lighting_atmosphere()
	var tree := Engine.get_main_loop() as SceneTree
	if tree and tree.current_scene:
		apply_to_scene(tree.current_scene)
	_restyle_ui_trees(tree)


static func _restyle_ui_trees(tree: SceneTree) -> void:
	if tree == null or tree.root == null:
		return
	for child in tree.root.get_children():
		if child is Control:
			GameUISkinScript.restyle_tree(child as Control)


static func _refresh_lighting_atmosphere() -> void:
	var lighting_script: Script = load("res://scripts/art/lighting/visual_lighting.gd")
	if lighting_script:
		lighting_script.call("refresh_atmosphere")


static func track(mat: ShaderMaterial) -> ShaderMaterial:
	if mat != null:
		_tracked.append(weakref(mat))
	return mat


static func restamp_tracked() -> void:
	var alive: Array[WeakRef] = []
	for ref in _tracked:
		var mat := ref.get_ref() as ShaderMaterial
		if mat != null:
			apply_to_shader_material(mat)
			alive.append(ref)
	_tracked = alive


const BIOME_GRADE_FLOAT_FIELDS := {
	"saturation": "saturation",
	"contrast": "contrast",
	"lift": "lift",
	"vignette": "vignette_strength",
	"vignetteSoftness": "vignette_softness",
	"posterizeLevels": "posterize_levels",
}


static func set_biome_screen_grade(biome_id: String) -> void:
	var override := BiomeRegistry.get_grade_profile(biome_id)
	var raw: Variant = BiomeRegistry.get_biome(biome_id).get("grade", {})
	if raw is Dictionary:
		var grade: Dictionary = raw as Dictionary
		for json_key in BIOME_GRADE_FLOAT_FIELDS:
			if grade.has(json_key):
				override[BIOME_GRADE_FLOAT_FIELDS[json_key]] = float(grade[json_key])
	_biome_grade_override = override
	_notify_viewport()


static func _graded_float(key: String, fallback: float) -> float:
	if _biome_grade_override.has(key):
		return float(_biome_grade_override[key])
	return fallback


static func _graded_color(key: String, fallback: Color) -> Color:
	if _biome_grade_override.has(key):
		return _biome_grade_override[key] as Color
	return fallback


static func clear_biome_screen_grade() -> void:
	_biome_grade_override = {}
	_notify_viewport()


static func mark_tuning_user_edited() -> void:
	tuning_is_preset_default = false


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
	nearest_texture_filter = DEFAULT_NEAREST_TEXTURE_FILTER
	anti_aliasing_off = DEFAULT_ANTI_ALIASING_OFF
	low_res_viewport_enabled = DEFAULT_LOW_RES_VIEWPORT
	var preset := _default_preset()
	viewport_width = int(preset.get("width", DEFAULT_VIEWPORT_WIDTH))
	viewport_height = int(preset.get("height", DEFAULT_VIEWPORT_HEIGHT))
	tuning_is_preset_default = false
	var tuning: Variant = preset.get("tuning", {})
	if tuning is Dictionary and not (tuning as Dictionary).is_empty():
		_apply_preset_tuning(tuning as Dictionary)
		tuning_is_preset_default = true
	camera_snap_enabled = DEFAULT_CAMERA_SNAP
	gameplay_camera_snap_enabled = DEFAULT_GAMEPLAY_CAMERA_SNAP
	screen_finish_enabled = true
	screen_contrast = DEFAULT_CONTRAST
	screen_saturation = DEFAULT_SATURATION
	vignette_strength = DEFAULT_VIGNETTE
	posterize_levels = DEFAULT_POSTERIZE_LEVELS
	shadow_quality = DEFAULT_SHADOW_QUALITY
	particle_quality = DEFAULT_PARTICLE_QUALITY
	hitstop_enabled = DEFAULT_HITSTOP_ENABLED
	screen_shake_scale = DEFAULT_SCREEN_SHAKE_SCALE
	light_animation = DEFAULT_LIGHT_ANIMATION
	screen_lift = DEFAULT_SCREEN_LIFT
	shadow_tint = DEFAULT_SHADOW_TINT
	shadow_tint_amount = DEFAULT_SHADOW_TINT_AMOUNT
	highlight_tint = DEFAULT_HIGHLIGHT_TINT
	highlight_tint_amount = DEFAULT_HIGHLIGHT_TINT_AMOUNT
	vignette_softness = DEFAULT_VIGNETTE_SOFTNESS
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
	var tuning: Variant = preset.get("tuning", {})
	if tuning is Dictionary and not (tuning as Dictionary).is_empty():
		_apply_preset_tuning(tuning as Dictionary)
		tuning_is_preset_default = true


static func is_native_hd_preset() -> bool:
	var preset := _preset_for_size(viewport_width, viewport_height)
	return not preset.is_empty() and bool(preset.get("native", false))


static func _default_preset() -> Dictionary:
	for entry in RESOLUTION_PRESETS:
		if bool(entry.get("default", false)):
			return entry
	return RESOLUTION_PRESETS[1]


static func _preset_for_size(width: int, height: int) -> Dictionary:
	for preset in RESOLUTION_PRESETS:
		if int(preset.get("width", 0)) == width and int(preset.get("height", 0)) == height:
			return preset
	return {}


static func _apply_preset_tuning(tuning: Dictionary) -> void:
	pixel_scale = float(tuning.get("pixel_scale", pixel_scale))
	color_levels = float(tuning.get("color_levels", color_levels))
	shade_bands = float(tuning.get("shade_bands", shade_bands))
	edge_strength = float(tuning.get("edge_strength", edge_strength))
	pattern_strength = float(tuning.get("pattern_strength", pattern_strength))
	shade_dither = float(tuning.get("shade_dither", shade_dither))


static func _migrate_settings(data: Dictionary, from_version: int) -> Dictionary:
	var migrated := data.duplicate(true)
	if from_version <= 0:
		migrated["tuning_is_preset_default"] = true
	migrated["version"] = SETTINGS_VERSION
	return migrated


static func current_resolution_preset() -> int:
	for i in RESOLUTION_PRESETS.size():
		var preset: Dictionary = RESOLUTION_PRESETS[i]
		if (
			int(preset.get("width", 0)) == viewport_width
			and int(preset.get("height", 0)) == viewport_height
		):
			return i
	return -1


## World-space height of one rendered pixel at the given focus distance. Snapping
## the render camera to this grid stops surface patterns from crawling as it moves.
static func camera_snap_step(fov_degrees: float = 75.0, focus_distance: float = 5.0) -> float:
	var half_extent := tan(deg_to_rad(clampf(fov_degrees, 10.0, 170.0)) * 0.5)
	var height := float(maxi(90, active_render_height))
	return maxf(0.001, 2.0 * maxf(0.5, focus_distance) * half_extent / height)


static func apply_render_quality(viewports: Array) -> void:
	var msaa := (
		Viewport.MSAA_DISABLED if anti_aliasing_off else Viewport.MSAA_2X
	)
	var ss_aa := (
		Viewport.SCREEN_SPACE_AA_DISABLED
		if anti_aliasing_off
		else Viewport.SCREEN_SPACE_AA_FXAA
	)
	for vp in viewports:
		if vp == null:
			continue
		(vp as Viewport).msaa_3d = msaa
		(vp as Viewport).screen_space_aa = ss_aa


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
static func configure_directional_shadow(
	light: DirectionalLight3D, enable_shadows: bool = true
) -> void:
	if light == null:
		return
	var shadows_on := enable_shadows and shadow_quality > 0
	light.shadow_enabled = shadows_on
	if not shadows_on:
		return
	light.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	match clampi(shadow_quality, 0, 2):
		2:
			light.directional_shadow_max_distance = 32.0
			light.shadow_bias = 0.008
			light.shadow_normal_bias = 0.18
		_:
			light.directional_shadow_max_distance = 24.0
			light.shadow_bias = 0.01
			light.shadow_normal_bias = 0.2
	light.shadow_opacity = 1.0


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
	var authored: Array = mat.get_meta("authored_params", [])
	if shader_path.ends_with(SURFACE_SHADER_SUFFIX):
		_set_shader_param_unless_authored(mat, authored, "pixel_scale", pixel_scale)
		_set_shader_param_unless_authored(mat, authored, "color_levels", color_levels)
		_set_shader_param_unless_authored(mat, authored, "edge_strength", edge_strength)
		_set_shader_param_unless_authored(mat, authored, "stitch_strength", stitch_strength)
		_set_shader_param_unless_authored(mat, authored, "pattern_strength", pattern_strength)
		_set_shader_param_unless_authored(mat, authored, "shade_bands", shade_bands)
		_set_shader_param_unless_authored(mat, authored, "shade_dither", shade_dither)
		_set_shader_param_unless_authored(mat, authored, "light_wrap", light_wrap)
		_set_shader_param_unless_authored(mat, authored, "rim_strength", rim_strength)
	elif shader_path.ends_with(EMISSIVE_SHADER_SUFFIX):
		_set_shader_param_unless_authored(mat, authored, "pixel_scale", pixel_scale)
		_set_shader_param_unless_authored(mat, authored, "color_levels", color_levels)
	elif shader_path.ends_with(PORTAL_SHADER_SUFFIX):
		mat.set_shader_parameter("pixel_scale", pixel_scale * (14.0 / DEFAULT_PIXEL_SCALE))
		mat.set_shader_parameter("color_levels", color_levels)


static func _set_shader_param_unless_authored(
	mat: ShaderMaterial, authored: Array, param: String, value: Variant
) -> void:
	if authored.has(param):
		return
	mat.set_shader_parameter(param, value)


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
	mat.set_shader_parameter("contrast", _graded_float("contrast", screen_contrast))
	mat.set_shader_parameter("saturation", _graded_float("saturation", screen_saturation))
	mat.set_shader_parameter("lift", _graded_float("lift", screen_lift))
	mat.set_shader_parameter("shadow_tint", _graded_color("shadow_tint", shadow_tint))
	mat.set_shader_parameter(
		"shadow_tint_amount", _graded_float("shadow_tint_amount", shadow_tint_amount)
	)
	mat.set_shader_parameter("highlight_tint", _graded_color("highlight_tint", highlight_tint))
	mat.set_shader_parameter(
		"highlight_tint_amount", _graded_float("highlight_tint_amount", highlight_tint_amount)
	)
	mat.set_shader_parameter(
		"vignette_strength", _graded_float("vignette_strength", vignette_strength)
	)
	mat.set_shader_parameter(
		"vignette_softness", _graded_float("vignette_softness", vignette_softness)
	)
	mat.set_shader_parameter("damage_pulse", 0.0)
	mat.set_shader_parameter("pulse_tint", pulse_tint)
	mat.set_shader_parameter("posterize_levels", _graded_float("posterize_levels", posterize_levels))


static func apply_to_scene(root: Node) -> void:
	if root == null:
		return
	_apply_world_environments(root)


static func bootstrap_scene_materials(root: Node) -> void:
	if root == null:
		return
	_track_materials_recursive(root)
	restamp_tracked()


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


static func _track_materials_recursive(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_inst := node as MeshInstance3D
		if mesh_inst.has_meta(&"material_dissolve_saved_override"):
			return
		var override_mat := mesh_inst.material_override
		if override_mat is ShaderMaterial:
			track(override_mat as ShaderMaterial)
		var mesh := mesh_inst.mesh
		if mesh:
			for surface_idx in mesh.get_surface_count():
				var surface_mat := mesh.surface_get_material(surface_idx)
				if surface_mat is ShaderMaterial:
					track(surface_mat as ShaderMaterial)
	for child in node.get_children():
		_track_materials_recursive(child)


static func _notify_viewport() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree == null:
		return
	var pixel_viewport := tree.root.get_node_or_null("PixelDioramaViewport")
	if pixel_viewport and pixel_viewport.has_method("apply_settings"):
		pixel_viewport.call("apply_settings")


static func _on_save_debounce_timeout() -> void:
	_save_timer = null
	save()


static func _color_to_save(color: Color) -> Array:
	return [color.r, color.g, color.b]


static func _color_from_save(raw: Variant, default_color: Color) -> Color:
	if raw is Array and (raw as Array).size() >= 3:
		var arr: Array = raw
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return default_color
