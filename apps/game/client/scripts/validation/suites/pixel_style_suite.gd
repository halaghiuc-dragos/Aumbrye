extends "res://scripts/validation/validation_suite.gd"

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const PixelDioramaSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")

const PALETTE_SLOTS: PackedStringArray = [
	"floor_base",
	"floor_shadow",
	"wall_base",
	"wall_shadow",
	"accent",
	"prop_wood",
	"prop_metal",
	"emissive",
]

const HUB_TENT_CHILD_NAMES: PackedStringArray = [
	"Plinth",
	"PlinthStep",
	"Corner0Pillar",
	"Corner0Capital",
	"Corner1Pillar",
	"Corner1Capital",
	"Corner2Pillar",
	"Corner2Capital",
	"Corner3Pillar",
	"Corner3Capital",
	"EntryLPillar",
	"EntryLCapital",
	"EntryRPillar",
	"EntryRCapital",
	"EntryLintel",
	"EntryKeystone",
	"EntryButtressL",
	"EntryButtressR",
	"Ridge",
	"RidgeCap",
	"RoofPanelFront",
	"RoofPanelBack",
	"RoofPanelLeft",
	"RoofPanelRight",
	"AwningTrim",
	"WallBack",
	"WallLeft",
	"WallRight",
	"WallFrontLipL",
	"WallFrontLipR",
	"FlapL",
	"FlapR",
	"TentPad",
	"TentPadTrim",
]


func get_category() -> String:
	return "graphics"


func run() -> void:
	BiomeRegistry.warm_index()
	_test_palette_json_loads()
	_test_palette_slots_complete()
	_test_biome_map_total()
	_test_no_tres_materials()
	_test_authored_param_survives()
	_test_atlas_probe_missing_ok()
	_test_atlas_dimensions()
	_test_structure_json_loads()
	_test_structure_child_names()
	_test_material_cache_keys()
	_test_cache_cleared_on_apply()
	_test_no_standard_material()
	_test_prop_material_no_alias()
	_test_surface_color_levels()
	_test_surface_uniform_coverage()


func _test_prop_material_no_alias() -> void:
	var start := Time.get_ticks_msec()
	PixelStyle.clear_material_caches()
	var wood := PixelStyle.make_prop_material(PixelStyle.PaletteTheme.CASTLE, false)
	var metal := PixelStyle.make_prop_material(PixelStyle.PaletteTheme.CRYSTAL, true)
	var ok := wood != metal and wood == PixelStyle.make_prop_material(PixelStyle.PaletteTheme.CASTLE, false)
	ctx.timed_record(
		"style.prop_material_no_alias",
		get_category(),
		ok,
		"prop materials are distinct instances per theme and branch",
		start,
		"PXS-10"
	)


func _palette_data() -> Dictionary:
	return ContentLoader.load_json("content/art/palettes.json")


func _test_palette_json_loads() -> void:
	var start := Time.get_ticks_msec()
	var data := _palette_data()
	var palettes: Dictionary = data.get("palettes", {})
	var ok := (
		int(data.get("version", 0)) == 1
		and FileAccess.file_exists(ContentLoader.content_path("content/schemas/palette.v1.json"))
		and palettes.size() == PixelStyle.THEME_IDS.size()
	)
	if ok:
		for theme_id in PixelStyle.THEME_IDS:
			if not palettes.has(theme_id):
				ok = false
				break
	ctx.timed_record(
		"style.palette_json_loads",
		get_category(),
		ok,
		"palettes.json declares all PaletteTheme ids",
		start,
		"PXS-03"
	)


func _test_palette_slots_complete() -> void:
	var start := Time.get_ticks_msec()
	var palettes: Dictionary = _palette_data().get("palettes", {})
	var ok := true
	var hex_re := RegEx.new()
	hex_re.compile("^#[0-9a-fA-F]{6}$")
	for theme_id in palettes.keys():
		var entry: Dictionary = palettes[theme_id]
		for slot in PALETTE_SLOTS:
			var value := str(entry.get(slot, ""))
			if not hex_re.search(value):
				ok = false
				break
	ctx.timed_record(
		"style.palette_slots_complete",
		get_category(),
		ok,
		"every palette slot is a six-digit hex colour",
		start,
		"PXS-03"
	)


func _test_biome_map_total() -> void:
	var start := Time.get_ticks_msec()
	var map: Dictionary = _palette_data().get("biome_theme_map", {})
	var ok := true
	for biome_id in BiomeRegistry.ALL_BIOMES:
		if not map.has(biome_id):
			ok = false
			break
		var theme_name := str(map[biome_id])
		if theme_name not in PixelStyle.THEME_IDS:
			ok = false
			break
	ctx.timed_record(
		"style.biome_map_total",
		get_category(),
		ok,
		"every BiomeRegistry id maps to a declared palette theme",
		start,
		"PXS-03"
	)


