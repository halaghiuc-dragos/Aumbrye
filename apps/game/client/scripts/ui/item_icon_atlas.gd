extends RefCounted
class_name ItemIconAtlas

## Item icon lookup — atlas cells keyed by item id or slot/<slot_name>.

const MANIFEST_PATH := "content/ui/item_icon_atlas.json"

static var _atlas: UISymbolAtlas
static var _loaded := false


static func get_icon(item_id: String, icon_path: String = "") -> AtlasTexture:
	_ensure_loaded()
	if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
		var standalone := AtlasTexture.new()
		standalone.atlas = load(icon_path) as Texture2D
		if standalone.atlas:
			standalone.region = Rect2(
				0, 0, standalone.atlas.get_width(), standalone.atlas.get_height()
			)
			return standalone
	if _atlas != null and _atlas.has_cell(item_id):
		return _atlas.cell(item_id)
	if _atlas != null:
		return _atlas.cell("unknown")
	return AtlasTexture.new()


static func has_icon(item_id: String) -> bool:
	_ensure_loaded()
	return _atlas != null and _atlas.has_cell(item_id)


static func get_slot_icon(slot_name: String) -> AtlasTexture:
	return get_icon("slot/%s" % slot_name)


static func icon_size() -> int:
	_ensure_loaded()
	return _atlas.cell_size() if _atlas != null else 16


static func reload() -> void:
	_loaded = false
	_atlas = null
	_ensure_loaded()


static func invalidate() -> void:
	if _atlas != null:
		_atlas.invalidate()


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_atlas = UISymbolAtlas.load_manifest(MANIFEST_PATH)
	_loaded = true
