extends RefCounted
class_name PixelDioramaStyle

## Shared pixel-diorama look: palettes, material factories, and primitive builders.
## Palette colours load from `content/art/palettes.json` with a GDScript fallback.

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

const PALETTE_JSON_PATH := "content/art/palettes.json"
const STRUCTURE_DIR := "content/art/structures"

const THEME_IDS: Array[String] = [
	"castle",
	"crystal",
	"swamp",
	"frozen",
	"cathedral",
	"vault",
	"prism",
	"mire",
	"hollow",
	"umbral",
	"hub",
]

const SHADER_PATH := "res://assets/shared/pixel_diorama_surface.gdshader"
const EMISSIVE_SHADER_PATH := "res://assets/shared/pixel_diorama_emissive.gdshader"
const PORTAL_SHADER_PATH := "res://assets/shared/portal_ellipse.gdshader"

const VoxelGridScript := preload("res://scripts/art/characters/voxel_grid.gd")

## Size of one Aumbrye art pixel in world units. Authored character voxels, billboards,
## world-space labels, decals and telegraph quads all quantise to this single unit so the
## whole diorama shares one pixel density rather than one per drawing surface.
const WORLD_PIXEL: float = VoxelGridScript.EDGE
const PIXELS_PER_UNIT: float = 1.0 / VoxelGridScript.EDGE

static var _surface_material_cache: Dictionary = {}
static var _prop_material_cache: Dictionary = {}
static var _accent_material_cache: Dictionary = {}
static var _emissive_material_cache: Dictionary = {}
static var _palette_loaded := false
static var _palette_rows: Array = []
static var _biome_theme_map: Dictionary = {}
static var _palette_tuning: Dictionary = {}
static var _atlas_exists_cache: Dictionary = {}
static var _warned_unknown_mats: Dictionary = {}
static var _portal_material_cache: Dictionary = {}


static func clear_material_caches() -> void:
	_surface_material_cache.clear()
	_prop_material_cache.clear()
	_accent_material_cache.clear()
	_emissive_material_cache.clear()
	# C-177: this line lived after a `return` inside `_deg_to_rad_array`, 119 lines away — a
	# copy-paste that landed in the wrong function. GDScript does not warn on unreachable code, so
	# the portal cache was never cleared, and two suites were written around the gap.
	_portal_material_cache.clear()


static func set_authored_param(mat: ShaderMaterial, param: String, value: Variant) -> void:
	mat.set_shader_parameter(param, value)
	var authored: Array = mat.get_meta("authored_params", [])
	if not authored.has(param):
		authored.append(param)
	mat.set_meta("authored_params", authored)


static func _ensure_palettes_loaded() -> void:
	if _palette_loaded:
		return
	_palette_loaded = true
	var data := ContentLoader.load_json(PALETTE_JSON_PATH)
	if data.is_empty():
		push_warning(
			"PixelDioramaStyle: failed to load %s; using fallback PALETTES" % PALETTE_JSON_PATH
		)
		_palette_rows = _fallback_palette_rows()
		_biome_theme_map = _fallback_biome_theme_map()
		return
	var palettes: Dictionary = data.get("palettes", {})
	_palette_rows.clear()
	for theme_id in THEME_IDS:
		var entry: Dictionary = palettes.get(theme_id, {})
		if entry.is_empty():
			push_warning("PixelDioramaStyle: palette '%s' missing in palettes.json" % theme_id)
			continue
		_palette_rows.append(_palette_row_from_dict(entry))
		if entry.has("tuning"):
			_palette_tuning[theme_id] = entry.get("tuning", {})
	_biome_theme_map = data.get("biome_theme_map", {})
	if _palette_rows.size() != THEME_IDS.size():
		push_warning("PixelDioramaStyle: palette row count mismatch; merging fallback rows")
		_palette_rows = _merge_palette_rows(_palette_rows, _fallback_palette_rows())


static func _palette_row_from_dict(entry: Dictionary) -> Array:
	return [
		Color.html(entry.get("floor_base", "#ffffff")),
		Color.html(entry.get("floor_shadow", "#000000")),
		Color.html(entry.get("wall_base", "#808080")),
		Color.html(entry.get("wall_shadow", "#404040")),
		Color.html(entry.get("accent", "#ffaa00")),
		Color.html(entry.get("prop_wood", "#6b4a2c")),
		Color.html(entry.get("prop_metal", "#808080")),
		Color.html(entry.get("emissive", "#ffaa00")),
	]


static func _merge_palette_rows(primary: Array, fallback: Array) -> Array:
	var merged: Array = []
	for i in fallback.size():
		if i < primary.size() and (primary[i] as Array).size() >= 8:
			merged.append(primary[i])
		else:
			merged.append(fallback[i])
	return merged


