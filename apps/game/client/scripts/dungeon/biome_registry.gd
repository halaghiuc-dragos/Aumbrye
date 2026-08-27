extends RefCounted
class_name BiomeRegistry


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
static var _threaded_paths: Dictionary = {}
static var _segment_cache: Dictionary = {}
static var _material_cache: Dictionary = {}
static var _prefix_index: Dictionary = {}


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


static func prewarm_content(biome_id: String) -> int:
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return 0

	var paths: Array[String] = []
	for entry in biome.get("enemyPool", []):
		if entry is Dictionary:
			var enemy_id := str((entry as Dictionary).get("enemyId", ""))
			if enemy_id != "":
				paths.append("content/enemies/%s.json" % enemy_id)
	for entry in biome.get("bossPool", []):
		if entry is Dictionary:
			var boss_id := str((entry as Dictionary).get("enemyId", ""))
			if boss_id != "":
				paths.append("content/bosses/%s.json" % boss_id)
	for entry in biome.get("trapPool", []):
		if entry is Dictionary:
			var trap_id := str((entry as Dictionary).get("trapId", ""))
			if trap_id != "":
				paths.append("content/traps/%s.json" % trap_id)

	var loot_table_path := str(biome.get("lootTablePath", ""))
	if loot_table_path != "":
		paths.append(loot_table_path)

	var audio_profile := get_audio_profile_path(biome_id)
	if audio_profile != "":
		paths.append(audio_profile)

	return ContentLoader.prime(paths)


static func prewarm_room_scenes(biome_id: String) -> void:
	if _room_scene_cache.has(biome_id):
		return
	var biome := get_biome(biome_id)
	if biome.is_empty():
		return
	var prefix := str(biome.get("templatePrefix", ""))
	var folder := str(biome.get("assetFolder", ""))
	for kind in ROOM_KINDS:
		var template_id := "%s_%s" % [prefix, kind]
		var path := "res://scenes/rooms/%s/%s.tscn" % [folder, template_id]
		if _threaded_paths.has(path) or not ResourceLoader.exists(path):
			continue
		if ResourceLoader.load_threaded_request(path) == OK:
			_threaded_paths[path] = true


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
		if not ResourceLoader.exists(path):
			continue
		scenes[template_id] = _load_room_scene(path)
	_room_scene_cache[biome_id] = scenes
	return scenes


static func _load_room_scene(path: String) -> Resource:
	if _threaded_paths.has(path):
		var status := ResourceLoader.load_threaded_get_status(path)
		if status == ResourceLoader.THREAD_LOAD_IN_PROGRESS:
			return ResourceLoader.load_threaded_get(path)
		if status == ResourceLoader.THREAD_LOAD_LOADED:
			return ResourceLoader.load_threaded_get(path)
		_threaded_paths.erase(path)
	return ResourceLoader.load(path)


static func get_room_scene(biome_id: String, template_id: String) -> Variant:
	return get_room_scenes(biome_id).get(template_id, null)


static func get_floor_material(biome_id: String) -> Material:
	return _load_material(biome_id, "floor")


static func get_wall_material(biome_id: String) -> Material:
	return _load_material(biome_id, "wall")


static func get_accent_material(biome_id: String) -> Material:
	return _load_material(biome_id, "accent")


static func biome_from_template_id(template_id: String) -> String:
	_ensure_biome_index()
	var prefix := template_id.get_slice("_", 0)
	if _prefix_index.is_empty():
		for biome_id in ALL_BIOMES:
			var prefix_value := str(get_biome(biome_id).get("templatePrefix", ""))
			if prefix_value != "":
				_prefix_index[prefix_value] = biome_id
	if _prefix_index.has(prefix):
		return str(_prefix_index[prefix])
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


