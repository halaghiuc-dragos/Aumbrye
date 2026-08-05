extends RefCounted
class_name PixelDioramaStyle

## Shared pixel-diorama look: palettes, pixel-scale constants, and surface materials.
##
## Palette slot indices (same for every theme row in PALETTES):
##   0 = floor_base, 1 = floor_shadow, 2 = wall_base, 3 = wall_shadow,
##   4 = accent, 5 = prop_wood, 6 = prop_metal, 7 = emissive
##
## PaletteTheme row indices (use theme_from_biome() for BiomeRegistry ids):
##   0 castle, 1 crystal, 2 swamp, 3 frozen, 4 cathedral,
##   5 vault, 6 prism, 7 mire, 8 hollow, 9 umbral, 10 hub

enum PaletteSlot {
	FLOOR_BASE,
	FLOOR_SHADOW,
	WALL_BASE,
	WALL_SHADOW,
	ACCENT,
	PROP_WOOD,
	PROP_METAL,
	EMISSIVE,
}

enum PaletteTheme {
	CASTLE,
	CRYSTAL,
	SWAMP,
	FROZEN,
	CATHEDRAL,
	VAULT,
	PRISM,
	MIRE,
	HOLLOW,
	UMBRAL,
	HUB,
}

enum SurfaceKind { FLOOR, WALL, PROP, ACCENT }

## Performance budget (plan/systems/20-PERFORMANCE.md, M7 deferred profiling):
## - Target: 1080p @ 60 FPS (16.67 ms/frame) on mid-tier GPU
## - Pixel diorama stack: SubViewport + 4 shaders + SSAO — budget ~8 ms GPU
## - Occlusion: OccluderInstance3D on castle wall segments (CastleBlockout)
## - LOD: MeshInstance3D.lod_bias on wall meshes
const PERF_TARGET_FRAME_MS := 16.67
const PERF_PIXEL_STACK_BUDGET_MS := 8.0

## Fallback values only. Live tuning comes from PixelDioramaSettings, which is the
## single source of truth; these keep the module usable before settings load.
const PIXEL_SCALE := 8.0
const PATTERN_STRENGTH := 0.58
const COLOR_LEVELS := 6.0
const EDGE_STRENGTH := 0.42
const UV_TILE_METERS := 1.0
const PROP_SNAP := 0.5

const SHADER_PATH := "res://assets/shared/pixel_diorama_surface.gdshader"
const EMISSIVE_SHADER_PATH := "res://assets/shared/pixel_diorama_emissive.gdshader"
const PORTAL_SHADER_PATH := "res://assets/shared/portal_ellipse.gdshader"
const FLOOR_MATERIAL_PATH := "res://assets/shared/mat_pixel_floor.tres"

static var _surface_material_cache: Dictionary = {}
static var _prop_material_cache: Dictionary = {}
static var _accent_material_cache: Dictionary = {}
static var _emissive_material_cache: Dictionary = {}


static func clear_material_caches() -> void:
	_surface_material_cache.clear()
	_prop_material_cache.clear()
	_accent_material_cache.clear()
	_emissive_material_cache.clear()

