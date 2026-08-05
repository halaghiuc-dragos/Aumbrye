extends RefCounted
class_name EnemyCatalog

## Single source of truth for enemy content paths and Godot scenes.

static var _definitions: Dictionary = {}
static var _scenes: Dictionary = {}

## Legacy boss IDs removed from content; map to canonical definitions.
const LEGACY_ALIASES: Dictionary = {
	"castle_knight": "boss_castle_knight",
}


static func resolve_id(enemy_id: String) -> String:
	return LEGACY_ALIASES.get(enemy_id, enemy_id)


static func get_definition(enemy_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(resolve_id(enemy_id), {})


static func get_content_path(enemy_id: String) -> String:
	var def := get_definition(enemy_id)
	return def.get("content_path", "")


static func get_scene(enemy_id: String) -> PackedScene:
	_ensure_loaded()
	var resolved := resolve_id(enemy_id)
	if _scenes.has(resolved):
		return _scenes[resolved]
	var def := get_definition(resolved)
	var scene_path: String = def.get("scene", "")
	if scene_path.is_empty():
		return null
	var scene: PackedScene = load(scene_path)
	if scene:
		_scenes[resolved] = scene
	return scene


static func has_enemy(enemy_id: String) -> bool:
	_ensure_loaded()
	return _definitions.has(resolve_id(enemy_id))


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	_load_directory("content/enemies")
	_load_directory("content/bosses")


static func _load_directory(relative_dir: String) -> void:
	var abs_dir := ContentLoader.content_path(relative_dir)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("EnemyCatalog: missing directory %s" % abs_dir)
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var relative := "%s/%s" % [relative_dir, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var enemy_id: String = data.get("id", "")
			if enemy_id.is_empty():
				push_warning("EnemyCatalog: skipping %s (missing id)" % relative)
			else:
				data["content_path"] = relative
				_definitions[enemy_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