static func _theme_id(theme: PaletteTheme) -> String:
	var idx := clampi(int(theme), 0, THEME_IDS.size() - 1)
	return THEME_IDS[idx]


static func _atlas_path_for_theme(theme: PaletteTheme) -> String:
	return "res://assets/textures/%s/tiles.png" % _theme_id(theme)


static func _load_tile_atlas(path: String) -> Texture2D:
	var loaded := load(path)
	if loaded is Texture2D:
		return loaded
	return null


static func _theme_has_tile_atlas(theme: PaletteTheme) -> bool:
	var theme_id := _theme_id(theme)
	if _atlas_exists_cache.has(theme_id):
		return bool(_atlas_exists_cache[theme_id])
	var path := _atlas_path_for_theme(theme)
	var exists := ResourceLoader.exists(path)
	_atlas_exists_cache[theme_id] = exists
	return exists


static func _apply_palette_tuning(mat: ShaderMaterial, theme: PaletteTheme) -> void:
	var tuning: Variant = _palette_tuning.get(_theme_id(theme), {})
	if not tuning is Dictionary:
		return
	for key in (tuning as Dictionary).keys():
		set_authored_param(mat, str(key), (tuning as Dictionary)[key])


static func _resolve_structure_material(mats: Dictionary, mat_key: String) -> Material:
	if mats.has(mat_key):
		return mats[mat_key]
	if not _warned_unknown_mats.has(mat_key):
		_warned_unknown_mats[mat_key] = true
		push_warning("PixelDioramaStyle.build_structure: unknown mat '%s', using wall" % mat_key)
	return mats.get("wall", mats.values()[0])


static func _vec3_from_array(raw: Variant, fallback := Vector3.ZERO) -> Vector3:
	if raw is Array and (raw as Array).size() >= 3:
		var arr: Array = raw
		return Vector3(float(arr[0]), float(arr[1]), float(arr[2]))
	return fallback


static func _deg_to_rad_array(raw: Variant) -> Vector3:
	var deg := _vec3_from_array(raw)
	return Vector3(deg_to_rad(deg.x), deg_to_rad(deg.y), deg_to_rad(deg.z))


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


static func _fallback_biome_theme_map() -> Dictionary:
	return {
		BiomeRegistry.BIOME_CRYSTAL: "crystal",
		BiomeRegistry.BIOME_SWAMP: "swamp",
		BiomeRegistry.BIOME_FROZEN: "frozen",
		BiomeRegistry.BIOME_CATHEDRAL: "cathedral",
		BiomeRegistry.BIOME_VAULT: "vault",
		BiomeRegistry.BIOME_PRISM: "prism",
		BiomeRegistry.BIOME_MIRE: "mire",
		BiomeRegistry.BIOME_HOLLOW: "hollow",
		BiomeRegistry.BIOME_UMBRAL: "umbral",
	}


static func _fallback_palette_rows() -> Array:
	return PALETTES.duplicate(true)


static func theme_from_biome(biome_id: String) -> PaletteTheme:
	_ensure_palettes_loaded()
	var theme_name: String = str(_biome_theme_map.get(biome_id, "castle"))
	var idx := THEME_IDS.find(theme_name)
	if idx < 0:
		return PaletteTheme.CASTLE
	return idx as PaletteTheme


static func get_palette(theme: PaletteTheme) -> Array[Color]:
	_ensure_palettes_loaded()
	var idx := clampi(int(theme), 0, _palette_rows.size() - 1)
	if idx != int(theme):
		push_warning(
			"PixelStyle.get_palette: theme %d out of range, clamped to %d" % [int(theme), idx]
		)
	var row: Array = _palette_rows[idx]
	var colors: Array[Color] = []
	colors.assign(row)
	return colors


static func get_palette_color(theme: PaletteTheme, slot: PaletteSlot) -> Color:
	_ensure_palettes_loaded()
	var idx := clampi(int(theme), 0, _palette_rows.size() - 1)
	if idx != int(theme):
		push_warning(
			"PixelStyle.get_palette_color: theme %d out of range, clamped to %d" % [int(theme), idx]
		)
	return _palette_rows[idx][slot] as Color


static func _surface_material_key(
	theme: PaletteTheme, surface: SurfaceKind, pattern_strength: float
) -> String:
	return "%d_%d_%.4f" % [theme, surface, pattern_strength]


static func _configure_shader_material(mat: ShaderMaterial) -> void:
	PixelDioramaSettings.apply_to_shader_material(mat)


