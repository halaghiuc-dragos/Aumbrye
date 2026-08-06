extends RefCounted
class_name NpcCatalog

## Data-driven NPC definitions from content/npcs/ (NPC-4.1).

const NPC_DIR := "content/npcs"

static var _definitions: Dictionary = {}
static var _loaded := false


static func get_definition(npc_id: String) -> Dictionary:
	_ensure_loaded()
	return _definitions.get(npc_id, {})


static func get_all_ids() -> Array[String]:
	_ensure_loaded()
	var ids: Array[String] = []
	for key in _definitions.keys():
		ids.append(str(key))
	return ids


static func reload() -> void:
	_definitions.clear()
	_loaded = false
	_ensure_loaded()


static func is_loaded() -> bool:
	return _loaded


static func _ensure_loaded() -> void:
	if _loaded:
		return
	var abs_dir := ContentLoader.content_path(NPC_DIR)
	var dir := DirAccess.open(abs_dir)
	if dir == null:
		push_warning("NpcCatalog: missing directory %s" % abs_dir)
		_loaded = true
		return
	dir.list_dir_begin()
	var file_name := dir.get_next()
	while file_name != "":
		if not dir.current_is_dir() and file_name.ends_with(".json"):
			var relative := "%s/%s" % [NPC_DIR, file_name]
			var data: Dictionary = ContentLoader.load_json(relative)
			var npc_id: String = data.get("id", "")
			if npc_id.is_empty():
				push_warning("NpcCatalog: skipping %s (missing id)" % relative)
			else:
				data["content_path"] = relative
				_definitions[npc_id] = data
		file_name = dir.get_next()
	dir.list_dir_end()
	_loaded = true
