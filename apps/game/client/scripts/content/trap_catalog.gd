class_name TrapCatalog
extends RefCounted

## Resolves trap ids to scene paths from content/traps/<id>.json (PLC-06).

static var _cache: Dictionary = {}


static func get_scene_path(trap_id: String) -> String:
	if trap_id.is_empty():
		return ""
	if _cache.has(trap_id):
		return str(_cache[trap_id])
	var data: Dictionary = ContentLoader.load_json("content/traps/%s.json" % trap_id)
	var scene_path := str(data.get("scene", ""))
	_cache[trap_id] = scene_path
	return scene_path


static func clear_cache() -> void:
	_cache.clear()