func _test_no_tres_materials() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	var dir := DirAccess.open("res://assets")
	if dir:
		ok = _dir_has_no_mat_tres(dir, "res://assets")
	ctx.timed_record(
		"style.no_tres_materials",
		get_category(),
		ok,
		"no mat_*.tres files remain under assets/",
		start,
		"PXS-03"
	)


func _dir_has_no_mat_tres(dir: DirAccess, prefix: String) -> bool:
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if entry == "." or entry == "..":
			entry = dir.get_next()
			continue
		var path := "%s/%s" % [prefix, entry]
		if dir.current_is_dir():
			var child := DirAccess.open(path)
			if child and not _dir_has_no_mat_tres(child, path):
				dir.list_dir_end()
				return false
		elif entry.begins_with("mat_") and entry.ends_with(".tres"):
			dir.list_dir_end()
			return false
		entry = dir.get_next()
	dir.list_dir_end()
	return true


func _test_authored_param_survives() -> void:
	var start := Time.get_ticks_msec()
	var prior_pattern := PixelDioramaSettings.pattern_strength
	PixelDioramaSettings.pattern_strength = 0.66
	var authored := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.PROP, PixelStyle.PaletteTheme.HUB, 0.28)
	PixelStyle.set_authored_param(authored as ShaderMaterial, "pattern_strength", 0.28)
	var plain := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.FLOOR, PixelStyle.PaletteTheme.CASTLE)
	PixelDioramaSettings.apply_all()
	var authored_val := float((authored as ShaderMaterial).get_shader_parameter("pattern_strength"))
	var plain_val := float((plain as ShaderMaterial).get_shader_parameter("pattern_strength"))
	var ok := is_equal_approx(authored_val, 0.28) and is_equal_approx(plain_val, 0.66)
	PixelDioramaSettings.pattern_strength = prior_pattern
	ctx.timed_record(
		"style.authored_param_survives",
		get_category(),
		ok,
		"authored pattern_strength survives apply_all",
		start,
		"PXS-02"
	)


func _test_atlas_probe_missing_ok() -> void:
	var start := Time.get_ticks_msec()
	PixelStyle.clear_material_caches()
	var theme_id := PixelStyle._theme_id(PixelStyle.PaletteTheme.PRISM)
	PixelStyle._atlas_exists_cache[theme_id] = false
	var mat := PixelStyle.make_surface_material(
		PixelStyle.SurfaceKind.WALL, PixelStyle.PaletteTheme.PRISM
	) as ShaderMaterial
	var ok := mat != null and not bool(mat.get_shader_parameter("use_tile_atlas"))
	ctx.timed_record(
		"style.atlas_probe_missing_ok",
		get_category(),
		ok,
		"missing tiles.png leaves use_tile_atlas false",
		start,
		"PXS-04"
	)


func _test_atlas_dimensions() -> void:
	var start := Time.get_ticks_msec()
	var ok := true
	for theme_id in PixelStyle.THEME_IDS:
		var path := "res://assets/textures/%s/tiles.png" % theme_id
		var fs_path := ProjectSettings.globalize_path(path)
		if not FileAccess.file_exists(fs_path):
			continue
		var image := Image.load_from_file(fs_path)
		if image == null or image.get_width() != 256 or image.get_height() != 256:
			ok = false
			break
	ctx.timed_record(
		"style.atlas_dimensions",
		get_category(),
		ok,
		"every tiles.png atlas is 256x256",
		start,
		"PXS-04"
	)


func _test_structure_json_loads() -> void:
	var start := Time.get_ticks_msec()
	var def := ContentLoader.load_json("content/art/structures/hub_tent.json")
	var mats := PixelStyle.make_hub_materials()
	var ok := (
		int(def.get("version", 0)) == 1
		and str(def.get("name", "")) == "hub_tent"
		and FileAccess.file_exists(ContentLoader.content_path("content/schemas/structure.v1.json"))
	)
	for raw in def.get("parts", []):
		if not raw is Dictionary:
			continue
		var mat_key := str((raw as Dictionary).get("mat", ""))
		if not mats.has(mat_key):
			ok = false
	ctx.timed_record(
		"style.structure_json_loads",
		get_category(),
		ok,
		"hub_tent.json loads and mat keys resolve in make_hub_materials",
		start,
		"PXS-05"
	)


func _test_structure_child_names() -> void:
	var start := Time.get_ticks_msec()
	var fixture := Node3D.new()
	fixture.name = "HubTentFixture"
	ctx.owner.add_child(fixture)
	var mats := PixelStyle.make_hub_materials()
	var visuals := PixelStyle.build_structure(fixture, "hub_tent", mats)
	var names: Dictionary = {}
	var ok := visuals != null
	for child in visuals.get_children():
		if names.has(child.name):
			ok = false
			break
		names[child.name] = true
	if ok:
		for expected in HUB_TENT_CHILD_NAMES:
			if not names.has(expected):
				ok = false
				break
	fixture.queue_free()
	ctx.timed_record(
		"style.structure_child_names",
		get_category(),
		ok,
		"build_structure hub_tent emits the documented child names",
		start,
		"PXS-05"
	)


