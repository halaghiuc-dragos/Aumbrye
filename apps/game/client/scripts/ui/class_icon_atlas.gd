class_name ClassIconAtlas
extends RefCounted

## Class portrait lookup — atlas cells keyed by class id.

const MANIFEST_PATH := "content/ui/class_icon_atlas.json"

static var _atlas: UISymbolAtlas
static var _loaded := false


static func get_icon(class_id: String, icon_path: String = "") -> AtlasTexture:
	_ensure_loaded()
	if icon_path.begins_with("class_icons:"):
		var key := icon_path.substr("class_icons:".length())
		if _atlas != null and _atlas.has_cell(key):
			return _atlas.cell(key)
	if _atlas != null and _atlas.has_cell(class_id):
		return _atlas.cell(class_id)
	if _atlas != null:
		return _atlas.cell("unknown")
	return AtlasTexture.new()


static func has_icon(class_id: String) -> bool:
	_ensure_loaded()
	return _atlas != null and _atlas.has_cell(class_id)


static func icon_size() -> int:
	_ensure_loaded()
	return _atlas.cell_size() if _atlas != null else 64


static func reload() -> void:
	_loaded = false
	_atlas = null
	_ensure_loaded()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_atlas = UISymbolAtlas.load_manifest(MANIFEST_PATH)
	_loaded = true
