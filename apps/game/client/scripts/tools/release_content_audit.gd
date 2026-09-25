extends Node


const DungeonProcgenScript := preload("res://scripts/dungeon/procgen/dungeon_procgen.gd")

const BIOMES: Array[String] = [
	"forgotten_castle", "crystal_caverns", "poison_swamp", "frozen_fortress", "dark_cathedral",
	"iron_vault", "prism_depths", "venom_mire", "glacial_hollow", "umbral_chapel",
]
const GENERATION_SEEDS := 8


func _ready() -> void:
	var root := ContentLoader.content_root()
	print("RELEASE_CONTENT_ROOT: %s" % root)
	var json_files: Array[String] = []
	_collect_json(root.path_join("content"), root, json_files)
	var load_failures := 0
	for relative_path in json_files:
		var file := FileAccess.open(root.path_join(relative_path), FileAccess.READ)
		if file == null or JSON.parse_string(file.get_as_text()) == null:
			load_failures += 1
			print("CONTENT_JSON_INVALID: %s" % relative_path)
			continue
		# ContentLoader intentionally exposes object-based definitions; fixtures may be arrays, and
		# the item-set index has its own keyed schema rather than the per-item schema.
		if relative_path.begins_with("content/fixtures/") or relative_path == "content/items/sets.json":
			continue
		var result := ContentLoader.load_json_result(relative_path)
		if not bool(result.get("ok", false)):
			load_failures += 1
			print("CONTENT_LOAD_FAILED: %s (%s)" % [relative_path, result.get("error", "unknown")])
	print("CONTENT_JSON: %d files, %d failures" % [json_files.size(), load_failures])
	var catalog_counts := _exercise_catalogs()
	print("CATALOG_COUNTS: %s" % JSON.stringify(catalog_counts))
	var generation_failures := 0
	for biome in BIOMES:
		var biome_failures := 0
		for seed_offset in GENERATION_SEEDS:
			var seed_value := 1 + seed_offset * 7919 + biome.hash()
			var result: Dictionary = DungeonProcgenScript.generate(biome, seed_value, 1, 1, 1, false, false)
			if bool(result.get("ok", false)):
				continue
			generation_failures += 1
			biome_failures += 1
			print("BIOME_FAILED: %s seed=%d error=%s reason=%s" % [biome, seed_value, result.get("error", "unknown"), result.get("reason", "")])
		print("BIOME_RESULT: %s %d/%d generated" % [biome, GENERATION_SEEDS - biome_failures, GENERATION_SEEDS])
	var failed := load_failures > 0 or generation_failures > 0
	for key in catalog_counts:
		if int(catalog_counts[key]) <= 0:
			failed = true
	print("RELEASE_CONTENT_AUDIT: %s" % ("FAIL" if failed else "PASS"))
	get_tree().quit(1 if failed else 0)


func _exercise_catalogs() -> Dictionary:
	var counts := {
		"classes": ClassCatalog.get_all_classes().size(),
		"relics": RelicCatalog.get_all_ids().size(),
		"enemies": 0,
		"items": 0,
		"item_sets": 0,
		"traps": 0,
	}
	for folder in ["content/enemies", "content/bosses"]:
		for path in _json_paths(folder):
			var data := ContentLoader.load_json(path)
			if not str(data.get("id", "")).is_empty() and EnemyCatalog.has_enemy(str(data.get("id"))):
				counts["enemies"] = int(counts["enemies"]) + 1
	for path in _json_paths("content/items"):
		var data := ContentLoader.load_json(path)
		var item_id := str(data.get("id", ""))
		if not item_id.is_empty() and not ItemCatalog.get_definition(item_id).is_empty():
			counts["items"] = int(counts["items"]) + 1
	for set_id in ContentLoader.load_json("content/items/sets.json"):
		if not ItemSetCatalog.get_definition(str(set_id)).is_empty():
			counts["item_sets"] = int(counts["item_sets"]) + 1
	for path in _json_paths("content/traps"):
		var data := ContentLoader.load_json(path)
		if not str(data.get("id", "")).is_empty() and not TrapCatalog.get_scene_path(str(data.get("id"))).is_empty():
			counts["traps"] = int(counts["traps"]) + 1
	return counts


func _json_paths(relative_dir: String) -> Array[String]:
	var paths: Array[String] = []
	_collect_json(ContentLoader.content_root().path_join(relative_dir), ContentLoader.content_root(), paths)
	return paths


func _collect_json(directory_path: String, root: String, output: Array[String]) -> void:
	var directory := DirAccess.open(directory_path)
	if directory == null:
		return
	directory.list_dir_begin()
	var entry := directory.get_next()
	while not entry.is_empty():
		var full_path := directory_path.path_join(entry)
		if directory.current_is_dir():
			if entry != "." and entry != "..":
				_collect_json(full_path, root, output)
		elif entry.ends_with(".json"):
			output.append(full_path.trim_prefix(root.path_join("/")))
		entry = directory.get_next()
	directory.list_dir_end()
