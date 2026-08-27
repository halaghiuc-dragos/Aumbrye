extends RefCounted
class_name PortalCatalog


const DATA_PATH := "content/art/portals.json"
const FALLBACK_ID := "hub_return"

static var _data: Dictionary = {}
static var _unknown_warned := false
static var _load_attempted := false


static func resolve(portal_id: String) -> Dictionary:
	_ensure_loaded()
	var resolved_id := portal_id
	if _data.has("aliases") and (_data["aliases"] as Dictionary).has(portal_id):
		resolved_id = str((_data["aliases"] as Dictionary)[portal_id])
	var portals: Dictionary = _data.get("portals", {})
	if portals.has(resolved_id):
		var copy := (portals[resolved_id] as Dictionary).duplicate(true)
		copy["_id"] = resolved_id
		return copy
	if not _unknown_warned:
		push_warning("PortalCatalog: unknown portal '%s', using %s" % [portal_id, FALLBACK_ID])
		_unknown_warned = true
	var fallback := (portals.get(FALLBACK_ID, {}) as Dictionary).duplicate(true)
	fallback["_id"] = FALLBACK_ID
	return fallback


static func portal_id_for_biome(biome_id: String) -> String:
	if BiomeRegistry.ALL_BIOMES.has(biome_id):
		return biome_id
	return FALLBACK_ID


static func clear_cache() -> void:
	_data.clear()
	_unknown_warned = false
	_load_attempted = false


static func _ensure_loaded() -> void:
	if _load_attempted:
		return
	_load_attempted = true
	var loaded := ContentLoader.load_json(DATA_PATH)
	if loaded.is_empty():
		push_error("PortalCatalog: failed to load %s" % DATA_PATH)
		return
	_data = loaded
