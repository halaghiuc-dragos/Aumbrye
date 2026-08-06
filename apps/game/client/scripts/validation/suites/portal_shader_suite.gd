extends "res://scripts/validation/validation_suite.gd"

const PixelStyle := preload("res://scripts/art/style/pixel_diorama_style.gd")
const PixelDioramaSettings := preload("res://scripts/art/pipeline/pixel_diorama_settings.gd")
const DioramaSkin := preload("res://scripts/art/props/diorama_interactable_skin.gd")
const ExitPortalScene := preload("res://scenes/dungeon/exit_portal.tscn")


func _init(context) -> void:
	super._init(context)
	manage_save_file = false


func get_category() -> String:
	return "graphics"


func run() -> void:
	_test_json_loads()
	_test_biome_coverage()
	_test_aliases_resolve()
	_test_unknown_id_safe()
	_test_colors_well_formed()
	_test_material_uniform_coverage()
	_test_settings_reach_shader()
	_test_material_cached()
	_test_builder_single_source()
	_test_build_child_names()
	_test_interior_layers()
	_test_interior_flat_when_zero()
	_test_no_emission_property_access()
	await _test_exit_portal_uses_shader()
	_test_merchant_not_portal()
	_test_sfx_keys_exist()


func _content_root() -> String:
	return ContentLoader.content_root()


func _shader_text() -> String:
	var path := "res://assets/shared/portal_ellipse.gdshader"
	if not FileAccess.file_exists(path):
		return ""
	return FileAccess.get_file_as_string(path)


func _test_json_loads() -> void:
	var start := Time.get_ticks_msec()
	var data_path := _content_root().path_join("content/art/portals.json")
	var schema_path := _content_root().path_join("content/schemas/portal.v1.json")
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(data_path))
	var ok: bool = (
		parsed is Dictionary
		and int((parsed as Dictionary).get("version", 0)) == 1
		and (parsed as Dictionary).has("portals")
		and FileAccess.file_exists(schema_path)
	)
	ctx.timed_record(
		"portal.json_loads",
		get_category(),
		ok,
		"portals.json parses with version 1 and schema file exists",
		start,
		"POR-04"
	)


func _test_biome_coverage() -> void:
	var start := Time.get_ticks_msec()
	BiomeRegistry.warm_index()
	var missing: Array[String] = []
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var def := PortalCatalog.resolve(biome_id)
		if def.is_empty():
			missing.append(biome_id)
	ctx.timed_record(
		"portal.biome_coverage",
		get_category(),
		missing.is_empty(),
		"all biomes resolve: %s" % ", ".join(missing),
		start,
		"POR-05"
	)


func _test_aliases_resolve() -> void:
	var start := Time.get_ticks_msec()
	var aliases := ["castle", "training", "skies", "cathedral", "umbral"]
	var ok := true
	for alias in aliases:
		var def := PortalCatalog.resolve(alias)
		if def.is_empty() or not def.has("interior"):
			ok = false
	ctx.timed_record(
		"portal.aliases_resolve",
		get_category(),
		ok,
		"legacy hub aliases resolve to portal definitions",
		start,
		"POR-05"
	)


func _test_unknown_id_safe() -> void:
	var start := Time.get_ticks_msec()
	PortalCatalog.clear_cache()
	var def := PortalCatalog.resolve("nope")
	var again := PortalCatalog.resolve("nope")
	var ok: bool = (
		not def.is_empty()
		and str(def.get("_id", "")) == PortalCatalog.FALLBACK_ID
		and str(again.get("display_name", "")) == str(def.get("display_name", ""))
	)
	ctx.timed_record(
		"portal.unknown_id_safe",
		get_category(),
		ok,
		"unknown portal id falls back to hub_return",
		start,
		"POR-05"
	)


func _test_colors_well_formed() -> void:
	var start := Time.get_ticks_msec()
	var data := ContentLoader.load_json("content/art/portals.json")
	var portals: Dictionary = data.get("portals", {})
	var color_re := RegEx.new()
	color_re.compile("^#[0-9a-fA-F]{6}$")
	var ok := true
	for portal_id in portals:
		var entry: Dictionary = portals[portal_id]
		var interior: Dictionary = entry.get("interior", {})
		for key in ["color_inner", "color_outer", "color_accent"]:
			var hex := str(interior.get(key, ""))
			if color_re.search(hex) == null:
				ok = false
		var ellipse: Array = interior.get("ellipse", [])
		if ellipse.size() != 2:
			ok = false
		else:
			ok = ok and float(ellipse[0]) >= 0.5 and float(ellipse[0]) <= 2.0
			ok = ok and float(ellipse[1]) >= 0.5 and float(ellipse[1]) <= 2.0
		var spin := float(interior.get("spin_speed", -1))
		var tight := float(interior.get("spiral_tightness", -1))
		ok = ok and spin >= 0.0 and spin <= 6.0 and tight >= 1.0 and tight <= 12.0
	ctx.timed_record(
		"portal.colors_well_formed",
		get_category(),
		ok,
		"portal color and tuning fields are within schema bounds",
		start,
		"POR-04"
	)