static func make_surface_material(
	surface: SurfaceKind, theme: PaletteTheme, pattern_strength: float = -1.0
) -> Material:
	var authored_pattern := pattern_strength >= 0.0
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

	if authored_pattern:
		set_authored_param(mat, "pattern_strength", pattern_strength)
	else:
		mat.set_shader_parameter("pattern_strength", pattern_strength)
	_apply_palette_tuning(mat, theme)
	if _theme_has_tile_atlas(theme) and surface in [SurfaceKind.FLOOR, SurfaceKind.WALL]:
		var atlas_tex := _load_tile_atlas(_atlas_path_for_theme(theme))
		if atlas_tex:
			mat.set_shader_parameter("tile_atlas", atlas_tex)
			set_authored_param(mat, "use_tile_atlas", true)
			set_authored_param(mat, "tile_row", 0 if surface == SurfaceKind.FLOOR else 1)
			set_authored_param(mat, "tile_variants", 4)
		else:
			set_authored_param(mat, "use_tile_atlas", false)
	else:
		set_authored_param(mat, "use_tile_atlas", false)
	_surface_material_cache[key] = mat
	return PixelDioramaSettings.track(mat)


static func make_floor_material(theme: PaletteTheme) -> Material:
	return make_surface_material(SurfaceKind.FLOOR, theme)


static func make_wall_material(theme: PaletteTheme) -> Material:
	return make_surface_material(SurfaceKind.WALL, theme)


static func make_ceiling_material(theme: PaletteTheme) -> Material:
	var palette := get_palette(theme)
	var mat := make_surface_material(SurfaceKind.WALL, theme).duplicate() as ShaderMaterial
	set_authored_param(mat, "color_base", palette[PaletteSlot.WALL_BASE].darkened(0.12))
	set_authored_param(mat, "color_shadow", palette[PaletteSlot.WALL_SHADOW].darkened(0.08))
	set_authored_param(mat, "color_accent", palette[PaletteSlot.ACCENT].darkened(0.12))
	return PixelDioramaSettings.track(mat)


static func make_prop_material(theme: PaletteTheme, use_metal: bool = false) -> Material:
	var key := "%d_%s" % [theme, use_metal]
	if _prop_material_cache.has(key):
		return _prop_material_cache[key] as Material

	var mat := make_surface_material(SurfaceKind.PROP, theme, 0.28).duplicate() as ShaderMaterial
	if use_metal:
		var palette := get_palette(theme)
		set_authored_param(mat, "color_base", palette[PaletteSlot.PROP_METAL])
		set_authored_param(mat, "color_shadow", palette[PaletteSlot.WALL_SHADOW])
	_prop_material_cache[key] = mat
	return PixelDioramaSettings.track(mat)


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
	set_authored_param(floor_alt, "color_base", palette[PaletteSlot.FLOOR_SHADOW])
	set_authored_param(floor_alt, "color_shadow", palette[PaletteSlot.WALL_SHADOW])
	set_authored_param(floor_alt, "pattern_strength", 0.34)
	var accent_mat := (
		make_surface_material(SurfaceKind.PROP, theme, 0.38).duplicate() as ShaderMaterial
	)
	set_authored_param(accent_mat, "color_base", palette[PaletteSlot.ACCENT])
	set_authored_param(accent_mat, "color_shadow", palette[PaletteSlot.ACCENT].darkened(0.22))
	set_authored_param(accent_mat, "color_accent", palette[PaletteSlot.EMISSIVE])
	set_authored_param(accent_mat, "pattern_strength", 0.42)
	var paper_mat := (
		make_surface_material(SurfaceKind.PROP, theme, 0.18).duplicate() as ShaderMaterial
	)
	set_authored_param(paper_mat, "color_base", Color(0.92, 0.86, 0.68))
	set_authored_param(paper_mat, "color_shadow", Color(0.78, 0.72, 0.55))
	set_authored_param(paper_mat, "color_accent", palette[PaletteSlot.ACCENT])
	set_authored_param(paper_mat, "pattern_strength", 0.18)
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
	core: Color, edge: Color, energy: float, pulse_speed: float = 0.0
) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(EMISSIVE_SHADER_PATH) as Shader
	mat.set_shader_parameter("color_core", core)
	mat.set_shader_parameter("color_edge", edge)
	mat.set_shader_parameter("emission_energy", energy)
	mat.set_shader_parameter("pulse_speed", pulse_speed)
	PixelDioramaSettings.apply_to_shader_material(mat)
	return PixelDioramaSettings.track(mat)


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
	var prop_pattern := PixelDioramaSettings.pattern_strength * 0.45
	set_authored_param(mat, "pattern_strength", prop_pattern)
	_prop_material_cache[key] = PixelDioramaSettings.track(mat)
	return mat


static func pixels_to_units(pixels: float) -> float:
	return pixels * WORLD_PIXEL