const PALETTES: Array = [
	# castle
	[
		Color(0.35, 0.32, 0.38),
		Color(0.24, 0.22, 0.28),
		Color(0.22, 0.2, 0.28),
		Color(0.14, 0.12, 0.18),
		Color(0.55, 0.42, 0.28),
		Color(0.42, 0.3, 0.18),
		Color(0.48, 0.46, 0.5),
		Color(1.0, 0.62, 0.28),
	],
	# crystal
	[
		Color(0.42, 0.55, 0.78),
		Color(0.28, 0.38, 0.58),
		Color(0.32, 0.48, 0.72),
		Color(0.18, 0.28, 0.45),
		Color(0.65, 0.82, 0.95),
		Color(0.35, 0.42, 0.55),
		Color(0.55, 0.62, 0.72),
		Color(0.55, 0.85, 1.0),
	],
	# swamp
	[
		Color(0.28, 0.34, 0.2),
		Color(0.18, 0.24, 0.12),
		Color(0.2, 0.28, 0.16),
		Color(0.12, 0.16, 0.1),
		Color(0.45, 0.55, 0.22),
		Color(0.32, 0.24, 0.14),
		Color(0.4, 0.38, 0.34),
		Color(0.7, 0.9, 0.35),
	],
	# frozen
	[
		Color(0.72, 0.8, 0.88),
		Color(0.55, 0.65, 0.78),
		Color(0.62, 0.72, 0.82),
		Color(0.42, 0.52, 0.65),
		Color(0.85, 0.92, 0.98),
		Color(0.48, 0.38, 0.28),
		Color(0.58, 0.62, 0.68),
		Color(0.75, 0.9, 1.0),
	],
	# cathedral
	[
		Color(0.2, 0.16, 0.28),
		Color(0.12, 0.1, 0.18),
		Color(0.16, 0.12, 0.22),
		Color(0.08, 0.06, 0.12),
		Color(0.62, 0.48, 0.28),
		Color(0.34, 0.22, 0.14),
		Color(0.45, 0.42, 0.48),
		Color(0.95, 0.72, 0.35),
	],
	# vault
	[
		Color(0.35, 0.32, 0.3),
		Color(0.22, 0.2, 0.18),
		Color(0.28, 0.26, 0.24),
		Color(0.16, 0.14, 0.12),
		Color(0.58, 0.5, 0.32),
		Color(0.32, 0.24, 0.16),
		Color(0.52, 0.5, 0.48),
		Color(1.0, 0.55, 0.2),
	],
	# prism
	[
		Color(0.55, 0.72, 0.92),
		Color(0.38, 0.52, 0.72),
		Color(0.42, 0.58, 0.82),
		Color(0.26, 0.38, 0.58),
		Color(0.78, 0.55, 0.95),
		Color(0.38, 0.32, 0.48),
		Color(0.58, 0.56, 0.62),
		Color(0.65, 0.45, 1.0),
	],
	# mire
	[
		Color(0.28, 0.42, 0.22),
		Color(0.18, 0.28, 0.14),
		Color(0.22, 0.34, 0.18),
		Color(0.12, 0.2, 0.1),
		Color(0.55, 0.72, 0.28),
		Color(0.34, 0.26, 0.14),
		Color(0.42, 0.4, 0.36),
		Color(0.75, 0.95, 0.35),
	],
	# hollow
	[
		Color(0.72, 0.8, 0.88),
		Color(0.55, 0.64, 0.74),
		Color(0.6, 0.7, 0.8),
		Color(0.4, 0.48, 0.58),
		Color(0.82, 0.9, 0.98),
		Color(0.42, 0.34, 0.26),
		Color(0.56, 0.6, 0.66),
		Color(0.7, 0.88, 1.0),
	],
	# umbral
	[
		Color(0.14, 0.1, 0.2),
		Color(0.08, 0.06, 0.12),
		Color(0.12, 0.08, 0.18),
		Color(0.06, 0.04, 0.1),
		Color(0.55, 0.38, 0.62),
		Color(0.28, 0.18, 0.22),
		Color(0.4, 0.36, 0.44),
		Color(0.85, 0.55, 0.95),
	],
	# hub
	[
		Color(0.62, 0.52, 0.4),
		Color(0.54, 0.44, 0.34),
		Color(0.48, 0.42, 0.36),
		Color(0.36, 0.32, 0.28),
		Color(0.78, 0.55, 0.28),
		Color(0.36, 0.24, 0.16),
		Color(0.58, 0.28, 0.22),
		Color(0.9, 0.42, 0.12),
	],
]


static func theme_from_biome(biome_id: String) -> PaletteTheme:
	match biome_id:
		BiomeRegistry.BIOME_CRYSTAL:
			return PaletteTheme.CRYSTAL
		BiomeRegistry.BIOME_SWAMP:
			return PaletteTheme.SWAMP
		BiomeRegistry.BIOME_FROZEN:
			return PaletteTheme.FROZEN
		BiomeRegistry.BIOME_CATHEDRAL:
			return PaletteTheme.CATHEDRAL
		BiomeRegistry.BIOME_VAULT:
			return PaletteTheme.VAULT
		BiomeRegistry.BIOME_PRISM:
			return PaletteTheme.PRISM
		BiomeRegistry.BIOME_MIRE:
			return PaletteTheme.MIRE
		BiomeRegistry.BIOME_HOLLOW:
			return PaletteTheme.HOLLOW
		BiomeRegistry.BIOME_UMBRAL:
			return PaletteTheme.UMBRAL
		_:
			return PaletteTheme.CASTLE


