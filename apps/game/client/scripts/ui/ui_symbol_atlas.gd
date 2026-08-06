extends RefCounted
class_name UISymbolAtlas

## Data-driven atlas loader for authored UI symbol textures.

var _manifest: Dictionary = {}
var _source: Texture2D
var _cell_cache: Dictionary = {}
var _cell_size: int = 16
var _unknown: Vector2i = Vector2i.ZERO


static func load_manifest(manifest_path: String) -> UISymbolAtlas:
	var atlas := UISymbolAtlas.new()
	atlas._load(manifest_path)
	return atlas


func _load(manifest_path: String) -> void:
	_manifest = ContentLoader.load_json(manifest_path)
	_cell_size = int(_manifest.get("cellSize", 16))
	var texture_path: String = str(_manifest.get("texture", ""))
	if texture_path.is_empty():
		push_warning("UISymbolAtlas: manifest '%s' has no texture path" % manifest_path)
		return
	if ResourceLoader.exists(texture_path):
		_source = load(texture_path) as Texture2D
	else:
		push_warning("UISymbolAtlas: missing texture %s" % texture_path)
		return
	var unknown: Variant = _manifest.get("unknown", {})
	if unknown is Dictionary:
		_unknown = Vector2i(int(unknown.get("col", 0)), int(unknown.get("row", 0)))


func has_cell(key: String) -> bool:
	var cells: Variant = _manifest.get("cells", {})
	return cells is Dictionary and (cells as Dictionary).has(key)


func keys() -> PackedStringArray:
	var cells: Variant = _manifest.get("cells", {})
	if not cells is Dictionary:
		return PackedStringArray()
	return PackedStringArray((cells as Dictionary).keys())


func cell_size() -> int:
	return _cell_size


func source_texture() -> Texture2D:
	return _source


func cell(key: String) -> AtlasTexture:
	if _cell_cache.has(key):
		return _cell_cache[key]
	var region := _region_for_key(key)
	var tex := AtlasTexture.new()
	tex.atlas = _source
	tex.region = region
	_cell_cache[key] = tex
	return tex


func invalidate() -> void:
	_cell_cache.clear()


func _region_for_key(key: String) -> Rect2:
	var cells: Variant = _manifest.get("cells", {})
	if cells is Dictionary and (cells as Dictionary).has(key):
		var entry: Dictionary = (cells as Dictionary)[key]
		return _rect_from_cell(int(entry.get("col", 0)), int(entry.get("row", 0)))
	if key != "unknown":
		push_warning("ui symbol atlas has no cell for key '%s'" % key)
	return _rect_from_cell(_unknown.x, _unknown.y)


func _rect_from_cell(col: int, row: int) -> Rect2:
	var size := float(_cell_size)
	return Rect2(float(col) * size, float(row) * size, size, size)
