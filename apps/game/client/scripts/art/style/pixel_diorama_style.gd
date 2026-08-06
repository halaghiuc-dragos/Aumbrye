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
	_portal_material_cache.clear()


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


static func make_character_material(theme: PaletteTheme) -> Material:
	var mat := make_surface_material(SurfaceKind.WALL, theme, 0.0).duplicate() as ShaderMaterial
	set_authored_param(mat, "pattern_strength", 0.0)
	set_authored_param(mat, "use_vertex_color", true)
	return mat


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

	_add_portal_accents(visuals, mats, def)

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


static func _add_portal_accents(visuals: Node3D, mats: Dictionary, def: Dictionary) -> void:
	var accents: Array = def.get("accents", [])
	for accent_id in accents:
		match str(accent_id):
			"torch_pair":
				add_box(
					visuals,
					Vector3(0.2, 3.0, 0.2),
					Vector3(-1.55, 1.6, 0.15),
					mats.accent,
					"TorchL"
				)
				add_box(
					visuals, Vector3(0.2, 3.0, 0.2), Vector3(1.55, 1.6, 0.15), mats.accent, "TorchR"
				)
			"rune_ring":
				var umbral_mat: Material = mats.get("umbral", mats.accent)
				add_box(
					visuals,
					Vector3(3.2, 0.18, 0.18),
					Vector3(0.0, 0.2, 0.85),
					umbral_mat,
					"RuneRing"
				)
			"training_torches":
				var training_mat: Material = mats.get("training", mats.accent)
				add_box(
					visuals,
					Vector3(0.22, 0.22, 0.22),
					Vector3(-1.0, 0.22, 0.75),
					training_mat,
					"EmberL"
				)
				add_box(
					visuals,
					Vector3(0.22, 0.22, 0.22),
					Vector3(1.0, 0.22, 0.75),
					training_mat,
					"EmberR"
				)
				add_box(
					visuals,
					Vector3(0.18, 2.8, 0.18),
					Vector3(-1.55, 1.6, 0.12),
					training_mat,
					"TorchL"
				)
				add_box(
					visuals,
					Vector3(0.18, 2.8, 0.18),
					Vector3(1.55, 1.6, 0.12),
					training_mat,
					"TorchR"
				)
			"dragon_horns":
				var dragon_mat: Material = mats.get("dragon", mats.accent)
				add_box(
					visuals,
					Vector3(0.28, 0.55, 0.28),
					Vector3(-0.55, 3.72, 0.0),
					dragon_mat,
					"HornL"
				)
				add_box(
					visuals,
					Vector3(0.28, 0.55, 0.28),
					Vector3(0.55, 3.72, 0.0),
					dragon_mat,
					"HornR"
				)
				add_box(
					visuals,
					Vector3(0.85, 0.12, 0.55),
					Vector3(-1.55, 1.9, 0.18),
					dragon_mat,
					"WingL"
				)
				add_box(
					visuals,
					Vector3(0.85, 0.12, 0.55),
					Vector3(1.55, 1.9, 0.18),
					dragon_mat,
					"WingR"
				)
				var forge_mat: Material = mats.get("forge", dragon_mat)
				add_box(
					visuals,
					Vector3(0.35, 0.35, 0.35),
					Vector3(0.0, 0.28, 0.82),
					forge_mat,
					"DragonEye"
				)
			"cathedral_trim":
				var cathedral_mat: Material = mats.get("cathedral", mats.accent)
				add_box(
					visuals,
					Vector3(0.22, 0.75, 0.18),
					Vector3(0.0, 3.55, 0.12),
					cathedral_mat,
					"CrossV"
				)
				add_box(
					visuals,
					Vector3(0.65, 0.18, 0.18),
					Vector3(0.0, 3.82, 0.12),
					cathedral_mat,
					"CrossH"
				)
				add_box(
					visuals,
					Vector3(0.2, 2.9, 0.2),
					Vector3(-1.55, 1.6, 0.12),
					cathedral_mat,
					"PillarTrimL"
				)
				add_box(
					visuals,
					Vector3(0.2, 2.9, 0.2),
					Vector3(1.55, 1.6, 0.12),
					cathedral_mat,
					"PillarTrimR"
				)


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
		return _build_hub_tent(parent, mats, params, facing_yaw, def)
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


