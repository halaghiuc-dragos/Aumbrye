extends RefCounted
class_name InputGlyphAtlas

## Input-glyph lookup — atlas cells keyed as `<family>/<key-or-button-index>`.

const MANIFEST_PATH := "content/ui/input_glyph_atlas.json"

static var _atlas: UISymbolAtlas
static var _loaded := false


static func get_glyph(cell_key: String) -> AtlasTexture:
	_ensure_loaded()
	if _atlas == null:
		return AtlasTexture.new()
	return _atlas.cell(cell_key)


static func has_glyph(cell_key: String) -> bool:
	_ensure_loaded()
	return _atlas != null and _atlas.has_cell(cell_key)


static func glyph_size() -> int:
	_ensure_loaded()
	return _atlas.cell_size() if _atlas != null else 16


static func reload() -> void:
	_loaded = false
	_atlas = null
	_ensure_loaded()


static func invalidate() -> void:
	if _atlas != null:
		_atlas.invalidate()


static func atlas() -> UISymbolAtlas:
	_ensure_loaded()
	return _atlas


static func _ensure_loaded() -> void:
	if _loaded:
		return
	_atlas = UISymbolAtlas.load_manifest(MANIFEST_PATH)
	_loaded = true