static func units_to_pixels(units: float) -> float:
	return units * PIXELS_PER_UNIT


static func snap_to_pixel_grid(value: float) -> float:
	return roundf(value * PIXELS_PER_UNIT) * WORLD_PIXEL


static func snap_vector_to_pixel_grid(value: Vector3) -> Vector3:
	return Vector3(
		snap_to_pixel_grid(value.x), snap_to_pixel_grid(value.y), snap_to_pixel_grid(value.z)
	)


## Quantises a 0..1 fill ratio to whole texture pixels so a scaled bar never lands on a
## fraction of a pixel. Returns the ratio rounded to the nearest 1/texel_width.
static func snap_fill_ratio(ratio: float, texel_width: int) -> float:
	if texel_width <= 0:
		return clampf(ratio, 0.0, 1.0)
	var steps := roundf(clampf(ratio, 0.0, 1.0) * float(texel_width))
	return steps / float(texel_width)


## Single entry point for every world-space sprite: nearest filtering, no shadow, and a
## texel density expressed in Aumbrye art pixels rather than an ad-hoc division.
static func configure_pixel_sprite(sprite: SpriteBase3D, texel_scale: float = 1.0) -> void:
	if sprite == null:
		return
	sprite.pixel_size = WORLD_PIXEL * maxf(texel_scale, 0.0001)
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Same contract as configure_pixel_sprite, for world-space text. font_pixel_height is the
## cap height in art pixels, which is what keeps labels at the same density as everything else.
static func configure_pixel_label(
	label: Label3D, font_pixel_height: int = 4, texel_scale: float = 1.0
) -> void:
	if label == null:
		return
	label.font_size = maxi(font_pixel_height, 1) * 16
	label.pixel_size = WORLD_PIXEL * maxf(texel_scale, 0.0001) / 16.0
	label.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	label.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF


## Rounds a world-space size to whole art pixels, never collapsing below one pixel.
static func snap_size_to_pixel_grid(size: Vector3) -> Vector3:
	return Vector3(
		maxf(WORLD_PIXEL, snap_to_pixel_grid(size.x)),
		maxf(WORLD_PIXEL, snap_to_pixel_grid(size.y)),
		maxf(WORLD_PIXEL, snap_to_pixel_grid(size.z))
	)


static func snap_size2_to_pixel_grid(size: Vector2) -> Vector2:
	return Vector2(
		maxf(WORLD_PIXEL, snap_to_pixel_grid(size.x)),
		maxf(WORLD_PIXEL, snap_to_pixel_grid(size.y))
	)


## Corner-cut box mesh, cached by (size, bevel).
##
## Props were the other half of the "everything is a rectangle" problem: a torch, a brazier, a
## pillar and an anvil were each one BoxMesh, so a room's furniture read as shipping crates next to
## characters that are now properly sculpted. Slicing the eight corners off at 45 degrees is the
## three-dimensional form of the same pixel-art line the voxel rigs use, and it catches light on a
## third facet, which is what stops a prop reading as a flat slab.
##
## Walls and floors deliberately keep the plain BoxMesh: a bevel there would open a visible seam
## everywhere two wall segments meet.
## Prop sizes snap to this grid so near-identical props share one mesh.
const MESH_SNAP := 0.1
## Smallest side that earns a chamfer at all.
const MIN_BEVEL_SIZE := 0.34

static var _bevel_mesh_cache: Dictionary = {}


