extends RefCounted
class_name StatusIconAtlas

## Authored status icon atlas — shared GPU texture with per-status regions.

const MANIFEST_PATH := "content/ui/status_icon_atlas.json"

static var _atlas: UISymbolAtlas
static var _loaded := false


static func get_icon(status_id: String) -> AtlasTexture:
	_ensure_loaded()
	if _atlas == null:
		return AtlasTexture.new()
	return _atlas.cell(status_id)


static func has_icon(status_id: String) -> bool:
	_ensure_loaded()
	return _atlas != null and _atlas.has_cell(status_id)


static func icon_size() -> int:
	_ensure_loaded()
	return _atlas.cell_size() if _atlas != null else 16


static func reload() -> void:
	_loaded = false
	_atlas = null
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_atlas = UISymbolAtlas.load_manifest(MANIFEST_PATH)
	_loaded = true