func _test_material_uniform_coverage() -> void:
	var start := Time.get_ticks_msec()
	var shader := _shader_text()
	var mat := PixelStyle.make_portal_material("forgotten_castle")
	PixelDioramaSettings.apply_to_shader_material(mat)
	var uniforms := ["color_inner", "color_outer", "color_accent", "pixel_scale", "spin_speed"]
	var ok := shader.contains("uniform float color_levels") and shader.contains("uniform float layer_alpha")
	for uniform_name in uniforms:
		ok = ok and mat.get_shader_parameter(uniform_name) != null
	ok = ok and mat.get_shader_parameter("color_levels") != null
	ctx.timed_record(
		"portal.material_uniform_coverage",
		get_category(),
		ok,
		"portal shader uniforms are written by make_portal_material and settings",
		start,
		"POR-03"
	)


func _test_settings_reach_shader() -> void:
	var start := Time.get_ticks_msec()
	PixelStyle.clear_material_caches()
	PixelDioramaSettings.color_levels = 4.0
	PixelDioramaSettings.pixel_scale = 10.0
	PixelDioramaSettings.apply_all()
	var mat := PixelStyle.make_portal_material("forgotten_castle")
	var levels := float(mat.get_shader_parameter("color_levels"))
	var px := float(mat.get_shader_parameter("pixel_scale"))
	var expected_px := 10.0 * (14.0 / PixelDioramaSettings.DEFAULT_PIXEL_SCALE)
	var ok := levels == 4.0 and absf(px - expected_px) < 0.01
	ctx.timed_record(
		"portal.settings_reach_shader",
		get_category(),
		ok,
		"color_levels=4 and scaled pixel_scale reach portal material",
		start,
		"POR-03"
	)


func _test_material_cached() -> void:
	var start := Time.get_ticks_msec()
	PixelStyle.clear_material_caches()
	var a := PixelStyle.make_portal_material("forgotten_castle")
	var b := PixelStyle.make_portal_material("forgotten_castle")
	ctx.timed_record(
		"portal.material_cached",
		get_category(),
		a == b,
		"duplicate make_portal_material calls share one cached object",
		start,
		"POR-08"
	)


func _test_builder_single_source() -> void:
	var start := Time.get_ticks_msec()
	var hub_src := FileAccess.get_file_as_string("res://scripts/hub/hub_diorama.gd")
	var arena_src := FileAccess.get_file_as_string("res://scripts/debug/arena_diorama.gd")
	var literal := "add_box(visuals, Vector3(4.2, 0.22, 2.2)"
	var ok := not literal in hub_src and not literal in arena_src
	ctx.timed_record(
		"portal.builder_single_source",
		get_category(),
		ok,
		"hub and arena no longer duplicate archway box literals",
		start,
		"POR-06"
	)


func _test_build_child_names() -> void:
	var start := Time.get_ticks_msec()
	var parent := Node3D.new()
	ctx.owner.add_child(parent)
	var def := PortalCatalog.resolve("forgotten_castle")
	var visuals := PixelStyle.build_portal(parent, def, 1.0)
	var expected := [
		"Base",
		"Step",
		"PillarL",
		"PillarR",
		"CapitalL",
		"CapitalR",
		"Lintel",
		"ArchKeystone",
		"ButtressL",
		"ButtressR",
		"Pad",
		"PortalInterior",
		"PortalGlow",
		"TorchL",
		"TorchR",
	]
	var names: Array[String] = []
	for child in visuals.get_children():
		names.append(child.name)
	var ok := true
	for name in expected:
		ok = ok and name in names
	ok = ok and "PortalInterior" in names
	parent.queue_free()
	ctx.timed_record(
		"portal.build_child_names",
		get_category(),
		ok,
		"build_portal yields documented child node names",
		start,
		"POR-06"
	)