static func get_palette(theme: PaletteTheme) -> Array[Color]:
	var row: Array = PALETTES[theme]
	var colors: Array[Color] = []
	colors.assign(row)
	return colors


static func get_palette_color(theme: PaletteTheme, slot: PaletteSlot) -> Color:
	return PALETTES[theme][slot] as Color


static func _surface_material_key(theme: PaletteTheme, surface: SurfaceKind, pattern_strength: float) -> String:
	return "%d_%d_%.4f" % [theme, surface, pattern_strength]


static func _configure_shader_material(mat: ShaderMaterial) -> void:
	PixelDioramaSettings.apply_to_shader_material(mat)


static func make_surface_material(
	surface: SurfaceKind,
	theme: PaletteTheme,
	pattern_strength: float = -1.0
) -> Material:
	if pattern_strength < 0.0:
		pattern_strength = PixelDioramaSettings.pattern_strength
	var key := _surface_material_key(theme, surface, pattern_strength)
	if _surface_material_cache.has(key):
		return _surface_material_cache[key] as Material

	var shader := load(SHADER_PATH) as Shader
	var mat := ShaderMaterial.new()
	mat.shader = shader
	_configure_shader_material(mat)

	var palette := get_palette(theme)
	match surface:
		SurfaceKind.FLOOR:
			mat.set_shader_parameter("color_base", palette[PaletteSlot.FLOOR_BASE])
			mat.set_shader_parameter("color_shadow", palette[PaletteSlot.FLOOR_SHADOW])
			mat.set_shader_parameter("color_accent", palette[PaletteSlot.ACCENT])
			mat.set_shader_parameter("surface_kind", 0)
		SurfaceKind.WALL:
			mat.set_shader_parameter("color_base", palette[PaletteSlot.WALL_BASE])
			mat.set_shader_parameter("color_shadow", palette[PaletteSlot.WALL_SHADOW])
			mat.set_shader_parameter("color_accent", palette[PaletteSlot.ACCENT])
			mat.set_shader_parameter("surface_kind", 1)
		SurfaceKind.PROP:
			mat.set_shader_parameter("color_base", palette[PaletteSlot.PROP_WOOD])
			mat.set_shader_parameter("color_shadow", palette[PaletteSlot.PROP_METAL])
			mat.set_shader_parameter("color_accent", palette[PaletteSlot.ACCENT])
			mat.set_shader_parameter("surface_kind", 2)
		SurfaceKind.ACCENT:
			mat.set_shader_parameter("color_base", palette[PaletteSlot.ACCENT])
			mat.set_shader_parameter("color_shadow", palette[PaletteSlot.WALL_SHADOW])
			mat.set_shader_parameter("color_accent", palette[PaletteSlot.EMISSIVE])
			mat.set_shader_parameter("surface_kind", 3)

	mat.set_shader_parameter("pattern_strength", pattern_strength)
	_surface_material_cache[key] = mat
	return mat


static func make_floor_material(theme: PaletteTheme) -> Material:
	return make_surface_material(SurfaceKind.FLOOR, theme)


static func make_wall_material(theme: PaletteTheme) -> Material:
	return make_surface_material(SurfaceKind.WALL, theme)


static func make_prop_material(theme: PaletteTheme, use_metal: bool = false) -> Material:
	var key := "%d_%s" % [theme, use_metal]
	if _prop_material_cache.has(key):
		return _prop_material_cache[key] as Material

	var mat: ShaderMaterial
	if use_metal:
		mat = make_surface_material(SurfaceKind.PROP, theme, 0.28).duplicate() as ShaderMaterial
		var palette := get_palette(theme)
		mat.set_shader_parameter("color_base", palette[PaletteSlot.PROP_METAL])
		mat.set_shader_parameter("color_shadow", palette[PaletteSlot.WALL_SHADOW])
	else:
		mat = make_surface_material(SurfaceKind.PROP, theme, 0.28) as ShaderMaterial

	_prop_material_cache[key] = mat
	return mat


static func make_accent_material(theme: PaletteTheme) -> Material:
	if _accent_material_cache.has(theme):
		return _accent_material_cache[theme] as Material

	var mat := make_surface_material(SurfaceKind.ACCENT, theme)
	_accent_material_cache[theme] = mat
	return mat


