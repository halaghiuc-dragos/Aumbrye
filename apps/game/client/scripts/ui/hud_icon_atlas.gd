extends RefCounted
class_name HudIconAtlas


const MANIFEST_PATH := "content/ui/hud_atlas.json"
const RETICLE_PATH := "res://assets/ui/hud_reticle.png"
const OBJECTIVE_PATH := "res://assets/ui/hud_objective.png"

static var _manifest: Dictionary = {}
static var _source: Texture2D
static var _reticle: Texture2D
static var _objective: Texture2D
static var _pip_cache: Dictionary = {}
static var _loaded := false


static func get_pip_filled() -> AtlasTexture:
	return _pip_region("pipFilled", "pip_filled")


static func get_pip_empty() -> AtlasTexture:
	return _pip_region("pipEmpty", "pip_empty")


static func _pip_region(manifest_key: String, cache_key: String) -> AtlasTexture:
	_ensure_loaded()
	if _pip_cache.has(cache_key):
		return _pip_cache[cache_key]
	var entry: Dictionary = _manifest.get(manifest_key, {})
	var tex := AtlasTexture.new()
	tex.atlas = _source
	tex.region = Rect2(
		float(entry.get("x", 0)),
		float(entry.get("y", 0)),
		float(entry.get("w", 14)),
		float(entry.get("h", 8))
	)
	_pip_cache[cache_key] = tex
	return tex


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_manifest = ContentLoader.load_json(MANIFEST_PATH)
	var texture_path: String = str(_manifest.get("texture", ""))
	if ResourceLoader.exists(texture_path):
		_source = load(texture_path) as Texture2D
	if ResourceLoader.exists(RETICLE_PATH):
		_reticle = load(RETICLE_PATH) as Texture2D
	if ResourceLoader.exists(OBJECTIVE_PATH):
		_objective = load(OBJECTIVE_PATH) as Texture2D
	_loaded = true