static func bevel_box_mesh(size: Vector3, bevel: float) -> Mesh:
	# Sizes are snapped before they become a cache key. Props arrive at hundreds of very slightly
	# different dimensions, and a distinct ArrayMesh per size defeats the batching a shared
	# primitive gets for free — measured, the unsnapped version cost 37% of the frame rate
	# (104 FPS -> 66) for a chamfer only a few pixels wide on screen.
	var snapped := Vector3(
		snappedf(size.x, MESH_SNAP), snappedf(size.y, MESH_SNAP), snappedf(size.z, MESH_SNAP)
	)
	var shortest: float = minf(snapped.x, minf(snapped.y, snapped.z))
	# Below this a prop is a handful of pixels and the chamfer is invisible, so it is not worth a
	# second mesh in the scene at all.
	if shortest < MIN_BEVEL_SIZE or bevel <= 0.001:
		var plain := BoxMesh.new()
		plain.size = size
		return plain
	# C-180: the doc comment says "cached by (size, bevel)" and `bevel` was absent from the key, so
	# two props of identical snapped size but different chamfer depth would silently share the
	# first-built mesh. Latent today — the sole caller derives the bevel purely from the size, so
	# equal sizes always meant equal bevels — and live the moment a second caller passes its own.
	# The bevel is snapped too, for the same batching reason the sizes are.
	var b: float = minf(bevel, shortest * 0.3)
	var snapped_bevel := snappedf(b, MESH_SNAP)
	var key := "%.2f_%.2f_%.2f_%.2f" % [snapped.x, snapped.y, snapped.z, snapped_bevel]
	if _bevel_mesh_cache.has(key):
		return _bevel_mesh_cache[key]
	var half := snapped * 0.5
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Vertical edges only: six faces plus four corner facets, twenty triangles against a box's
	# twelve. Cutting the horizontal edges as well needs another twenty-four and reads almost
	# identically from a camera that never looks straight down at a prop.
	var ix := half.x - b
	var iz := half.z - b
	var top := half.y
	var bot := -half.y
	var ring := [
		Vector2(ix, half.z), Vector2(-ix, half.z),
		Vector2(-half.x, iz), Vector2(-half.x, -iz),
		Vector2(-ix, -half.z), Vector2(ix, -half.z),
		Vector2(half.x, -iz), Vector2(half.x, iz),
	]
	for i in ring.size():
		var a: Vector2 = ring[i]
		var c: Vector2 = ring[(i + 1) % ring.size()]
		var outward := Vector3(a.x + c.x, 0.0, a.y + c.y).normalized()
		_emit_quad(
			st,
			[
				Vector3(a.x, bot, a.y), Vector3(c.x, bot, c.y),
				Vector3(c.x, top, c.y), Vector3(a.x, top, a.y),
			],
			outward
		)
	# Caps, as a fan around the ring.
	for i in range(1, ring.size() - 1):
		_emit_tri(
			st,
			[
				Vector3(ring[0].x, top, ring[0].y),
				Vector3(ring[i].x, top, ring[i].y),
				Vector3(ring[i + 1].x, top, ring[i + 1].y),
			],
			Vector3.UP
		)
		_emit_tri(
			st,
			[
				Vector3(ring[0].x, bot, ring[0].y),
				Vector3(ring[i].x, bot, ring[i].y),
				Vector3(ring[i + 1].x, bot, ring[i + 1].y),
			],
			Vector3.DOWN
		)
	st.index()
	var mesh := st.commit()
	_bevel_mesh_cache[key] = mesh
	return mesh


## Emits a polygon wound so its face normal points along `outward`, so callers never have to
## reason about winding for any of the twenty-six facets.
static func _emit_tri(st: SurfaceTool, pts: Array[Vector3], outward: Vector3) -> void:
	var ordered := pts.duplicate()
	var n: Vector3 = (ordered[1] as Vector3 - ordered[0]).cross(ordered[2] as Vector3 - ordered[0])
	if n.dot(outward) < 0.0:
		ordered.reverse()
	for pt in ordered:
		st.set_normal(outward)
		st.add_vertex(pt)


static func _emit_quad(st: SurfaceTool, pts: Array[Vector3], outward: Vector3) -> void:
	_emit_tri(st, [pts[0], pts[1], pts[2]], outward)
	_emit_tri(st, [pts[0], pts[2], pts[3]], outward)