static func apply_run_presentation(
	parent: Node3D, biome_id: String, run_mode: String = ""
) -> WorldEnvironment:
	if get_biome(biome_id).is_empty():
		return null
	var profile_id := VisualLighting.profile_for_biome(biome_id)
	if run_mode == RunModeConfig.MODE_WAVES:
		profile_id = "waves_arena"
	VisualLighting.apply_profile(parent, profile_id)
	var env_node := parent.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if env_node == null:
		return null
	var uses_indoor_lighting := run_mode in [RunModeConfig.MODE_CASTLE, RunModeConfig.MODE_ENDLESS]
	var sun := parent.get_node_or_null("DirectionalLight3D") as DirectionalLight3D
	if sun and uses_indoor_lighting:
		sun.visible = false
	if run_mode == RunModeConfig.MODE_WAVES and parent.get_node_or_null("ArenaFillLight") == null:
		var torch_cfg := VisualLighting.get_torch_config(profile_id)
		var fill := OmniLight3D.new()
		fill.name = "ArenaFillLight"
		var torch_color: Color = torch_cfg.get("color", Color(0.72, 0.68, 0.9))
		fill.light_color = torch_color.lerp(Color(0.72, 0.68, 0.9), 0.35)
		fill.light_energy = float(torch_cfg.get("energy", 0.55)) * 0.25
		fill.omni_range = 28.0
		fill.position = Vector3(0, 10, 0)
		parent.add_child(fill)
	VisualLighting.attach_atmosphere(parent, profile_id)
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


const ENDLESS_SEGMENT_MIN_FLOORS := 10
const ENDLESS_SEGMENT_MAX_FLOORS := 20


static func biome_for_floor(run_seed: int, floor_index: int) -> String:
	return segment_for_floor(run_seed, floor_index).get("biomeId", BIOME_UMBRAL)


static func segment_for_floor(run_seed: int, floor_index: int) -> Dictionary:
	_ensure_biome_index()
	if ALL_BIOMES.is_empty():
		return {"biomeId": BIOME_UMBRAL, "firstFloor": 1, "lastFloor": 1, "index": 0}
	var target := maxi(1, floor_index)
	var segments: Array = _segments_for_seed(run_seed)
	while segments.is_empty() or int(segments[segments.size() - 1].get("lastFloor", 0)) < target:
		_extend_segments(run_seed, segments, target)
	for segment in segments:
		if target <= int(segment.get("lastFloor", 0)):
			return segment
	return segments[segments.size() - 1]


static func _segments_for_seed(run_seed: int) -> Array:
	if not _segment_cache.has(run_seed):
		_segment_cache[run_seed] = []
	return _segment_cache[run_seed]


static func _extend_segments(run_seed: int, segments: Array, target_floor: int) -> void:
	var rng := RandomNumberGenerator.new()
	var floor_cursor := 1
	var previous_biome := ""
	var segment_index := 0
	if not segments.is_empty():
		var last: Dictionary = segments[segments.size() - 1]
		floor_cursor = int(last.get("lastFloor", 0)) + 1
		previous_biome = str(last.get("biomeId", ""))
		segment_index = int(last.get("index", 0)) + 1
	while segments.is_empty() or int(segments[segments.size() - 1].get("lastFloor", 0)) < target_floor:
		rng.seed = FloorSeedMix.mix(run_seed, segment_index + 2)
		var segment_length := rng.randi_range(
			ENDLESS_SEGMENT_MIN_FLOORS, ENDLESS_SEGMENT_MAX_FLOORS
		)
		var candidates: Array[String] = ALL_BIOMES.duplicate()
		if candidates.size() > 1 and previous_biome != "":
			candidates.erase(previous_biome)
		var chosen: String = candidates[rng.randi_range(0, candidates.size() - 1)]
		(
			segments
			. append(
				{
					"biomeId": chosen,
					"firstFloor": floor_cursor,
					"lastFloor": floor_cursor + segment_length - 1,
					"index": segment_index,
				}
			)
		)
		floor_cursor += segment_length
		previous_biome = chosen
		segment_index += 1


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
	var theme := PixelDioramaStyle.theme_from_biome(biome_id)
	var base: Material = null
	match slot:
		"floor":
			base = PixelDioramaStyle.make_floor_material(theme)
		"wall":
			base = PixelDioramaStyle.make_wall_material(theme)
		"ceiling":
			base = PixelDioramaStyle.make_ceiling_material(theme)
		"accent":
			base = PixelDioramaStyle.make_accent_material(theme)
		_:
			push_error("BiomeRegistry: unknown material slot '%s' for '%s'" % [slot, biome_id])
			return null
	if base == null:
		return null
	var cache_key := "%s/%s" % [biome_id, slot]
	if _material_cache.has(cache_key):
		var cached: Material = _material_cache[cache_key]
		if is_instance_valid(cached):
			return cached
	var resolved: Material = base
	if base is ShaderMaterial:
		resolved = PixelDioramaSettings.track((base as ShaderMaterial).duplicate() as ShaderMaterial)
	else:
		resolved = base.duplicate()
	_material_cache[cache_key] = resolved
	return resolved


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