static func make_hub_materials() -> Dictionary:
	var theme := PaletteTheme.HUB
	var palette := get_palette(theme)
	var floor_alt := make_surface_material(SurfaceKind.FLOOR, theme).duplicate() as ShaderMaterial
	floor_alt.set_shader_parameter("color_base", palette[PaletteSlot.FLOOR_SHADOW])
	floor_alt.set_shader_parameter("color_shadow", palette[PaletteSlot.WALL_SHADOW])
	var accent_mat := make_surface_material(SurfaceKind.PROP, theme, 0.38).duplicate() as ShaderMaterial
	accent_mat.set_shader_parameter("color_base", palette[PaletteSlot.ACCENT])
	accent_mat.set_shader_parameter("color_shadow", palette[PaletteSlot.ACCENT].darkened(0.22))
	accent_mat.set_shader_parameter("color_accent", palette[PaletteSlot.EMISSIVE])
	var paper_mat := make_surface_material(SurfaceKind.PROP, theme, 0.18).duplicate() as ShaderMaterial
	paper_mat.set_shader_parameter("color_base", Color(0.92, 0.86, 0.68))
	paper_mat.set_shader_parameter("color_shadow", Color(0.78, 0.72, 0.55))
	paper_mat.set_shader_parameter("color_accent", palette[PaletteSlot.ACCENT])
	return {
		"floor": make_floor_material(theme),
		"floor_alt": floor_alt,
		"wall": make_wall_material(theme),
		"accent": accent_mat,
		"wood": make_prop_material(theme, false),
		"roof": make_prop_material(theme, true),
		"umbral": make_emissive_material(PaletteTheme.UMBRAL, 1.1),
		"training": make_custom_emissive(Color(0.95, 0.48, 0.12), 1.2),
		"dragon": make_custom_emissive(Color(0.72, 0.18, 0.1), 1.15),
		"cathedral": make_custom_emissive(Color(0.98, 0.9, 0.45), 0.95),
		"forge": make_emissive_material(theme, 1.35),
		"paper": paper_mat,
	}


