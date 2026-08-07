extends RefCounted
class_name EnemyCatalog

## Single source of truth for enemy content paths and Godot scenes.

static var _definitions: Dictionary = {}
static var _scenes: Dictionary = {}

## Legacy boss IDs removed from content; map to canonical definitions.
const LEGACY_ALIASES: Dictionary = {
	"castle_knight": "boss_castle_knight",
	"crystal_sovereign": "boss_crystal_sovereign",
}

const ENEMY_DIRS: Array[String] = [
	"content/enemies",
	"content/bosses",
]


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


static func clear_cache() -> void:
	_definitions.clear()
	_scenes.clear()


static func _ensure_loaded() -> void:
	if not _definitions.is_empty():
		return
	_definitions = ContentDirLoader.load_id_map(ENEMY_DIRS, "id", "EnemyCatalog", true, true)