static func add_box(
	parent: Node3D, size: Vector3, position: Vector3, material: Material, node_name: String = ""
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
	if PixelDioramaSettings._debug_flat_cached:
		var std := StandardMaterial3D.new()
		std.albedo_color = Color(0.62, 0.56, 0.5)
		mesh_inst.material_override = std
	parent.add_child(mesh_inst)
	return mesh_inst


static func make_portal_material(portal_id: String) -> ShaderMaterial:
	if _portal_material_cache.has(portal_id):
		return _portal_material_cache[portal_id] as ShaderMaterial

	var def := PortalCatalog.resolve(portal_id)
	var interior: Dictionary = def.get("interior", {})
	var mat := ShaderMaterial.new()
	mat.shader = load(PORTAL_SHADER_PATH) as Shader
	mat.set_shader_parameter(
		"color_inner", _color_from_hex(str(interior.get("color_inner", "#8cc7ff")))
	)
	mat.set_shader_parameter(
		"color_outer", _color_from_hex(str(interior.get("color_outer", "#29479e")))
	)
	mat.set_shader_parameter(
		"color_accent", _color_from_hex(str(interior.get("color_accent", "#e6f5ff")))
	)
	var ellipse: Array = interior.get("ellipse", [0.72, 1.0])
	mat.set_shader_parameter("ellipse_x", float(ellipse[0]))
	mat.set_shader_parameter("ellipse_y", float(ellipse[1]))
	mat.set_shader_parameter("spin_speed", float(interior.get("spin_speed", 2.2)))
	mat.set_shader_parameter("spiral_tightness", float(interior.get("spiral_tightness", 5.5)))
	PixelDioramaSettings.apply_to_shader_material(mat)
	_portal_material_cache[portal_id] = PixelDioramaSettings.track(mat)
	return _portal_material_cache[portal_id] as ShaderMaterial


static func make_portal_layer_material(
	portal_id: String, spin_scale: float, alpha: float
) -> ShaderMaterial:
	var mat := make_portal_material(portal_id).duplicate() as ShaderMaterial
	var base_spin := float(mat.get_shader_parameter("spin_speed"))
	mat.set_shader_parameter("spin_speed", base_spin * spin_scale)
	mat.set_shader_parameter("layer_alpha", alpha)
	return mat


static func add_portal_interior(
	parent: Node3D,
	size: Vector2,
	position: Vector3,
	portal_id: String,
	depth: float = 0.35,
	node_name: String = "PortalInterior"
) -> Node3D:
	var root := Node3D.new()
	root.name = node_name
	root.position = position
	parent.add_child(root)

	if depth <= 0.0:
		_add_portal_quad(root, size, Vector3.ZERO, portal_id, 1.0, 1.0)
		return root

	var layers := [
		{"z": 0.0, "scale": 1.0, "spin": 1.0, "alpha": 1.0},
		{"z": -depth * 0.5, "scale": 0.92, "spin": 0.72, "alpha": 0.7},
		{"z": -depth, "scale": 0.84, "spin": 0.5, "alpha": 0.45},
	]
	for i in layers.size():
		var layer: Dictionary = layers[i]
		var layer_size := size * float(layer["scale"])
		_add_portal_quad(
			root,
			layer_size,
			Vector3(0.0, 0.0, float(layer["z"])),
			portal_id,
			float(layer["spin"]),
			float(layer["alpha"]),
			"Layer%d" % i
		)
	return root


static func _add_portal_quad(
	parent: Node3D,
	size: Vector2,
	position: Vector3,
	portal_id: String,
	spin_scale: float,
	alpha: float,
	node_name: String = "Quad"
) -> MeshInstance3D:
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = node_name
	var quad := QuadMesh.new()
	quad.size = size
	mesh_inst.mesh = quad
	mesh_inst.position = position
	mesh_inst.material_override = make_portal_layer_material(portal_id, spin_scale, alpha)
	parent.add_child(mesh_inst)
	return mesh_inst


## Builds a complete portal: archway, layered interior, glow light, and accents.
## `def` is a portal definition from `PortalCatalog.resolve()`.
static func build_portal(
	parent: Node3D, def: Dictionary, scale: float = 1.0, hub_mats: Dictionary = {}
) -> Node3D:
	var existing := parent.get_node_or_null("DioramaVisuals")
	if existing:
		existing.queue_free()

	hide_legacy_meshes(parent)
	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	visuals.scale = Vector3(scale, scale, scale)
	parent.add_child(visuals)

	var portal_id := str(def.get("_id", PortalCatalog.FALLBACK_ID))
	var mats := _portal_hub_mats(def, hub_mats)
	var frame_mat: Material = _portal_frame_material(mats, def)
	var accent_mat: Material = mats.get("accent", frame_mat)
	var floor_mat: Material = mats.get("floor", accent_mat)
	var interior: Dictionary = def.get("interior", {})
	var depth := float(interior.get("depth", 0.35))
	var o := Vector3.ZERO

	add_box(visuals, Vector3(4.2, 0.22, 2.2), o + Vector3(0.0, 0.11, 0.0), frame_mat, "Base")
	add_box(visuals, Vector3(3.6, 0.16, 1.8), o + Vector3(0.0, 0.28, 0.0), accent_mat, "Step")
	add_box(visuals, Vector3(0.62, 3.6, 0.62), o + Vector3(-1.75, 1.8, 0.0), frame_mat, "PillarL")
	add_box(visuals, Vector3(0.62, 3.6, 0.62), o + Vector3(1.75, 1.8, 0.0), frame_mat, "PillarR")
	add_box(
		visuals, Vector3(0.92, 0.38, 0.92), o + Vector3(-1.75, 3.72, 0.0), accent_mat, "CapitalL"
	)
	add_box(
		visuals, Vector3(0.92, 0.38, 0.92), o + Vector3(1.75, 3.72, 0.0), accent_mat, "CapitalR"
	)
	add_box(visuals, Vector3(4.2, 0.55, 0.72), o + Vector3(0.0, 3.95, 0.0), frame_mat, "Lintel")
	add_box(
		visuals, Vector3(3.0, 0.22, 0.22), o + Vector3(0.0, 3.2, 0.0), accent_mat, "ArchKeystone"
	)
	add_box(visuals, Vector3(0.35, 2.8, 0.35), o + Vector3(-1.2, 1.6, 0.28), frame_mat, "ButtressL")
	add_box(visuals, Vector3(0.35, 2.8, 0.35), o + Vector3(1.2, 1.6, 0.28), frame_mat, "ButtressR")
	add_portal_interior(visuals, Vector2(2.6, 2.2), o + Vector3(0.0, 1.55, 0.04), portal_id, depth)
	add_box(visuals, Vector3(3.8, 0.16, 1.9), o + Vector3(0.0, 0.08, 0.0), floor_mat, "Pad")

	PixelDioramaPortalAccents.add_accents(visuals, mats, def)

	var glow: Dictionary = def.get("glow", {})
	var portal_light := OmniLight3D.new()
	portal_light.name = "PortalGlow"
	portal_light.light_color = _color_from_hex(str(glow.get("color", "#d9b873")))
	portal_light.light_energy = float(glow.get("energy", 1.0))
	portal_light.omni_range = float(glow.get("range", 4.0))
	portal_light.position = Vector3(0.0, 1.7, 0.75)
	visuals.add_child(portal_light)

	var sfx: Dictionary = def.get("sfx", {})
	var ambient_key := str(sfx.get("ambient", ""))
	if ambient_key != "":
		AudioDirector.attach_loop_emitter(visuals, ambient_key, 6.0)

	return visuals


static func build_merchant_stall(parent: Node3D, biome_id: String) -> Node3D:
	var existing := parent.get_node_or_null("DioramaVisuals")
	if existing:
		existing.queue_free()
	var legacy := parent.get_node_or_null("DioramaVisual")
	if legacy:
		legacy.queue_free()

	var theme := theme_from_biome(biome_id)
	var wall := make_wall_material(theme)
	var wood := make_prop_material(theme, false)
	var accent := make_accent_material(theme)
	var roof := make_prop_material(theme, true)

	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	parent.add_child(visuals)

	add_box(visuals, Vector3(2.8, 0.9, 1.2), Vector3(0.0, 0.45, 0.0), wall, "Counter")
	add_box(visuals, Vector3(3.2, 0.12, 1.6), Vector3(0.0, 0.06, 0.0), wood, "FloorPad")
	add_box(visuals, Vector3(3.4, 0.08, 0.35), Vector3(0.0, 1.15, -0.35), roof, "Awning")
	add_box(visuals, Vector3(0.45, 0.45, 0.45), Vector3(-0.95, 0.22, 0.55), wood, "CrateL")
	add_box(visuals, Vector3(0.45, 0.45, 0.45), Vector3(0.95, 0.22, 0.55), wood, "CrateR")
	add_box(visuals, Vector3(0.35, 0.55, 0.08), Vector3(0.0, 1.35, -0.35), accent, "AwningTrim")
	return visuals


static func _portal_hub_mats(def: Dictionary, hub_mats: Dictionary) -> Dictionary:
	if not hub_mats.is_empty():
		return hub_mats
	var theme := _palette_theme_from_string(str(def.get("palette_theme", "castle")))
	return {
		"wall": make_wall_material(theme),
		"accent": make_accent_material(theme),
		"floor": make_floor_material(theme),
	}


static func _portal_frame_material(mats: Dictionary, def: Dictionary) -> Material:
	var frame_key := str(def.get("frame_material", ""))
	if frame_key != "" and mats.has(frame_key):
		return mats[frame_key]
	if mats.has("wall"):
		return mats.wall
	return mats.get("accent", make_accent_material(PaletteTheme.CASTLE))


static func _palette_theme_from_string(name: String) -> PaletteTheme:
	match name:
		"crystal":
			return PaletteTheme.CRYSTAL
		"swamp":
			return PaletteTheme.SWAMP
		"frozen":
			return PaletteTheme.FROZEN
		"cathedral":
			return PaletteTheme.CATHEDRAL
		"vault":
			return PaletteTheme.VAULT
		"prism":
			return PaletteTheme.PRISM
		"mire":
			return PaletteTheme.MIRE
		"hollow":
			return PaletteTheme.HOLLOW
		"umbral":
			return PaletteTheme.UMBRAL
		"hub":
			return PaletteTheme.HUB
		_:
			return PaletteTheme.CASTLE


static func color_from_hex(hex: String) -> Color:
	var cleaned := hex.strip_edges()
	if cleaned.begins_with("#"):
		cleaned = cleaned.substr(1)
	if cleaned.length() != 6:
		return Color.WHITE
	return Color(
		cleaned.substr(0, 2).hex_to_int() / 255.0,
		cleaned.substr(2, 2).hex_to_int() / 255.0,
		cleaned.substr(4, 2).hex_to_int() / 255.0,
		1.0
	)


static func _color_from_hex(hex: String) -> Color:
	return color_from_hex(hex)


static func add_collision_box(
	parent: Node3D, size: Vector3, position: Vector3, node_name: String = "Collision"
) -> CollisionShape3D:
	var shape_node := CollisionShape3D.new()
	shape_node.name = node_name
	var box := BoxShape3D.new()
	box.size = size
	shape_node.shape = box
	shape_node.position = position
	parent.add_child(shape_node)
	return shape_node


static func add_portal_column(
	parent: Node3D,
	center: Vector3,
	frame_mat: Material,
	accent_mat: Material,
	height: float,
	column_w: float = 0.62,
	node_name: String = "Column"
) -> void:
	add_box(parent, Vector3(column_w, height, column_w), center, frame_mat, "%sPillar" % node_name)
	var cap_w := column_w * 1.48
	var cap_h := column_w * 0.62
	add_box(
		parent,
		Vector3(cap_w, cap_h, cap_w),
		center + Vector3(0.0, height * 0.5 + cap_h * 0.5, 0.0),
		accent_mat,
		"%sCapital" % node_name
	)


static func build_structure(
	parent: Node3D, def_name: String, mats: Dictionary, overrides: Dictionary = {}
) -> Node3D:
	var def := ContentLoader.load_json("%s/%s.json" % [STRUCTURE_DIR, def_name])
	var params: Dictionary = def.get("params", {}).duplicate()
	for key in overrides.keys():
		if key != "facing_yaw":
			params[key] = overrides[key]
	var facing_yaw := float(overrides.get("facing_yaw", 0.0))
	var generator := str(def.get("generator", ""))
	if generator == "hub_tent":
		return PixelDioramaHubStructures.build_tent(parent, mats, params, facing_yaw, def)
	return _build_structure_parts(parent, mats, def.get("parts", []), facing_yaw)


static func _build_structure_parts(
	parent: Node3D, mats: Dictionary, parts: Array, facing_yaw: float
) -> Node3D:
	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	parent.add_child(visuals)
	visuals.rotation.y = facing_yaw
	for raw in parts:
		if not raw is Dictionary:
			continue
		var part: Dictionary = raw
		var mat := _resolve_structure_material(mats, str(part.get("mat", "wall")))
		var size := _vec3_from_array(part.get("size"), Vector3.ONE)
		var pos := _vec3_from_array(part.get("pos"))
		var rot := _deg_to_rad_array(part.get("rot_deg", null))
		var node_name := str(part.get("name", ""))
		var kind := str(part.get("kind", "box"))
		if kind == "column":
			add_portal_column(visuals, pos, mat, mats.get("accent", mat), size.y, size.x, node_name)
		else:
			var mesh := add_box(visuals, size, pos, mat, node_name)
			mesh.rotation = rot
	return visuals


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
	return build_structure(
		landmark,
		"hub_tent",
		mats,
		{
			"width": width,
			"depth": depth,
			"wall_height": wall_height,
			"entrance_width": entrance_width,
			"roof_peak": roof_peak,
			"facing_yaw": facing_yaw,
		}
	)


static func add_hub_fountain(parent: Node3D, mats: Dictionary, position: Vector3) -> Node3D:
	return PixelDioramaHubStructures.build_fountain(parent, mats, position)


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
	# C-181: `add_box` honoured `debug_flat_materials` and this did not, so toggling the debug view
	# produced a half-flattened scene — boxes grey, cylinders still fully shaded. A debug view that
	# only partly applies is worse than none, because it invites the wrong conclusion about which
	# surface is misbehaving.
	if PixelDioramaSettings._debug_flat_cached:
		var std := StandardMaterial3D.new()
		std.albedo_color = Color(0.62, 0.56, 0.5)
		mesh_inst.material_override = std
	parent.add_child(mesh_inst)
	return mesh_inst


static func hide_legacy_meshes(root: Node) -> void:
	## Hide only meshes explicitly marked as legacy blockout in the scene file.
	const SKIP_SUBTREES := ["DioramaVisual", "DioramaVisuals", "Viewmodel"]
	const LEGACY_NAMES := [
		"Floor",
		"NorthWall",
		"EastWall",
		"WestWall",
		"SouthWall",
		"Body",
	]
	for child in root.get_children():
		if child.name in SKIP_SUBTREES:
			continue
		if child is MeshInstance3D:
			if child.has_meta(&"legacy_blockout") or child.name in LEGACY_NAMES:
				child.visible = false
		elif (
			child.name != "InteractArea"
			and child.name != "PortalLabel"
			and child.name != "Label"
			and child.name != "DoorLabel"
			and child.name != "NameLabel"
		):
			hide_legacy_meshes(child)
