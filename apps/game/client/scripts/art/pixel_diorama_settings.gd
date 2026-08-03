extends RefCounted
class_name PixelDioramaSettings

## User-configurable pixel-diorama visual settings (persisted in LocalSave meta).

const SAVE_KEY := "pixel_diorama"

const SURFACE_SHADER_SUFFIX := "pixel_diorama_surface.gdshader"
const LEGACY_SHADER_SUFFIX := "pixel_diorama.gdshader"

const DEFAULT_PIXEL_SCALE := 8.0
const DEFAULT_COLOR_LEVELS := 6.0
const DEFAULT_EDGE_STRENGTH := 0.42
const DEFAULT_STITCH_STRENGTH := 0.28
const DEFAULT_PATTERN_STRENGTH := 0.58
const DEFAULT_LINEAR_TONEMAP := true
const DEFAULT_GLOW_ENABLED := false
const DEFAULT_NEAREST_TEXTURE_FILTER := true
const DEFAULT_ANTI_ALIASING_OFF := true
const DEFAULT_LOW_RES_VIEWPORT := true
const DEFAULT_VIEWPORT_WIDTH := 480
const DEFAULT_VIEWPORT_HEIGHT := 270
const DEFAULT_CAMERA_SNAP := true

static var pixel_scale: float = DEFAULT_PIXEL_SCALE
static var color_levels: float = DEFAULT_COLOR_LEVELS
static var edge_strength: float = DEFAULT_EDGE_STRENGTH
static var stitch_strength: float = DEFAULT_STITCH_STRENGTH
static var pattern_strength: float = DEFAULT_PATTERN_STRENGTH
static var linear_tonemap: bool = DEFAULT_LINEAR_TONEMAP
static var glow_enabled: bool = DEFAULT_GLOW_ENABLED
static var nearest_texture_filter: bool = DEFAULT_NEAREST_TEXTURE_FILTER
static var anti_aliasing_off: bool = DEFAULT_ANTI_ALIASING_OFF
static var low_res_viewport_enabled: bool = DEFAULT_LOW_RES_VIEWPORT
static var viewport_width: int = DEFAULT_VIEWPORT_WIDTH
static var viewport_height: int = DEFAULT_VIEWPORT_HEIGHT
static var camera_snap_enabled: bool = DEFAULT_CAMERA_SNAP


static func load_from_save() -> void:
	var data: Dictionary = LocalSave.get_meta_data().get(SAVE_KEY, {})
	pixel_scale = float(data.get("pixel_scale", DEFAULT_PIXEL_SCALE))
	color_levels = float(data.get("color_levels", DEFAULT_COLOR_LEVELS))
	edge_strength = float(data.get("edge_strength", DEFAULT_EDGE_STRENGTH))
	stitch_strength = float(data.get("stitch_strength", DEFAULT_STITCH_STRENGTH))
	pattern_strength = float(data.get("pattern_strength", DEFAULT_PATTERN_STRENGTH))
	linear_tonemap = bool(data.get("linear_tonemap", DEFAULT_LINEAR_TONEMAP))
	glow_enabled = bool(data.get("glow_enabled", DEFAULT_GLOW_ENABLED))
	nearest_texture_filter = bool(data.get("nearest_texture_filter", DEFAULT_NEAREST_TEXTURE_FILTER))
	anti_aliasing_off = bool(data.get("anti_aliasing_off", DEFAULT_ANTI_ALIASING_OFF))
	low_res_viewport_enabled = bool(data.get("low_res_viewport_enabled", DEFAULT_LOW_RES_VIEWPORT))
	viewport_width = int(data.get("viewport_width", DEFAULT_VIEWPORT_WIDTH))
	viewport_height = int(data.get("viewport_height", DEFAULT_VIEWPORT_HEIGHT))
	camera_snap_enabled = bool(data.get("camera_snap_enabled", DEFAULT_CAMERA_SNAP))


static func save() -> void:
	var meta := LocalSave.get_meta_data()
	meta[SAVE_KEY] = {
		"pixel_scale": pixel_scale,
		"color_levels": color_levels,
		"edge_strength": edge_strength,
		"stitch_strength": stitch_strength,
		"pattern_strength": pattern_strength,
		"linear_tonemap": linear_tonemap,
		"glow_enabled": glow_enabled,
		"nearest_texture_filter": nearest_texture_filter,
		"anti_aliasing_off": anti_aliasing_off,
		"low_res_viewport_enabled": low_res_viewport_enabled,
		"viewport_width": viewport_width,
		"viewport_height": viewport_height,
		"camera_snap_enabled": camera_snap_enabled,
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


static func viewport_internal_size() -> Vector2i:
	return Vector2i(maxi(160, viewport_width), maxi(90, viewport_height))


static func camera_snap_step() -> float:
	return maxf(0.05, PixelDioramaStyle.PROP_SNAP / maxf(1.0, float(viewport_height) / 180.0))


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
		mat.set_shader_parameter("pattern_strength", pattern_strength)
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