func _test_interior_layers() -> void:
	var start := Time.get_ticks_msec()
	var parent := Node3D.new()
	ctx.owner.add_child(parent)
	var interior_root := PixelStyle.add_portal_interior(
		parent, Vector2(2.6, 2.2), Vector3.ZERO, "forgotten_castle", 0.35
	)
	var meshes: Array[MeshInstance3D] = []
	for child in interior_root.get_children():
		if child is MeshInstance3D:
			meshes.append(child)
	var alphas: Array[float] = []
	var zs: Array[float] = []
	for mesh in meshes:
		var mat := mesh.material_override as ShaderMaterial
		alphas.append(float(mat.get_shader_parameter("layer_alpha")))
		zs.append(mesh.position.z)
	var ok := meshes.size() == 3 and alphas[0] > alphas[1] and alphas[1] > alphas[2]
	ok = ok and zs[0] > zs[1] and zs[1] > zs[2]
	parent.queue_free()
	ctx.timed_record(
		"portal.interior_layers",
		get_category(),
		ok,
		"depth=0.35 yields three layers with decreasing alpha and z",
		start,
		"POR-07"
	)


func _test_interior_flat_when_zero() -> void:
	var start := Time.get_ticks_msec()
	var parent := Node3D.new()
	ctx.owner.add_child(parent)
	var interior_root := PixelStyle.add_portal_interior(
		parent, Vector2(2.6, 2.2), Vector3.ZERO, "forgotten_castle", 0.0
	)
	var mesh_count := 0
	for child in interior_root.get_children():
		if child is MeshInstance3D:
			mesh_count += 1
	parent.queue_free()
	ctx.timed_record(
		"portal.interior_flat_when_zero",
		get_category(),
		mesh_count == 1,
		"depth=0.0 yields exactly one interior quad",
		start,
		"POR-07"
	)


func _test_no_emission_property_access() -> void:
	var start := Time.get_ticks_msec()
	var src := FileAccess.get_file_as_string("res://scripts/art/props/diorama_interactable_skin.gd")
	var ok := ".emission" not in src
	ctx.timed_record(
		"portal.no_emission_property_access",
		get_category(),
		ok,
		"diorama_interactable_skin has no ShaderMaterial.emission access",
		start,
		"POR-02"
	)


func _test_exit_portal_uses_shader() -> void:
	var start := Time.get_ticks_msec()
	var portal := ExitPortalScene.instantiate()
	ctx.owner.add_child(portal)
	portal.call("configure", BiomeRegistry.BIOME_CASTLE)
	await ctx.owner.get_tree().process_frame
	var visuals := portal.get_node_or_null("DioramaVisuals")
	var ok := false
	if visuals:
		var interior := visuals.get_node_or_null("PortalInterior")
		if interior:
			for layer in interior.get_children():
				if layer is MeshInstance3D:
					var mat := layer.material_override as ShaderMaterial
					if mat and mat.shader:
						ok = mat.shader.resource_path.ends_with("portal_ellipse.gdshader")
	portal.queue_free()
	ctx.timed_record(
		"portal.exit_portal_uses_shader",
		get_category(),
		ok,
		"configured exit portal interior uses portal_ellipse.gdshader",
		start,
		"POR-01"
	)


func _test_merchant_not_portal() -> void:
	var start := Time.get_ticks_msec()
	var merchant_src := FileAccess.get_file_as_string(
		"res://scripts/dungeon/room_content/room_merchant_content.gd"
	)
	var uses_stall := "build_merchant_stall" in merchant_src
	var parent := Node3D.new()
	ctx.owner.add_child(parent)
	var stall := PixelStyle.build_merchant_stall(parent, BiomeRegistry.BIOME_CASTLE)
	var has_interior := stall.get_node_or_null("PortalInterior") != null
	parent.queue_free()
	ctx.timed_record(
		"portal.merchant_not_portal",
		get_category(),
		uses_stall and not has_interior,
		"merchant stall builder avoids PortalInterior",
		start,
		"POR-01"
	)


func _test_sfx_keys_exist() -> void:
	var start := Time.get_ticks_msec()
	var data := ContentLoader.load_json("content/art/portals.json")
	var portals: Dictionary = data.get("portals", {})
	var ok := AudioDirector.has_sfx("portal_enter")
	for portal_id in portals:
		var sfx: Dictionary = portals[portal_id].get("sfx", {})
		var ambient := str(sfx.get("ambient", ""))
		var enter := str(sfx.get("enter", ""))
		if ambient != "":
			ok = ok and AudioDirector.has_sfx(ambient)
		if enter != "":
			ok = ok and (AudioDirector.has_sfx(enter) or enter == "portal_enter")
	ctx.timed_record(
		"portal.sfx_keys_exist",
		get_category(),
		ok,
		"portal ambient and enter sfx keys resolve in AudioDirector",
		start,
		"POR-09"
	)
