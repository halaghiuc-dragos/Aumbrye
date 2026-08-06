extends RefCounted
class_name BiomeRegistry

## Data-driven biome kit loader: room scenes, materials, lighting, audio.

const LootTableLoaderScript := preload("res://scripts/loot/loot_table_loader.gd")

const BIOME_CASTLE := "forgotten_castle"
const BIOME_CRYSTAL := "crystal_caverns"
const BIOME_SWAMP := "poison_swamp"
const BIOME_FROZEN := "frozen_fortress"
const BIOME_CATHEDRAL := "dark_cathedral"
const BIOME_VAULT := "iron_vault"
const BIOME_PRISM := "prism_depths"
const BIOME_MIRE := "venom_mire"
const BIOME_HOLLOW := "glacial_hollow"
const BIOME_UMBRAL := "umbral_chapel"

const ROOM_KINDS := [
	"entrance",
	"stairs",
	"corridor",
	"courtyard",
	"hall",
	"treasure",
	"secret",
	"arena",
	"boss",
	"puzzle",
]

static var ALL_BIOMES: Array[String] = []
static var _cache: Dictionary = {}
static var _room_scene_cache: Dictionary = {}
static var _index_ready := false


static func warm_index() -> void:
	_ensure_biome_index()


static func get_biome(biome_id: String) -> Dictionary:
	if _cache.has(biome_id):
		return (_cache[biome_id] as Dictionary).duplicate(true)
	var data := ContentLoader.load_json("content/biomes/%s.json" % biome_id)
	if data.is_empty():
		push_error("BiomeRegistry: unknown biome '%s'" % biome_id)
		return {}
	if not _validate_biome(data, biome_id):
		return {}
	data = _resolve_loot_tables(data, biome_id)
	_cache[biome_id] = data.duplicate(true)
	return data.duplicate(true)


static func get_display_name(biome_id: String) -> String:
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return ""
	return str(biome.get("name", ""))


static func get_room_scenes(biome_id: String) -> Dictionary:
	if _room_scene_cache.has(biome_id):
		return _room_scene_cache[biome_id]
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return {}
	var prefix := str(biome.get("templatePrefix", ""))
	var folder := str(biome.get("assetFolder", ""))
	var scenes := {}
	for kind in ROOM_KINDS:
		var template_id := "%s_%s" % [prefix, kind]
		var path := "res://scenes/rooms/%s/%s.tscn" % [folder, template_id]
		if ResourceLoader.exists(path):
			scenes[template_id] = ResourceLoader.load(path)
	_room_scene_cache[biome_id] = scenes
	return scenes


static func get_room_scene(biome_id: String, template_id: String) -> Variant:
	return get_room_scenes(biome_id).get(template_id, null)


static func get_floor_material(biome_id: String) -> Material:
	return _load_material(biome_id, "floor")


static func get_wall_material(biome_id: String) -> Material:
	return _load_material(biome_id, "wall")


static func get_ceiling_material(biome_id: String) -> Material:
	return _load_material(biome_id, "ceiling")


static func get_accent_material(biome_id: String) -> Material:
	return _load_material(biome_id, "accent")


static func biome_from_template_id(template_id: String) -> String:
	_ensure_biome_index()
	var prefix := template_id.get_slice("_", 0)
	for biome_id in ALL_BIOMES:
		var biome := get_biome(biome_id)
		if str(biome.get("templatePrefix", "")) == prefix:
			return biome_id
	return BIOME_CASTLE if prefix == "castle" else ""


static func get_grade_profile(biome_id: String) -> Dictionary:
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return {}
	var grade: Variant = biome.get("grade", {})
	if not grade is Dictionary:
		return {}
	var raw: Dictionary = grade as Dictionary
	var profile := {}
	if raw.has("shadowTint"):
		profile["shadow_tint"] = _color_from_array(raw.get("shadowTint"))
	if raw.has("shadowTintAmount"):
		profile["shadow_tint_amount"] = float(raw.get("shadowTintAmount"))
	if raw.has("highlightTint"):
		profile["highlight_tint"] = _color_from_array(raw.get("highlightTint"))
	if raw.has("highlightTintAmount"):
		profile["highlight_tint_amount"] = float(raw.get("highlightTintAmount"))
	return profile


static func get_lighting_profile(biome_id: String) -> Dictionary:
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return {}
	var lighting: Dictionary = biome.get("lighting", {})
	return {
		"ambient_color": _color_from_array(lighting.get("ambientColor", [0.4, 0.4, 0.45])),
		"ambient_energy": float(lighting.get("ambientEnergy", 0.5)),
		"fog_enabled": bool(lighting.get("fogEnabled", false)),
		"fog_color": _color_from_array(lighting.get("fogColor", [0.2, 0.2, 0.25])),
		"fog_density": float(lighting.get("fogDensity", 0.01)),
		"torch_color": _color_from_array(lighting.get("torchColor", [1.0, 0.72, 0.38])),
		"torch_energy": float(lighting.get("torchEnergy", 2.2)),
	}