func _test_material_cache_keys() -> void:
	var start := Time.get_ticks_msec()
	PixelStyle.clear_material_caches()
	var a := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.FLOOR, PixelStyle.PaletteTheme.CASTLE, 0.2)
	var b := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.WALL, PixelStyle.PaletteTheme.CASTLE, 0.2)
	var c := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.FLOOR, PixelStyle.PaletteTheme.CRYSTAL, 0.2)
	var d := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.FLOOR, PixelStyle.PaletteTheme.CASTLE, 0.4)
	var repeat := PixelStyle.make_surface_material(PixelStyle.SurfaceKind.FLOOR, PixelStyle.PaletteTheme.CASTLE, 0.2)
	var ok := a != b and b != c and c != d and a != d and repeat == a
	ctx.timed_record(
		"style.material_cache_keys",
		get_category(),
		ok,
		"distinct surface requests cache separately and repeats alias",
		start,
		"PXS-10"
	)


func _test_cache_cleared_on_apply() -> void:
	var start := Time.get_ticks_msec()
	PixelStyle.make_surface_material(PixelStyle.SurfaceKind.FLOOR, PixelStyle.PaletteTheme.HUB)
	PixelStyle.make_prop_material(PixelStyle.PaletteTheme.HUB, false)
	PixelStyle.make_accent_material(PixelStyle.PaletteTheme.HUB)
	PixelStyle.make_emissive_material(PixelStyle.PaletteTheme.HUB, 1.0)
	PixelStyle.clear_material_caches()
	var ok := (
		PixelStyle._surface_material_cache.is_empty()
		and PixelStyle._prop_material_cache.is_empty()
		and PixelStyle._accent_material_cache.is_empty()
		and PixelStyle._emissive_material_cache.is_empty()
	)
	ctx.timed_record(
		"style.cache_cleared_on_apply",
		get_category(),
		ok,
		"clear_material_caches empties all four dictionaries",
		start,
		"PXS-09"
	)


func _test_no_standard_material() -> void:
	var start := Time.get_ticks_msec()
	var prior := PixelDioramaSettings.debug_flat_materials
	PixelDioramaSettings.debug_flat_materials = false
	PixelDioramaSettings._debug_flat_cached = false
	var fixture := Node3D.new()
	ctx.owner.add_child(fixture)
	var wall := PixelStyle.make_wall_material(PixelStyle.PaletteTheme.HUB)
	var mesh := PixelStyle.add_box(fixture, Vector3.ONE, Vector3.ZERO, wall, "Probe")
	var ok := not (mesh.material_override is StandardMaterial3D)
	fixture.queue_free()
	PixelDioramaSettings.debug_flat_materials = prior
	ctx.timed_record(
		"style.no_standard_material",
		get_category(),
		ok,
		"add_box keeps ShaderMaterial when debug_flat_materials is false",
		start,
		"PXS-13"
	)


func _test_surface_color_levels() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string("res://assets/shared/pixel_diorama_surface.gdshader")
	var fragment_idx := text.find("void fragment()")
	var fragment_body := text.substr(fragment_idx) if fragment_idx >= 0 else ""
	var ok := fragment_idx >= 0 and "quantize_color" in fragment_body and "color_levels" in fragment_body
	ctx.timed_record(
		"style.color_levels_used",
		get_category(),
		ok,
		"surface shader quantizes albedo with color_levels in fragment()",
		start,
		"PXS-01"
	)


func _test_surface_uniform_coverage() -> void:
	var start := Time.get_ticks_msec()
	var text := FileAccess.get_file_as_string("res://assets/shared/pixel_diorama_surface.gdshader")
	var body_start := text.find("void vertex()")
	var body := text.substr(body_start) if body_start >= 0 else text
	var ok := true
	for line in text.split("\n"):
		var name := _surface_uniform_name(line)
		if name.is_empty():
			continue
		if name not in body:
			ok = false
			break
	ctx.timed_record(
		"style.surface_uniform_coverage",
		get_category(),
		ok,
		"every surface shader uniform appears in the shader body",
		start,
		"PXS-14"
	)


func _surface_uniform_name(line: String) -> String:
	var trimmed := line.strip_edges()
	if not trimmed.begins_with("uniform "):
		return ""
	var tokens: PackedStringArray = trimmed.trim_prefix("uniform ").split(" ")
	if tokens.is_empty():
		return ""
	var idx := 0
	if tokens[0] in ["sampler2D", "samplerCube", "bool", "int", "float", "vec2", "vec3", "vec4"]:
		idx = 1
	if idx >= tokens.size():
		return ""
	return tokens[idx].split(":")[0].split("=")[0].trim_suffix(";")