static func _build_hub_tent(
	parent: Node3D, mats: Dictionary, params: Dictionary, facing_yaw: float, def: Dictionary
) -> Node3D:
	var width := float(params.get("width", 5.0))
	var depth := float(params.get("depth", 4.2))
	var wall_height := float(params.get("wall_height", 2.2))
	var entrance_width := float(params.get("entrance_width", 1.8))
	var roof_peak := float(params.get("roof_peak", 1.2))

	var visuals := Node3D.new()
	visuals.name = "DioramaVisuals"
	parent.add_child(visuals)
	visuals.rotation.y = facing_yaw

	var fabric_mat: Material = mats.wall
	var pole_mat: Material = mats.wood
	var roof_mat: Material = mats.accent
	var half_w := width * 0.5
	var half_d := depth * 0.5
	var wall_thickness := 0.22
	var lip_width := (width - entrance_width) * 0.5
	var lip_z := half_d - wall_thickness * 0.5
	var floor_alt: Material = mats.get("floor_alt", mats.get("floor", pole_mat))

	for raw in def.get("parts", []):
		if not raw is Dictionary:
			continue
		var part: Dictionary = raw
		var mat := _resolve_structure_material(mats, str(part.get("mat", "wall")))
		add_box(
			visuals,
			_vec3_from_array(part.get("size"), Vector3.ONE),
			_vec3_from_array(part.get("pos")),
			mat,
			str(part.get("name", ""))
		)

	var column_h := wall_height
	var corner_positions := [
		Vector3(-half_w + 0.22, column_h * 0.5, -half_d + 0.22),
		Vector3(half_w - 0.22, column_h * 0.5, -half_d + 0.22),
		Vector3(-half_w + 0.22, column_h * 0.5, half_d - 0.22),
		Vector3(half_w - 0.22, column_h * 0.5, half_d - 0.22),
	]
	for i in corner_positions.size():
		add_portal_column(
			visuals, corner_positions[i], pole_mat, roof_mat, column_h, 0.48, "Corner%d" % i
		)

	var entrance_z := lip_z - 0.08
	var col_x := entrance_width * 0.5 + 0.22
	add_portal_column(
		visuals,
		Vector3(-col_x, wall_height * 0.5, entrance_z),
		pole_mat,
		roof_mat,
		wall_height,
		0.42,
		"EntryL"
	)
	add_portal_column(
		visuals,
		Vector3(col_x, wall_height * 0.5, entrance_z),
		pole_mat,
		roof_mat,
		wall_height,
		0.42,
		"EntryR"
	)
	add_box(
		visuals,
		Vector3(entrance_width + 1.1, 0.42, 0.55),
		Vector3(0.0, wall_height + 0.21, entrance_z - 0.12),
		pole_mat,
		"EntryLintel"
	)
	add_box(
		visuals,
		Vector3(0.28, 0.28, 0.28),
		Vector3(0.0, wall_height + 0.52, entrance_z - 0.1),
		roof_mat,
		"EntryKeystone"
	)
	add_box(
		visuals,
		Vector3(0.3, wall_height * 0.85, 0.28),
		Vector3(-col_x + 0.35, wall_height * 0.42, entrance_z + 0.12),
		pole_mat,
		"EntryButtressL"
	)
	add_box(
		visuals,
		Vector3(0.3, wall_height * 0.85, 0.28),
		Vector3(col_x - 0.35, wall_height * 0.42, entrance_z + 0.12),
		pole_mat,
		"EntryButtressR"
	)

	var ridge_y := wall_height + roof_peak
	add_box(
		visuals, Vector3(width + 0.42, 0.18, 0.18), Vector3(0.0, ridge_y, 0.0), roof_mat, "Ridge"
	)
	add_box(
		visuals,
		Vector3(width + 0.22, 0.08, 0.08),
		Vector3(0.0, ridge_y + 0.1, 0.0),
		pole_mat,
		"RidgeCap"
	)

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

	add_box(
		visuals,
		Vector3(width + 0.5, 0.14, 0.5),
		Vector3(0.0, 0.38, half_d + 0.18),
		roof_mat,
		"AwningTrim"
	)

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

	add_box(
		visuals,
		Vector3(width + 0.55, 0.12, depth + 0.55),
		Vector3(0.0, 0.06, 0.0),
		floor_alt,
		"TentPad"
	)
	add_box(
		visuals,
		Vector3(width + 0.35, 0.08, depth + 0.35),
		Vector3(0.0, 0.14, 0.0),
		roof_mat,
		"TentPadTrim"
	)

	var collision_root := parent.get_node_or_null("TentCollision") as StaticBody3D
	if collision_root == null:
		collision_root = StaticBody3D.new()
		collision_root.name = "TentCollision"
		parent.add_child(collision_root)
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
	AudioDirector.attach_loop_emitter(fountain, "fountain", 8.0)

	return fountain


static func _make_fountain_particle_mesh(radius: float) -> SphereMesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2.0
	mesh.radial_segments = 6
	mesh.rings = 4
	return mesh


static func _make_fountain_particle_material(
	color: Color, emission_energy: float
) -> ShaderMaterial:
	var mat := make_glow_material(color, color.darkened(0.18), emission_energy)
	set_authored_param(mat, "color_core", color)
	set_authored_param(mat, "color_edge", color.darkened(0.18))
	return PixelDioramaSettings.track(mat)


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