## Quantized glow surface. Emissives go through the pixel shader too, otherwise
## torches and crystals read as smooth blobs next to banded pixel geometry.
static func make_glow_material(
	core: Color,
	edge: Color,
	energy: float,
	pulse_speed: float = 0.0
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(EMISSIVE_SHADER_PATH) as Shader
	mat.set_shader_parameter("color_core", core)
	mat.set_shader_parameter("color_edge", edge)
	mat.set_shader_parameter("emission_energy", energy)
	mat.set_shader_parameter("pulse_speed", pulse_speed)
	PixelDioramaSettings.apply_to_shader_material(mat)
	return mat


static func make_custom_emissive(color: Color, energy: float = 1.1) -> Material:
	return make_glow_material(color.lightened(0.14), color.darkened(0.22), energy)


static func make_emissive_material(theme: PaletteTheme, energy: float = 1.6) -> Material:
	var key := "%d_%.4f" % [theme, energy]
	if _emissive_material_cache.has(key):
		return _emissive_material_cache[key] as Material

	var glow := get_palette_color(theme, PaletteSlot.EMISSIVE)
	var mat := make_glow_material(glow, glow.darkened(0.3), energy)
	_emissive_material_cache[key] = mat
	return mat


static func load_floor_material_template() -> ShaderMaterial:
	return load(FLOOR_MATERIAL_PATH).duplicate() as ShaderMaterial


static func apply_theme_to_blockout(blockout: CastleBlockout, biome_id: String) -> void:
	if blockout == null:
		return
	var theme := theme_from_biome(biome_id)
	blockout.floor_material = make_floor_material(theme)
	blockout.wall_material = make_wall_material(theme)
	blockout.accent_material = make_accent_material(theme)


static func load_material(path: String) -> Material:
	return load(path) as Material


## Ad-hoc coloured surface for props and NPCs that are not palette driven.
## Routed through the pixel shaders so nothing falls back to smooth PBR shading.
static func make_material(color: Color, emission: Color = Color.BLACK) -> Material:
	if emission != Color.BLACK:
		return make_glow_material(color.lightened(0.1), color.darkened(0.25), 1.15)
	var key := "solid_%s" % color.to_html(false)
	if _prop_material_cache.has(key):
		return _prop_material_cache[key] as Material
	var mat := ShaderMaterial.new()
	mat.shader = load(SHADER_PATH) as Shader
	mat.set_shader_parameter("color_base", color)
	mat.set_shader_parameter("color_shadow", color.darkened(0.3))
	mat.set_shader_parameter("color_accent", color.lightened(0.2))
	mat.set_shader_parameter("surface_kind", 2)
	PixelDioramaSettings.apply_to_shader_material(mat)
	mat.set_shader_parameter("pattern_strength", PixelDioramaSettings.pattern_strength * 0.45)
	_prop_material_cache[key] = mat
	return mat


static func add_box(
	parent: Node3D,
	size: Vector3,
	position: Vector3,
	material: Material,
	node_name: String = ""
) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	if node_name != "":
		mesh_inst.name = node_name
	var box := BoxMesh.new()
	box.size = size
	mesh_inst.mesh = box
	mesh_inst.position = position
	if material:
		mesh_inst.material_override = material
	if OS.has_environment("AUMBRYE_STD_MAT"):
		var std := StandardMaterial3D.new()
		std.albedo_color = Color(0.62, 0.56, 0.5)
		mesh_inst.material_override = std
	parent.add_child(mesh_inst)
	return mesh_inst


static func make_portal_material(theme: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PORTAL_SHADER_PATH) as Shader
	match theme:
		"castle":
			mat.set_shader_parameter("color_inner", Color(0.55, 0.78, 1.0, 1.0))
			mat.set_shader_parameter("color_outer", Color(0.16, 0.28, 0.62, 1.0))
			mat.set_shader_parameter("color_accent", Color(0.9, 0.96, 1.0, 1.0))
			mat.set_shader_parameter("ellipse_x", 0.72)
			mat.set_shader_parameter("ellipse_y", 1.0)
		"training":
			mat.set_shader_parameter("color_inner", Color(1.0, 0.62, 0.18, 1.0))
			mat.set_shader_parameter("color_outer", Color(0.58, 0.22, 0.05, 1.0))
			mat.set_shader_parameter("color_accent", Color(1.0, 0.82, 0.42, 1.0))
			mat.set_shader_parameter("ellipse_x", 0.7)
			mat.set_shader_parameter("ellipse_y", 0.98)
			mat.set_shader_parameter("spin_speed", 1.2)
		"skies":
			mat.set_shader_parameter("color_inner", Color(0.98, 0.42, 0.12, 1.0))
			mat.set_shader_parameter("color_outer", Color(0.42, 0.08, 0.06, 1.0))
			mat.set_shader_parameter("color_accent", Color(1.0, 0.72, 0.22, 1.0))
			mat.set_shader_parameter("ellipse_x", 0.74)
			mat.set_shader_parameter("ellipse_y", 1.02)
			mat.set_shader_parameter("spin_speed", 2.1)
		"cathedral":
			mat.set_shader_parameter("color_inner", Color(1.0, 0.96, 0.78, 1.0))
			mat.set_shader_parameter("color_outer", Color(0.82, 0.72, 0.28, 1.0))
			mat.set_shader_parameter("color_accent", Color(1.0, 1.0, 0.92, 1.0))
			mat.set_shader_parameter("ellipse_x", 0.7)
			mat.set_shader_parameter("ellipse_y", 0.96)
			mat.set_shader_parameter("spin_speed", 0.9)
		_: # umbral and fallback
			mat.set_shader_parameter("color_inner", Color(0.62, 0.38, 0.92, 1.0))
			mat.set_shader_parameter("color_outer", Color(0.22, 0.1, 0.38, 1.0))
			mat.set_shader_parameter("color_accent", Color(0.85, 0.55, 1.0, 1.0))
			mat.set_shader_parameter("ellipse_x", 0.68)
			mat.set_shader_parameter("ellipse_y", 0.95)
			mat.set_shader_parameter("spin_speed", 1.8)
	return mat


static func add_portal_interior(
	parent: Node3D,
	size: Vector2,
	position: Vector3,
	theme: String,
	node_name: String = "PortalInterior"
) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = node_name
	var quad := QuadMesh.new()
	quad.size = size
	mesh_inst.mesh = quad
	mesh_inst.position = position
	mesh_inst.material_override = make_portal_material(theme)
	parent.add_child(mesh_inst)
	return mesh_inst


static func add_collision_box(
	parent: Node3D,
	size: Vector3,
	position: Vector3,
	node_name: String = "Collision"
) -> CollisionShape3D:
	var shape_node := CollisionShape3D.new()
	shape_node.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = position
	parent.add_child(shape_node)
	return shape_node


static func add_hub_tent(
	landmark: Node3D,
	mats: Dictionary,
	width: float,
	depth: float,
	wall_height: float,
	entrance_width: float,
	roof_peak: float = 1.2,
	facing_yaw: float = 0.0
) -> Node3D:
	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	landmark.add_child(visuals)
	visuals.rotation.y = facing_yaw

	var fabric_mat: Material = mats.wall
	var pole_mat: Material = mats.wood
	var roof_mat: Material = mats.accent
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thickness := 0.22
	var pole_h := wall_height + roof_peak * 0.35
	var lip_width := (width - entrance_width) * 0.5
	var lip_z := half_d - wall_thickness * 0.5

	for corner in [
		Vector3(-half_w + 0.18, 0.0, -half_d + 0.18),
		Vector3(half_w - 0.18, 0.0, -half_d + 0.18),
		Vector3(-half_w + 0.18, 0.0, half_d - 0.18),
		Vector3(half_w - 0.18, 0.0, half_d - 0.18),
	]:
		add_cylinder(visuals, 0.07, 0.09, pole_h, corner + Vector3(0.0, pole_h * 0.5, 0.0), pole_mat, "Pole")

	var ridge_y := wall_height + roof_peak
	add_box(visuals, Vector3(width + 0.35, 0.14, 0.14), Vector3(0.0, ridge_y, 0.0), roof_mat, "Ridge")

	var front_slope_len := sqrt(half_d * half_d + roof_peak * roof_peak)
	var front_slope_angle := atan2(roof_peak, half_d)
	var front_roof := add_box(
		visuals,
		Vector3(width + 0.25, 0.1, front_slope_len + 0.15),
		Vector3(0.0, wall_height + roof_peak * 0.5, half_d * 0.5),
		fabric_mat,
		"RoofPanelFront"
	)
	front_roof.rotation.x = front_slope_angle
	var back_roof := add_box(
		visuals,
		Vector3(width + 0.25, 0.1, front_slope_len + 0.15),
		Vector3(0.0, wall_height + roof_peak * 0.5, -half_d * 0.5),
		fabric_mat,
		"RoofPanelBack"
	)
	back_roof.rotation.x = -front_slope_angle

	var side_slope_len := sqrt(half_w * half_w + roof_peak * roof_peak)
	var side_slope_angle := atan2(roof_peak, half_w)
	var left_roof := add_box(
		visuals,
		Vector3(side_slope_len + 0.15, 0.1, depth + 0.25),
		Vector3(-half_w * 0.5, wall_height + roof_peak * 0.5, 0.0),
		fabric_mat,
		"RoofPanelLeft"
	)
	left_roof.rotation.z = side_slope_angle
	var right_roof := add_box(
		visuals,
		Vector3(side_slope_len + 0.15, 0.1, depth + 0.25),
		Vector3(half_w * 0.5, wall_height + roof_peak * 0.5, 0.0),
		fabric_mat,
		"RoofPanelRight"
	)
	right_roof.rotation.z = -side_slope_angle

	var stake_pos := Vector3(half_w + 0.55, 0.0, half_d + 0.35)
	add_cylinder(visuals, 0.04, 0.05, 0.35, stake_pos + Vector3(0.0, 0.18, 0.0), pole_mat, "Stake")
	var guy_line := add_box(visuals, Vector3(0.04, 0.04, 0.65), Vector3(0.0, 0.0, 0.0), pole_mat, "GuyLine")
	guy_line.position = (Vector3(half_w - 0.18, pole_h * 0.85, half_d - 0.18) + stake_pos) * 0.5
	guy_line.look_at(Vector3(half_w - 0.18, pole_h * 0.85, half_d - 0.18), Vector3.UP)

	add_box(
		visuals,
		Vector3(width, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, -half_d),
		fabric_mat,
		"WallBack"
	)
	add_box(
		visuals,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(-half_w, wall_height * 0.5, 0.0),
		fabric_mat,
		"WallLeft"
	)
	add_box(
		visuals,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(half_w, wall_height * 0.5, 0.0),
		fabric_mat,
		"WallRight"
	)

	if lip_width > 0.15:
		var lip_left_x := -half_w + lip_width * 0.5
		var lip_right_x := half_w - lip_width * 0.5
		add_box(
			visuals,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(lip_left_x, wall_height * 0.5, lip_z),
			fabric_mat,
			"WallFrontLipL"
		)
		add_box(
			visuals,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(lip_right_x, wall_height * 0.5, lip_z),
			fabric_mat,
			"WallFrontLipR"
		)

	var flap_h := wall_height * 0.55
	var flap_z := half_d - wall_thickness * 0.35
	add_box(
		visuals,
		Vector3(0.12, flap_h, 0.08),
		Vector3(-entrance_width * 0.25, flap_h * 0.5, flap_z),
		fabric_mat,
		"FlapL"
	)
	add_box(
		visuals,
		Vector3(0.12, flap_h, 0.08),
		Vector3(entrance_width * 0.25, flap_h * 0.5, flap_z),
		fabric_mat,
		"FlapR"
	)

	add_box(visuals, Vector3(width + 0.6, 0.1, depth + 0.6), Vector3(0.0, 0.05, 0.0), mats.floor_alt, "TentPad")

	var collision_root := landmark.get_node_or_null("TentCollision") as StaticBody3D
	if collision_root == null:
		collision_root = StaticBody3D.new()
		collision_root.name = "TentCollision"
		landmark.add_child(collision_root)
	else:
		for child in collision_root.get_children():
			child.queue_free()
	collision_root.collision_layer = 1
	collision_root.collision_mask = 0
	collision_root.rotation.y = facing_yaw

	add_collision_box(
		collision_root,
		Vector3(width, wall_height, wall_thickness),
		Vector3(0.0, wall_height * 0.5, -half_d),
		"ColBack"
	)
	add_collision_box(
		collision_root,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(-half_w, wall_height * 0.5, 0.0),
		"ColLeft"
	)
	add_collision_box(
		collision_root,
		Vector3(wall_thickness, wall_height, depth),
		Vector3(half_w, wall_height * 0.5, 0.0),
		"ColRight"
	)
	if lip_width > 0.15:
		add_collision_box(
			collision_root,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(-half_w + lip_width * 0.5, wall_height * 0.5, lip_z),
			"ColFrontLipL"
		)
		add_collision_box(
			collision_root,
			Vector3(lip_width, wall_height, wall_thickness),
			Vector3(half_w - lip_width * 0.5, wall_height * 0.5, lip_z),
			"ColFrontLipR"
		)

	return visuals


static func add_hub_fountain(parent: Node3D, mats: Dictionary, position: Vector3) -> Node3D:
	var fountain := Node3D.new()
	fountain.name = "PlazaFountain"
	fountain.position = position
	parent.add_child(fountain)

	var water_mat := make_material(Color(0.42, 0.68, 0.92, 0.85))
	var stone_mat: Material = mats.wall
	var accent_mat: Material = mats.accent

	add_cylinder(fountain, 2.35, 2.55, 0.22, Vector3(0.0, 0.11, 0.0), water_mat, "PoolRim")
	add_cylinder(fountain, 1.85, 1.95, 0.16, Vector3(0.0, 0.2, 0.0), water_mat, "PoolWater")
	add_cylinder(fountain, 0.42, 0.55, 0.95, Vector3(0.0, 0.62, 0.0), stone_mat, "Pedestal")
	add_cylinder(fountain, 0.18, 0.24, 0.35, Vector3(0.0, 1.18, 0.0), accent_mat, "Spout")

	var droplet_mesh := _make_fountain_particle_mesh(0.14)
	var droplet_mat := _make_fountain_particle_material(Color(0.55, 0.82, 1.0, 0.9), 1.1)
	var mist_mat := _make_fountain_particle_material(Color(0.78, 0.92, 1.0, 0.45), 0.35)

	var spray := CPUParticles3D.new()
	spray.name = "WaterSpray"
	spray.position = Vector3(0.0, 1.55, 0.0)
	spray.emitting = true
	spray.amount = 88
	spray.lifetime = 1.15
	spray.one_shot = false
	spray.preprocess = 1.0
	spray.explosiveness = 0.12
	spray.randomness = 0.4
	spray.direction = Vector3(0.0, 1.0, 0.0)
	spray.spread = 18.0
	spray.flatness = 0.1
	spray.gravity = Vector3(0.0, -9.8, 0.0)
	spray.initial_velocity_min = 4.8
	spray.initial_velocity_max = 7.2
	spray.scale_amount_min = 0.1
	spray.scale_amount_max = 0.2
	spray.color = Color(0.62, 0.86, 1.0, 0.92)
	spray.mesh = droplet_mesh
	spray.material_override = droplet_mat
	spray.visibility_aabb = AABB(Vector3(-2.5, -2.0, -2.5), Vector3(5.0, 7.5, 5.0))
	fountain.add_child(spray)

	var fall := CPUParticles3D.new()
	fall.name = "WaterFall"
	fall.position = Vector3(0.0, 1.85, 0.0)
	fall.emitting = true
	fall.amount = 64
	fall.lifetime = 1.35
	fall.one_shot = false
	fall.preprocess = 1.0
	fall.explosiveness = 0.08
	fall.randomness = 0.55
	fall.direction = Vector3(0.0, 1.0, 0.0)
	fall.spread = 42.0
	fall.flatness = 0.3
	fall.gravity = Vector3(0.0, -12.0, 0.0)
	fall.initial_velocity_min = 2.8
	fall.initial_velocity_max = 5.2
	fall.scale_amount_min = 0.07
	fall.scale_amount_max = 0.14
	fall.color = Color(0.48, 0.74, 0.98, 0.82)
	fall.mesh = droplet_mesh
	fall.material_override = droplet_mat
	fall.visibility_aabb = AABB(Vector3(-2.5, -2.0, -2.5), Vector3(5.0, 7.5, 5.0))
	fountain.add_child(fall)

	var mist := CPUParticles3D.new()
	mist.name = "WaterMist"
	mist.position = Vector3(0.0, 1.25, 0.0)
	mist.emitting = true
	mist.amount = 32
	mist.lifetime = 1.35
	mist.one_shot = false
	mist.preprocess = 0.8
	mist.direction = Vector3(0.0, 1.0, 0.0)
	mist.spread = 55.0
	mist.flatness = 0.5
	mist.gravity = Vector3(0.0, -3.5, 0.0)
	mist.initial_velocity_min = 0.5
	mist.initial_velocity_max = 1.6
	mist.scale_amount_min = 0.16
	mist.scale_amount_max = 0.28
	mist.color = Color(0.85, 0.94, 1.0, 0.4)
	mist.mesh = _make_fountain_particle_mesh(0.22)
	mist.material_override = mist_mat
	mist.visibility_aabb = AABB(Vector3(-2.5, -2.0, -2.5), Vector3(5.0, 7.5, 5.0))
	fountain.add_child(mist)

	var glow := OmniLight3D.new()
	glow.name = "WaterGlow"
	glow.light_color = Color(0.62, 0.82, 1.0)
	glow.light_energy = 0.42
	glow.omni_range = 3.2
	glow.position = Vector3(0.0, 0.85, 0.0)
	fountain.add_child(glow)

	return fountain


static func _make_fountain_particle_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 4
	return mesh


static func _make_fountain_particle_material(color: Color, emission_energy: float) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.emission_enabled = true
	mat.emission = Color(color.r, color.g, color.b)
	mat.emission_energy_multiplier = emission_energy
	mat.texture_filter = PixelDioramaSettings.texture_filter_mode()
	return mat


static func add_cylinder(
	parent: Node3D,
	top_radius: float,
	bottom_radius: float,
	height: float,
	position: Vector3,
	material: Material,
	node_name: String = ""
) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	if node_name != "":
		mesh_inst.name = node_name
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = top_radius
	cylinder.bottom_radius = bottom_radius
	cylinder.height = height
	mesh_inst.mesh = cylinder
	mesh_inst.position = position
	if material:
		mesh_inst.material_override = material
	parent.add_child(mesh_inst)
	return mesh_inst


static func hide_legacy_meshes(root: Node) -> void:
	## Capsule/blockout meshes only — never recurse into authored diorama rigs.
	const SKIP_SUBTREES := ["DioramaVisual", "DioramaVisuals", "Viewmodel"]
	for child in root.get_children():
		if child.name in SKIP_SUBTREES:
			continue
		if child is MeshInstance3D:
			child.visible = false
		elif child.name != "InteractArea" and child.name != "PortalLabel" and child.name != "Label" and child.name != "DoorLabel" and child.name != "NameLabel":
			hide_legacy_meshes(child)