static func apply_run_presentation(
	parent: Node3D, biome_id: String, run_mode: String = ""
) -> WorldEnvironment:
	var lighting := get_lighting_profile(biome_id)
	if lighting.is_empty():
		return null
	var env_node := WorldEnvironment.new()
	env_node.name = "WorldEnvironment"
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	var profile_ambient: Color = lighting.get("ambient_color", Color(0.4, 0.4, 0.45))
	var profile_energy: float = float(lighting.get("ambient_energy", 0.5))
	environment.ambient_light_color = profile_ambient
	environment.ambient_light_energy = profile_energy
	environment.fog_enabled = bool(lighting.get("fog_enabled", false))
	environment.fog_light_color = lighting.get("fog_color", Color(0.2, 0.2, 0.25))
	environment.fog_density = float(lighting.get("fog_density", 0.01))

	var uses_indoor_lighting := run_mode in [RunModeConfig.MODE_CASTLE, RunModeConfig.MODE_ENDLESS]
	var needs_arena_boost := run_mode == RunModeConfig.MODE_WAVES
	if needs_arena_boost:
		var waves_tint := Color(0.48, 0.42, 0.62)
		environment.ambient_light_color = profile_ambient.lerp(waves_tint, 0.4)
		environment.ambient_light_energy = maxf(profile_energy, profile_energy * 1.3)
		environment.background_color = profile_ambient.lerp(Color(0.12, 0.1, 0.18), 0.55)
		environment.fog_enabled = false
	elif uses_indoor_lighting:
		VisualLighting.apply_indoor_environment(environment, lighting)
	else:
		environment.background_color = profile_ambient.lerp(Color(0.12, 0.11, 0.16), 0.55)
		PixelDioramaSettings.configure_environment(environment)

	env_node.environment = environment
	parent.add_child(env_node)

	var sun := parent.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun:
		if uses_indoor_lighting:
			sun.visible = false
		elif needs_arena_boost:
			sun.light_energy = 1.35
			sun.light_color = Color(0.95, 0.92, 1.0)
			PixelDioramaSettings.configure_directional_shadow(sun)

	if needs_arena_boost and parent.get_node_or_null("ArenaFillLight") == null:
		var fill := OmniLight3D.new()
		fill.name = "ArenaFillLight"
		var torch: Color = lighting.get("torch_color", Color(0.72, 0.68, 0.9))
		fill.light_color = torch.lerp(Color(0.72, 0.68, 0.9), 0.35)
		fill.light_energy = float(lighting.get("torch_energy", 0.55)) * 0.25
		fill.omni_range = 28.0
		fill.position = Vector3(0, 10, 0)
		parent.add_child(fill)

	VisualLighting.apply_biome_atmosphere(parent, biome_id)
	PixelDioramaSettings.set_biome_screen_grade(biome_id)
	AudioDirector.set_biome(biome_id)
	return env_node


static func get_audio_profile_path(biome_id: String) -> String:
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return ""
	return str(biome.get("audioProfile", ""))


static func resolve_biome_id(definition: Dictionary, fallback: String = BIOME_CASTLE) -> String:
	var biome_id: String = str(definition.get("biomeId", fallback))
	if biome_id == "":
		return fallback
	return biome_id


static func room_scene_path(biome_id: String, kind: String) -> String:
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return ""
	var prefix := str(biome.get("templatePrefix", ""))
	var folder := str(biome.get("assetFolder", ""))
	return "res://scenes/rooms/%s/%s_%s.tscn" % [folder, prefix, kind]


static func clear_caches() -> void:
	_cache.clear()
	_room_scene_cache.clear()


static func _ensure_biome_index() -> void:
	if _index_ready:
		return
	_index_ready = true
	ALL_BIOMES.clear()
	var dir_path := ContentLoader.content_path("content/biomes")
	var dir := DirAccess.open(dir_path)
	if dir == null:
		push_error("BiomeRegistry: cannot open %s" % dir_path)
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while entry != "":
		if not dir.current_is_dir() and entry.ends_with(".json"):
			var biome_id := entry.get_basename()
			ALL_BIOMES.append(biome_id)
		entry = dir.get_next()
	dir.list_dir_end()
	ALL_BIOMES.sort()


static func _load_material(biome_id: String, slot: String) -> Material:
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return null
	var materials: Dictionary = biome.get("materials", {})
	var path := str(materials.get(slot, ""))
	if path.is_empty() or not ResourceLoader.exists(path):
		push_error("BiomeRegistry: missing material '%s' for '%s'" % [slot, biome_id])
		return null
	var mat := load(path) as Material
	if mat == null:
		return null
	var dup := mat.duplicate()
	if dup is ShaderMaterial:
		return PixelDioramaSettings.track(dup as ShaderMaterial)
	return dup


static func _color_from_array(raw: Variant) -> Color:
	if raw is Array and (raw as Array).size() >= 3:
		var arr: Array = raw
		return Color(float(arr[0]), float(arr[1]), float(arr[2]))
	return Color(0.4, 0.4, 0.45)


static func _validate_biome(data: Dictionary, biome_id: String) -> bool:
	if str(data.get("id", "")) != biome_id:
		push_error("BiomeRegistry: id mismatch for '%s'" % biome_id)
		return false
	for key in [
		"templatePrefix",
		"assetFolder",
		"materials",
		"lighting",
		"audioProfile",
		"propKit",
		"enemyPool",
		"bossPool",
		"budgets",
		"trapPool",
	]:
		if not data.has(key):
			push_error("BiomeRegistry: missing '%s' in '%s'" % [key, biome_id])
			return false
	if not data.has("lootTables") and not data.has("lootTablePath"):
		push_error("BiomeRegistry: missing lootTables or lootTablePath in '%s'" % biome_id)
		return false
	var tables: Dictionary = LootTableLoaderScript.resolve_loot_tables(data)
	for role in ["treasure", "secret", "side", "armory"]:
		if not tables.has(role) or not (tables[role] is Array):
			push_error("BiomeRegistry: lootTables.%s missing in '%s'" % [role, biome_id])
			return false
	return true


static func _resolve_loot_tables(data: Dictionary, _biome_id: String) -> Dictionary:
	var resolved := data.duplicate(true)
	var tables: Dictionary = LootTableLoaderScript.resolve_loot_tables(resolved)
	if not tables.is_empty():
		resolved["lootTables"] = tables
	return resolved
