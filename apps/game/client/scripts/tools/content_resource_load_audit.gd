extends Node

const EXCLUSION_CONFIG := "res://export_presets.cfg"

var _failures := 0
var _json_count := 0
var _resource_paths: Dictionary = {}
var _excluded_prefixes: Array[String] = []
var _dynamic_room_scene_count := 0


func _ready() -> void:
	_load_export_exclusions()
	_scan_json(ContentLoader.content_root().path_join("content"))
	var ordered_paths: Array[String] = []
	for path in _resource_paths:
		ordered_paths.append(str(path))
	ordered_paths.sort()
	for path in ordered_paths:
		if _is_excluded(path):
			_check(false, "content references a release-excluded resource: %s" % path)
			continue
		if not ResourceLoader.exists(path):
			_check(false, "content resource does not exist: %s" % path)
			continue
		var resource := ResourceLoader.load(path)
		_check(resource != null, "content resource failed to load: %s" % path)
		if ordered_paths.find(path) % 40 == 0:
			await get_tree().process_frame
	_audit_mode_routes()
	print(
		"CONTENT RESOURCE LOAD RESULT %d failures (%d JSON files, %d unique resources, %d dynamic room scenes)"
		% [_failures, _json_count, ordered_paths.size(), _dynamic_room_scene_count]
	)
	get_tree().quit(0 if _failures == 0 else 1)


func _audit_mode_routes() -> void:
	var routes := [
		"res://scenes/ui/main_menu.tscn",
		RunSceneRouter.HUB_SCENE,
		RunSceneRouter.CASTLE_RUN_SCENE,
		RunSceneRouter.WAVES_RUN_SCENE,
		RunSceneRouter.ARENA_SCENE,
		RunSceneRouter.RESULTS_SCENE,
	]
	for route in routes:
		if _is_excluded(str(route)):
			_check(false, "shipped mode route is release-excluded: %s" % route)
			continue
		if not ResourceLoader.exists(str(route)):
			_check(false, "shipped mode route does not exist: %s" % route)
			continue
		var packed_scene := ResourceLoader.load(str(route)) as PackedScene
		_check(packed_scene != null, "shipped mode route did not load as a PackedScene: %s" % route)
	_audit_dynamic_biome_room_scenes()


func _audit_dynamic_biome_room_scenes() -> void:
	# The production loader assembles these paths from the biome's templatePrefix/assetFolder and
	# the shared room-kind table. Exercise that exact path construction across every shipped biome.
	BiomeRegistry.biome_for_floor(1, 1) # Ensures the biome index is populated.
	for biome_id in BiomeRegistry.ALL_BIOMES:
		var biome := BiomeRegistry.get_biome(biome_id)
		var prefix := str(biome.get("templatePrefix", ""))
		var folder := str(biome.get("assetFolder", ""))
		for kind in BiomeRegistry.ROOM_KINDS:
			var path := "res://scenes/rooms/%s/%s_%s.tscn" % [folder, prefix, kind]
			if _is_excluded(path):
				_check(false, "dynamically assembled biome room is release-excluded: %s" % path)
				continue
			if not ResourceLoader.exists(path):
				_check(false, "dynamically assembled biome room is missing: %s" % path)
				continue
			var packed_scene := ResourceLoader.load(path) as PackedScene
			_check(packed_scene != null, "dynamically assembled biome room failed to load: %s" % path)
			if packed_scene != null:
				_dynamic_room_scene_count += 1


func _load_export_exclusions() -> void:
	var file := FileAccess.open(EXCLUSION_CONFIG, FileAccess.READ)
	if file == null:
		_check(false, "export presets could not be read")
		return
	for line in file.get_as_text().split("\n"):
		if not line.begins_with("exclude_filter=\""):
			continue
		var encoded := line.trim_prefix("exclude_filter=\"").trim_suffix("\"")
		for raw in encoded.split(","):
			var prefix := str(raw).strip_edges().trim_suffix("*")
			if not prefix.is_empty():
				_excluded_prefixes.append(prefix)


func _scan_json(directory: String) -> void:
	var dir := DirAccess.open(directory)
	if dir == null:
		_check(false, "content directory is missing: %s" % directory)
		return
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while not entry_name.is_empty():
		var path := directory.path_join(entry_name)
		if dir.current_is_dir():
			if entry_name != "." and entry_name != "..":
				_scan_json(path)
		elif entry_name.get_extension().to_lower() == "json":
			_json_count += 1
			var file := FileAccess.open(path, FileAccess.READ)
			if file == null:
				_check(false, "content JSON could not be read: %s" % path)
			else:
				var parsed: Variant = JSON.parse_string(file.get_as_text())
				if parsed == null:
					_check(false, "content JSON could not be parsed: %s" % path)
				else:
					_collect_resources(parsed)
		entry_name = dir.get_next()
	dir.list_dir_end()


func _collect_resources(value: Variant) -> void:
	if value is String:
		var path := str(value)
		if path.begins_with("res://") and not path.contains("%"):
			_resource_paths[path] = true
	elif value is Dictionary:
		for child in value.values():
			_collect_resources(child)
	elif value is Array:
		for child in value:
			_collect_resources(child)


func _is_excluded(path: String) -> bool:
	var relative := path.trim_prefix("res://")
	for prefix in _excluded_prefixes:
		if relative.begins_with(prefix):
			return true
	return false


func _check(ok: bool, label: String) -> void:
	if ok:
		return
	_failures += 1
	push_error(label)
